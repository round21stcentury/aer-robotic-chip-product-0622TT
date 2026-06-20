#!/usr/bin/env bash
# TT 스켈레톤 시뮬 (Vivado xsim). SPI 연결 + 병렬 반사 출력 검증.
#   실행: bash run_sim.sh
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim.dir *.jou *.log .Xil
echo "== xvlog =="; xvlog ../rtl/spi_slave.v ../rtl/reflex_core_tt.v ../rtl/tt_um_reflex.v tb_tt_um_reflex.v
echo "== xelab =="; xelab tb_tt_um_reflex -s tt_snap --timescale 1ns/1ps
echo "== xsim  =="; xsim tt_snap -R
