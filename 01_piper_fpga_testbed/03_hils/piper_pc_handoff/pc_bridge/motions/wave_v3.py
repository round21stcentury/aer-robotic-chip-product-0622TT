#!/usr/bin/env python3
"""손인사(hand wave) v3 — v2의 ★스레드 버그 수정판★.

[v2 문제] tkinter 속도창을 별도(데몬) 스레드에서 띄우고 모션을 메인 스레드에서 돌렸음.
  tkinter 는 thread-safe 가 아니라 ★메인 스레드에서만★ 돌려야 한다. 비메인 스레드의 Tk 는
  Tcl/X 빌드에 따라 예외(이건 except 로 잡힘)거나 행/세그폴트(이건 못 잡음 → 프로세스째 죽어
  모션도 같이 안 돎)로 끝난다. 그래서 "속도조절 넣었더니 동작 안 함"이 났다.

[v3 수정] 정상 동작하는 joint_slider_gui_v2.py 와 ★같은 구조★로 뒤집었다:
  - rclpy.init() 과 tkinter mainloop 은 ★메인 스레드★.
  - rclpy.spin 은 데몬 스레드. 목표자세는 ROS 타이머(_tick)가 PUB_HZ 로 지속 발행(로봇이 유지).
  - 손인사 시퀀스 진행은 블로킹 루프가 아니라 root.after() 이벤트로(메인 스레드, GUI와 공존).
  - 디스플레이가 없으면 GUI 없이 메인 스레드에서 시퀀스만 돌린다(SPEED 고정, 안전 폴백).

실행:  make run MODE=hil APP=motions/wave_v3.py
"""
import threading
import time

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
PUB_HZ = 50          # 목표자세 지속 발행 주기(로봇이 목표 유지) — slider_v2 와 동일

# ─── 데모 조절 ───────────────────────────────────────────────
WAVES   = 10      # 손목 흔드는 횟수
WAVE_T  = 0.65    # 한 번 흔드는 시간(s)
LOOP    = True    # True = 계속 반복 (창 닫기/Ctrl-C 종료)
SPEED   = 25      # % 시작 속도 (슬라이더로 실시간 변경)
# ────────────────────────────────────────────────────────────

READY = [0.0, -0.6, 0.6, 0.0, 0.0, 0.0]
POSES = [(READY, 1.2)]
for _ in range(WAVES):
    POSES.append(([0.0, -0.6, 0.6, 0.0,  0.6, 0.0], WAVE_T))   # →
    POSES.append(([0.0, -0.6, 0.6, 0.0, -0.6, 0.0], WAVE_T))   # ←
POSES.append((READY, 0.6))


class WaveNode(Node):
    """slider_v2.SliderNode 와 같은 발행 규약 — 목표를 PUB_HZ 로 지속 발행."""
    def __init__(self):
        super().__init__("hils_wave")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)
        self.target = list(READY)
        self.speed = SPEED        # % (MotionCtrl 속도율). 슬라이더로 실시간 변경
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in self.target[:6]]
        # velocity[6] = 속도율(%) → 컨트롤러가 MotionCtrl 속도로 사용 (없으면 100%)
        m.velocity = [0.0] * 6 + [float(self.speed)]
        self.cmd_pub.publish(m)

    def enable(self, on=True):
        self.en_pub.publish(Bool(data=on))


def main():
    rclpy.init()
    node = WaveNode()
    spin = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin.start()
    time.sleep(0.5)

    # 모터 enable (motion_main 과 동일하게 몇 번 발행)
    for _ in range(3):
        node.enable(True)
        time.sleep(0.2)
    node.get_logger().info("enable 발행")

    # ── GUI 있으면: Tk(메인 스레드) + after() 로 시퀀스 진행 ──
    try:
        import tkinter as tk
    except Exception as e:
        tk = None
        node.get_logger().warn(f"tkinter 없음 → GUI 없이 진행 ({e})")

    if tk is not None:
        try:
            root = tk.Tk()
        except Exception as e:
            # 디스플레이 없음 등 → 폴백
            node.get_logger().warn(f"속도창 못 띄움(디스플레이?) → SPEED={SPEED}% 고정 ({e})")
            _run_headless(node)
            return

        root.title("wave 속도% (실시간)")
        tk.Label(root, text="손인사 속도 — 낮추면 천천히 (반사 중간정지 관찰)").pack(padx=10, pady=6)
        spd = tk.IntVar(value=node.speed)
        tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=320,
                 variable=spd,
                 command=lambda v: setattr(node, "speed", int(float(v)))).pack(padx=10, pady=6)

        # 손인사 시퀀스를 after() 로 한 자세씩 진행 (메인 스레드, mainloop 과 공존)
        state = {"i": 0}

        def step():
            if state["i"] >= len(POSES):
                if not LOOP:
                    return
                state["i"] = 0
            pos, hold = POSES[state["i"]]
            node.target = list(pos)
            node.get_logger().info(f"→ {[round(x,2) for x in pos]} ({hold}s @ {node.speed}%)")
            state["i"] += 1
            root.after(int(hold * 1000), step)

        def on_close():
            node.destroy_node()
            rclpy.shutdown()
            root.destroy()
        root.protocol("WM_DELETE_WINDOW", on_close)

        root.geometry("+80+80")
        root.lift()
        root.attributes("-topmost", True)
        root.after(0, step)
        root.mainloop()
    else:
        _run_headless(node)


def _run_headless(node):
    """GUI 없이 메인 스레드에서 시퀀스만 진행 (속도 SPEED 고정)."""
    try:
        first = True
        while first or LOOP:
            first = False
            for pos, hold in POSES:
                node.target = list(pos)
                node.get_logger().info(f"→ {[round(x,2) for x in pos]} ({hold}s @ {node.speed}%)")
                time.sleep(hold)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info("모션 종료")
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
