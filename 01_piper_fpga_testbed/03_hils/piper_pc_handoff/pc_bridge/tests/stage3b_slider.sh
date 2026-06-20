#!/usr/bin/env bash
# stage 3b (실제 FPGA) + 슬라이더 GUI — 대화형 데모.
#   Gazebo + 파이프라인 기동 후, 스크립트 자세 대신 슬라이더 GUI 로 사람이 직접 조종.
#   슬라이더 → 컨트롤러 → 실제 Zybo CAN → 가상로봇 → Gazebo.
#   HOST 선행: 보드 program + make fpga-prep + make can-setup
set -uo pipefail
set +u
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPGA_IP="${FPGA_IP:-192.168.1.10}"
PIDS=()
cleanup() { echo "[3b-ui] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

for n in vcan0 can0; do
  ip link show "$n" >/dev/null 2>&1 || { echo "❌ $n 없음 — HOST 에서 fpga-prep + can-setup 먼저"; exit 1; }
done

# ★순차 실행★ gazebo 컨트롤러가 "격리된 상태로" 다 뜬 뒤 파이프라인 시작.
#  (동시에 시작하면 스폰 경합으로 컨트롤러가 !rclpy.ok() 로 죽음 = 로봇 안 움직임.)
echo "=== Gazebo + ros2_control 기동 ==="
echo "    ⏳ gazebo 컨트롤러 준비 중 — 슬라이더는 준비 끝나면 자동으로 뜹니다. ★이 창들 닫지 마세요★"
ros2 launch piper_gazebo piper_gazebo.launch.py & PIDS+=($!)
ok=0
for i in $(seq 1 30); do
  timeout 3 ros2 control list_controllers 2>/dev/null | grep -q "arm_controller.*active" && { echo "[3b-ui] ✅ arm_controller active (${i}초) — 이제 파이프라인+슬라이더"; ok=1; break; }
  echo "    ... gazebo 준비 대기 ${i}/30초 (닫지 마세요)"
  sleep 1
done
[ "$ok" = 0 ] && echo "[3b-ui] ⚠️ arm_controller 확인 못함 — 그래도 진행"

echo "=== bridge→실제FPGA + virtual_robot[gazebo](cmd=can0) ★can0→gazebo 옮기는 핵심★ ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip "$FPGA_IP" --port 5000 & PIDS+=($!)
python3 $PB/vrobot/virtual_robot.py --cmd-iface can0 --fb-iface vcan0 --backend gazebo --fb-hz 200 & PIDS+=($!)
sleep 2

echo "=== 컨트롤러(piper_sdk, vcan0, judge_flag=false) ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=true -p judge_flag:=false & PIDS+=($!)  # ★gripper_exist=true → position[6] 슬라이더가 0x159 GripperCtrl 발신
sleep 4

echo "=== 슬라이더 GUI 기동 — Enable 누르고 슬라이더 움직이면 Gazebo 팔이 움직임 ==="
echo "    (명령은 실제 Zybo 의 CAN 을 거쳐 나갑니다. 창 닫으면 종료)"
python3 $PB/tools/joint_slider_gui_v3.py
