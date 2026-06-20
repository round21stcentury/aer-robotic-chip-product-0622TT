#!/usr/bin/env python3
"""hil_corruption_test.py — ★FPGA 패스스루 손상 자동검사 (Gazebo·슬라이더 불필요)

  PC가 보내는 입력을 ★완벽히 통제★해서 can0 출력의 손상을 정량화한다.
  세 id(0x155/156/157)에 ★서로 구별되는 패턴★을 실어 보내, 출력이 자기 패턴과
  다르면 손상으로 집계 + 어느 id 데이터가 샜는지 보여준다.

  메커니즘 배경(2026-06-18 규명): mcp_tx_send 가 RTS 후 MCP 송신완료를 안 기다리고
  바로 다음 프레임을 TXB0 에 적재하면, MCP 송신중(~120µs) TXB0 덮어써서
  "앞 k바이트=N, 뒤=N+1" splice 손상. 단일 id 는 100Hz 도 멀쩡, 여러 id 섞이면 손상.

  사용:
    python3 hil_corruption_test.py             # 기본 50Hz, 2초, 세 id
    python3 hil_corruption_test.py --hz 100 --secs 3
    python3 hil_corruption_test.py --single     # 0x155 만 (단일 id 기준선)
"""
import argparse, socket, struct, subprocess, time, threading, re, sys

FPGA = ("192.168.1.10", 5000)
# 세 id 의 구별 패턴 (어느 id 가 어디로 새는지 한눈에)
PATS = {
    0x155: bytes([0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88]),
    0x156: bytes([0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x99,0x00]),
    0x157: bytes([0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8]),
}

def hexpat(b): return " ".join("%02X" % x for x in b)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hz", type=float, default=50.0)
    ap.add_argument("--secs", type=float, default=2.0)
    ap.add_argument("--iface", default="can0")
    ap.add_argument("--single", action="store_true", help="0x155 만 보냄(단일 id 기준선)")
    args = ap.parse_args()

    ids = [0x155] if args.single else [0x155, 0x156, 0x157]
    expect = {i: hexpat(PATS[i]) for i in ids}

    # candump 백그라운드
    cap = subprocess.Popen(["candump", "-tz", args.iface], stdout=subprocess.PIPE, text=True)
    lines = []
    def reader():
        for ln in cap.stdout:
            lines.append(ln)
    th = threading.Thread(target=reader, daemon=True); th.start()
    time.sleep(0.3)

    # 송신
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    pkts = {i: struct.pack(">IB", i, 8) + PATS[i] for i in ids}
    delay = 1.0 / args.hz
    n = int(args.secs / delay)
    for _ in range(n):
        for i in ids:
            s.sendto(pkts[i], FPGA)
        time.sleep(delay)
    time.sleep(0.4)
    cap.terminate(); time.sleep(0.2)

    # 분석
    rx = re.compile(r"\b(15[567])\b\s+\[8\]\s+((?:[0-9A-Fa-f]{2}\s*){8})")
    per = {i: {"good": 0, "bad": 0, "samples": []} for i in ids}
    for ln in lines:
        m = rx.search(ln)
        if not m: continue
        cid = int(m.group(1), 16)
        data = " ".join(m.group(2).split()).upper()
        if cid not in per: continue
        if data == expect[cid]:
            per[cid]["good"] += 1
        else:
            per[cid]["bad"] += 1
            if len(per[cid]["samples"]) < 8:
                per[cid]["samples"].append(data)

    print(f"\n=== HIL 손상검사: {args.hz}Hz × {args.secs}s, id={[hex(i) for i in ids]} ===")
    total_bad = 0
    for i in ids:
        g, b = per[i]["good"], per[i]["bad"]
        tot = g + b
        rate = (100.0 * b / tot) if tot else 0.0
        total_bad += b
        print(f"  0x{i:03X}: 출력 {tot}개, 정확 {g}, 손상 {b}  ({rate:.1f}%)  기대={expect[i]}")
        for sm in per[i]["samples"]:
            # 손상 바이트가 어느 id 꼬리인지 표시
            tag = ""
            for j in ids:
                if j != i and expect[j].split()[-3:] == sm.split()[-3:]:
                    tag = f"  ← 뒤쪽이 0x{j:03X} 꼬리"
            print(f"           손상: {sm}{tag}")
    verdict = "PASS (손상 0)" if total_bad == 0 else f"FAIL (손상 {total_bad}개)"
    print(f"=== 판정: {verdict} ===\n")
    sys.exit(0 if total_bad == 0 else 1)

if __name__ == "__main__":
    main()
