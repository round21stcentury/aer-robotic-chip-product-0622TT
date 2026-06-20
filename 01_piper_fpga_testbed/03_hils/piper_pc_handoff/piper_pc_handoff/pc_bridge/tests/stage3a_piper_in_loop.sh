#!/usr/bin/env bash
# stage 3a — piper_sdk 를 루프에 넣어 코덱을 '실코드'로 양방향 교차검증 (Gazebo 불필요).
# 계약서 §부록의 골든 레퍼런스 검증: piper_sdk 인코딩 ↔ 우리 디코딩 ↔ 우리 인코딩 ↔ piper_sdk 디코딩.
#
# 컨테이너 안에서 실행 (network_mode host 로 host vcan 공유). 선행: host 에서 vcan0/vcan1 생성.
#   docker run --rm --network host -v /home/sihun/workspace/pc_bridge:/pc_bridge \
#       piper-hil:humble bash /pc_bridge/tests/stage3a_piper_in_loop.sh
#
# 경로: 컨트롤러(can_port=vcan0) → 0x155-7 → bridge → UDP → mock_fpga → vcan1
#        → virtual_robot(kinematic) → 0x2A5-7 → vcan0 → 컨트롤러 → joint_states_feedback
set -uo pipefail
set +u   # ROS setup.bash 가 언바운드 변수를 참조함
source /opt/ros/humble/setup.bash
[ -f /root/ros2_ws/install/setup.bash ] && source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 스크립트 위치 기준 (컨테이너=/pc_bridge, 어디든 OK)
PIDS=()
cleanup() { echo "[3a] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

# vcan 확인
for n in vcan0 vcan1; do
  ip link show "$n" >/dev/null 2>&1 || { echo "❌ $n 없음 — host 에서 setup_can.sh sim 먼저"; exit 1; }
done

echo "=== PC측 파이프라인 기동 (bridge + mock_fpga + virtual_robot[kinematic]) ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip 127.0.0.1 --port 5000 & PIDS+=($!)
python3 $PB/tools/mock_fpga.py --out-iface vcan1 --port 5000 & PIDS+=($!)
python3 $PB/vrobot/virtual_robot.py --cmd-iface vcan1 --fb-iface vcan0 \
        --backend kinematic --fb-hz 200 & PIDS+=($!)
sleep 1

echo "=== 컨트롤러(piper_sdk) 기동: can_port=vcan0 ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=false \
    -p judge_flag:=false & PIDS+=($!)   # judge_flag=false 면 exist/up/bitrate 체크 모두 스킵
sleep 4   # ConnectPort + 피드백 수신으로 isOk 안정화

echo "=== enable (enable_flag=true; 피드백 게이팅 없음) ==="
timeout 15 ros2 topic pub --once /enable_flag std_msgs/msg/Bool "{data: true}"
sleep 1

CMD="0.20 -0.30 0.40 0.0 0.10 -0.15"
echo "=== 관절 명령 발행 (rad): $CMD ==="
read -r j1 j2 j3 j4 j5 j6 <<< "$CMD"
for i in 1 2 3 4 5; do
  timeout 15 ros2 topic pub --once /joint_ctrl_single sensor_msgs/msg/JointState \
    "{name: [joint1,joint2,joint3,joint4,joint5,joint6], position: [$j1,$j2,$j3,$j4,$j5,$j6]}" >/dev/null
  sleep 0.3
done
sleep 1

echo "=== 피드백 수신 (joint_states_feedback) — 명령과 일치해야 루프 성공 ==="
echo "commanded: $CMD"
timeout 5 ros2 topic echo --once /joint_states_feedback || echo "(피드백 echo 타임아웃)"
echo "=== 끝. position 이 commanded 와 ~일치하면 ✅ 전체 CAN 루프 + 코덱 교차검증 OK ==="
