#!/usr/bin/env python3
"""손인사(hand wave) v2 — v1(wave.py)에 ★실시간 속도 제어★ 추가.

작은 "속도%" 슬라이더 창을 같이 띄워서, 손인사 도중에 속도를 낮추면 천천히 움직이고,
그때 반사(센서 임계 초과 등)가 걸려 동작 "중간"에 멈추는지를 눈으로 볼 수 있다.
(속도가 빠르면 타이밍상 중간정지가 안 보임 — 느리게 = 보간을 흉내내 관찰 가능)

실행:  make run MODE=hil APP=motions/wave_v2.py
  - 디스플레이 있으면 속도창 뜸(슬라이더로 실시간 조절).
  - 디스플레이 없으면 SPEED 고정으로 그냥 실행(에러 없이).
"""
import os
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from motions.lib import motion_main  # noqa: E402

# ─── 데모 조절 ───────────────────────────────────────────────
WAVES   = 10      # 손목 흔드는 횟수
WAVE_T  = 0.65    # 한 번 흔드는 시간(s)
LOOP    = True    # True = 계속 반복 (Ctrl-C 종료)
SPEED   = 25      # % 시작 속도 (슬라이더로 실시간 변경)
# ────────────────────────────────────────────────────────────

READY = [0.0, -0.6, 0.6, 0.0, 0.0, 0.0]
POSES = [(READY, 1.2)]
for _ in range(WAVES):
    POSES.append(([0.0, -0.6, 0.6, 0.0,  0.6, 0.0], WAVE_T))   # →
    POSES.append(([0.0, -0.6, 0.6, 0.0, -0.6, 0.0], WAVE_T))   # ←
POSES.append((READY, 0.6))

# 실시간 공유 속도 (슬라이더가 바꾸고, motion_main 이 매 발행마다 읽음)
_speed = [SPEED]
def get_speed():
    return _speed[0]


def speed_gui():
    """작은 속도% 슬라이더 창. 디스플레이 없으면 조용히 포기(모션은 계속 돔)."""
    try:
        import tkinter as tk
        root = tk.Tk()
        root.title("wave 속도% (실시간)")
        tk.Label(root, text="손인사 속도 — 낮추면 천천히 (반사 중간정지 관찰)").pack(padx=10, pady=6)
        sv = tk.IntVar(value=SPEED)
        tk.Scale(root, from_=1, to=100, resolution=1, orient="horizontal", length=320,
                 variable=sv,
                 command=lambda v: _speed.__setitem__(0, int(float(v)))).pack(padx=10, pady=6)
        root.geometry("+80+80")
        root.lift()
        root.attributes("-topmost", True)
        root.mainloop()
    except Exception as e:
        print(f"[wave_v2] 속도창 못 띄움(디스플레이?) → SPEED={SPEED}% 고정 ({e})", flush=True)


if __name__ == "__main__":
    # 속도창은 별도 스레드(베스트에포트), 모션은 메인 스레드(rclpy 시그널 정상)
    threading.Thread(target=speed_gui, daemon=True).start()
    motion_main(POSES, speed=get_speed, loop=LOOP)
