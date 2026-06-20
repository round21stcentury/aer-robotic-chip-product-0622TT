# ══════════════════════════════════════════════════════════════
# 스텝3 — 덕포즈/홈복귀 반사 (FSR 트리거 + 홈 0x155~7). FPGA 프로그래밍 자동화.
#   ※ 이 폴더 안에서 실행.
# ══════════════════════════════════════════════════════════════
SHELL   := /bin/bash
XDIR    ?= /opt/Xilinx/2025.2
VIV_ENV := source $(XDIR)/Vivado/settings64.sh
VTS_ENV := source $(XDIR)/Vitis/settings64.sh
XSCT    := $(XDIR)/Vitis/bin/xsct
PROJ    := fpga/vivado/reflex_vivado
APP     := reflex_s3_app

# ★칩 파라미터는 options.config 에서 (없으면 아래 ?= 기본값). 명령줄 make build VAR=x 가 최우선.
-include options.config

# ── PS 프로그래밍(재합성 불필요) ── (options.config 에 없는 항목만 아래 기본값 적용)
SPI_DIV  ?= 4                       # 칩→MCP SPI 속도
THRESH_V ?= 0.76                    # FSR 임계 전압 → 코드(전압×4096)
FSR_RULE ?= 0x005A                  # ★FSR 규칙=기능선택(rule2): 0x5A=덕포즈 / 0x79=estop / 0x5B=움찔 / 0=비활성. DIP estop(rule0)은 항상 별도 고정
FLINCH_MS ?= 200                    # ★움찔(0x5B) 1회성 지속(ms). 틱 = FLINCH_MS×CLK_MHZ×1000
CLK_MHZ   ?= 50                     # ★칩 클럭(MHz). 클럭 바꾸면 여기만 조정 → 움찔 틱 자동 재계산(클럭상대)
REFLEX_SPEED ?= 100                 # ★반사(덕포즈/움찔) 0x151 속도율(1~100, 기본 100=최대). 실로봇 move_spd_rate
THRESH_CODE := $(shell awk "BEGIN{c=$(THRESH_V)*4096+0.5; if(c>4095)c=4095; if(c<0)c=0; printf \"%d\", c}")
FLINCH_TICKS := $(shell awk "BEGIN{printf \"%d\", $(FLINCH_MS)*$(CLK_MHZ)*1000}")

ASCII_WS := ../_vitis_ws/s3
PROG_BIT ?= $(shell find $(PROJ) -name 'design_1_wrapper.bit' 2>/dev/null | head -1)
PROG_PS7 ?= $(shell find $(PROJ) -name 'ps7_init.tcl' 2>/dev/null | head -1)
PROG_ELF ?= $(shell find $(ASCII_WS)/$(APP) -name '*.elf' 2>/dev/null | head -1)
ZYBO_TTY ?= /dev/ttyUSB1
BITRATE  ?= 1000000

.PHONY: help sim project reflex xsa fpga gui build program rerun rebuild serial can-up can-down can-mon clean

help:
	@echo "═══ tt_design1 — TT 반사 칩 (DIP estop 항상 + FSR estop/덕포즈/움찔 택1) ═══"
	@echo " make sim      칩+PL 시뮬 PASS 확인 (먼저)"
	@echo " make fpga     재합성 project→reflex→xsa (XADC 포함). ★Chrome 닫기·-jobs2. ★RTL바꾸면 reflex_vivado 먼저 삭제"
	@echo " make build    PS앱(칩 파라미터 주입) — 재합성 불필요    make program  보드 JTAG(비트+ELF)"
	@echo " make rerun    ELF만 다시(빠름·MCP리셋) — 파라미터만 바꿨을 때    make serial  MCP 되읽기 관측"
	@echo ""
	@echo " ── 칩 파라미터 → ★options.config 파일에서 조작 (또는 make build OPT=값, 재합성 없이) ──"
	@echo "  FSR_RULE=0x5A  ★FSR 반사 선택: 0x79=estop · 0x5A=덕포즈 · 0x5B=움찔 · 0=비활성  (기본 0x5A)"
	@echo "  THRESH_V=0.76  FSR 발동 임계전압(V, 입력 0.55~1.0)"
	@echo "  FLINCH_MS=200  움찔 1회성 지속(ms)     CLK_MHZ=50  칩클럭(MHz, 움찔틱 계산용)"
	@echo "  SPI_DIV=4      칩→MCP SPI 속도(클수록 느림)"
	@echo "  REFLEX_SPEED=100  ★반사(덕포즈/움찔) 이동 속도율(1~100, 실로봇 move_spd_rate). estop은 무관"
	@echo "  예) make build FSR_RULE=0x5B FLINCH_MS=150 REFLEX_SPEED=80 && make rerun"
	@echo ""
	@echo " ── HIL 주의 ── ①SW0(DIP) 내려둘 것(올리면 estop 항상)  ②virtual_robot 먼저→make rerun→트리거(bus-off 방지)"
	@echo " 상세: README.md / 칩_사양서.md / 수행기록.md"

sim:
	@echo "── 칩 통합 (tt_um_reflex_s3) ──"
	bash chip/sim/run_sim_top.sh  | grep -E '====|FAIL'
	@echo "── PL 통합 (reflex_top_s3) ──"
	bash pl/sim/run_sim_topc.sh   | grep -E '====|FAIL'

project:
	@test ! -d $(PROJ) || { echo "이미 있음 → make clean"; exit 1; }
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source create_project_s3.tcl
reflex:
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source add_reflex_s3.tcl
xsa:
	@echo "★Chrome 닫기 (OOM 방지). -jobs 2."
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source build_xsa_s3.tcl
fpga: project reflex xsa
gui:
	$(VIV_ENV) && vivado $(PROJ)/reflex_vivado.xpr &

build:
	@echo "→ (options.config) SPI_DIV=$(SPI_DIV) THRESH_V=$(THRESH_V)→$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_MS=$(FLINCH_MS)→$(FLINCH_TICKS)틱 REFLEX_SPEED=$(REFLEX_SPEED)"
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) THRESH_CODE=$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_TICKS=$(FLINCH_TICKS) REFLEX_SPEED=$(REFLEX_SPEED) vitis -s build_app_s3.py

program:
	@test -f "$(PROG_BIT)" || { echo "★비트 없음: make fpga 먼저"; exit 1; }
	@test -f "$(PROG_ELF)" || { echo "★elf 없음: make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/program_board.tcl $(abspath $(PROG_BIT)) $(abspath $(PROG_PS7)) $(abspath $(PROG_ELF))
rerun:
	@test -f "$(PROG_ELF)" || { echo "★elf 없음 — make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/rerun_board.tcl $(abspath $(PROG_ELF))
rebuild:
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) THRESH_CODE=$(THRESH_CODE) FSR_RULE=$(FSR_RULE) FLINCH_TICKS=$(FLINCH_TICKS) REFLEX_SPEED=$(REFLEX_SPEED) vitis -s build_app_s3.py
serial:
	picocom -b 115200 $(ZYBO_TTY)
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
