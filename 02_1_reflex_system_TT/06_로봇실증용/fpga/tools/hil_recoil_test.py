#!/usr/bin/env python3
"""hil_recoil_test.py — ★스텝4 현재포즈 움츠림 반사 자율검증

  ★현재포즈를 can0 에 cansend → 칩이 MCP RX 로 받음 → 움츠림 = 현재+델타.
  ① 현재포즈(0x2A5 j1=20000) + 미도달(0x2A1) 계속 cansend (배경) → 칩 RX 갱신
  ② enable+스윕(정상명령, UDP) → can0 0x155 j1 이 스윕(비-0 변동)
  ③ 움츠림 트리거(0x7F0 d0=1) → 칩이 ★현재(20000)+델타(-8000)=12000★ 주입, 정상차단
     → can0 0x155 j1 ≈ 12000 (고정, 스냅샷). 스윕 아님.
  ④ 도달(0x2A1 reached) cansend + 트리거 해제 → 정상 스윕 재개.
"""
import socket, struct, subprocess, time, threading, re, math, sys

FPGA = ("192.168.1.10", 5000)
CUR_J1 = 20000            # 현재포즈 j1 (cansend 로 칩에 줌)
DELTA1 = -8000            # recoil_d1 기본값(칩) → 움츠림 j1 = 20000-8000 = 12000
EXP_RECOIL = CUR_J1 + DELTA1
def pkt(cid, data): return struct.pack(">IB", cid, 8) + data

stop_rx = False
def rx_feeder(reached_holder):
    # 현재포즈 0x2A5(j1=20000,j2=0) + 0x2A1(도달여부) 를 can0 에 계속 cansend
    j1b = struct.pack(">i", CUR_J1).hex().upper()      # j1 BE 4바이트
    a5 = j1b + "00000000"                               # j1 + j2(0)
    while not stop_rx:
        subprocess.run(["cansend","can0","2A5#"+a5], capture_output=True)
        a1 = "0000000001000000" if not reached_holder[0] else "0000000000000000"  # D4=1 미도달/0 도달
        subprocess.run(["cansend","can0","2A1#"+a1], capture_output=True)
        time.sleep(0.05)

def main():
    global stop_rx
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    can0=[]
    cap=subprocess.Popen(["candump","-tz","can0"],stdout=subprocess.PIPE,text=True)
    threading.Thread(target=lambda:[can0.append((time.time(),l)) for l in cap.stdout],daemon=True).start()
    reached=[False]
    threading.Thread(target=rx_feeder,args=(reached,),daemon=True).start()
    time.sleep(0.5)
    en=pkt(0x471,bytes([0xFF,0x02,0,0,0,0,0,0]))
    z156=pkt(0x156,struct.pack(">ii",0,0)); z157=pkt(0x157,struct.pack(">ii",0,0))
    def stream(dur):
        t0=time.time(); k=0
        while time.time()-t0<dur:
            j1=int(8000+8000*math.sin(2*math.pi*(k%200)/200))
            s.sendto(en,FPGA); s.sendto(pkt(0x155,struct.pack(">ii",j1,0)),FPGA)
            s.sendto(z156,FPGA); s.sendto(z157,FPGA); k+=1; time.sleep(0.02)
        return t0
    print(f"① 평상시 스윕 3초 (현재포즈 j1={CUR_J1} cansend 중)"); t1=stream(3.0); t1e=time.time()
    print(f"② 움츠림 트리거 ON + 스윕 3초 (현재{CUR_J1}+델타{DELTA1}={EXP_RECOIL} 기대)"); s.sendto(pkt(0x7F0,bytes([1,0,0,0,0,0,0,0])),FPGA); time.sleep(0.05); t2=time.time(); stream(3.0); t2e=time.time()
    print("③ 도달 + 트리거 해제 + 스윕 3초 (정상 재개)"); reached[0]=True; time.sleep(0.2); s.sendto(pkt(0x7F0,bytes([0,0,0,0,0,0,0,0])),FPGA); time.sleep(0.05); t3=time.time(); stream(3.0); t3e=time.time()
    stop_rx=True; time.sleep(0.3); cap.terminate(); time.sleep(0.2)

    def j1s(t0,t1):
        v=[]
        for t,ln in can0:
            if not (t0<=t<=t1): continue
            m=re.search(r'\b155\b\s+\[8\]\s+((?:[0-9A-Fa-f]{2}\s*){8})',ln)
            if m:
                b=bytes(int(x,16) for x in m.group(1).split()); v.append(int.from_bytes(b[0:4],'big',signed=True))
        return v
    n1=j1s(t1,t1e); n2=j1s(t2+0.5,t2e); n3=j1s(t3+0.3,t3e)
    def span(v): return (max(v)-min(v)) if v else 0
    import statistics
    med2 = statistics.median(n2) if n2 else 0
    print(f"\n=== can0 0x155 joint1 (구간별) ===")
    print(f"  ① 평상시: N={len(n1)} 폭={span(n1)}  (스윕이면 폭 큼)")
    print(f"  ② 움츠림: N={len(n2)} 폭={span(n2)} 중앙값={med2}  (현재+델타={EXP_RECOIL} 고정 기대)")
    print(f"  ③ 해제후: N={len(n3)} 폭={span(n3)}  (스윕 재개)")
    ok=True
    if span(n1)<3000: ok=False; print("[FAIL] ① 스윕 안 보임")
    else: print("[ ok ] ① 평상시 정상 스윕 통과")
    if not n2: ok=False; print("[FAIL] ② 움츠림 0x155 없음")
    elif span(n2)>3000: ok=False; print(f"[FAIL] ② 움츠림인데 스윕(폭{span(n2)}) — 스냅샷 아님")
    elif abs(med2-EXP_RECOIL)>2500: ok=False; print(f"[FAIL] ② 움츠림 j1={med2} (현재포즈+델타 {EXP_RECOIL} 기대) — 현재포즈 반영 안 됨")
    else: print(f"[ ok ] ② 움츠림 -> 0x155 j1≈{med2} = 현재{CUR_J1}+델타{DELTA1} ★현재포즈 기반, 정상차단")
    if span(n3)<3000: ok=False; print("[FAIL] ③ 스윕 재개 안 됨")
    else: print("[ ok ] ③ 해제 후 정상 스윕 재개")
    print(f"\n=== {'PASS: 현재포즈 움츠림 반사 동작' if ok else 'FAIL'} ===")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
