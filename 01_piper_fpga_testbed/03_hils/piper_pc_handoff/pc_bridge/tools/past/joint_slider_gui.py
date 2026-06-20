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
        self.create_timer(1.0 / PUB_HZ, self._tick)

    def _tick(self):
        m = JointState()
        m.name = JOINTS
        m.position = list(self.targets)
        self.cmd_pub.publish(m)

    def enable(self, on=True):
        self.en_pub.publish(Bool(data=on))


def _dbg(m):
    print(f"[slider] {m}", flush=True)


def main():
    _dbg("start → rclpy.init()")
    rclpy.init()
    _dbg("rclpy OK → SliderNode 생성")
    node = SliderNode()
    spin = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin.start()

    _dbg("tk.Tk() 호출 — 여기서 막히면 X(DISPLAY) 연결 문제")
    root = tk.Tk()
    _dbg("tk.Tk() OK — 창 객체 생성됨")
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

    def reset():
        for v, s in vars_:
            s.set(0.0)
        for i in range(6):
            node.targets[i] = 0.0

    btns = tk.Frame(root)
    btns.grid(row=7, column=0, columnspan=3, pady=8)
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

    # ★Gazebo 위에서 안 덮이게: 맨앞을 "영구 유지" (1.5초마다 다시 올림)★
    #  (이전 버그: 0.8초만 맨앞→해제 → gazebo가 그 위를 덮어 "안 뜨는 것처럼" 보였음)
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

    _dbg("mainloop 진입 — 창 떠 있어야 정상(맨앞 영구유지)")
    root.mainloop()
    _dbg("mainloop 종료(창 닫힘)")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        import sys
        traceback.print_exc()
        sys.stderr.flush()
        print(f"[slider] FATAL: {e}", flush=True)
