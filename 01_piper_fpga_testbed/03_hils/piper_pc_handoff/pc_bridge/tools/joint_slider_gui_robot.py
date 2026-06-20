#!/usr/bin/env python3
"""관절 슬라이더 GUI — /joint_ctrl_single 로 발행해 HIL 루프를 대화형으로 구동.

슬라이더를 움직이면 → 컨트롤러(piper_sdk) → 0x155-7 → bridge → 실제 FPGA → CAN
  → 가상로봇 → Gazebo 로봇 이동. (스크립트 자세 대신 사람이 직접 조종)

컨테이너 안에서 디스플레이와 함께 실행 (stage3b 파이프라인이 떠 있는 상태에서):
  python3 tools/joint_slider_gui.py
"""
import threading
import tkinter as tk

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
LIMIT = 2.0          # rad, 데모용 ±2.0 (실 Piper 한계 내)
PUB_HZ = 50          # 지속 발행(로봇이 목표 유지)


class SliderNode(Node):
    def __init__(self):
        super().__init__("joint_slider_gui")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)
        self.targets = [0.0] * 6
        self.grip = 0.0          # ★그리퍼 (position[6], m). 0=닫힘 ~ 0.07=열림
        self.speed = 20          # % (MotionCtrl 속도율). ★실로봇 안전: 기본 낮게★
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        m = JointState()
        m.name = JOINTS + ["gripper"]                   # ★7번째 = 그리퍼
        m.position = list(self.targets) + [self.grip]   # ★position[6]=그리퍼 → 컨트롤러가 0x159 GripperCtrl 로
        # velocity[6] = 속도율(%) → 컨트롤러가 MotionCtrl_2 속도로 사용 (실로봇 속도제한/부드러움)
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
    root.title("Piper 관절 슬라이더 — HIL (명령이 실제 FPGA CAN을 거침)")
    tk.Label(root, text="슬라이더 → piper_sdk → 브리지 → 실제 Zybo CAN → Gazebo",
             font=("", 11, "bold")).grid(row=0, column=0, columnspan=3, pady=6)

    vars_ = []
    def on_move(i, val):
        node.targets[i] = float(val)

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

    # 속도(%) — ★실로봇 안전: 낮게 시작, 천천히 올릴 것★
    tk.Label(root, text="속도%", width=8, fg="#a00").grid(row=8, column=0, sticky="e")
    spd = tk.IntVar(value=node.speed)
    tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=380,
             variable=spd, fg="#a00",
             command=lambda val: setattr(node, "speed", int(float(val)))
             ).grid(row=8, column=1, padx=6, pady=2)

    def reset():
        for v, s in vars_:
            s.set(0.0)
        for i in range(6):
            node.targets[i] = 0.0

    btns = tk.Frame(root)
    btns.grid(row=9, column=0, columnspan=3, pady=8)
    tk.Button(btns, text="● Enable", width=12, bg="#cfc",
              command=lambda: node.enable(True)).pack(side="left", padx=5)
    tk.Button(btns, text="○ Disable", width=12, bg="#fcc",
              command=lambda: node.enable(False)).pack(side="left", padx=5)
    tk.Button(btns, text="↺ 0 자세", width=12,
              command=reset).pack(side="left", padx=5)

    def on_close():
        node.destroy_node()
        rclpy.shutdown()
        root.destroy()
    root.protocol("WM_DELETE_WINDOW", on_close)

    # ★Gazebo 큰 창 뒤에 가려지지 않게: 생성 시 맨 앞으로 끌어올림★
    root.geometry("+60+60")          # 좌상단쯤에 배치
    root.lift()
    root.attributes("-topmost", True)
    root.focus_force()
    root.after(800, lambda: root.attributes("-topmost", False))  # 잠깐 위로 → 이후 일반 동작
    root.mainloop()


if __name__ == "__main__":
    main()
