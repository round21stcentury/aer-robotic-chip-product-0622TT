#!/usr/bin/env python3
"""mobius — 뫼비우스 띠 느낌의 robot policy. 관절공간 figure-8(∞) + 손목 트위스트.

진짜 3D 뫼비우스는 Cartesian IK 가 필요하지만, 관절을 서로 다른 주파수/위상의 사인파로
구동하면(리사주) ∞ 모양 루프 + 손목 반바퀴 트위스트로 "꼬이며 도는 띠"처럼 보인다.
  - 2배 주파수 성분이 figure-8 을, 손목 roll(j6) 의 2배 트위스트가 뫼비우스 리본 느낌을 줌.

정책 규약은 back_and_forth 와 동일(/joint_ctrl_single + /enable_flag). 사인파라 별도 보간 불필요
— 50Hz 로 매 tick 함수값을 그대로 발행(연속·매끈). 시작 2초는 home→궤적으로 ease-in.

실행 (컨테이너 안, ROS 소싱 후):
  python3 motions/mobius.py [--period 8] [--scale 1.0] [--hz 50]
"""
import argparse
import math

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]

# 관절 한계 내 진폭/중심 (j1[-2.62,2.62] j2[0,3.14] j3[-2.97,0] j4[±1.75] j5[±1.22] j6[±2.09])
def trajectory(phase, scale):
    """phase = 2π·t/period (한 바퀴=2π). 반환: 6관절 목표각(rad)."""
    s, c = math.sin(phase), math.cos(phase)
    s2, c2 = math.sin(2 * phase), math.cos(2 * phase)
    return [
        scale * 0.8 * s,                 # j1 베이스 좌우 (1x)
        0.9 + scale * 0.35 * s2,         # j2 어깨 상하 (2x → figure-8)
        -0.9 + scale * 0.30 * c2,        # j3 팔꿈치 (2x, 90° 위상)
        scale * 0.5 * c,                 # j4 (1x, 90° 위상)
        scale * 0.4 * s2,                # j5 손목 피치 (2x)
        scale * 1.1 * s2,                # j6 손목 roll 트위스트 (2x → 뫼비우스 리본)
    ]


class Mobius(Node):
    def __init__(self, period, scale, hz):
        super().__init__("robot_policy_mobius")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)
        self.period = period
        self.scale = scale
        self.t = 0.0
        self.dt = 1.0 / hz
        self.ease_t = 2.0           # 시작 ease-in 시간(초)
        self._enable_ticks = 5
        self.create_timer(self.dt, self._tick)
        self.get_logger().info(f"mobius: period={period}s scale={scale} hz={hz}")

    def _tick(self):
        if self._enable_ticks > 0:
            self.en_pub.publish(Bool(data=True))
            self._enable_ticks -= 1

        phase = 2.0 * math.pi * (self.t / self.period)
        goal = trajectory(phase, self.scale)
        # home(0)→궤적 ease-in (시작 점프 방지)
        e = min(1.0, self.t / self.ease_t)
        pos = [e * g for g in goal]

        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in pos]
        m.velocity = [0.0] * 6 + [50.0]   # 속도%(실로봇용); sim 은 무시
        self.cmd_pub.publish(m)
        self.t += self.dt


def main():
    ap = argparse.ArgumentParser(description="mobius (figure-8 + twist) policy")
    ap.add_argument("--period", type=float, default=8.0, help="한 바퀴 주기(초). 클수록 천천히")
    ap.add_argument("--scale", type=float, default=1.0, help="전체 진폭 배율 0~1.2")
    ap.add_argument("--hz", type=float, default=50.0)
    args = ap.parse_args()

    rclpy.init()
    node = Mobius(args.period, args.scale, args.hz)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
