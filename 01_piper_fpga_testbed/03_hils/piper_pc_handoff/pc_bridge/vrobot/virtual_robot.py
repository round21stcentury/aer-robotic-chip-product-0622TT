#!/usr/bin/env python3
"""가상로봇 노드 — piper_sdk 의 역방향("로봇 노릇").

- 명령 버스(can0; 순수sim이면 vcan1)에서 0x151/0x155-7/0x471 디코드
- 시뮬 백엔드(kinematic 또는 gazebo) 구동
- 관절 상태를 0x2A1/0x2A5-7 피드백으로 인코드 -> 피드백 버스(vcan0)에 송신
  (컨트롤러용 피드백은 FPGA 안 거치고 vcan0 직행 — 브리지 계약서 §7.1)
- ★상태 브로드캐스트(반사 칩용): 실로봇은 자기 물리 CAN 버스에 0x2A1/2A5~7을 쏜다.
  그 버스의 CAN 노드(반사 칩)가 도달플래그(0x2A1 B4)·현재포즈(0x2A5~7)를 읽어야 반사가 풀린다.
  → cmd-iface 가 실제 CAN(can*)이면 ★그 버스에도 상태를 송신★(--status-iface 로 override, 'off'로 끔).
  (이게 없으면 HIL에서 칩이 reached 를 못 받아 포즈 반사가 영구히 안 풀려 PS가 계속 막힘.)

실행:
  # 1·2단계 검증 (ROS 불필요):
  python3 vrobot/virtual_robot.py --cmd-iface vcan1 --fb-iface vcan0 --backend kinematic
  # 3단계 (컨테이너 안, ROS2 소싱 후):
  python3 vrobot/virtual_robot.py --cmd-iface can0 --fb-iface vcan0 --backend gazebo
"""
import argparse
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import caniface, frames, ids  # noqa: E402


class VirtualRobot:
    def __init__(self, backend, cmd_iface, fb_iface, fb_hz, status_iface="", reached_tol=2000):
        self.backend = backend
        self.fb_dt = 1.0 / fb_hz
        self.reached_tol = reached_tol      # 도달판정 허용오차(millideg). Gazebo는 0.05°론 안 정착 → 2° 기본.
        # 명령 수신: 1차 범위 명령만
        self.cmd_sock = caniface.open_can(
            cmd_iface, recv_ids=ids.COMMAND_IDS_WITH_ESTOP, recv_timeout=0.2)  # ★0x150 포함(반사 e-stop)★
        self.fb_sock = caniface.open_can(fb_iface)
        # ★상태 브로드캐스트 버스(반사 칩용): 빈값=cmd-iface가 can*면 자동 그 버스, vcan이면 off. 'off'=강제 끔.
        if status_iface == "" or status_iface is None:
            status_iface = cmd_iface if cmd_iface.startswith("can") else None  # 'vcan*'는 startswith('can')=False
        elif status_iface in ("off", "none", "None"):
            status_iface = None
        # ★전용 송신 소켓(cmd_sock 재사용 안 함: RX스레드와 동시접근 회피). 같은 버스라도 별도 fd.
        self.status_sock = caniface.open_can(status_iface) if status_iface else None
        self.status_iface = status_iface
        self.targets_raw = [0]* 6   # 0.001°
        self.ctrl_mode = 0x01
        self.last_estop = -1.0      # ★반사 e-stop★ 마지막 0x150(B0=01) 수신시각 (정지 판단용)
        self.running = True

    # ── 명령 수신 스레드 ──
    def _cmd_loop(self):
        while self.running:
            try:
                can_id, data = caniface.recv(self.cmd_sock)
            except OSError:
                continue
            if can_id == ids.JOINT_CTRL_12:
                self.targets_raw[0], self.targets_raw[1] = frames.dec_joint_ctrl(can_id, data)
            elif can_id == ids.JOINT_CTRL_34:
                self.targets_raw[2], self.targets_raw[3] = frames.dec_joint_ctrl(can_id, data)
            elif can_id == ids.JOINT_CTRL_56:
                self.targets_raw[4], self.targets_raw[5] = frames.dec_joint_ctrl(can_id, data)
                # 56까지 받으면 한 사이클 목표 완성 -> 백엔드에 반영.
                # ★반사 e-stop(0x150 B0=01)을 0.2s 이내 받았으면 목표 무시 = 현재 자세 유지(정지)★
                if time.perf_counter() - self.last_estop > 0.2:
                    self.backend.set_targets([frames.raw_to_rad(r) for r in self.targets_raw])
            elif can_id == ids.MOTOR_ENABLE:
                motor_num, flag = frames.dec_motor_enable(data)
                self.backend.set_enable(flag == 0x02)
            elif can_id == ids.MOTION_CTRL_2:
                self.ctrl_mode = frames.dec_motion_ctrl_2(data)["ctrl_mode"]
            elif can_id == ids.MOTION_CTRL_1:        # 0x150 — ★반사 e-stop★
                if len(data) >= 1 and data[0] == 0x01:    # B0=0x01 비상정지
                    self.last_estop = time.perf_counter()
                    # (DIP 내리면 0x150 멈춤 → 0.2s 뒤 위 조건 풀려 자동 재개)

    # ── 피드백 송신 루프 (메인) ──
    def run(self):
        t = threading.Thread(target=self._cmd_loop, daemon=True)
        t.start()
        _sb = self.status_iface if self.status_sock is not None else "off"
        print(f"[vrobot] running, feedback @ {1/self.fb_dt:.0f}Hz, 상태브로드캐스트(반사칩)={_sb}", flush=True)
        last = time.perf_counter()
        while self.running:
            now = time.perf_counter()
            dt = now - last
            last = now
            self.backend.spin_once(dt)
            state_rad = self.backend.get_state()
            raw = [frames.fb_rad_to_raw(r) for r in state_rad]

            # 0x2A1 상태: 도달 여부 (목표-현재). ★허용오차 self.reached_tol(millideg).
            #   기본 50(0.05°)은 Gazebo 동역학엔 너무 빡빡해 영영 "미도달"(B4=01) → 반사 칩이 reached 못 받아 포즈 안 풀림.
            #   현실적 2°(2000)로. (실로봇은 펌웨어가 도달판정하므로 HIL 모델 충실도 문제.)
            reached = all(abs(self.targets_raw[i] - raw[i]) < self.reached_tol for i in range(6))
            cid, sdata = frames.enc_arm_status(
                ctrl_mode=self.ctrl_mode, arm_status=0x00, mode_feed=self.ctrl_mode,
                motion_status=0x00 if reached else 0x01)
            caniface.send(self.fb_sock, cid, sdata)
            if self.status_sock is not None:
                caniface.send(self.status_sock, cid, sdata)       # ★0x2A1 → 물리버스(칩이 reached 읽음)
            # 0x2A5-7 관절 피드백
            for cid, fdata in frames.enc_joint_feedback(*raw):
                caniface.send(self.fb_sock, cid, fdata)
                if self.status_sock is not None:
                    caniface.send(self.status_sock, cid, fdata)   # ★0x2A5~7 → 물리버스(07 현재포즈용)

            sleep = self.fb_dt - (time.perf_counter() - now)
            if sleep > 0:
                time.sleep(sleep)


def main():
    ap = argparse.ArgumentParser(description="Piper 가상로봇 (CAN<->sim)")
    ap.add_argument("--cmd-iface", default="vcan1", help="명령 수신 버스 (HW=can0)")
    ap.add_argument("--fb-iface", default="vcan0", help="피드백 송신 버스 (컨트롤러)")
    ap.add_argument("--status-iface", default="",
                    help="상태(0x2A1/2A5~7) 추가 송신 버스(반사 칩용). 빈값=cmd-iface가 can*면 자동, vcan이면 off. 'off'=끔")
    ap.add_argument("--reached-tol", type=int, default=2000,
                    help="도달판정 허용오차(millideg, 0.001°). 기본 2000=2°(Gazebo 정착용). 반사 해제(0x2A1 B4)에 쓰임")
    ap.add_argument("--backend", choices=["kinematic", "gazebo"], default="kinematic")
    ap.add_argument("--fb-hz", type=float, default=200.0, help="피드백 주기 (Piper ~200Hz)")
    ap.add_argument("--tau", type=float, default=0.0, help="kinematic 1차지연 시상수(초)")
    args = ap.parse_args()

    if args.backend == "kinematic":
        from vrobot.backend_kinematic import KinematicBackend
        backend = KinematicBackend(tau=args.tau)
    else:
        from vrobot.backend_gazebo import GazeboBackend
        backend = GazeboBackend()

    robot = VirtualRobot(backend, args.cmd_iface, args.fb_iface, args.fb_hz,
                         status_iface=args.status_iface, reached_tol=args.reached_tol)
    try:
        robot.run()
    except KeyboardInterrupt:
        robot.running = False
        backend.close()
        print("\n[vrobot] stopped")


if __name__ == "__main__":
    main()
