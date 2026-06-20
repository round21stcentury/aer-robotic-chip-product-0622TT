#!/usr/bin/env python3
# ============================================================================
# reflex_pursue.py — 반사 연동 "목표 추구" 정책 (Cartesian goal + IK)
# ----------------------------------------------------------------------------
#   행동: 고정된 end pose(goal)를 매번 '조금씩 다른 경로/자세'로 grip 하러 간다.
#         반사(/reflex_active)가 들어오면 → 로봇이 멈출 때까지 대기 → HOME 복귀
#         → ★막혔던 길과 다른★ 새 random 경로로 다시 goal 추구. (강아지가 다른 길로)
#
#   "random" = 막 헤매는 게 아니라, goal 로 단조 접근하되(s:0→1) 도중 자세가
#   에피소드마다 다른 '단일 아치' 우회(sin(πs)·perp). 끝(s=1)에서는 항상 goal 정확.
#
#   제어는 관절각이라 Cartesian goal 은 ikpy 로 IK. 에피소드 시작 시 경로를
#   미리 IK(이전 해 seed=연속성) → 관절 웨이포인트 → 50Hz 매끈 재생.
#
#   상태머신 (reflex_aware_template 골격 재사용):
#     PURSUE   에피소드 재생(goal 추구)
#     REFLEX   /reflex_active=True — 발행 중지(칩 제어), 현재각 hold
#     SETTLING True→False — 로봇이 실제로 멈출 때까지 피드백으로 대기
#     GOHOME   현재(반사)자세 → HOME smoothstep 복귀
#     ATGOAL   goal 도달 → 그 자세 유지 (home 복귀·재추구는 ★반사 때만★)
#   토픽: 구독 /reflex_active, /joint_states_feedback / 발행 /joint_ctrl_single, /enable_flag
#   필요: pip install ikpy  (+ piper URDF)
# ============================================================================
import argparse
import math

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool
from ikpy.chain import Chain

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]
HOME   = [0.0, 0.8, -0.8, 0.0, 0.0, 0.0]
# JointCtrl 한계
LIM = [(-2.6179, 2.6179), (0.0, 3.14), (-2.967, 0.0),
       (-1.745, 1.745), (-1.22, 1.22), (-2.0944, 2.0944)]
URDF_DEFAULT = ("/root/ros2_ws/src/piper_ros/src/piper_description/"
                "urdf/piper_no_gripper_description.urdf")


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def clamp_q(q):
    return [min(LIM[i][1], max(LIM[i][0], q[i])) for i in range(6)]


class ReflexPursue(Node):
    def __init__(self, a):
        super().__init__("reflex_pursue")
        self.hz = a.hz
        self.speed = a.speed
        self.resume_sec = a.resume
        self.ep_dur = a.episode          # 한 에피소드(home→goal) 시간(초)
        self.hold_sec = a.hold
        self.bump = a.bump               # 우회 아치 크기(m)
        self.grip_close = a.grip_close   # 항상 닫힘 값(m). 0=완전닫힘
        self.n_wp = 70                   # 에피소드 웨이포인트 수
        self.max_step = 0.18             # 웨이포인트 간 관절변화 상한(rad). 넘으면 진폭↓/직선 폴백
        # settle 판정 (템플릿과 동일)
        self.settle_eps, self.settle_need, self.settle_max = 0.01, 0.3, 3.0

        # ── IK 체인 ──
        self.chain = Chain.from_urdf_file(a.urdf)
        self.ee_home = self._fk(HOME)
        if a.goal is not None:
            self.goal = np.array(a.goal, dtype=float)
        else:
            self.goal = self.ee_home + np.array(a.goal_offset, dtype=float)
        self.get_logger().info(
            f"EE(home)={np.round(self.ee_home,3)}  GOAL={np.round(self.goal,3)}")

        self.cmd = self.create_publisher(JointState, "/joint_ctrl_single", 10)
        self.en  = self.create_publisher(Bool, "/enable_flag", 10)
        self.create_subscription(Bool, "/reflex_active", self.on_reflex, 10)
        self.create_subscription(JointState, "/joint_states_feedback", self.on_fb, 10)

        self.reflex = False
        self.cur = list(HOME)
        self.have_fb = False
        self.last_perp = None            # 직전 에피소드 우회 방향 (다음엔 다르게)
        self.rng = np.random.default_rng(a.seed)

        self.state = "PURSUE"
        self.ep_qs = self._make_episode(HOME)   # 첫 에피소드 (home 출발)
        self.ep_phase = 0.0
        self.hold_t = 0.0
        self.settle_ref = list(HOME); self.stable_t = 0.0; self.settle_el = 0.0
        self.resume_from = list(HOME); self.resume_t = 0.0

        for _ in range(5):
            self.en.publish(Bool(data=True))
        self.create_timer(1.0 / self.hz, self.tick)
        self.get_logger().info("reflex_pursue 시작 (PURSUE)")

    # ── kinematics ──
    def _fk(self, q6):
        return self.chain.forward_kinematics([0.0] + list(q6))[:3, 3]

    def _ik(self, xyz, seed):
        sol = self.chain.inverse_kinematics(xyz, initial_position=[0.0] + list(seed))
        return clamp_q(list(sol[1:7]))

    # ── 에피소드 생성: start_q(보통 HOME)에서 goal 까지 '다른 경로'로 IK 궤적 ──
    def _make_episode(self, start_q):
        ee_start = self._fk(start_q)
        d = self.goal - ee_start
        dist = np.linalg.norm(d)
        if dist < 1e-6:
            return [list(start_q)] * self.n_wp
        axis = d / dist
        # 1차 우회 방향 u1 (goal 축에 수직, 직전 에피소드와 확연히 다르게 = "다른 길")
        for _ in range(10):
            r = self.rng.standard_normal(3)
            u1 = r - np.dot(r, axis) * axis
            n = np.linalg.norm(u1)
            if n < 1e-6:
                continue
            u1 = u1 / n
            if self.last_perp is None or np.dot(u1, self.last_perp) < 0.2:
                break
        self.last_perp = u1
        u2 = np.cross(axis, u1)                               # u1,u2,axis 직교
        sgn = 1.0 if self.rng.random() < 0.5 else -1.0
        A = self.bump * float(self.rng.uniform(0.9, 1.6))     # 1차 아치(크게 부풀어 돌아감)
        B = self.bump * float(self.rng.uniform(0.4, 0.9)) * sgn   # 2차 S커브(휘감아 도는 느낌)
        # ★부드러움 가드: 우회가 IK 특이점/한계 근처에서 튀면(웨이포인트 간 관절변화 큼)
        #   진폭을 줄여 재시도, 그래도 안 되면 직선 접근으로 폴백(항상 매끈). 실기 격한 튐 방지.
        for _ in range(4):
            qs, ms = self._build_path(start_q, ee_start, d, A, B, u1, u2)
            if ms <= self.max_step:
                return qs
            A *= 0.6; B *= 0.6
        qs, _ = self._build_path(start_q, ee_start, d, 0.0, 0.0, u1, u2)  # 직선 폴백
        self.get_logger().info("이 방향은 작업영역 경계 근처 → 이번엔 직선 접근(안전)")
        return qs

    def _build_path(self, start_q, ee_start, d, A, B, u1, u2):
        """(A,B,u1,u2) 우회로 웨이포인트 IK 생성. 반환 (qs, 웨이포인트간 최대관절변화)."""
        qs = [list(start_q)]; seed = list(start_q); prev = list(start_q); ms = 0.0
        for i in range(1, self.n_wp):
            s = i / (self.n_wp - 1)
            detour = math.sin(math.pi * s) * A * u1 + math.sin(2 * math.pi * s) * B * u2
            q = self._ik(ee_start + smoothstep(s) * d + detour, seed)
            ms = max(ms, max(abs(q[j] - prev[j]) for j in range(6)))
            qs.append(q); seed = q; prev = q
        return qs, ms

    def _sample(self, phase):
        x = min(1.0, max(0.0, phase)) * (self.n_wp - 1)
        i = int(x); f = x - i
        if i >= self.n_wp - 1:
            return list(self.ep_qs[-1])
        a, b = self.ep_qs[i], self.ep_qs[i + 1]
        return [(1 - f) * a[j] + f * b[j] for j in range(6)]

    # ── 콜백 ──
    def on_fb(self, msg):
        if len(msg.position) >= 6:
            self.cur = list(msg.position[:6]); self.have_fb = True

    def on_reflex(self, msg):
        if msg.data and not self.reflex:                 # 시작
            self.state = "REFLEX"
            self.get_logger().info("★반사 발동 → 칩 제어 (hold, 에피소드 정지)")
        elif (not msg.data) and self.reflex:             # 끝 → 정지 대기
            self.settle_ref = list(self.cur); self.stable_t = 0.0; self.settle_el = 0.0
            self.state = "SETTLING"
            self.get_logger().info("반사 해제 → 로봇 정지 대기 (SETTLING)")
        self.reflex = msg.data

    # ── 메인 루프 ──
    def tick(self):
        self.en.publish(Bool(data=True))                 # enable 항상 유지
        dt = 1.0 / self.hz

        if self.state == "REFLEX":
            if self.have_fb:
                self.publish(self.cur)                   # 메일박스 warm
            return

        if self.state == "SETTLING":
            self.publish(self.cur)
            self.settle_el += dt
            delta = max(abs(self.cur[i] - self.settle_ref[i]) for i in range(6))
            if delta < self.settle_eps:
                self.stable_t += dt
            else:
                self.stable_t = 0.0; self.settle_ref = list(self.cur)
            if self.stable_t >= self.settle_need or self.settle_el >= self.settle_max:
                self.resume_from = list(self.cur); self.resume_t = 0.0
                self.state = "GOHOME"
                self.get_logger().info("정지 확인 → HOME 복귀 (GOHOME)")
            return

        if self.state == "GOHOME":                       # 반사자세 → HOME
            self.resume_t += dt
            r = smoothstep(self.resume_t / self.resume_sec)
            goal = [(1 - r) * self.resume_from[i] + r * HOME[i] for i in range(6)]
            self.publish(goal)
            if r >= 1.0:
                self.ep_qs = self._make_episode(HOME)    # ★새 경로로 재추구
                self.ep_phase = 0.0; self.state = "PURSUE"
                self.get_logger().info("HOME 복귀 완료 → 새 경로로 goal 추구 (PURSUE)")
            return

        if self.state == "ATGOAL":                        # goal 도달 → 거기 유지
            # ★반사 없으면 계속 grip 자세 유지. home 복귀·재추구는 오직 반사(on_reflex)로만.
            self.publish(self.ep_qs[-1])
            return

        # PURSUE
        self.ep_phase += dt / self.ep_dur
        if self.ep_phase >= 1.0:
            self.ep_phase = 1.0
            self.state = "ATGOAL"
            self.get_logger().info("goal 도달 (grip) → 유지 (home 복귀·재추구는 반사 때만)")
        self.publish(self._sample(self.ep_phase))

    def publish(self, q6):
        # 그리퍼: ★항상 닫힘★ (self.grip_close, 기본 0=완전닫힘). 컨트롤러 gripper_exist=true 필요.
        m = JointState()
        m.name = JOINTS + ["joint7"]
        m.position = [float(x) for x in clamp_q(q6)] + [float(self.grip_close)]
        m.velocity = [0.0] * 6 + [float(self.speed)]    # velocity[6]=팔 속도율%
        self.cmd.publish(m)


def main():
    ap = argparse.ArgumentParser(description="reflex-aware Cartesian goal pursuit")
    ap.add_argument("--urdf", default=URDF_DEFAULT)
    ap.add_argument("--goal", type=float, nargs=3, default=None,
                    help="goal 절대좌표 x y z (m). 없으면 home+offset")
    ap.add_argument("--goal-offset", type=float, nargs=3, default=[0.18, 0.0, -0.26],
                    help="home 말단 기준 goal 오프셋(m). 기본=앞으로+살짝 낮게(캔, 작업영역 안쪽 매끈)")
    ap.add_argument("--bump", type=float, default=0.14, help="우회 아치 크기(m). 가드가 튀면 자동 축소")
    ap.add_argument("--grip-close", type=float, default=0.0, help="그리퍼 닫힘 개방(m). 0=완전닫힘(항상 닫힘)")
    ap.add_argument("--episode", type=float, default=4.0, help="home→goal 시간(초)")
    ap.add_argument("--hold", type=float, default=1.0, help="goal 도달 후 유지(초)")
    ap.add_argument("--resume", type=float, default=1.5, help="HOME 복귀 보간(초)")
    ap.add_argument("--speed", type=int, default=30, help="속도율 1~100")
    ap.add_argument("--hz", type=int, default=50)
    ap.add_argument("--seed", type=int, default=None)
    a, _ = ap.parse_known_args()

    rclpy.init()
    node = ReflexPursue(a)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node(); rclpy.shutdown()


if __name__ == "__main__":
    main()
