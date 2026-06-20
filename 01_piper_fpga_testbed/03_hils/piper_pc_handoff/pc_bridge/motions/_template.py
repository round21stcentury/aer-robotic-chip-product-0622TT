#!/usr/bin/env python3
"""커스텀 동작 템플릿 — 이 파일 복사해서 POSES 만 채우면 sim/real 양쪽에서 바로 실행.

실행:  make run MODE=sim   APP=motions/내파일.py     # 시뮬(Gazebo)
       make run MODE=robot APP=motions/내파일.py     # ★실제 로봇★ (속도 낮게!)

자세 값은 슬라이더 GUI(make run APP=slider)로 좋은 값 찾아 여기 박으면 편함.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from motions.lib import motion_main  # noqa: E402

# ── 채워넣기: (관절1~6 rad, 유지초) ──
POSES = [
    ([0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 1.0),    # 기본 자세
    # ([0.3, -0.3, 0.4, 0.0, 0.2, 0.0], 1.5),  # 자세 추가 …
    # ([0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 1.0),
]
SPEED = 20      # % (★실로봇 안전: 낮게 시작★)
LOOP = False    # True 면 무한 반복

if __name__ == "__main__":
    motion_main(POSES, speed=SPEED, loop=LOOP)
