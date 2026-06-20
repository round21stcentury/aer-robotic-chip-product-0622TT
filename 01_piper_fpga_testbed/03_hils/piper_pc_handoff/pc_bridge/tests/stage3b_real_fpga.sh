#!/usr/bin/env bash
# stage 3b (★실제 FPGA★) — Gazebo 3D 루프. 팀원 stage3b 의 mock_fpga 를 실제 Zybo 로 교체.
#
# 전체 경로:
#   /joint_ctrl_single → 컨트롤러(piper_sdk, vcan0) → 0x155-7 → bridge → UDP → ★실제 Zybo★
#     → 물리CAN → can0 → virtual_robot(gazebo) → /arm_controller/joint_trajectory → Gazebo 로봇 이동
#     → Gazebo /joint_states → virtual_robot → 0x2A5-7 → vcan0 → 컨트롤러 → joint_states_feedback
#
# 컨테이너 안에서 디스플레이와 함께 실행 (make sdk-gazebo 가 docker run 처리).
#   ★HOST 선행★: 보드 program(05) + make fpga-prep + make can-setup
set -uo pipefail
set +u
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPGA_IP="${FPGA_IP:-192.168.1.10}"
PIDS=()
cleanup() { echo "[3b-hw] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

for n in vcan0 can0; do
  ip link show "$n" >/dev/null 2>&1 || { echo "❌ $n 없음 — HOST 에서 fpga-prep + can-setup 먼저"; exit 1; }
done

echo "=== Gazebo + ros2_control 기동 (스폰/컨트롤러 active 까지 ~15s) ==="
ros2 launch piper_gazebo piper_gazebo.launch.py & PIDS+=($!)
for i in $(seq 1 40); do
  if ros2 control list_controllers 2>/dev/null | grep -q "arm_controller.*active"; then
    echo "[3b-hw] arm_controller active"; break
  fi
  sleep 1
done

echo "=== PC측 파이프라인 (bridge→실제FPGA $FPGA_IP, virtual_robot[gazebo] cmd=can0) ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip "$FPGA_IP" --port 5000 & PIDS+=($!)
python3 $PB/vrobot/virtual_robot.py --cmd-iface can0 --fb-iface vcan0 \
        --backend gazebo --fb-hz 200 & PIDS+=($!)
sleep 2

echo "=== 컨트롤러(piper_sdk, vcan0, judge_flag=false) ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=false \
    -p judge_flag:=false & PIDS+=($!)
sleep 4

echo "=== enable + 관절 명령(천천히 여러 자세) — Gazebo 에서 로봇이 움직이는지 관찰 ==="
timeout 15 ros2 topic pub --once /enable_flag std_msgs/msg/Bool "{data: true}"
sleep 1
POSES=(
  "0.0 0.0 0.0 0.0 0.0 0.0"
  "0.5 -0.4 0.6 0.0 0.3 0.0"
  "-0.5 0.4 -0.6 0.0 -0.3 0.2"
  "0.0 0.0 0.0 0.0 0.0 0.0"
)
for p in "${POSES[@]}"; do
  read -r j1 j2 j3 j4 j5 j6 <<< "$p"
  echo "[3b-hw] target rad: $p"
  for i in 1 2 3 4 5 6; do
    ros2 topic pub --once /joint_ctrl_single sensor_msgs/msg/JointState \
      "{name: [joint1,joint2,joint3,joint4,joint5,joint6], position: [$j1,$j2,$j3,$j4,$j5,$j6]}" >/dev/null
    sleep 0.4
  done
  sleep 2
done

echo "=== 피드백 확인 (joint_states_feedback) ==="
timeout 5 ros2 topic echo --once /joint_states_feedback || true
echo "=== 끝. Gazebo 에서 로봇이 명령대로 움직였으면 ✅ 실제FPGA HIL 3D 루프 완성 ==="
echo "    (명령은 실제 Zybo CAN을 거쳐 나갔고, Gazebo가 그걸 받아 움직인 것)"
echo "    (Ctrl-C 로 종료)"
wait
