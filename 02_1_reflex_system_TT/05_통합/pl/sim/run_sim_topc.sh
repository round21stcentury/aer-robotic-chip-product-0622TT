#!/usr/bin/env bash
# 스텝4 PL 통합 시뮬 (Vivado xsim). reflex_top_s4 ─ MCP 모델.
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil *.pb
xvlog ../rtl/*.v ../../chip/rtl/*.v ../../../common/mcp2515_model_v2.v tb_reflex_top_s4.v
xelab tb_reflex_top_s4 -s s4pl_snap --timescale 1ns/1ps
xsim s4pl_snap -R
