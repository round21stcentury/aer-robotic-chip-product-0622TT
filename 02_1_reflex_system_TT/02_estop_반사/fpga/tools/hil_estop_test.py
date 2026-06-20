#!/usr/bin/env python3
"""hil_estop_test.py — ★스텝2 e-stop 반사 자율검증 (Gazebo·DIP 불필요)

  FPGA에 직접 UDP로: ① enable + 1번관절 스윕(정상명령) → 로봇 추종 확인
  ② 소프트 반사트리거(0x7F0 d0=1) → can0에 0x150 e-stop 뜨고 ★정상명령(0x155) 차단★ 확인
  ③ 트리거 해제(0x7F0 d0=0) → 정상명령 재개 확인.
  로봇 피드백(vcan0 0x2A5)으로 트리거 중 ★멈춤(추종 정지)★ 도 확인.

  사용: python3 hil_estop_test.py
"""
import socket, struct, subprocess, time, threading, re, math, sys

FPGA = ("192.168.1.10", 5000)

def pkt(cid, data): return struct.pack(">IB", cid, 8) + data

def cap(iface, secs, store):
    p = subprocess.Popen(["candump","-tz",iface], stdout=subprocess.PIPE, text=True)
    def rd():
        for ln in p.stdout: store.append((time.time(), ln))
    threading.Thread(target=rd, daemon=True).start()
    return p

def ids_in(lines, t0, t1):
    s = {}
    for t, ln in lines:
        if not (t0 <= t <= t1): continue
        m = re.search(r'\b(15[0-9a-fA-F]|471)\b\s+\[8\]', ln)
        if m: s[m.group(1)] = s.get(m.group(1),0)+1
    return s

def j1_fb(lines, t0, t1):
    vs=[]
    for t, ln in lines:
        if not (t0 <= t <= t1): continue
        m = re.search(r'\b2A5\b\s+\[8\]\s+((?:[0-9A-Fa-f]{2}\s*){8})', ln)
        if m:
            b=bytes(int(x,16) for x in m.group(1).split()); vs.append(int.from_bytes(b[0:4],'big',signed=True))
    return vs

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    can0=[]; vcan0=[]
    c0=cap("can0",100,can0); v0=cap("vcan0",100,vcan0)
    time.sleep(0.4)
    en=pkt(0x471,bytes([0xFF,0x02,0,0,0,0,0,0]))
    z156=pkt(0x156,struct.pack(">ii",0,0)); z157=pkt(0x157,struct.pack(">ii",0,0))
    TRIG_ON =pkt(0x7F0,bytes([0x01,0,0,0,0,0,0,0]))
    TRIG_OFF=pkt(0x7F0,bytes([0x00,0,0,0,0,0,0,0]))

    def stream(dur, label):
        t0=time.time(); k=0
        while time.time()-t0 < dur:
            j1=int(15000*(1-math.cos(2*math.pi*(k%200)/200)))
            s.sendto(en,FPGA); s.sendto(pkt(0x155,struct.pack(">ii",j1,0)),FPGA)
            s.sendto(z156,FPGA); s.sendto(z157,FPGA); k+=1; time.sleep(0.02)
        return t0

    print("① 평상시: enable+1번관절 스윕 3초 (정상 추종)")
    t_norm = stream(3.0, "normal"); t_norm_end=time.time()

    print("② 반사 트리거 ON (0x7F0 d0=1) + 스윕 계속 3초 (e-stop 주입·정상차단)")
    s.sendto(TRIG_ON,FPGA); time.sleep(0.05); t_trig=time.time(); stream(3.0,"trig"); t_trig_end=time.time()

    print("③ 트리거 OFF + 스윕 3초 (정상 재개)")
    s.sendto(TRIG_OFF,FPGA); time.sleep(0.05); t_rel=time.time(); stream(3.0,"release"); t_rel_end=time.time()
    time.sleep(0.4); c0.terminate(); v0.terminate(); time.sleep(0.2)

    n_norm=ids_in(can0,t_norm,t_norm_end); n_trig=ids_in(can0,t_trig,t_trig_end); n_rel=ids_in(can0,t_rel,t_rel_end)
    fb_norm=j1_fb(vcan0,t_norm,t_norm_end); fb_trig=j1_fb(vcan0,t_trig+1.0,t_trig_end); fb_rel=j1_fb(vcan0,t_rel,t_rel_end)
    print("\n=== can0 id별 (구간별) ===")
    print(f"  ① 평상시 : {n_norm}")
    print(f"  ② 트리거 : {n_trig}")
    print(f"  ③ 해제후 : {n_rel}")
    def rng(v): return f"[{min(v)}..{max(v)}]({(max(v)-min(v))/1000:.1f}deg폭)" if v else "없음"
    print(f"\n=== 로봇 1번관절 피드백 폭 ===")
    print(f"  ① 평상시 : {rng(fb_norm)}   ② 트리거중 : {rng(fb_trig)}   ③ 해제후 : {rng(fb_rel)}")

    ok = True
    if n_norm.get('155',0)==0: ok=False; print("[FAIL] ① 평상시 0x155 정상명령 없음")
    else: print("[ ok ] ① 평상시 0x155 정상명령 통과")
    if n_trig.get('150',0)==0: ok=False; print("[FAIL] ② 트리거 시 0x150 e-stop 안 나옴")
    else: print("[ ok ] ② 트리거 시 0x150 e-stop 주입")
    if n_trig.get('155',0)>2: ok=False; print(f"[FAIL] ② 트리거 중 정상명령 0x155 {n_trig['155']}개 샘(차단 실패)")
    else: print("[ ok ] ② 트리거 중 정상명령 0x155 차단")
    if fb_trig and (max(fb_trig)-min(fb_trig))>5000: ok=False; print("[FAIL] ② 트리거 중 로봇이 계속 움직임(정지 실패)")
    elif fb_trig: print("[ ok ] ② 트리거 중 로봇 정지(추종 멈춤)")
    if n_rel.get('155',0)==0: ok=False; print("[FAIL] ③ 해제 후 0x155 정상명령 재개 안 됨")
    else: print("[ ok ] ③ 해제 후 0x155 정상명령 재개")
    print(f"\n=== {'PASS: e-stop 반사 동작' if ok else 'FAIL'} ===")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
