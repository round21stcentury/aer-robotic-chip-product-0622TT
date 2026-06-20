"""HILS 동작 헬퍼 — 커스텀 모션 스크립트 공용.

모션 스크립트는 POSES(자세 시퀀스)만 정의하고 motion_main()을 호출하면,
sim/hil/robot 어느 MODE에서든 동일하게 /joint_ctrl_single 로 발행되어 실행된다.
(슬라이더 GUI와 같은 프론트엔드 — 뒤 파이프라인은 MODE가 처리)
"""
import threading
import time

import rclpy
from sensor_msgs.msg import JointState
from std_msgs.msg import Bool

JOINTS = ["joint1", "joint2", "joint3", "joint4", "joint5", "joint6"]


def motion_main(sequence, speed=20, loop=False, settle=0.05, enable=True):
    """관절 자세 시퀀스를 순서대로 실행.

    sequence : [(positions[6] rad, hold_sec), ...]
    speed    : % (MotionCtrl 속도율). ★실로봇은 낮게(20 등)★
    loop     : True 면 무한 반복 (Ctrl-C 종료)
    settle   : 유지 중 재발행 주기(s) — 목표를 계속 보내 로봇이 유지하게
    enable   : 시작 시 /enable_flag True 발행 (모터 enable)
    """
    rclpy.init()
    node = rclpy.create_node("hils_motion")
    pub = node.create_publisher(JointState, "/joint_ctrl_single", 10)
    en = node.create_publisher(Bool, "/enable_flag", 10)
    spin = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spin.start()
    time.sleep(0.5)

    if enable:
        for _ in range(3):
            en.publish(Bool(data=True))
            time.sleep(0.2)
        node.get_logger().info("enable 발행")

    # speed 는 숫자 또는 함수(callable). 함수면 매번 호출 → 실시간 속도 변경 가능(하위호환).
    def _spd():
        return float(speed() if callable(speed) else speed)

    def send(pos):
        m = JointState()
        m.name = JOINTS
        m.position = [float(x) for x in pos[:6]]
        m.velocity = [0.0] * 6 + [_spd()]   # velocity[6]=속도율%
        pub.publish(m)

    try:
        first = True
        while first or loop:
            first = False
            for pos, hold in sequence:
                node.get_logger().info(f"→ {[round(x,2) for x in pos]} ({hold}s @ {round(_spd())}%)")
                t0 = time.time()
                while time.time() - t0 < hold:
                    send(pos)
                    time.sleep(settle)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info("모션 종료")
        node.destroy_node()
        rclpy.shutdown()
