# ─────────────────────────────────────────────────────────────
# CAN v2 작업 자동화 (사용법: make help)
# 이번 브링업에서 손으로 반복했던 작업들을 타깃으로 정리
# ─────────────────────────────────────────────────────────────
# can-up 용 (1000000/500000/125000)
BITRATE   ?= 1000000
# bitrate-code 용 (1000/500/250/125)
KBPS      ?= 1000
XSA       ?= zybo_can_v2_vivado/zybo_can_v2.xsa
ZYBO_TTY  ?= /dev/ttyUSB1
DUE_TTY   ?= /dev/ttyACM0
VITIS_SRC  = zybo_can_v2_vitis/can_app/src/can_main.c

# ── HIL (UDP→CAN) ──
FPGA_IP   ?= 192.168.1.10
HIL_TOOL   = tools/udp_can_test.py
HIL_ID    ?= 0x151
HIL_DATA  ?= 0001320000000000

.PHONY: help can-up can-down can-status dump dump-err send send-piper \
        monitor serial serial-due bitrate-code sync-src xsa-verify workbench \
        eth-ping hil-send hil-verify hil-latency hil-check

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
	@echo "── HIL (UDP→CAN) ─────────────────────────────────────"
	@echo " make eth-ping                   보드(192.168.1.10) ping"
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

# ── HIL (UDP→CAN) ─────────────────────────────────────────────
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
	@echo "── ① 이더넷 도달 ──"; $(MAKE) -s eth-ping || { echo "✗ ping 실패 — IP/케이블/보드 부팅 확인"; exit 1; }
	@echo "── ② UDP→CAN 바이트 무결 ──"; python3 $(HIL_TOOL) verify --id $(HIL_ID) --data $(HIL_DATA)
	@echo "── 통과 시: make hil-latency 로 레이턴시 측정 ──"

# ── 기타 ──────────────────────────────────────────────────────
serial:
	picocom -b 115200 $(ZYBO_TTY)

serial-due:
	picocom -b 115200 $(DUE_TTY)

workbench:
	./can_workbench.sh
