#!/usr/bin/env bash
# 스텝3 PL 통합 시뮬 (Vivado xsim). reflex_top_s3 ─ MCP 모델.
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil *.pb
# glob: pl/rtl(spi_master,chip_feeder_s3,reflex_top_s3,xadc_reader) + chip/rtl 전체(spi_slave_full,mcp_tx_mux 포함)
xvlog ../rtl/*.v ../../chip/rtl/*.v ../../../common/mcp2515_model_v2.v tb_reflex_top_s3.v >/dev/null
xelab tb_reflex_top_s3 -s s3pl_snap --timescale 1ns/1ps >/dev/null 2>&1
xsim s3pl_snap -R
