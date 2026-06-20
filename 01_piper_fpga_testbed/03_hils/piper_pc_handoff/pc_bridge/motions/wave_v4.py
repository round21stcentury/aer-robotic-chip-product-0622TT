#!/usr/bin/env python3
"""손인사(hand wave) v4 — v3에서 ★속도 슬라이더가 실제로 먹게★ 수정.

[v3 문제] 속도 슬라이더를 내려도 안 느려짐 (계속 빠름).
  원인은 v3 코드가 아니라 ★HIL/Gazebo 경로가 속도%를 안 쓴다★는 데 있었다:
    - virtual_robot 은 관절각(0x155-7)만 backend.set_targets() 로 반영. 백엔드(Gazebo)는
      목표각만 받고 자기 컨트롤러 속도로 움직인다.
    - MOTION_CTRL_2(0x151) 핸들러는 ctrl_mode 만 읽고 move_spd_rate(속도%)는 버린다.
    => velocity[6] 로 보낸 속도% 는 시뮬에서 소비처가 없다(실로봇 move_spd_rate 에서나 의미).
  v3 는 자세를 0.65s 고정 간격(root.after)으로 휙휙 바꿨으므로, 슬라이더와 무관하게 항상 같은 속도였다.

[v4 수정] 시뮬에서 진짜 느려지게: ★목표각 자체를 속도%에 비례한 속도로 보간(ramp)★해서
  중간 목표를 흘린다. 관절이 천천히 이동 → 반사 "중간정지"도 관찰 가능.
  - SPEED_RATE_100 = 100% 일 때 관절 각속도(rad/s). 실제 = SPEED_RATE_100 * speed/100.
  - 보간 tick(TICK_MS)마다 현재 명령각 cur 를 goal 쪽으로 step=rate*dt 만큼 이동.
  - 구조는 v3(=slider_v2)와 동일: Tk·rclpy.init = 메인 스레드, spin = 데몬, 발행 = ROS 타이머.
  - velocity[6]=속도% 발행은 유지(실로봇 move_spd_rate 호환). 시뮬에선 보간이 속도를 만든다.

실행:  make run MODE=hil APP=motions/wave_v4.py
"""
import threading
import time

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
PUB_HZ = 50          # 목표자세 지속 발행 주기 (로봇이 목표 유지)

# ─── 데모 조절 ───────────────────────────────────────────────
WAVES          = 10      # 손목 흔드는 횟수
LOOP           = True    # True = 계속 반복 (창 닫기/Ctrl-C 종료)
SPEED          = 25      # % 시작 속도 (슬라이더로 실시간 변경)
SPEED_RATE_100 = 3.0     # 100%일 때 관절 각속도(rad/s). 낮출수록 전체가 느려짐
TICK_MS        = 33      # 보간 주기(ms) ≈ 30Hz
# ────────────────────────────────────────────────────────────

READY = [0.0, -0.6, 0.6, 0.0,  0.0, 0.0]
RIGHT = [0.0, -0.6, 0.6, 0.0,  0.6, 0.0]   # 손목 →
LEFT  = [0.0, -0.6, 0.6, 0.0, -0.6, 0.0]   # 손목 ←

GOALS = [list(READY)]
for _ in range(WAVES):
    GOALS.append(list(RIGHT))
    GOALS.append(list(LEFT))
GOALS.append(list(READY))


class WaveNode(Node):
    """slider_v2.SliderNode 와 같은 발행 규약 — 목표를 PUB_HZ 로 지속 발행."""
    def __init__(self):
        super().__init__("hils_wave")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)
        self.target = list(READY)   # 보간된 현재 명령각 (메인 스레드가 갱신)
        self.speed = SPEED          # % — 슬라이더로 실시간 변경
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in self.target[:6]]
        # velocity[6] = 속도율(%) → 실로봇 move_spd_rate 용(시뮬은 무시). 호환 위해 유지.
        m.velocity = [0.0] * 6 + [float(self.speed)]
        self.cmd_pub.publish(m)

    def enable(self, on=True):
        self.en_pub.publish(Bool(data=on))


def _advance(cur, goal, step):
    """cur 를 goal 쪽으로 관절당 최대 step 만큼 이동(제자리 수정). 모두 도달하면 True."""
    reached = True
    for j in range(6):
        d = goal[j] - cur[j]
        if abs(d) <= step:
            cur[j] = goal[j]
        else:
            cur[j] += step if d > 0 else -step
            reached = False
    return reached


def main():
    rclpy.init()
    node = WaveNode()
    spin = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin.start()
    time.sleep(0.5)

    for _ in range(3):              # 모터 enable
        node.enable(True)
        time.sleep(0.2)
    node.get_logger().info("enable 발행")

    try:
        import tkinter as tk
    except Exception as e:
        tk = None
        node.get_logger().warn(f"tkinter 없음 → GUI 없이 진행 ({e})")

    if tk is not None:
        try:
            root = tk.Tk()
        except Exception as e:
            node.get_logger().warn(f"속도창 못 띄움(디스플레이?) → SPEED={SPEED}% 고정 ({e})")
            _run_headless(node)
            return

        root.title("wave 속도% (실시간) v4")
        tk.Label(root, text="손인사 속도 — 낮추면 천천히 (반사 중간정지 관찰)").pack(padx=10, pady=6)
        tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=320,
                 variable=tk.IntVar(value=node.speed),
                 command=lambda v: setattr(node, "speed", int(float(v)))).pack(padx=10, pady=6)

        cur = list(READY)
        st = {"gi": 0}
        dt = TICK_MS / 1000.0

        def tick():
            goal = GOALS[st["gi"]]
            step = SPEED_RATE_100 * (node.speed / 100.0) * dt
            if _advance(cur, goal, step):
                st["gi"] += 1
                if st["gi"] >= len(GOALS):
                    if not LOOP:
                        node.target = list(cur)
                        return
                    st["gi"] = 0
            node.target = list(cur)
            root.after(TICK_MS, tick)

        def on_close():
            node.destroy_node()
            rclpy.shutdown()
            root.destroy()
        root.protocol("WM_DELETE_WINDOW", on_close)

        root.geometry("+80+80")
        root.lift()
        root.attributes("-topmost", True)
        root.after(0, tick)
        root.mainloop()
    else:
        _run_headless(node)


def _run_headless(node):
    """GUI 없이 메인 스레드에서 보간 진행 (속도 SPEED 고정)."""
    cur = list(READY)
    gi = 0
    dt = TICK_MS / 1000.0
    try:
        while rclpy.ok():
            goal = GOALS[gi]
            step = SPEED_RATE_100 * (node.speed / 100.0) * dt
            if _advance(cur, goal, step):
                gi += 1
                if gi >= len(GOALS):
                    if not LOOP:
                        node.target = list(cur)
                        break
                    gi = 0
            node.target = list(cur)
            time.sleep(dt)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info("모션 종료")
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
