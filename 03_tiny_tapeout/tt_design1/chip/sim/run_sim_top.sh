#!/usr/bin/env bash
# 스텝3 칩 통합 시뮬 (Vivado xsim).
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil *.pb
xvlog ../../pl/rtl/spi_master.v ../rtl/*.v ../../../common/mcp2515_model_v2.v tb_tt_um_reflex_s3.v >/dev/null
xelab tb_tt_um_reflex_s3 -s s3_snap --timescale 1ns/1ps >/dev/null 2>&1
xsim s3_snap -R
