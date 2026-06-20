# ══════════════════════════════════════════════════════════════
# 스텝1 — MCP 제어기 실증 (칩이 MCP2515 로 CAN 직접). FPGA 프로그래밍 자동화.
#   흐름: make sim → make fpga → make build → make program → (HIL) make can-up + candump
#   ※ 이 폴더(01_mcp_제어기_실증) 안에서 실행.
# ══════════════════════════════════════════════════════════════
SHELL   := /bin/bash
XDIR    ?= /opt/Xilinx/2025.2
VIV_ENV := source $(XDIR)/Vivado/settings64.sh
VTS_ENV := source $(XDIR)/Vitis/settings64.sh
XSCT    := $(XDIR)/Vitis/bin/xsct
PROJ    := fpga/vivado/reflex_vivado
APP     := reflex_s1_app

# ── PS 가 칩→MCP SPI 속도를 정함 (재합성 불필요, make build SPI_DIV=6). 기본 4 → 6.25MHz ──
SPI_DIV ?= 4

# ★Vitis 워크스페이스는 ASCII 경로(스텝폴더명이 한글이라 Vitis lopper 가 한글경로서 깨짐).
ASCII_WS := ../_vitis_ws/s1
# 산출물 자동탐색 (비트/ps7=Vivado(한글경로 OK), elf=ASCII 워크스페이스)
PROG_BIT ?= $(shell find $(PROJ) -name 'design_1_wrapper.bit' 2>/dev/null | head -1)
PROG_PS7 ?= $(shell find $(PROJ) -name 'ps7_init.tcl' 2>/dev/null | head -1)
PROG_ELF ?= $(shell find $(ASCII_WS)/$(APP) -name '*.elf' 2>/dev/null | head -1)
ZYBO_TTY ?= /dev/ttyUSB1
BITRATE  ?= 1000000

.PHONY: help sim project reflex xsa fpga gui build program rerun rebuild serial can-up can-down can-mon clean

help:
	@echo "═══ 스텝1: MCP 제어기 실증 ═══"
	@echo " make sim       RTL 시뮬 (칩 통합 + PL 통합) — PASS 확인"
	@echo " make fpga      project → reflex → xsa (합성+비트+XSA) ★OOM주의: Chrome 닫기, -jobs2"
	@echo " make build     PS 앱 빌드. SPI 속도: make build SPI_DIV=6 (기본 4, ★재합성 불필요)"
	@echo " make program   보드 JTAG: 비트+ps7+elf 다운로드+실행"
	@echo " make rerun     비트 유지 + elf만 재실행 (빠름)"
	@echo " make rebuild   PS 앱만 재빌드 (SPI_DIV 바꿔도 이거)"
	@echo " make serial    시리얼 콘솔 — ★MCP CANSTAT/CNF 되읽기 관측★"
	@echo " make can-up    USB-CAN can0 $(BITRATE)bps 올리기"
	@echo " make can-mon   candump can0 — DIP 올리면 150# 주기 송신 확인"
	@echo " make clean     생성물 정리"
	@echo ""
	@echo " HIL 합격: make program → make serial 에 CNF=00/C0/80 + DIP ON → candump 150#"

# ── RTL 시뮬 ──
sim:
	@echo "── 칩 통합 (tt_um_reflex_s1) ──"
	bash chip/sim/run_sim_top.sh  | grep -E '====|FAIL'
	@echo "── PL 통합 (reflex_top_s1) ──"
	bash pl/sim/run_sim_topc.sh   | grep -E '====|FAIL'

# ── Vivado ──
project:
	@test ! -d $(PROJ) || { echo "이미 있음: $(PROJ) → make clean 후 재생성"; exit 1; }
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source create_project_s1.tcl
reflex:
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source add_reflex_s1.tcl
xsa:
	@echo "★Chrome 닫았는지 확인 (OOM 방지). -jobs 2."
	cd fpga/vivado && $(VIV_ENV) && vivado -mode batch -source build_xsa_s1.tcl
fpga: project reflex xsa
gui:
	$(VIV_ENV) && vivado $(PROJ)/reflex_vivado.xpr &

# ── PS 앱 (XSA 필요). SPI 속도 주입: make build SPI_DIV=6 ──
build:
	@echo "→ 칩→MCP SPI 속도 코드: SPI_DIV=$(SPI_DIV)"
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) vitis -s build_app_s1.py

# ── 보드 ──
program:
	@test -f "$(PROG_BIT)" || { echo "★비트 없음: make fpga 먼저"; exit 1; }
	@test -f "$(PROG_ELF)" || { echo "★elf 없음: make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/program_board.tcl $(abspath $(PROG_BIT)) $(abspath $(PROG_PS7)) $(abspath $(PROG_ELF))
	@echo "→ make serial (MCP 되읽기 관측) + DIP ON → make can-mon (150#)"
rerun:
	@test -f "$(PROG_ELF)" || { echo "★elf 없음 — make build 먼저"; exit 1; }
	$(XSCT) fpga/tools/rerun_board.tcl $(abspath $(PROG_ELF))
rebuild:
	cd fpga && $(VTS_ENV) && SPI_DIV=$(SPI_DIV) vitis -s build_app_s1.py
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
	@echo "✅ 생성물 정리 (소스/스크립트 유지)"
