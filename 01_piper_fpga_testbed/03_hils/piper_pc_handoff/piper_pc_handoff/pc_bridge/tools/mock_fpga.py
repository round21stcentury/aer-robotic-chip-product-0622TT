#!/usr/bin/env python3
"""Mock FPGA — 실제 FPGA 하드웨어 없이 PC 측을 단독 검증.

FPGA 측 절반(UDP->CAN)을 흉내: UDP 5000 수신 -> 13바이트 언팩 -> CAN 인터페이스로 재전송.
실제 구성에선 FPGA가 물리 CAN으로 TX하고 USB-CAN(can0)이 받지만,
PC 단독 테스트에선 mock 이 반환 버스(기본 can0, 순수 sim이면 vcan1)로 그대로 써준다.

실행:
  python3 tools/mock_fpga.py [--out-iface can0] [--port 5000]
"""
import argparse
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import caniface, frames  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Mock FPGA: UDP->CAN")
    ap.add_argument("--out-iface", default="can0",
                    help="FPGA가 CAN TX할 버스 (HW=can0, 순수sim=vcan1)")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("0.0.0.0", args.port))
    can = caniface.open_can(args.out_iface)

    print(f"[mock_fpga] UDP {args.port} -> CAN {args.out_iface}", flush=True)
    n = 0
    while True:
        pkt, _addr = udp.recvfrom(64)
        if len(pkt) != frames.UDP_PACKET_LEN:
            print(f"[mock_fpga] WARN: {len(pkt)}바이트 패킷 무시 (13 아님)", flush=True)
            continue
        can_id, dlc, data = frames.unpack_udp(pkt)
        caniface.send(can, can_id, data)   # 물리 CAN TX 흉내
        n += 1
        if args.verbose:
            print(f"[mock_fpga] {hex(can_id)} dlc={dlc} {data.hex()} (#{n})", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[mock_fpga] stopped")
