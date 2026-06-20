#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# latency_display.py — 반사 지연 전체화면 표시기 (06/07_로봇실증용)
#   FPGA 시리얼의 [LAT] 줄을 읽어 전체화면에 크게 표시.
#     · 평시      = 초록 배경 + 흰 글씨 "0 us"
#     · 반사 발동 = 빨강 배경 + 흰 글씨 "1500 us" (측정값) → HOLD초 뒤 초록 복귀
#   실행:  python3 latency_display.py [포트] [보레이트]
#          예) python3 latency_display.py /dev/ttyUSB1 115200
#   준비:  pip install pyserial   (tkinter 없으면: sudo apt install python3-tk)
#   종료:  ESC 또는 q     |  전체화면 토글: f
#   ※ picocom / make serial 과 동시에 시리얼을 못 엶 → 이거 쓸 땐 picocom 닫기.
import sys, re, threading, time
import tkinter as tk
try:
    import serial
except ImportError:
    print("pyserial 가 필요합니다:  pip install pyserial"); sys.exit(1)

PORT    = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
BAUD    = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
HOLD_S  = 3.0                       # 반사(빨강) 표시 유지 시간(초) → 이후 초록 복귀
GREEN, RED = "#0a7a0a", "#c00000"   # 평시 초록 / 반사 빨강

# [LAT] 줄의 'NNNN cyc(NNN us)' 쌍을 모두 추출 → 첫째=결정, 둘째=발사(RTS).
#   (한글이 깨져도 숫자 패턴으로 잡히게 — 태그 [LAT] 만 ASCII 로 검사)
RE_PAIR = re.compile(r"(\d+)\s*cyc\s*\(\s*(\d+)\s*us\s*\)")

S = {"us": 0, "dec_us": 0, "cyc": 0, "t": 0.0, "conn": False, "msg": "연결 대기"}

def reader():
    """백그라운드 스레드: 시리얼 열고 [LAT] 줄 파싱해 S 갱신 (실패 시 1초마다 재시도)."""
    while True:
        try:
            ser = serial.Serial(PORT, BAUD, timeout=1)
        except Exception as e:
            S["conn"], S["msg"] = False, f"{PORT} 열기 실패: {e}"
            time.sleep(1.0); continue
        S["conn"], S["msg"] = True, f"{PORT} @ {BAUD} 연결됨"
        while True:
            try:
                line = ser.readline().decode("utf-8", "replace").strip()
            except Exception as e:
                S["conn"], S["msg"] = False, f"읽기 오류: {e}"; break
            if not line:
                continue
            if "[LAT]" in line:
                pairs = RE_PAIR.findall(line)
                if len(pairs) >= 2:                          # 결정, 발사 둘 다
                    S["dec_us"] = int(pairs[0][1])
                    S["cyc"], S["us"] = int(pairs[1][0]), int(pairs[1][1])
                    S["t"] = time.time()
                elif len(pairs) == 1:                        # 발사만
                    S["cyc"], S["us"], S["dec_us"] = int(pairs[0][0]), int(pairs[0][1]), 0
                    S["t"] = time.time()
        try: ser.close()
        except Exception: pass

class App:
    def __init__(self, root):
        self.root = root
        root.title("반사 지연")
        root.attributes("-fullscreen", False)
        root.configure(bg=GREEN)
        root.bind("<Escape>", lambda e: root.destroy())
        root.bind("q",        lambda e: root.destroy())
        root.bind("f", lambda e: root.attributes("-fullscreen",
                                                  not root.attributes("-fullscreen")))
        sh = root.winfo_screenheight() or 1080
        self.big = tk.Label(root, text="0 us", fg="white", bg=GREEN,
                            font=("DejaVu Sans", max(80, int(sh * 0.22)), "bold"))
        self.big.place(relx=0.5, rely=0.43, anchor="center")
        self.sub = tk.Label(root, text="평시 (대기)", fg="white", bg=GREEN,
                            font=("DejaVu Sans", max(20, int(sh * 0.045))))
        self.sub.place(relx=0.5, rely=0.76, anchor="center")
        self.status = tk.Label(root, text="", fg="white", bg=GREEN,
                               font=("DejaVu Sans", max(12, int(sh * 0.022))))
        self.status.place(relx=0.5, rely=0.94, anchor="center")
        self.tick()

    def tick(self):
        active = (time.time() - S["t"]) < HOLD_S and S["us"] > 0
        bg = RED if active else GREEN
        if active:
            self.big.config(text=f'{S["us"]} us')
            self.sub.config(text=f'★반사!  결정 {S["dec_us"]}us → 발사 {S["us"]}us  (+CAN버스 ~120us)')
        else:
            self.big.config(text="0 us")
            self.sub.config(text="평시 (대기)")
        self.status.config(text=("● 연결" if S["conn"] else "○ 끊김") + f'   {S["msg"]}')
        for w in (self.root, self.big, self.sub, self.status):
            w.config(bg=bg)
        self.root.after(50, self.tick)

def main():
    threading.Thread(target=reader, daemon=True).start()
    root = tk.Tk()
    App(root)
    root.mainloop()

if __name__ == "__main__":
    main()
