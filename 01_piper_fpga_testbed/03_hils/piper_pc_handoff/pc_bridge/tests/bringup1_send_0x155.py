#!/usr/bin/env python3
"""브링업 1단계 — transport + HW 무결성.

컨트롤러를 흉내내 vcan0 에 0x155 한 프레임을 쏘고, 반환 버스(can0/vcan1)에서
'바이트 그대로(13B/빅엔디언)' 도착하는지 검증한다. (핸드오프 §5-1)

선행: setup_can.sh + bridge + mock_fpga 실행 중이어야 함.
  터미널A: sudo bash setup/setup_can.sh sim
  터미널B: python3 bridge/can_udp_bridge.py --iface vcan0
  터미널C: python3 tools/mock_fpga.py --out-iface vcan1
  터미널D: python3 tests/bringup1_send_0x155.py --return-iface vcan1

실행하면 vcan0로 송신 후 return-iface 에서 수신·검증해 PASS/FAIL 출력.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import caniface, frames, ids  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tx-iface", default="vcan0", help="컨트롤러 버스 (브리지 입력)")
    ap.add_argument("--return-iface", default="vcan1",
                    help="반환 버스 (mock_fpga 출력; HW면 can0)")
    ap.add_argument("--timeout", type=float, default=2.0)
    args = ap.parse_args()

    # 검증용 관절각: joint1=1.000°(1000), joint2=-2.000°(-2000)
    cid, data = frames.enc_joint_ctrl(1000, -2000, 0, 0, 0, 0)[0]
    assert cid == ids.JOINT_CTRL_12

    rx = caniface.open_can(args.return_iface, recv_ids={cid}, recv_timeout=args.timeout)
    tx = caniface.open_can(args.tx_iface)

    print(f"[bringup1] TX {hex(cid)} {data.hex()} -> {args.tx_iface}", flush=True)
    caniface.send(tx, cid, data)

    try:
        rid, rdata = caniface.recv(rx)
    except OSError:
        print(f"[bringup1] ❌ FAIL: {args.return_iface} 에서 {args.timeout}s 내 수신 없음")
        print("  → bridge / mock_fpga 실행 여부, iface 이름 확인")
        sys.exit(1)

    ok_id = (rid == cid)
    ok_data = (rdata == data)
    print(f"[bringup1] RX {hex(rid)} {rdata.hex()} <- {args.return_iface}")
    print(f"  id  match: {'PASS' if ok_id else 'FAIL'} (기대 {hex(cid)})")
    print(f"  data match (바이트 그대로/빅엔디언): {'PASS' if ok_data else 'FAIL'}")
    if ok_id and ok_data:
        print("✅ transport+HW 무결성 OK (13바이트 그대로 도착)")
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
