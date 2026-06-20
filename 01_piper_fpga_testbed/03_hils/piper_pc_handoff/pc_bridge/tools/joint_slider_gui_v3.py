#!/usr/bin/env python3
"""관절 슬라이더 GUI v3 — v2에서 ★속도 슬라이더가 실제로 먹게★ 수정 (HIL/시뮬용).

[v2 문제] 속도% 슬라이더를 내려도 안 느려짐. 다른 동작은 정상.
  원인은 v2 코드가 아니라 ★시뮬 경로가 속도%를 안 쓴다★는 데 있었다:
    virtual_robot 은 관절각만 Gazebo 에 넘기고, velocity[6](=move_spd_rate, 속도%)는 버린다.
    (속도% 는 실로봇 펌웨어에서나 의미 → robot 슬라이더는 정상.)
  v2 는 슬라이더 값을 그대로 즉시 publish 했으므로, Gazebo 가 자기 속도로 즉시 추종 = 항상 빠름.

[v3 수정] 시뮬에서 진짜 느려지게: 슬라이더 값을 "goal" 로 받고, ★publish 하는 cmd 를
  속도%에 비례한 속도로 goal 쪽으로 보간(ramp)★한다. 속도 낮추면 천천히 추종 → 반사 중간정지 관찰.
  - SPEED_RATE_100 = 100%일 때 관절 각속도(rad/s). 실제 = SPEED_RATE_100 * speed/100.
  - 보간은 이미 도는 _tick(ROS 타이머, PUB_HZ)에서 수행 → 구조 변경 없음.
  - velocity[6]=속도% 발행은 유지(실로봇 move_spd_rate 호환).
  - 스레드 구조는 v2 그대로: tkinter=메인, rclpy.spin=데몬.

슬라이더 → 컨트롤러(piper_sdk) → 0x155-7 → bridge → 실제 FPGA → CAN → 가상로봇 → Gazebo.
실행(컨테이너 안, 파이프라인 떠 있는 상태): python3 tools/joint_slider_gui_v3.py
"""
import threading
import tkinter as tk

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
LIMIT = 2.0          # rad, 데모용 ±2.0 (실 Piper 한계 내)
PUB_HZ = 50          # 지속 발행(로봇이 목표 유지) + 보간 주기
SPEED_RATE_100 = 8.0 # 100%일 때 관절 각속도(rad/s). 낮출수록 전체가 느려짐


class SliderNode(Node):
    def __init__(self):
        super().__init__("joint_slider_gui")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)
        self.goal = [0.0] * 6     # 슬라이더가 정하는 목표
        self.cmd = [0.0] * 6      # 실제 발행하는 보간된 명령 (goal 로 ramp)
        self.grip = 0.0           # ★그리퍼 (position[6], m). 0=닫힘 ~ 0.07=열림
        self.speed = 100          # % (MotionCtrl 속도율). 낮추면 천천히 → 반사 중간정지 관찰
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        # cmd 를 goal 쪽으로 속도%에 비례해 이동 (시뮬에서 실제 속도를 만드는 부분)
        step = SPEED_RATE_100 * (self.speed / 100.0) / PUB_HZ
        for j in range(6):
            d = self.goal[j] - self.cmd[j]
            if abs(d) <= step:
                self.cmd[j] = self.goal[j]
            else:
                self.cmd[j] += step if d > 0 else -step

        m = JointState()
        m.name = JOINTS + ["gripper"]              # ★7번째 = 그리퍼
        m.position = list(self.cmd) + [self.grip]  # ★position[6]=그리퍼 → 컨트롤러가 0x159 GripperCtrl 로
        # velocity[6] = 속도율(%) → 실로봇 move_spd_rate 용(시뮬은 무시). 호환 위해 유지.
        m.velocity = [0.0] * 6 + [float(self.speed)]
        self.cmd_pub.publish(m)

    def enable(self, on=True):
        self.en_pub.publish(Bool(data=on))


def main():
    rclpy.init()
    node = SliderNode()
    spin = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin.start()

    root = tk.Tk()
    root.title("Piper 관절 슬라이더 v3 — HIL (속도제어 실동작)")
    tk.Label(root, text="슬라이더 → piper_sdk → 브리지 → 실제 Zybo CAN → Gazebo",
             font=("", 11, "bold")).grid(row=0, column=0, columnspan=3, pady=6)

    vars_ = []
    def on_move(i, val):
        node.goal[i] = float(val)      # ★목표만 갱신, 실제 추종은 _tick 보간★

    for i, name in enumerate(JOINTS):
        tk.Label(root, text=name, width=8).grid(row=i + 1, column=0, sticky="e")
        v = tk.DoubleVar(value=0.0)
        s = tk.Scale(root, from_=-LIMIT, to=LIMIT, resolution=0.01,
                     orient="horizontal", length=380, variable=v,
                     command=lambda val, idx=i: on_move(idx, val))
        s.grid(row=i + 1, column=1, padx=6, pady=2)
        vars_.append((v, s))

    # ★그리퍼 슬라이더 (position[6], m). 0=닫힘 ~ 0.07=열림. 컨트롤러가 0x159 GripperCtrl 로 변환
    tk.Label(root, text="그리퍼", width=8, fg="#a30").grid(row=7, column=0, sticky="e")
    grp = tk.DoubleVar(value=0.0)
    tk.Scale(root, from_=0.0, to=0.07, resolution=0.001, orient="horizontal", length=380,
             variable=grp, fg="#a30",
             command=lambda val: setattr(node, "grip", float(val))
             ).grid(row=7, column=1, padx=6, pady=2)

    # ★속도(%) — 낮추면 천천히 움직여 반사가 동작 중간을 끊는지 보임★
    tk.Label(root, text="속도%", width=8, fg="#06a").grid(row=8, column=0, sticky="e")
    spd = tk.IntVar(value=node.speed)
    tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=380,
             variable=spd, fg="#06a",
             command=lambda val: setattr(node, "speed", int(float(val)))
             ).grid(row=8, column=1, padx=6, pady=2)

    def reset():
        for v, s in vars_:
            s.set(0.0)
        for i in range(6):
            node.goal[i] = 0.0          # cmd 는 _tick 이 0 으로 천천히 ramp

    btns = tk.Frame(root)
    btns.grid(row=9, column=0, columnspan=3, pady=8)
    tk.Button(btns, text="● Enable", width=12, bg="#cfc",
              command=lambda: node.enable(True)).pack(side="left", padx=5)
    tk.Button(btns, text="○ Disable", width=12, bg="#fcc",
              command=lambda: node.enable(False)).pack(side="left", padx=5)
    tk.Button(btns, text="↺ 0 자세", width=12, command=reset).pack(side="left", padx=5)

    def on_close():
        node.destroy_node()
        rclpy.shutdown()
        root.destroy()
    root.protocol("WM_DELETE_WINDOW", on_close)

    # Gazebo 위에서 안 덮이게 맨앞 영구 유지
    root.geometry("+80+80")
    root.lift()
    root.attributes("-topmost", True)
    root.focus_force()

    def _keep_top():
        try:
            root.lift()
            root.attributes("-topmost", True)
        except Exception:
            return
        root.after(1500, _keep_top)
    root.after(1500, _keep_top)
    root.mainloop()


if __name__ == "__main__":
    main()
