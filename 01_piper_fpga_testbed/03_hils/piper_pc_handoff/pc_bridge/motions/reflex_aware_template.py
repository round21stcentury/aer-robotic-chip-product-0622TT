#!/usr/bin/env python3
# ============================================================================
# reflex_aware_template.py — 반사(reflex) 연동 트래젝토리 템플릿
# ----------------------------------------------------------------------------
#   ★ trajectory(t) 함수만 네 동작(뫼비우스/백앤포스 등)으로 바꾸면 끝.
#   설명: 반사연동_트래젝토리_가이드.md
#
#   상태머신 (반사 타이밍 정확히 처리):
#     RUNNING   평소 — trajectory(t) 발행
#     REFLEX    반사 중(/reflex_active=True) — 칩이 로봇 제어. ★현재각을 계속 발행해
#               메일박스를 warm 유지 → 칩이 손 떼는 순간 옛 명령으로 튀는 것 방지
#     SETTLING  반사 끝(False) 직후 — 로봇이 아직 움직일 수 있으니 ★실제로 멈출 때까지 대기★
#               (피드백이 settle_eps 안에서 settle_need 초 동안 안 변하면 "정지"로 판정)
#     RESUMING  로봇 정지 확인 → 현재 실제각에서 trajectory 로 smoothstep 보간(점프 방지)
#   → 반사 트리거 + 반사 동작이 완전히 끝난 뒤에야 새 트래젝토리를 내린다.
#
#   토픽: 구독 /reflex_active(Bool), /joint_states_feedback(JointState)
#         발행 /joint_ctrl_single(JointState, position rad, velocity[6]=속도율%), /enable_flag(Bool)
#   실행:  make run MODE=sim APP=motions/reflex_aware_template.py
#          (반사상태 받으려면 PC에서 tools/reflex_status_node.py 도 떠 있어야 함)
# ============================================================================
import math, argparse, rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
HOME   = [0.0, 0.8, -0.8, 0.0, 0.0, 0.0]


class ReflexAwareMotion(Node):
    def __init__(self, args):
        super().__init__("reflex_aware_motion")
        self.hz         = args.hz
        self.speed      = args.speed        # 이동 속도율(1~100). 실로봇은 낮게!
        self.resume_sec = args.resume       # 정지자세→트래젝토리 재진입 보간 시간(초)
        self.settle_eps  = 0.01             # rad. 이만큼도 안 움직이면 "멈춤"
        self.settle_need = 0.3              # 초. 이 동안 계속 안 움직이면 정지로 판정
        self.settle_max  = 3.0              # 초. 안전: 이 안에 안 멈춰도 강제 복귀

        self.cmd = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en  = self.create_publisher(Bool, "/enable_flag", 10)
        self.create_subscription(Bool, "/reflex_active", self.on_reflex, 10)
        self.create_subscription(JointState, "/joint_states_feedback", self.on_fb, 10)

        self.reflex  = False
        self.cur     = list(HOME)           # 로봇 실제 현재각(피드백)
        self.have_fb = False
        self.state   = "RUNNING"
        self.t       = 0.0                  # 트래젝토리 내부 시간 (반사 중엔 멈춤)
        self.hold    = list(HOME)           # SETTLING 중 명령할 고정 정지자세
        self.settle_ref = list(HOME); self.stable_t = 0.0; self.settle_el = 0.0
        self.resume_from = list(HOME); self.resume_t = 0.0

        for _ in range(5):
            self.en.publish(Bool(data=True))
        self.create_timer(1.0 / self.hz, self.tick)
        self.get_logger().info("reflex_aware_motion 시작 (RUNNING)")

    # ── 콜백 ──
    def on_fb(self, msg):                   # 로봇 실제 현재각 갱신
        if len(msg.position) >= 6:
            self.cur = list(msg.position[:6]); self.have_fb = True

    def on_reflex(self, msg):
        if msg.data and not self.reflex:                 # 정상 → 반사 (시작)
            self.state = "REFLEX"
            self.get_logger().info("★반사 발동 → 칩이 제어 (현재각 hold 발행, t 정지)")
        elif (not msg.data) and self.reflex:             # 반사 → 정상 (끝) — 아직 움직일 수 있음
            self.hold = list(self.cur)
            self.settle_ref = list(self.cur); self.stable_t = 0.0; self.settle_el = 0.0
            self.state = "SETTLING"
            self.get_logger().info("반사 해제 → 로봇 정지 대기 (SETTLING)")
        self.reflex = msg.data

    # ── ★★ 여기만 네 동작으로 바꿔라: 시간 t(초)에서의 목표 6관절각(rad) ──
    def trajectory(self, t):
        a = 0.6 * math.sin(2 * math.pi * 0.2 * t)        # 예시: joint1 좌우
        return [a, 0.8, -0.8, 0.0, 0.0, 0.0]

    # ── 메인 루프 ──
    def tick(self):
        self.en.publish(Bool(data=True))                 # ★enable 은 항상 유지
        dt = 1.0 / self.hz

        if self.state == "REFLEX":
            # 칩이 로봇 제어 중. 현재각을 계속 발행 → 메일박스 warm (gate 열릴 때 점프 방지)
            if self.have_fb:
                self.publish(self.cur)
            return

        if self.state == "SETTLING":
            self.publish(self.hold)                      # 멈춤 자세 고정 명령
            self.settle_el += dt
            delta = max(abs(self.cur[i] - self.settle_ref[i]) for i in range(6))
            if delta < self.settle_eps:
                self.stable_t += dt
            else:
                self.stable_t = 0.0; self.settle_ref = list(self.cur)
            if self.stable_t >= self.settle_need or self.settle_el >= self.settle_max:
                # ★반사 트리거 + 동작 완전 종료 확인됨 → 이제 새 트래젝토리 시작
                self.resume_from = list(self.cur); self.resume_t = 0.0
                self.state = "RESUMING"
                self.get_logger().info("로봇 정지 확인 → 재진입 (RESUMING)")
            return

        if self.state == "RESUMING":
            self.resume_t += dt
            r = min(1.0, self.resume_t / self.resume_sec)
            r = r * r * (3 - 2 * r)                       # smoothstep
            tgt = self.trajectory(self.t)                 # t 는 멈춰있던 지점 그대로 이어감
            goal = [(1 - r) * self.resume_from[i] + r * tgt[i] for i in range(6)]
            if r >= 1.0:
                self.state = "RUNNING"; self.get_logger().info("복귀 완료 (RUNNING)")
            self.publish(goal)
            return

        # RUNNING
        self.t += dt
        self.publish(self.trajectory(self.t))

    def publish(self, q6):
        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in q6]
        m.velocity = [0.0] * 6 + [float(self.speed)]      # ★[6]=속도율. 비우면 100%(위험)
        self.cmd.publish(m)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speed",  type=int,   default=30, help="이동 속도율 1~100 (실로봇 낮게)")
    ap.add_argument("--hz",     type=int,   default=50)
    ap.add_argument("--resume", type=float, default=1.5, help="반사 후 재진입 보간 시간(초)")
    args, _ = ap.parse_known_args()
    rclpy.init(); node = ReflexAwareMotion(args)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node(); rclpy.shutdown()


if __name__ == "__main__":
    main()
