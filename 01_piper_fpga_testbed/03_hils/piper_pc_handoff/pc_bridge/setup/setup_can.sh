#!/usr/bin/env bash
# CAN 인터페이스 brings-up. 두 모드:
#   sim : vcan0(컨트롤러 버스) + vcan1(can0 대역, mock_fpga 출력)  — FPGA 없이 PC 단독
#   hw  : vcan0 + 실제 can0(gs_usb 1Mbps)                          — 실제 USB-CAN/FPGA 통합
#
# 사용: sudo bash setup/setup_can.sh [sim|hw]   (기본 sim)
# 다운: sudo bash setup/setup_can.sh down
set -euo pipefail
MODE="${1:-sim}"
BITRATE=1000000

up_vcan() {
  local name="$1"
  sudo modprobe vcan
  if ! ip link show "$name" >/dev/null 2>&1; then
    sudo ip link add dev "$name" type vcan
  fi
  sudo ip link set up "$name"
  echo "[setup] $name (vcan) up"
}

case "$MODE" in
  sim)
    up_vcan vcan0
    up_vcan vcan1   # mock_fpga 가 여기로 TX → 가상로봇이 여기서 RX (can0 대역)
    echo "[setup] sim 모드 준비됨. 반환 버스 = vcan1 (mock_fpga --out-iface vcan1)"
    ;;
  hw)
    up_vcan vcan0
    sudo modprobe gs_usb || true
    # 실제 USB-CAN 을 can0 1Mbps 로. 기존 can_activate.sh 가 있으면 그걸 권장.
    if ip link show can0 >/dev/null 2>&1; then
      sudo ip link set can0 down 2>/dev/null || true
      sudo ip link set can0 type can bitrate "$BITRATE"
      sudo ip link set up can0
      echo "[setup] can0 (gs_usb) up @ ${BITRATE}bps"
    else
      echo "[setup] ⚠️ can0 인터페이스 없음 — USB-CAN 연결 확인 후"
      echo "        piper_ros/can_activate.sh can0 ${BITRATE} 사용 권장"
      exit 1
    fi
    ;;
  down)
    for n in vcan0 vcan1 can0; do
      if ip link show "$n" >/dev/null 2>&1; then
        sudo ip link set "$n" down 2>/dev/null || true
        [ "$n" != can0 ] && sudo ip link delete "$n" 2>/dev/null || true
      fi
    done
    echo "[setup] interfaces down"
    ;;
  *)
    echo "usage: sudo bash setup/setup_can.sh [sim|hw|down]"; exit 1 ;;
esac

ip -br link show type vcan 2>/dev/null || true
ip -br link show type can 2>/dev/null || true
