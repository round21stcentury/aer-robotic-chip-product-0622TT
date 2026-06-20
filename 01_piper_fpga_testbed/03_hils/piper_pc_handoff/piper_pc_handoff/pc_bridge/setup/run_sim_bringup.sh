#!/usr/bin/env bash
# sim 모드 1·2단계 자동 브링업 (root 필요 — vcan 생성 + AF_CAN raw 소켓).
# 사용:  sudo bash pc_bridge/setup/run_sim_bringup.sh
#
# vcan0/vcan1 생성 -> bridge + mock_fpga 백그라운드 기동 ->
# 코덱테스트 -> 1단계(13B 도착) -> 2단계(레이턴시) -> 정리.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY=python3
PIDS=()

cleanup() {
  echo "[run] cleanup..."
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  ip link set vcan0 down 2>/dev/null || true
  ip link set vcan1 down 2>/dev/null || true
  ip link delete vcan0 2>/dev/null || true
  ip link delete vcan1 2>/dev/null || true
}
trap cleanup EXIT

echo "=== setup vcan0/vcan1 ==="
modprobe vcan
for n in vcan0 vcan1; do
  ip link show "$n" >/dev/null 2>&1 || ip link add dev "$n" type vcan
  ip link set up "$n"
done
ip -br link show type vcan

echo "=== 코덱 골든벡터 테스트 ==="
"$PY" "$HERE/tests/test_frames.py" || { echo "코덱 FAIL"; exit 1; }

echo "=== bridge + mock_fpga 기동 (sim: FPGA=127.0.0.1, 반환=vcan1) ==="
"$PY" "$HERE/bridge/can_udp_bridge.py" --iface vcan0 --fpga-ip 127.0.0.1 --port 5000 &
PIDS+=($!)
"$PY" "$HERE/tools/mock_fpga.py" --out-iface vcan1 --port 5000 &
PIDS+=($!)
sleep 1

echo "=== 1단계: transport+HW 무결성 (0x155 바이트 그대로 도착) ==="
"$PY" "$HERE/tests/bringup1_send_0x155.py" --tx-iface vcan0 --return-iface vcan1
RC1=$?

echo "=== 2단계: 왕복 레이턴시 ==="
"$PY" "$HERE/tests/latency_probe.py" --tx-iface vcan0 --return-iface vcan1 --n 200

echo "=== 결과 ==="
[ "$RC1" -eq 0 ] && echo "✅ 1단계 PASS" || echo "❌ 1단계 FAIL"
