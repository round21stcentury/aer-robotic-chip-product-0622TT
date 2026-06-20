#!/usr/bin/env bash
# 스텝2 PL 통합 시뮬 (Vivado xsim). reflex_top_s2 ─ MCP 모델.
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil *.pb
xvlog ../rtl/spi_master.v ../rtl/chip_feeder_s2.v ../rtl/reflex_top_s2.v \
      ../../chip/rtl/spi_slave_s2.v ../../chip/rtl/reflex_core_s2.v ../../chip/rtl/reflex_tx_s2.v \
      ../../chip/rtl/mcp_init.v ../../chip/rtl/mcp_tx_send.v ../../chip/rtl/mcp_probe.v \
      ../../chip/rtl/mcp_arb4.v ../../chip/rtl/spi_master_mcp_v2.v ../../chip/rtl/tt_um_reflex_s2.v \
      ../../../common/mcp2515_model_v2.v tb_reflex_top_s2.v >/dev/null
xelab tb_reflex_top_s2 -s s2pl_snap --timescale 1ns/1ps >/dev/null 2>&1
xsim s2pl_snap -R
