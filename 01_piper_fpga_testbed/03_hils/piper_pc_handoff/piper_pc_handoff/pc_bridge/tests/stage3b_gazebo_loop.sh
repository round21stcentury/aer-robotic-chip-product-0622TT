#!/usr/bin/env bash
# stage 3b — Gazebo 3D 루프. 컨테이너 '안'에서 디스플레이와 함께 실행.
#
# 전체 경로:
#   /joint_ctrl_single → 컨트롤러(piper_sdk, vcan0) → 0x155-7 → bridge → UDP → mock_fpga → vcan1
#     → virtual_robot(gazebo) → /arm_controller/joint_trajectory → Gazebo 로봇 이동
#     → Gazebo /joint_states → virtual_robot → 0x2A5-7 → vcan0 → 컨트롤러 → joint_states_feedback
#
# 컨테이너 진입(호스트, 디스플레이+마운트):
#   xhost +local: 2>/dev/null
#   docker run --rm -it --network host \
#     -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
#     --device /dev/dri \
#     -v /home/sihun/workspace/pc_bridge:/pc_bridge \
#     -v <...>/ros2_ws:/root/ros2_ws \
#     piper-hil:humble bash
#   # 컨테이너 안에서:
#   bash /pc_bridge/tests/stage3b_gazebo_loop.sh
#
# 선행(호스트): sudo bash pc_bridge/setup/setup_can.sh sim   # vcan0/vcan1
set -uo pipefail
set +u
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 스크립트 위치 기준 (컨테이너=/pc_bridge, 어디든 OK)
PIDS=()
cleanup() { echo "[3b] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

for n in vcan0 vcan1; do
  ip link show "$n" >/dev/null 2>&1 || { echo "❌ $n 없음 — host 에서 setup_can.sh sim 먼저"; exit 1; }
done

echo "=== Gazebo + ros2_control 기동 (스폰/컨트롤러 active 까지 ~15s) ==="
ros2 launch piper_gazebo piper_gazebo.launch.py & PIDS+=($!)
# arm_controller 가 active 될 때까지 대기 (최대 40s)
for i in $(seq 1 40); do
  if ros2 control list_controllers 2>/dev/null | grep -q "arm_controller.*active"; then
    echo "[3b] arm_controller active"; break
  fi
  sleep 1
done

echo "=== PC측 파이프라인 (bridge + mock_fpga + virtual_robot[gazebo]) ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip 127.0.0.1 --port 5000 & PIDS+=($!)
python3 $PB/tools/mock_fpga.py --out-iface vcan1 --port 5000 & PIDS+=($!)
python3 $PB/vrobot/virtual_robot.py --cmd-iface vcan1 --fb-iface vcan0 \
        --backend gazebo --fb-hz 200 & PIDS+=($!)
sleep 2

echo "=== 컨트롤러(piper_sdk, vcan0, judge_flag=false) ==="
# ros2 run 사용: launch 의 joint_ctrl_single->/joint_states 리맵을 피해 /joint_ctrl_single 로 받음
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
  echo "[3b] target rad: $p"
  for i in 1 2 3 4 5 6; do
    ros2 topic pub --once /joint_ctrl_single sensor_msgs/msg/JointState \
      "{name: [joint1,joint2,joint3,joint4,joint5,joint6], position: [$j1,$j2,$j3,$j4,$j5,$j6]}" >/dev/null
    sleep 0.4
  done
  sleep 2
done

echo "=== 피드백 확인 (joint_states_feedback) ==="
timeout 5 ros2 topic echo --once /joint_states_feedback || true
echo "=== 끝. Gazebo 에서 로봇이 명령대로 움직였고 피드백이 돌아왔으면 ✅ HIL 루프(시뮬) 완성 ==="
echo "    (Ctrl-C 로 종료; 백그라운드 정리됨)"
wait
