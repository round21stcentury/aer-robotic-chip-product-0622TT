#!/usr/bin/env python3
"""관절 슬라이더 GUI v2 — HIL 루프 대화형 구동 + ★속도(%) 제어 추가★.

v1(joint_slider_gui.py)에서 추가: 속도 슬라이더.
  슬라이더를 천천히 움직이게 해서, 동작 "도중"에 반사(예: 센서 임계 초과)가
  걸려 로봇이 중간에 멈추는지를 눈으로 확인할 수 있다. (빠르면 타이밍상 안 보임)

슬라이더 → 컨트롤러(piper_sdk) → 0x155-7 → bridge → 실제 FPGA → CAN → 가상로봇 → Gazebo.
실행(컨테이너 안, 파이프라인 떠 있는 상태): python3 tools/joint_slider_gui_v2.py
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
        self.speed = 100        # % (MotionCtrl 속도율). 낮추면 천천히 → 반사 중간정지 관찰
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        m = JointState()
        m.name = JOINTS
        m.position = list(self.targets)
        # velocity[6] = 속도율(%) → 컨트롤러가 MotionCtrl 속도로 사용 (없으면 100%)
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
    root.title("Piper 관절 슬라이더 v2 — HIL (속도제어)")
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

    # ★속도(%) — 낮추면 천천히 움직여 반사가 동작 중간을 끊는지 보임★
    tk.Label(root, text="속도%", width=8, fg="#06a").grid(row=7, column=0, sticky="e")
    spd = tk.IntVar(value=node.speed)
    tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=380,
             variable=spd, fg="#06a",
             command=lambda val: setattr(node, "speed", int(float(val)))
             ).grid(row=7, column=1, padx=6, pady=2)

    def reset():
        for v, s in vars_:
            s.set(0.0)
        for i in range(6):
            node.targets[i] = 0.0

    btns = tk.Frame(root)
    btns.grid(row=8, column=0, columnspan=3, pady=8)
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
