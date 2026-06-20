#!/usr/bin/env python3
"""hil_pose_test.py — ★스텝3 홈포즈 반사 자율검증 (Gazebo·FSR 불필요)

  ① enable + 1번관절 스윕(정상명령) → can0 0x155 joint1 이 스윕(비-0) 따라감
  ② 소프트 pose 트리거(0x7F0 d0=1) → 칩이 ★홈포즈(0x155~7 전부 0)★ 주입, 정상 스윕 차단
     → can0 0x155 joint1 = 0 (홈). 로봇 피드백도 0(홈)으로.
  ③ 트리거 해제(0x7F0 d0=0) → 정상 스윕 재개.
  ※ estop(0x150)과 달리 홈포즈는 정상과 ★같은 id(0x155~7)★ 라 ★데이터(0 vs 스윕)★ 로 구분.
"""
import socket, struct, subprocess, time, threading, re, math, sys

FPGA = ("192.168.1.10", 5000)
def pkt(cid, data): return struct.pack(">IB", cid, 8) + data
def cap(iface, store):
    p = subprocess.Popen(["candump","-tz",iface], stdout=subprocess.PIPE, text=True)
    threading.Thread(target=lambda:[store.append((time.time(),l)) for l in p.stdout], daemon=True).start()
    return p
def j1_of(lines, t0, t1, idfilt):
    vs=[]
    for t, ln in lines:
        if not (t0<=t<=t1): continue
        m=re.search(r'\b(%s)\b\s+\[8\]\s+((?:[0-9A-Fa-f]{2}\s*){8})'%idfilt, ln)
        if m:
            b=bytes(int(x,16) for x in m.group(2).split()); vs.append(int.from_bytes(b[0:4],'big',signed=True))
    return vs

def main():
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); can0=[]; vcan0=[]
    c0=cap("can0",can0); v0=cap("vcan0",vcan0); time.sleep(0.4)
    en=pkt(0x471,bytes([0xFF,0x02,0,0,0,0,0,0]))
    z156=pkt(0x156,struct.pack(">ii",0,0)); z157=pkt(0x157,struct.pack(">ii",0,0))
    ON=pkt(0x7F0,bytes([1,0,0,0,0,0,0,0])); OFF=pkt(0x7F0,bytes([0,0,0,0,0,0,0,0]))
    def stream(dur):
        t0=time.time(); k=0
        while time.time()-t0<dur:
            j1=int(8000+8000*math.sin(2*math.pi*(k%200)/200))   # 0~16000 (항상 비-0 중심)
            s.sendto(en,FPGA); s.sendto(pkt(0x155,struct.pack(">ii",j1,0)),FPGA)
            s.sendto(z156,FPGA); s.sendto(z157,FPGA); k+=1; time.sleep(0.02)
        return t0
    print("① 평상시 스윕 3초"); t1=stream(3.0); t1e=time.time()
    print("② pose 트리거 ON + 스윕 3초 (홈포즈 주입·정상차단)"); s.sendto(ON,FPGA); time.sleep(0.05); t2=time.time(); stream(3.0); t2e=time.time()
    print("③ 트리거 OFF + 스윕 3초 (정상 재개)"); s.sendto(OFF,FPGA); time.sleep(0.05); t3=time.time(); stream(3.0); t3e=time.time()
    time.sleep(0.4); c0.terminate(); v0.terminate(); time.sleep(0.2)

    # can0 0x155 joint1: 평상시=스윕(폭 큼), pose=홈(0 근처), 해제=스윕
    n1=j1_of(can0,t1,t1e,'155'); n2=j1_of(can0,t2+0.5,t2e,'155'); n3=j1_of(can0,t3,t3e,'155')
    f2=j1_of(vcan0,t2+1.0,t2e,'2A5')   # 로봇 피드백 (pose 중)
    def span(v): return (max(v)-min(v)) if v else 0
    def amax(v): return max(abs(x) for x in v) if v else 0
    print(f"\n=== can0 0x155 joint1 (구간별) ===")
    print(f"  ① 평상시 : N={len(n1)} 폭={span(n1)} 최대|{amax(n1)}|")
    print(f"  ② pose   : N={len(n2)} 폭={span(n2)} 최대|{amax(n2)}|  (홈이면 ~0)")
    print(f"  ③ 해제후 : N={len(n3)} 폭={span(n3)} 최대|{amax(n3)}|")
    if f2: print(f"  로봇 피드백(pose중) 1번관절 최대|{amax(f2)}| (홈 추종이면 ~0)")

    ok=True
    if span(n1)<3000: ok=False; print("[FAIL] ① 평상시 스윕이 can0에 안 보임")
    else: print("[ ok ] ① 평상시 정상 스윕 통과")
    if amax(n2)>2000: ok=False; print(f"[FAIL] ② pose 중에도 0x155가 비-0(={amax(n2)}) — 홈포즈 주입/차단 실패")
    else: print("[ ok ] ② pose 트리거 -> 홈포즈(0x155~7=0) 주입, 정상 스윕 차단")
    if span(n3)<3000: ok=False; print("[FAIL] ③ 해제 후 스윕 재개 안 됨")
    else: print("[ ok ] ③ 해제 후 정상 스윕 재개")
    print(f"\n=== {'PASS: 홈포즈 반사 동작' if ok else 'FAIL'} ===")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
