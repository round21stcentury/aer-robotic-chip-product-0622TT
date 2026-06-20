# ─────────────────────────────────────────────────────────────
# CAN v2 작업 자동화 (사용법: make help)
# 이번 브링업에서 손으로 반복했던 작업들을 타깃으로 정리
# ─────────────────────────────────────────────────────────────
# ★레시피를 bash로★ (기본 /bin/sh=dash엔 source 없음 → Vitis settings64.sh source 실패 방지)
SHELL := /bin/bash
# can-up 용 (1000000/500000/125000)
BITRATE   ?= 1000000
# bitrate-code 용 (1000/500/250/125)
KBPS      ?= 1000
# 06 XSA 자동탐색 (vivado/ 아래 어디 있든)
XSA       ?= $(firstword $(wildcard vivado/*/*.xsa) $(wildcard vivado/*.xsa) $(wildcard *.xsa))
ZYBO_TTY  ?= /dev/ttyUSB1
DUE_TTY   ?= /dev/ttyACM0
VITIS_SRC  = zybo_can_v2_vitis/can_app/src/can_main.c

# ── HIL (UDP→CAN) ──
FPGA_IP   ?= 192.168.1.10
HIL_TOOL   = tools/udp_can_test.py
HIL_ID    ?= 0x151
HIL_DATA  ?= 0001320000000000
# PC 이더넷 어댑터 (재배치 시 이름 바뀌면 ETH_IF 덮어쓰기)
ETH_IF    ?= enx70198851908f
PC_IP     ?= 192.168.1.100/24
# 보드 MAC (udp_can_main.c의 mac[]와 일치). 단방향 HIL이라 보드가 ARP응답 안 함 → 정적 ARP로 박음
BOARD_MAC ?= 00:0a:35:00:01:02

# ── 보드 프로그래밍 (Vitis GUI 없이 JTAG) ──
XSCT       = /opt/Xilinx/2025.2/Vitis/bin/xsct
# 06: build_hil_app.py 의 APP 이름과 일치. 산출물은 이름 안 박고 자동탐색(07/08도 안 깨짐)
APP        = udp_can_pl_app
APP_IDE    = vitis_ws/$(APP)/_ide
PROG_BIT  ?= $(shell find vitis_ws -name '*.bit' 2>/dev/null | head -1)
PROG_PS7  ?= $(shell find vitis_ws -name 'ps7_init*.tcl' 2>/dev/null | head -1)
PROG_ELF  ?= $(shell find vitis_ws/$(APP) -name '*.elf' 2>/dev/null | head -1)

.PHONY: guide help can-up can-down can-status dump dump-err send send-piper \
        monitor serial serial-due bitrate-code sync-src xsa-verify workbench \
        eth-ping hil-send hil-verify hil-latency hil-check program rebuild rerun \
        install-jtag-driver pc-ip arp-static

# ── 기본 타깃: 작업 순서 가이드 (그냥 'make' 치면 이게 나옴) ──
guide:
	@echo ""
	@echo "══════════ Zybo HIL 브리지 — 작업 순서 ══════════"
	@echo ""
	@echo " [처음 1회만 / 노트북 옮긴 후] JTAG 드라이버:"
	@echo "   make install-jtag-driver     # udev 규칙 설치 → 끝나면 보드 USB 뽑았다 다시 꽂기"
	@echo ""
	@echo " [보드 전원 켤 때마다] 순서대로:"
	@echo "   1) make program              # 비트스트림+앱 JTAG 다운로드+실행"
	@echo "   2) make pc-ip                # PC 어댑터 정적IP(192.168.1.100) — 어댑터 뽑았다 꽂으면 필수"
	@echo "   3) make can-up               # USB-CAN 1Mbps (FPGA 송신 ACK 줄 노드 — 필수)"
	@echo "   4) make hil-check            # ping + UDP→CAN 바이트검증 (PASS/FAIL)"
	@echo "   5) make hil-latency          # 레이턴시 (선택)"
	@echo ""
	@echo " [부팅 메시지 보려면] 다른 터미널:"
	@echo "   sudo picocom -b 115200 /dev/ttyUSB1   # [CAN]NORMAL/[NET]/[UDP] 확인"
	@echo "      (UART tty 번호는 ls /dev/ttyUSB* 로 확인. 다르면 ZYBO_TTY=... 로 덮어쓰기)"
	@echo ""
	@echo " [앱 코드(src/udp_can_main.c) 고쳤을 때]:"
	@echo "   make rebuild  →  make program"
	@echo ""
	@echo " 전체 명령 목록:  make help"
	@echo "════════════════════════════════════════════════"

help:
	@echo "── CAN 버스 ──────────────────────────────────────────"
	@echo " make can-up [BITRATE=1000000]   can0 down→설정→up (속도 변경 시 항상 이걸로)"
	@echo " make can-down                   can0 내리기"
	@echo " make can-status                 상태/에러카운터 한 번 출력"
	@echo " make monitor                    상태 실시간 감시 (watch)"
	@echo "── 송수신 ────────────────────────────────────────────"
	@echo " make dump                       candump (타임스탬프+색)"
	@echo " make dump-err                   candump + 에러프레임 ★디버깅용★"
	@echo " make send                       테스트 프레임 456#DEADBEEF"
	@echo " make send-piper                 Piper 스타일 0x151 프레임"
	@echo "── 코드/빌드 ─────────────────────────────────────────"
	@echo " make bitrate-code KBPS=500      can_main.c 비트레이트 변경 (원본+Vitis 동시)"
	@echo " make sync-src                   src/can_main.c → Vitis 앱으로 복사"
	@echo " make xsa-verify [XSA=...]       XSA 해부 검증 (EMIO/APER/CAN클럭/ENET/비트스트림)"
	@echo "── 보드 (Vitis GUI 없이) ─────────────────────────────"
	@echo " make install-jtag-driver        JTAG udev 드라이버 설치 (노트북 옮긴 후 1회)"
	@echo " make program                    JTAG로 비트스트림+elf 다운로드+실행 (전원 켤 때마다 이거)"
	@echo " make rebuild                    src/udp_can_main.c 변경분 앱 재빌드 (vitis -s)"
	@echo "── HIL (UDP→CAN) ─────────────────────────────────────"
	@echo " make pc-ip                      PC 어댑터 정적IP 부여 (어댑터 뽑았다 꽂으면 다시)"
	@echo " make arp-static                 보드 MAC 정적 ARP (단방향이라 ping응답 없음 → 이걸로 우회)"
	@echo " make eth-ping                   보드 ping (※단방향이라 실패 정상 — 진단용)"
	@echo " make hil-send [HIL_ID=0x151]    UDP 13B 패킷 1개 전송"
	@echo " make hil-verify                 UDP 전송+candump 비교 (바이트 일치 PASS/FAIL)"
	@echo " make hil-latency                UDP→can0 레이턴시 측정 (100샘플)"
	@echo " make hil-check                  ★검증체인★ ping→verify 순차 (can-up 먼저)"
	@echo "── 기타 ──────────────────────────────────────────────"
	@echo " make serial / serial-due        시리얼 콘솔 (ZYBO_TTY/DUE_TTY 변수로 변경)"
	@echo " make workbench                  tmux 5분할 워크벤치"

# ── CAN 버스 ──────────────────────────────────────────────────
can-up:
	sudo ip link set can0 down
	sudo ip link set can0 type can bitrate $(BITRATE)
	sudo ip link set can0 up
	@ip -details link show can0 | grep -E 'can state|bitrate'

can-down:
	sudo ip link set can0 down

can-status:
	@ip -details -statistics link show can0 | grep -E 'can state|bitrate|RX:|TX:' -A1

monitor:
	watch -n1 "ip -details -statistics link show can0 | grep -E 'can state|bitrate|RX:|TX:' -A1"

# ── 송수신 ────────────────────────────────────────────────────
dump:
	candump -ta -c can0

dump-err:
	candump -ta -e can0,0:0,#FFFFFFFF

send:
	cansend can0 456#DEADBEEF

send-piper:
	cansend can0 151#0001320000000000

# ── 코드/빌드 ─────────────────────────────────────────────────
# 비트레이트 변경: 원본과 Vitis 복사본을 동시에 (한쪽만 바꾸는 실수 방지)
bitrate-code:
	sed -i 's/#define BITRATE_KBPS  *[0-9]\+/#define BITRATE_KBPS  $(KBPS)/' src/can_main.c $(VITIS_SRC)
	@grep -Hn "define BITRATE_KBPS" src/can_main.c $(VITIS_SRC)
	@echo "→ Vitis에서 Build 필요. PC쪽도 잊지 말 것: make can-up BITRATE=$(KBPS)000"

sync-src:
	cp src/can_main.c $(VITIS_SRC)
	@echo "복사 완료: $(VITIS_SRC)"

# XSA 검증: 브링업 때 손으로 하던 해부 절차 자동화
#  - EMIO=1, IO=EMIO, CAN클럭 100MHz 파라미터
#  - ps7_init: APER(0xF800012C) bit16=1 필수 / CAN_CLK(0xF8000128)=0x00700F01이면
#    Vivado 2025.2 버그 잔존(정상임 — 앱 안전망이 부팅 시 교정. 버그분석 문서 참고)
xsa-verify:
	@rm -rf /tmp/xsa_verify && mkdir -p /tmp/xsa_verify
	@unzip -o -q $(XSA) -d /tmp/xsa_verify
	@echo "=== ① hwh 파라미터 (EMIO=1 / EMIO / 100 이어야) ==="
	@grep -ohE '"PCW_(EN_EMIO_CAN0|CAN0_CAN0_IO|CAN_PERIPHERAL_FREQMHZ)" VALUE="[^"]*"' /tmp/xsa_verify/*.hwh
	@echo "=== ② ps7_init 레지스터 (12C는 bit16=1 / 128은 0x00700F01=버그잔존→앱이 교정) ==="
	@grep -hE '0XF8000128|0XF800012C' /tmp/xsa_verify/ps7_init.tcl | sort -u
	@echo "=== ③ 비트스트림 포함 여부 ==="
	@ls /tmp/xsa_verify/*.bit >/dev/null 2>&1 && echo "OK: $$(ls /tmp/xsa_verify/*.bit)" || echo "★실패: .bit 없음 — Export 시 Include bitstream 체크!"
	@echo "=== ④ 이더넷(lwIP용) — ENET0=1 / MDIO=1 이어야 (아니면 Vivado에서 ENET0 켜야) ==="
	@grep -ohE '"PCW_(EN_ENET0|ENET0_PERIPHERAL_ENABLE|ENET0_GRP_MDIO_ENABLE)" VALUE="[^"]*"' /tmp/xsa_verify/*.hwh | sort -u

# ── 보드 프로그래밍 (Vitis GUI 없이 JTAG) ─────────────────────
# JTAG udev 드라이버 설치 (노트북 옮긴 후 1회). ftdi_sio가 JTAG 채널 잡는 것 방지.
JTAG_DRV_DIR = /opt/Xilinx/2025.2/data/xicom/cable_drivers/lin64/install_script/install_drivers
install-jtag-driver:
	cd $(JTAG_DRV_DIR) && sudo ./install_drivers
	@echo ""
	@echo "→ 완료. ★보드 USB를 뽑았다 다시 꽂으세요★ (ftdi_sio가 JTAG 채널을 놓도록)."
	@echo "  그 뒤: ttyUSB가 1개(UART)만 남아야 정상. → make program"

#  보드 전원 켤 때마다: make program  (비트스트림+ps7_init+elf 다운로드+실행)
program:
	@test -f $(PROG_BIT) || { echo "★비트스트림 없음: $(PROG_BIT) — 먼저 빌드"; exit 1; }
	@test -f $(PROG_ELF) || { echo "★elf 없음: $(PROG_ELF) — make rebuild"; exit 1; }
	$(XSCT) tools/program_board.tcl $(abspath $(PROG_BIT)) $(abspath $(PROG_PS7)) $(abspath $(PROG_ELF))
	@echo "→ 시리얼 확인: sudo picocom -b 115200 $(ZYBO_TTY)"

# 보드 재실행 (비트스트림 유지 + 새 ELF만 다운+실행). program보다 빠름. 부팅메시지 다시 보기/코드만 바꿨을 때.
#  ★아두이노 리셋 느낌★ — serial은 다른 터미널에 열어두고 이걸 치면 부팅 출력이 다시 나옴.
rerun:
	@test -f $(PROG_ELF) || { echo "★elf 없음: $(PROG_ELF) — make rebuild 먼저"; exit 1; }
	$(XSCT) tools/rerun_board.tcl $(abspath $(PROG_ELF))

# src/udp_can_main.c 만 고쳤을 때 앱 재빌드 (플랫폼 재빌드 없이, vitis -s)
rebuild:
	source /opt/Xilinx/2025.2/Vitis/settings64.sh && vitis -s rebuild_app.py

# ── HIL (UDP→CAN) ─────────────────────────────────────────────
# PC 이더넷 어댑터에 정적 IP 부여 (어댑터 뽑았다 꽂으면 IP 날아가므로 그때 다시)
pc-ip:
	sudo ip addr replace $(PC_IP) dev $(ETH_IF)
	sudo ip link set $(ETH_IF) up
	@ip -br addr show $(ETH_IF)

# 정적 ARP: 보드(단방향 HIL)는 ARP 응답을 안 하므로 보드 MAC을 직접 박아 PC가 UDP 송신 가능하게
arp-static:
	sudo ip neigh replace $(FPGA_IP) lladdr $(BOARD_MAC) dev $(ETH_IF)
	@ip neigh show $(FPGA_IP)

eth-ping:
	ping -c 3 -W 1 $(FPGA_IP)

hil-send:
	python3 $(HIL_TOOL) send --id $(HIL_ID) --data $(HIL_DATA)

hil-verify:
	python3 $(HIL_TOOL) verify --id $(HIL_ID) --data $(HIL_DATA)

hil-latency:
	python3 $(HIL_TOOL) latency

# 검증체인: CAN 브링업 때 xsa-verify→can-up→send/dump 하던 흐름의 HIL 버전.
#  (can0 가 1Mbps up & 보드 실행 중이라는 전제. can-up 은 먼저 따로 돌릴 것)
hil-check:
	@echo "── ① 정적 ARP (보드는 단방향이라 ping/ARP응답 안 함) ──"; sudo ip neigh replace $(FPGA_IP) lladdr $(BOARD_MAC) dev $(ETH_IF)
	@echo "── ② UDP→CAN 바이트 무결 ──"; python3 $(HIL_TOOL) verify --id $(HIL_ID) --data $(HIL_DATA)
	@echo "── 통과 시: make hil-latency 로 레이턴시 측정 ──"

# ── 기타 ──────────────────────────────────────────────────────
serial:
	picocom -b 115200 $(ZYBO_TTY)

serial-due:
	picocom -b 115200 $(DUE_TTY)

workbench:
	./can_workbench.sh
