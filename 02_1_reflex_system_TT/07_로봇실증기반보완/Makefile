# ══════════════════════════════════════════════════════════════
# 스텝4 — 현재포즈 움츠림 (FSR 트리거 → 현재포즈 + J5 움츠림 델타). FPGA 프로그래밍 자동화.
#   ※ 이 폴더 안에서 실행.
# ══════════════════════════════════════════════════════════════
SHELL   := /bin/bash
XDIR    ?= /opt/Xilinx/2025.2
VIV_ENV := source $(XDIR)/Vivado/settings64.sh
VTS_ENV := source $(XDIR)/Vitis/settings64.sh
XSCT    := $(XDIR)/Vitis/bin/xsct
PROJ    := fpga/vivado/reflex_vivado
APP     := reflex_s4_app

# ★칩 파라미터는 options.config 에서 (없으면 아래 ?= 기본값). 명령줄 make build VAR=x 가 최우선.
-include options.config

# ── PS 프로그래밍(재합성 불필요) ── (options.config 에 없는 항목만 아래 기본값 적용)
SPI_DIV  ?= 2                       # ★20MHz: 칩→MCP=20/(2×2)=5MHz (05@50MHz는 4). MCP 최대 10MHz
THRESH_V ?= 0.76                    # FSR 임계 전압 → 코드(전압×4096)
FSR_RULE ?= 0x005C                  # ★FSR 규칙=기능선택(rule2): 0x5B=움츠림_덕포즈 / 0x5C=움츠림_현재 / 0x5A=덕포즈 / 0x79=estop / 0=비활성. DIP estop(rule0)은 항상 별도 고정
FLINCH_MS ?= 200                    # ★움츠림(0x5B) 1회성 지속(ms). 틱 = FLINCH_MS×CLK_MHZ×1000
CLK_MHZ   ?= 20                     # ★TT칩 20MHz. 움츠림 틱 + 반사지연 µs 환산(클럭상대, 여기만 조정)
RECOIL_RAD ?= 0.30                  # ★J5 움츠림 증가량(rad). 칩엔 ×57296 해서 0.001도로. 0.30rad≈17.2도
REFLEX_SPEED ?= 100                 # ★반사(움츠림) 0x151 속도율(1~100, 기본 100=최대). 실로봇 move_spd_rate
PACE_US  ?= 400                     # ★프레임 페이싱(µs). 20MHz는 SPI 느려 파이프라인↑ → 400 (05@50MHz는 300)
DEBOUNCE_MS ?= 2                    # ★FSR 디바운스(ms). 트리거 이만큼 지속돼야 발동(노이즈 자가발동 방지). 클럭상대→사이클. 최대 ~3.27ms(16비트)
HYST_SHIFT ?= 2                     # ★07 슈미트 히스테리시스 시프트(해제임계=thr×(1−1/2^n)). 1=50%/2=25%/3=12.5%. 재합성X(make build)
THRESH_CODE := $(shell awk "BEGIN{c=$(THRESH_V)*4096+0.5; if(c>4095)c=4095; if(c<0)c=0; printf \"%d\", c}")
FLINCH_TICKS := $(shell awk "BEGIN{printf \"%d\", $(FLINCH_MS)*$(CLK_MHZ)*1000}")
RECOIL_RAW := $(shell awk "BEGIN{printf \"%d\", $(RECOIL_RAD)*57295.78+0.5}")
DEBOUNCE_CYC := $(shell awk "BEGIN{c=$(DEBOUNCE_MS)*$(CLK_MHZ)*1000; if(c>65535)c=65535; if(c<1)c=1; printf \"%d\", c}")

ASCII_WS := ../_vitis_ws/s6
PROG_BIT ?= $(shell find $(PROJ) -name 'design_1_wrapper.bit' 2>/dev/null | head -1)
PROG_PS7 ?= $(shell find $(PROJ) -name 'ps7_init.tcl' 2>/dev/null | head -1)
PROG_ELF ?= $(shell find $(ASCII_WS)/$(APP) -name '*.elf' 2>/dev/null | head -1)
ZYBO_TTY ?= /dev/ttyUSB1
BITRATE  ?= 1000000

.PHONY: help sim project reflex xsa fpga refpga gui build program rerun rebuild serial latency-gui can-up can-down can-mon clean

help:
	@echo "═══ 07_로봇실증기반보완 — TT 반사 칩 ★20MHz + ★슈미트 히스테리시스 (FSR 꾹눌러도 1회 락) ═══"
	@echo " make sim      칩+PL 시뮬 PASS 확인 (먼저) — tb_hyst_core 슈미트 단위시험 포함"
	@echo " make fpga     최초 합성 project→reflex→xsa (XADC 포함). ★Chrome 닫기·-jobs2"
	@echo " make refpga   ★RTL 바꾼 뒤 재합성 (reflex_vivado 자동삭제 후 재빌드). estop/RX/디바운스 고치면 이거!"
	@echo " make build    PS앱(칩 파라미터 주입) — 재합성 불필요    make program  보드 JTAG(비트+ELF)"
	@echo " make rerun    ELF만 다시(빠름·MCP리셋) — 파라미터만 바꿨을 때    make serial  MCP 되읽기 관측"
	@echo " make latency-gui  ★반사지연 전체화면 표시 (시리얼 [LAT]→초록0us/빨강측정값). pip install pyserial"
	@echo ""
	@echo " ── 칩 파라미터 → ★options.config 파일에서 조작 (또는 make build OPT=값, 재합성 없이) ──"
	@echo "  FSR_RULE=0x5B  ★FSR 반사 선택: 0x79=estop · 0x5A=덕포즈 · 0x5B=움츠림_덕포즈 · 0x5C=움츠림_현재 · 0=비활성 (기본 0x5C)"
	@echo "  THRESH_V=0.76  FSR 발동 임계전압(V, 입력 0.55~1.0)"
	@echo "  FLINCH_MS=200  움츠림 1회성 지속(ms)     CLK_MHZ=50  칩클럭(MHz, 움츠림틱 계산용)"
	@echo "  RECOIL_RAD=0.30  ★J5 움츠림 증가량(rad). 칩엔 ×57296 해서 0.001도로(0.30rad≈17.2도)"
	@echo "  SPI_DIV=4      칩→MCP SPI 속도(클수록 느림)"
	@echo "  REFLEX_SPEED=100  ★반사(움츠림) 이동 속도율(1~100, 실로봇 move_spd_rate). estop은 무관"
	@echo "  DEBOUNCE_MS=2  ★FSR 디바운스(ms). 트리거 이만큼 지속돼야 발동(노이즈/자가발동 방지). 최대 ~3.27ms. 재합성X"
	@echo "  HYST_SHIFT=2   ★슈미트 히스테리시스(꾹눌러도 1회 락). 1=50%빡빡/2=25%/3=12.5%헐겁. 재합성X(make build)"
	@echo "  ★DIP2(SW1=P15) = 덕포즈 복귀 스위치(켜면 홈 유지·끄면 재개). DIP1(SW0)=estop/freeze"
	@echo "  예) make build FSR_RULE=0x5C FLINCH_MS=150 RECOIL_RAD=0.20 REFLEX_SPEED=80 && make rerun"
	@echo ""
	@echo " ── HIL 주의 ── ①SW0(DIP) 내려둘 것(올리면 estop 항상)  ②virtual_robot 먼저→make rerun→트리거(bus-off 방지)"
	@echo " (HIL: PC 에서 virtual_robot --cmd-iface can0 → 임의포즈로 둔 뒤 FSR → 그만큼 J5 움츠림)"
	@echo " 상세: README.md / 칩_사양서.md / 수행기록.md"

sim:
	@echo "── 칩 통합 (tt_um_reflex_s4) ──"
	bash chip/sim/run_sim_top.sh  | grep -E '====|FAIL'
	@echo "── ★슈미트 히스테리시스 단위 (reflex_core_c: 꾹눌러도 1회 락) ──"
	bash chip/sim/run_sim_hyst.sh | grep -E '====|FAIL|\[ ok \]'
	@echo "── PL 통합 (reflex_top_s4) ──"
	bash pl/sim/run_sim_topc.sh   | grep -E '====|FAIL'

project:
	@test ! -d $(PROJ) || { echo "이미 있음 → make clean"; exit 1; }
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source create_project_s4.tcl
reflex:
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source add_reflex_s4.tcl
xsa:
	@echo "★Chrome 닫기 (OOM 방지). -jobs 2."
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source build_xsa_s4.tcl
fpga: project reflex xsa
refpga:
	@echo "★RTL 변경 재합성: reflex_vivado 지우고 project→reflex→xsa. Chrome 닫기·-jobs2. (가드 때문에 그냥 make fpga 는 '이미 있음'으로 멈춤)"
	rm -rf $(PROJ)
	$(MAKE) project reflex xsa
gui:
	$(VIV_ENV) && vivado $(PROJ)/reflex_vivado.xpr &

build:
	@echo "→ (options.config·20MHz) SPI_DIV=$(SPI_DIV) CLK_MHZ=$(CLK_MHZ) PACE=$(PACE_US)us THRESH_V=$(THRESH_V)→$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_MS=$(FLINCH_MS)→$(FLINCH_TICKS)틱 RECOIL_RAD=$(RECOIL_RAD)→$(RECOIL_RAW)(0.001도) REFLEX_SPEED=$(REFLEX_SPEED) DEBOUNCE_MS=$(DEBOUNCE_MS)→$(DEBOUNCE_CYC)cyc HYST_SHIFT=$(HYST_SHIFT)"
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) THRESH_CODE=$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_TICKS=$(FLINCH_TICKS) RECOIL_RAW=$(RECOIL_RAW) REFLEX_SPEED=$(REFLEX_SPEED) PACE_US=$(PACE_US) CLK_MHZ=$(CLK_MHZ) DEBOUNCE_CYC=$(DEBOUNCE_CYC) HYST_SHIFT=$(HYST_SHIFT) vitis -s build_app_s4.py

program:
	@test -f "$(PROG_BIT)" || { echo "★비트 없음: make fpga 먼저"; exit 1; }
	@test -f "$(PROG_ELF)" || { echo "★elf 없음: make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/program_board.tcl $(abspath $(PROG_BIT)) $(abspath $(PROG_PS7)) $(abspath $(PROG_ELF))
rerun:
	@test -f "$(PROG_ELF)" || { echo "★elf 없음 — make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/rerun_board.tcl $(abspath $(PROG_ELF))
rebuild:
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) THRESH_CODE=$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_TICKS=$(FLINCH_TICKS) RECOIL_RAW=$(RECOIL_RAW) REFLEX_SPEED=$(REFLEX_SPEED) PACE_US=$(PACE_US) CLK_MHZ=$(CLK_MHZ) DEBOUNCE_CYC=$(DEBOUNCE_CYC) HYST_SHIFT=$(HYST_SHIFT) vitis -s build_app_s4.py
serial:
	picocom -b 115200 $(ZYBO_TTY)
latency-gui:
	@echo "→ 반사지연 전체화면 (picocom/make serial 닫고 실행). ESC/q 종료, f 전체화면토글. 필요: pip install pyserial"
	python3 latency_display.py $(ZYBO_TTY)
can-up:
	sudo ip link set can0 down 2>/dev/null; sudo ip link set can0 type can bitrate $(BITRATE); sudo ip link set can0 up
	@ip -details link show can0 | grep -E 'can state|bitrate'
can-down:
	sudo ip link set can0 down
can-mon:
	candump -ta -c can0

clean:
	rm -rf $(PROJ) fpga/vitis_ws $(ASCII_WS) chip/sim/xsim.dir chip/sim/*.jou chip/sim/*.log chip/sim/.Xil chip/sim/*.pb \
	       pl/sim/xsim.dir pl/sim/*.jou pl/sim/*.log pl/sim/.Xil pl/sim/*.pb \
	       fpga/vivado/*.jou fpga/vivado/*.log fpga/vivado/.Xil
	@echo "✅ 정리"
