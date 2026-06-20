#!/usr/bin/env bash
# stage 3a (★실제 FPGA★) — piper_sdk 컨트롤러를 루프에 넣어 실제 Zybo 하드웨어로 교차검증.
#   팀원 stage3a_piper_in_loop.sh 의 mock_fpga(127.0.0.1) 자리를 실제 보드(192.168.1.10)로 교체.
#
# 경로: 컨트롤러(can_port=vcan0) → 0x155-7 → bridge → UDP → ★실제 Zybo★ → 물리CAN → can0
#        → virtual_robot(kinematic, cmd=can0) → 0x2A5-7 피드백 → vcan0 → 컨트롤러 → joint_states_feedback
#
# 컨테이너 안에서 실행 (network host 로 host 의 vcan0/can0/이더넷 공유).
#   ★HOST 선행조건(컨테이너 밖)★:
#     - 보드에 앱 program 돼 있음 (05_zybo_can_eth: make program)
#     - make -C 03_hils fpga-prep      # PC 정적IP + 보드 정적ARP
#     - sudo bash setup/setup_can.sh hw  # vcan0 + 실제 can0(1M)   (또는 make can-setup)
set -uo pipefail
set +u
source /opt/ros/humble/setup.bash
[ -f /root/ros2_ws/install/setup.bash ] && source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FPGA_IP="${FPGA_IP:-192.168.1.10}"
PIDS=()
cleanup() { echo "[3a-hw] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

# 인터페이스 확인 (vcan0=컨트롤러 버스, can0=실제 USB-CAN = FPGA 출력)
for n in vcan0 can0; do
  ip link show "$n" >/dev/null 2>&1 || { echo "❌ $n 없음 — HOST 에서 setup_can.sh hw + fpga-prep 먼저"; exit 1; }
done

echo "=== PC측 파이프라인 (bridge→실제FPGA $FPGA_IP, virtual_robot cmd=can0) ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip "$FPGA_IP" --port 5000 & PIDS+=($!)
python3 $PB/vrobot/virtual_robot.py --cmd-iface can0 --fb-iface vcan0 \
        --backend kinematic --fb-hz 200 & PIDS+=($!)
sleep 1

echo "=== 컨트롤러(piper_sdk) 기동: can_port=vcan0  judge_flag=false ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=false \
    -p judge_flag:=false & PIDS+=($!)
sleep 4   # ConnectPort + 피드백 수신으로 isOk 안정화

echo "=== enable ==="
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
echo "=== 끝. position 이 commanded 와 ~일치하면 ✅ piper_sdk→실제Zybo CAN 루프 + 코덱 교차검증 OK ==="
