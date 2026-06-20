#!/usr/bin/env python3
"""손인사(hand wave) 동작 — 팔 들고 손목을 좌우로 흔든다. sim/real 공용.

실행:  make motion MODE=hil M=wave        # HIL(시뮬) 손인사 — ★DIP 반사 데모★
       make motion MODE=robot M=wave      # 실제 로봇 (속도 낮게 확인 후)

※ 길이/속도는 아래 "데모 조절" 숫자만 바꾸면 됨.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from motions.lib import motion_main  # noqa: E402

# ─── 데모 조절 (여기만 바꾸면 됨) ────────────────────────────
WAVES   = 10      # 손목 흔드는 횟수 (많을수록 길어짐)
WAVE_T  = 0.65    # 한 번 흔드는 시간(s) (클수록 천천히/길게)
LOOP    = True    # ★True = 계속 반복(Ctrl-C로 종료) — DIP 누를 시간 충분, 데모 권장★
SPEED   = 25      # % (MotionCtrl 속도율, 실로봇은 낮게)
# ────────────────────────────────────────────────────────────

# 팔을 들어 인사 준비 자세 (joint2/3 으로 들어올림)
READY = [0.0, -0.6, 0.6, 0.0, 0.0, 0.0]

POSES = [
    (READY, 1.2),                                    # 준비 자세로
]
# 손목(joint5)을 좌우로 WAVES 번 흔들기
for _ in range(WAVES):
    POSES.append(([0.0, -0.6, 0.6, 0.0,  0.6, 0.0], WAVE_T))   # →
    POSES.append(([0.0, -0.6, 0.6, 0.0, -0.6, 0.0], WAVE_T))   # ←
POSES.append((READY, 0.6))                           # 다시 준비 자세
# (LOOP=True 면 위 시퀀스를 계속 반복 = 끝없이 손인사. Ctrl-C 로 종료.)
# (한 번만 하고 원위치로 끝내려면 LOOP=False + 아래 줄 주석 해제)
# POSES.append(([0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 1.2))

if __name__ == "__main__":
    motion_main(POSES, speed=SPEED, loop=LOOP)
