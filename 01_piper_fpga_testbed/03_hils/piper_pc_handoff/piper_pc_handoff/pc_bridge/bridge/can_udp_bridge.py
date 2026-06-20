#!/usr/bin/env python3
"""CAN -> UDP 브리지 (PC 측 핵심 산출물).

vcan0 에서 '명령' 프레임만 골라 13바이트 UDP 패킷으로 FPGA(192.168.1.10:5000)에 즉시 송신.
  - 프레임 1개 = 패킷 1개, 버퍼링/배칭 없음 (브리지 계약서 §1, §4)
  - 피드백(0x2A1, 0x2A5-7 ...)은 절대 FPGA로 보내지 않음 (recv 필터 화이트리스트 + 안전 가드)
  - 반환 경로는 실제 CAN(can0)이라 UDP 수신부는 구현하지 않음 (핸드오프 §2-1)

실행:
  python3 bridge/can_udp_bridge.py [--iface vcan0] [--fpga-ip 192.168.1.10] [--port 5000] [--estop]
"""
import argparse
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import caniface, frames, ids  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Piper CAN->UDP bridge (PC side)")
    ap.add_argument("--iface", default="vcan0", help="명령을 읽을 CAN 인터페이스 (컨트롤러 쪽)")
    ap.add_argument("--fpga-ip", default="192.168.1.10", help="FPGA IP (고정)")
    ap.add_argument("--port", type=int, default=5000, help="명령 UDP 포트")
    ap.add_argument("--estop", action="store_true",
                    help="0x150 비상정지도 포워딩 (기본은 1차 범위 명령만)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    allow = ids.COMMAND_IDS_WITH_ESTOP if args.estop else ids.SCOPE_COMMAND_IDS
    dst = (args.fpga_ip, args.port)

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    can = caniface.open_can(args.iface, recv_ids=allow)  # 하드웨어 필터로 명령만 수신

    print(f"[bridge] {args.iface} 명령 -> UDP {dst}  허용 ID="
          f"{sorted(hex(i) for i in allow)}", flush=True)
    sent = 0
    while True:
        can_id, data = caniface.recv(can)
        # 이중 안전: 피드백 ID는 절대 FPGA로 보내지 않음
        if ids.is_feedback_id(can_id):
            continue
        pkt = frames.pack_udp(can_id, data)
        udp.sendto(pkt, dst)          # 즉시 전송, 버퍼링 없음
        sent += 1
        if args.verbose:
            print(f"[bridge] -> {hex(can_id)} {data.hex()} (#{sent})", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[bridge] stopped")
