#!/usr/bin/env bash
# 스텝1 칩 전체 통합 시뮬 (Vivado xsim). PL master ─ 칩 ─ MCP 모델.
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil *.pb
xvlog ../../pl/rtl/spi_master.v \
      ../rtl/spi_slave_s1.v ../rtl/mcp_init.v ../rtl/estop_tx_src.v ../rtl/mcp_tx_send.v \
      ../rtl/mcp_probe.v ../rtl/mcp_arb4.v ../rtl/spi_master_mcp_v2.v ../rtl/tt_um_reflex_s1.v \
      ../../../common/mcp2515_model_v2.v tb_tt_um_reflex_s1.v >/dev/null
xelab tb_tt_um_reflex_s1 -s s1_snap --timescale 1ns/1ps >/dev/null 2>&1
xsim s1_snap -R
