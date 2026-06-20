#!/usr/bin/env bash
# ★07 슈미트 히스테리시스 단위시험 (reflex_core_c) — 꾹 누르면 1회 락, 떼야 재발동.
set -e
cd "$(dirname "$0")"
source /opt/Xilinx/2025.2/Vivado/settings64.sh
rm -rf xsim_hyst.dir hyst_*.log .Xil_hyst *.pb
xvlog ../rtl/reflex_core_c.v tb_hyst_core.v >/dev/null
xelab tb_hyst_core -s hyst_snap --timescale 1ns/1ps >/dev/null
xsim hyst_snap -R
