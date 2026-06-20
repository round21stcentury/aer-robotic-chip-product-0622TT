#!/usr/bin/env bash
# ★실제 Piper 로봇★ 슬라이더 제어 — Gazebo/가상로봇/USB-CAN 없음.
#   슬라이더 → 컨트롤러(piper_sdk, vcan0) → 0x155-7 → bridge → 실제 Zybo → 물리 CAN → ★진짜 로봇★
#
#   USB-CAN/Gazebo 불필요: 진짜 로봇이 CAN 버스에서 직접 명령을 받고 ACK도 줌(=로봇 대역 그 자체).
#   피드백은 컨트롤러로 안 돌아옴(우리 FPGA 단방향) — 명령 송신은 enable_flag 만 있으면 되므로 동작 OK.
#
# ★★ 안전 ★★ 실제 팔이 움직인다:
#   - 주변 치우고, 비상정지(로봇 물리 E-STOP) 손 닿는 곳에.
#   - 속도% 슬라이더 낮게(기본 20) 시작. 관절 슬라이더는 0에서 조금씩.
#   - 컨트롤러는 피드백을 못 봐서(개루프) 충돌을 모름 — 로봇 자체 펌웨어 보호만 작동. 천천히.
#
# HOST 선행: 보드 program(05) + make fpga-prep(PC IP+정적ARP) + vcan0 up.  (USB-CAN/can0 불필요)
set -uo pipefail
set +u
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPGA_IP="${FPGA_IP:-192.168.1.10}"
PIDS=()
cleanup() { echo "[robot] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

ip link show vcan0 >/dev/null 2>&1 || { echo "❌ vcan0 없음 — HOST 에서 vcan0 먼저 (make robot-prep)"; exit 1; }

echo "=== bridge: vcan0 명령 → 실제 FPGA($FPGA_IP) → 물리 CAN → 진짜 로봇 ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip "$FPGA_IP" --port 5000 & PIDS+=($!)
sleep 1

echo "=== 컨트롤러(piper_sdk, vcan0, judge_flag=false) ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=true \
    -p judge_flag:=false -p exit_on_loss:=false & PIDS+=($!)  # ★gripper_exist=true → position[6] 슬라이더가 0x159 GripperCtrl 발신
sleep 4

echo ""
echo "  ★★★ 실제 로봇이 움직입니다 ★★★"
echo "  슬라이더 창에서: ① 속도% 낮게 확인  ② [Enable] 누름  ③ 관절 슬라이더 천천히"
echo "  멈추려면 [Disable] 또는 로봇 물리 E-STOP. 창 닫으면 종료."
echo ""
python3 $PB/tools/joint_slider_gui_robot.py   # ★속도% 슬라이더 포함(실로봇 안전 저속 시작)★
