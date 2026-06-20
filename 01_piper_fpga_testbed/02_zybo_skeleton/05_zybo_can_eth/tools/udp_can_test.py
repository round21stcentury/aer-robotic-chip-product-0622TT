#!/usr/bin/env python3
"""
HIL 검증 도구 — PC에서 13바이트 UDP 패킷을 FPGA로 쏘고, can0(USB-CAN)에서
실제 CAN 프레임으로 나오는지 확인한다. (CAN-이더넷_브리지_계약서 §2/§7.3)

패킷 = can_id(빅엔디언 4B) + dlc(1B) + data(8B) = 13B.

서브커맨드:
  send     : UDP 패킷 1개(또는 N개) 전송만.
  verify   : UDP 전송 + candump 캡처 → 바이트 일치(엔디언/DLC/데이터) 검증. PASS/FAIL.
  latency  : N개 전송하며 UDP송신→can0수신 시각차 측정(편도 근사, 같은 PC 기준).

전제: can0 가 1Mbps로 up 돼 있어야 함 (make can-up).  보드가 켜져 UDP5000 바인드 상태.
"""
import argparse, socket, subprocess, sys, time, re, threading, queue

FPGA_IP   = "192.168.1.10"
UDP_PORT  = 5000
CANDUMP_RE = re.compile(r'\(([\d.]+)\)\s+(\S+)\s+([0-9A-Fa-f]+)\s+\[(\d+)\]\s+([0-9A-Fa-f ]*)')


def pack_frame(can_id: int, data: bytes) -> bytes:
    data = bytes(data)[:8]
    dlc = len(data)
    return can_id.to_bytes(4, "big") + bytes([dlc]) + data.ljust(8, b"\x00")


def parse_data(s: str) -> bytes:
    s = s.replace(" ", "").replace("#", "")
    if len(s) % 2: s = "0" + s
    return bytes.fromhex(s) if s else b""


def candump_reader(iface, q, stop):
    """candump -ta 를 읽어 (ts, id, dlc, data_bytes) 튜플을 큐에 넣는다."""
    p = subprocess.Popen(["candump", "-ta", iface],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        for line in p.stdout:
            if stop.is_set():
                break
            m = CANDUMP_RE.search(line)
            if not m:
                continue
            ts = float(m.group(1)); cid = int(m.group(3), 16); dlc = int(m.group(4))
            data = bytes.fromhex(m.group(5).replace(" ", "")) if m.group(5).strip() else b""
            q.put((ts, cid, dlc, data))
    finally:
        p.terminate()


def cmd_send(args):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    data = parse_data(args.data)
    pkt = pack_frame(args.id, data)
    for i in range(args.count):
        sock.sendto(pkt, (args.ip, args.port))
        if args.count > 1:
            time.sleep(args.interval)
    print(f"보냄 x{args.count}: id=0x{args.id:03X} dlc={len(data)} data={data.hex(' ')}  "
          f"→ {args.ip}:{args.port}  (13B: {pkt.hex(' ')})")


def cmd_verify(args):
    data = parse_data(args.data)
    pkt = pack_frame(args.id, data)
    expect_data = bytes(data)[:8]
    q, stop = queue.Queue(), threading.Event()
    t = threading.Thread(target=candump_reader, args=(args.iface, q, stop), daemon=True)
    t.start()
    time.sleep(0.3)  # candump 떠오를 시간

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    t0 = time.time()
    sock.sendto(pkt, (args.ip, args.port))
    print(f"→ UDP 전송: id=0x{args.id:03X} dlc={len(expect_data)} data={expect_data.hex(' ')}")

    deadline = t0 + args.timeout
    while time.time() < deadline:
        try:
            ts, cid, dlc, rxdata = q.get(timeout=deadline - time.time())
        except queue.Empty:
            break
        if cid != args.id:
            continue  # 다른 ID 무시
        stop.set()
        ok_id   = (cid == args.id)
        ok_dlc  = (dlc == len(expect_data))
        ok_data = (rxdata[:dlc] == expect_data[:dlc])
        print(f"← can0 수신: id=0x{cid:03X} dlc={dlc} data={rxdata.hex(' ')}  (+{(ts-t0)*1000:.2f}ms 표기)")
        print(f"   ID {'OK' if ok_id else 'FAIL'} / DLC {'OK' if ok_dlc else 'FAIL'} / DATA {'OK' if ok_data else 'FAIL'}")
        if ok_id and ok_dlc and ok_data:
            print("✅ PASS — UDP→FPGA→실제CAN 바이트 일치 (엔디언/13바이트 무결)")
            return 0
        print("❌ FAIL — 바이트 불일치 (엔디언/레이아웃 점검)")
        return 1
    stop.set()
    print("❌ FAIL — 타임아웃: can0에서 해당 프레임 안 나옴")
    print("   점검: 보드 NORMAL 진입? can0 up & 1Mbps? 트랜시버/종단저항? 보드 [stat] canTX 증가?")
    return 2


def cmd_latency(args):
    q, stop = queue.Queue(), threading.Event()
    t = threading.Thread(target=candump_reader, args=(args.iface, q, stop), daemon=True)
    t.start()
    time.sleep(0.3)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    samples = []
    for i in range(args.count):
        # 시퀀스를 payload 앞 2바이트에 박아 매칭
        data = i.to_bytes(2, "big") + b"\x00" * 6
        pkt = pack_frame(args.id, data)
        t0 = time.time()
        sock.sendto(pkt, (args.ip, args.port))
        # 매칭되는 프레임 대기
        deadline = t0 + args.timeout
        while time.time() < deadline:
            try:
                ts, cid, dlc, rxdata = q.get(timeout=deadline - time.time())
            except queue.Empty:
                break
            if cid == args.id and rxdata[:2] == data[:2]:
                samples.append((time.time() - t0) * 1000)
                break
        time.sleep(args.interval)
    stop.set()
    if not samples:
        print("❌ 샘플 0개 — verify부터 통과시키고 다시")
        return 2
    samples.sort()
    n = len(samples)
    print(f"레이턴시(UDP송신→can0수신, 편도 근사, n={n}/{args.count}):")
    print(f"  min={samples[0]:.3f}ms  median={samples[n//2]:.3f}ms  "
          f"max={samples[-1]:.3f}ms  mean={sum(samples)/n:.3f}ms")
    print("  ※ candump 타임스탬프가 아니라 PC 송신~수신 왕복이라 USB-CAN 지연 포함. 절대값보다 추세로.")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ip", default=FPGA_IP); ap.add_argument("--port", type=int, default=UDP_PORT)
    ap.add_argument("--iface", default="can0")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("send", help="UDP 전송만")
    s.add_argument("--id", type=lambda x: int(x, 0), default=0x151)
    s.add_argument("--data", default="0001320000000000")
    s.add_argument("--count", type=int, default=1); s.add_argument("--interval", type=float, default=0.01)
    s.set_defaults(func=cmd_send)

    v = sub.add_parser("verify", help="전송+candump 비교")
    v.add_argument("--id", type=lambda x: int(x, 0), default=0x151)
    v.add_argument("--data", default="0001320000000000")
    v.add_argument("--timeout", type=float, default=2.0)
    v.set_defaults(func=cmd_verify)

    l = sub.add_parser("latency", help="레이턴시 측정")
    l.add_argument("--id", type=lambda x: int(x, 0), default=0x155)
    l.add_argument("--count", type=int, default=100); l.add_argument("--interval", type=float, default=0.02)
    l.add_argument("--timeout", type=float, default=1.0)
    l.set_defaults(func=cmd_latency)

    args = ap.parse_args()
    sys.exit(args.func(args) or 0)


if __name__ == "__main__":
    main()
