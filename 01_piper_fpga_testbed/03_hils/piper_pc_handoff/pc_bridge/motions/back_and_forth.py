#!/usr/bin/env python3
"""back_and_forth — 가장 단순한 robot policy. 두 자세 사이를 일정 각속도로 왕복.

핵심 (wave_v4 에서 가져온 교훈):
  - 명령 토픽 = /joint_ctrl_single (JointState, position=관절각 rad), enable = /enable_flag (Bool).
    → 우리 컨트롤러(piper_single_ctrl)와 동일 규약.
  - ★sim 에선 속도%가 소비되지 않는다★ (virtual_robot 은 목표각만 backend 에 전달).
    그래서 '천천히'를 만들려면 policy 가 ★목표각을 직접 보간(ramp)해 스트리밍★ 한다.
    (velocity[6]=속도% 는 실로봇 move_spd_rate 호환용으로 같이 실어 보냄 — sim 은 무시)
  - CAN 위에는 항상 '절대 목표각'만 흐른다. 이 노드가 매 tick 흘리는 cur 이 곧 그 절대 목표.

단일 스레드: 발행 타이머 + 보간 타이머 + rclpy.spin (스레드/Tk 불필요).
실행 (컨테이너 안, ROS 소싱 후):
  python3 motions/back_and_forth.py [--speed 0.6] [--hz 50] [--hold 0.3]
"""
import argparse
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]

# 고정 자세(스윙 축 외 관절은 그대로). JointCtrl 한계 내:
#   j1[-2.62,2.62] j2[0,3.14] j3[-2.97,0] j4[-1.75,1.75] j5[-1.22,1.22] j6[-2.09,2.09]
POSTURE = [0.0, 0.8, -0.8, 0.0, 0.0, 0.0]   # 팔을 적당히 든 자세
SWING_JOINT = 0                              # 0=joint1(베이스 좌우 회전). 4=joint5(손목)


def _pose(swing_joint, amp):
    """POSTURE 에서 swing_joint 만 amp 로 바꾼 자세."""
    p = list(POSTURE)
    p[swing_joint] = amp
    return p


class BackAndForth(Node):
    def __init__(self, speed, hz, hold, pose_a, pose_b):
        super().__init__("robot_policy_back_and_forth")
        self.cmd_pub = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en_pub = self.create_publisher(Bool, "/enable_flag", 10)

        self.speed = speed          # rad/s — 보간 각속도(= sim 에서 실제 동작 속도)
        self.hold = hold            # 자세 도달 후 멈춤 시간(초)
        self.poses = [pose_a, pose_b]
        self.gi = 1                 # 다음 목표 인덱스 (A 에서 시작 → B 로)
        self.cur = list(pose_a)     # 현재 보간된 명령각 (= 흘려보내는 절대 목표)
        self.hold_left = 0.0

        self.dt = 1.0 / 30.0        # 보간 tick
        self._enable_ticks = 5      # 시작 시 enable 몇 번 발행

        self.create_timer(1.0 / hz, self._publish)   # 목표 지속 발행 (로봇이 유지)
        self.create_timer(self.dt, self._interp)     # 목표각 보간 진행
        self.get_logger().info(
            f"back_and_forth: speed={speed}rad/s hz={hz} hold={hold}s")

    def _publish(self):
        if self._enable_ticks > 0:
            self.en_pub.publish(Bool(data=True))
            self._enable_ticks -= 1
        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in self.cur]
        # velocity[6] = 속도%(실로봇 move_spd_rate 호환). sim 은 무시, 보간이 속도를 만든다.
        m.velocity = [0.0] * 6 + [float(max(1, min(100, int(self.speed / 3.0 * 100))))]
        self.cmd_pub.publish(m)

    def _interp(self):
        if self.hold_left > 0.0:
            self.hold_left -= self.dt
            return
        goal = self.poses[self.gi]
        step = self.speed * self.dt
        reached = True
        for j in range(6):
            d = goal[j] - self.cur[j]
            if abs(d) <= step:
                self.cur[j] = goal[j]
            else:
                self.cur[j] += step if d > 0 else -step
                reached = False
        if reached:
            self.gi = 1 - self.gi          # 반대 자세로 토글 → 왕복
            self.hold_left = self.hold


def main():
    ap = argparse.ArgumentParser(description="back-and-forth robot policy")
    ap.add_argument("--speed", type=float, default=0.6, help="보간 각속도 rad/s (느리게=작게)")
    ap.add_argument("--hz", type=float, default=50.0, help="목표 발행 주기")
    ap.add_argument("--hold", type=float, default=0.0, help="끝점 멈춤(초). 0=계속 좌우 왕복")
    ap.add_argument("--amp", type=float, default=0.8, help="좌우 스윙 진폭(rad)")
    ap.add_argument("--swing-joint", type=int, default=SWING_JOINT,
                    help="흔들 관절 인덱스 0~5 (0=베이스 좌우, 4=손목)")
    args = ap.parse_args()

    pose_a = _pose(args.swing_joint, +args.amp)   # 한쪽 끝
    pose_b = _pose(args.swing_joint, -args.amp)   # 반대쪽 끝
    rclpy.init()
    node = BackAndForth(args.speed, args.hz, args.hold, pose_a, pose_b)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
