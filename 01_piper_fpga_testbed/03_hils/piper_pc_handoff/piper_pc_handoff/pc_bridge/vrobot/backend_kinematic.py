#!/usr/bin/env python3
"""가상로봇 시뮬 백엔드 A — 순수 운동학 echo (의존성 0).

명령 목표각을 그대로(또는 1차 지연으로) 현재각에 반영. ROS/Gazebo 없이
CAN 루프(명령 디코드 -> 피드백 인코드)를 닫아 1·2단계 검증에 사용.
"""
import math


class KinematicBackend:
    def __init__(self, tau: float = 0.0):
        """tau: 1차 지연 시상수(초). 0이면 즉시 목표각 도달(echo)."""
        self.tau = tau
        self.target = [0.0] * 6   # rad
        self.state = [0.0] * 6    # rad
        self.enabled = False

    def set_targets(self, rad6):
        self.target = list(rad6)

    def set_enable(self, on: bool):
        self.enabled = on

    def get_state(self):
        return list(self.state)

    def spin_once(self, dt: float):
        if self.tau <= 0.0:
            self.state = list(self.target)
            return
        a = 1.0 - math.exp(-dt / self.tau)
        self.state = [s + a * (t - s) for s, t in zip(self.state, self.target)]

    def reached(self, tol_rad: float = 1e-3) -> bool:
        return all(abs(t - s) < tol_rad for t, s in zip(self.target, self.state))

    def close(self):
        pass
