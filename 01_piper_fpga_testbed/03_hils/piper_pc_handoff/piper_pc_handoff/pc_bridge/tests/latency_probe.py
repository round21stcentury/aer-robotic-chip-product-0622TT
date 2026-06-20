#!/usr/bin/env python3
"""브링업 2단계 — 왕복 레이턴시 측정. (핸드오프 §5-2)

vcan0 송신 시각 ~ 반환 버스 수신 시각의 왕복(vcan0->bridge->UDP->FPGA/mock->can0) 측정.
※ gs_usb USB 왕복 지연 때문에 편도 <1ms 를 못 맞출 수 있음 → 결함 아님, 측정 대상.

선행: setup + bridge + mock_fpga (또는 실제 FPGA) 실행 중.
실행: python3 tests/latency_probe.py [--n 200] [--return-iface vcan1]
"""
import argparse
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import caniface, frames, ids  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tx-iface", default="vcan0")
    ap.add_argument("--return-iface", default="vcan1")
    ap.add_argument("--n", type=int, default=200, help="샘플 수")
    ap.add_argument("--interval", type=float, default=0.005, help="송신 간격(초)")
    ap.add_argument("--timeout", type=float, default=1.0)
    args = ap.parse_args()

    cid = ids.JOINT_CTRL_12
    rx = caniface.open_can(args.return_iface, recv_ids={cid}, recv_timeout=args.timeout)
    tx = caniface.open_can(args.tx_iface)

    samples = []
    lost = 0
    for i in range(args.n):
        # 관절1 자리에 시퀀스 카운터를 실어 송수신 매칭
        _, data = frames.enc_joint_ctrl(i, 0, 0, 0, 0, 0)[0]
        t0 = time.perf_counter()
        caniface.send(tx, cid, data)
        try:
            while True:
                rid, rdata = caniface.recv(rx)
                if rdata == data:        # 같은 시퀀스만 채택
                    break
            samples.append((time.perf_counter() - t0) * 1e3)  # ms
        except OSError:
            lost += 1
        time.sleep(args.interval)

    if not samples:
        print("❌ 수신 0 — bridge/mock_fpga/iface 확인")
        sys.exit(1)

    samples.sort()
    def pct(p): return samples[min(len(samples) - 1, int(len(samples) * p))]
    print(f"[latency] n={len(samples)} lost={lost}/{args.n}")
    print(f"  min={samples[0]:.3f} ms  median={statistics.median(samples):.3f} ms  "
          f"mean={statistics.mean(samples):.3f} ms")
    print(f"  p95={pct(0.95):.3f} ms  p99={pct(0.99):.3f} ms  max={samples[-1]:.3f} ms")
    print("  (왕복 = vcan0->bridge->UDP->FPGA/mock->return. 편도는 대략 절반)")


if __name__ == "__main__":
    main()
