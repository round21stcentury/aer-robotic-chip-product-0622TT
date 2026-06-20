#!/usr/bin/env python3
"""가상로봇 노드 — piper_sdk 의 역방향("로봇 노릇").

- 명령 버스(can0; 순수sim이면 vcan1)에서 0x151/0x155-7/0x471 디코드
- 시뮬 백엔드(kinematic 또는 gazebo) 구동
- 관절 상태를 0x2A1/0x2A5-7 피드백으로 인코드 -> 피드백 버스(vcan0)에 송신
  (피드백은 FPGA 안 거치고 vcan0 직행 — 브리지 계약서 §7.1)

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
    def __init__(self, backend, cmd_iface, fb_iface, fb_hz):
        self.backend = backend
        self.fb_dt = 1.0 / fb_hz
        # 명령 수신: 1차 범위 명령만
        self.cmd_sock = caniface.open_can(
            cmd_iface, recv_ids=ids.SCOPE_COMMAND_IDS, recv_timeout=0.2)
        self.fb_sock = caniface.open_can(fb_iface)
        self.targets_raw = [0]* 6   # 0.001°
        self.ctrl_mode = 0x01
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
                # 56까지 받으면 한 사이클 목표 완성 -> 백엔드에 반영
                self.backend.set_targets([frames.raw_to_rad(r) for r in self.targets_raw])
            elif can_id == ids.MOTOR_ENABLE:
                motor_num, flag = frames.dec_motor_enable(data)
                self.backend.set_enable(flag == 0x02)
            elif can_id == ids.MOTION_CTRL_2:
                self.ctrl_mode = frames.dec_motion_ctrl_2(data)["ctrl_mode"]

    # ── 피드백 송신 루프 (메인) ──
    def run(self):
        t = threading.Thread(target=self._cmd_loop, daemon=True)
        t.start()
        print(f"[vrobot] running, feedback @ {1/self.fb_dt:.0f}Hz", flush=True)
        last = time.perf_counter()
        while self.running:
            now = time.perf_counter()
            dt = now - last
            last = now
            self.backend.spin_once(dt)
            state_rad = self.backend.get_state()
            raw = [frames.fb_rad_to_raw(r) for r in state_rad]

            # 0x2A1 상태: 도달 여부 (목표-현재)
            reached = all(abs(self.targets_raw[i] - raw[i]) < 50 for i in range(6))
            cid, sdata = frames.enc_arm_status(
                ctrl_mode=self.ctrl_mode, arm_status=0x00, mode_feed=self.ctrl_mode,
                motion_status=0x00 if reached else 0x01)
            caniface.send(self.fb_sock, cid, sdata)
            # 0x2A5-7 관절 피드백
            for cid, fdata in frames.enc_joint_feedback(*raw):
                caniface.send(self.fb_sock, cid, fdata)

            sleep = self.fb_dt - (time.perf_counter() - now)
            if sleep > 0:
                time.sleep(sleep)


def main():
    ap = argparse.ArgumentParser(description="Piper 가상로봇 (CAN<->sim)")
    ap.add_argument("--cmd-iface", default="vcan1", help="명령 수신 버스 (HW=can0)")
    ap.add_argument("--fb-iface", default="vcan0", help="피드백 송신 버스 (컨트롤러)")
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

    robot = VirtualRobot(backend, args.cmd_iface, args.fb_iface, args.fb_hz)
    try:
        robot.run()
    except KeyboardInterrupt:
        robot.running = False
        backend.close()
        print("\n[vrobot] stopped")


if __name__ == "__main__":
    main()
