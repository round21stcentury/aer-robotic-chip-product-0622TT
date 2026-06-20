#!/usr/bin/env python3
# ============================================================================
# reflex_status_node — FPGA(PS)가 보내는 반사 활성상태 UDP를 받아 /reflex_active(Bool) 발행
# ----------------------------------------------------------------------------
#   FPGA PS(reflex_s4_main.c)가 칩의 reflex_active 비트가 바뀔 때마다 UDP 2바이트
#   ('R', 0/1)를 PC:5001 로 보낸다. 이 노드가 받아 /reflex_active (std_msgs/Bool) 발행.
#     1 = 반사 발동 중(정상명령 막히고 칩이 반사 주입), 0 = 해제(정상 제어 복귀).
#   용도: 상위 제어(ROS)가 "지금 반사 중"을 알고 재계획/일시정지 가능 (반사 자각 층).
#   실행(ROS2 환경에서):  python3 reflex_status_node.py     (브리지와 같은 PC에서)
# ============================================================================
import socket
import rclpy
from rclpy.node import Node
from rclpy.executors import ExternalShutdownException
from std_msgs.msg import Bool

REFLEX_PORT = 5001          # ★PS의 REFLEX_PORT 와 일치


class ReflexStatus(Node):
    def __init__(self):
        super().__init__('reflex_status')
        self.pub = self.create_publisher(Bool, '/reflex_active', 10)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('0.0.0.0', REFLEX_PORT))
        self.sock.setblocking(False)
        self.last = None
        self.create_timer(0.01, self.poll)   # 100Hz 폴링
        self.get_logger().info(f'reflex_status: UDP {REFLEX_PORT} 수신 → /reflex_active 발행')

    def poll(self):
        try:
            while True:                         # 큐에 쌓인 것 모두 처리(최신 상태 반영)
                data, _ = self.sock.recvfrom(16)
                if len(data) >= 2 and data[0] == ord('R'):
                    active = (data[1] != 0)
                    self.pub.publish(Bool(data=active))
                    if active != self.last:
                        self.last = active
                        self.get_logger().info('★ 반사 발동' if active else '  반사 해제 (정상 복귀)')
        except BlockingIOError:
            pass


def main():
    rclpy.init()
    node = ReflexStatus()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
