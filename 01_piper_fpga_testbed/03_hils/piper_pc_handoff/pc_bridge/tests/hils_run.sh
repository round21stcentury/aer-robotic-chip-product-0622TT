#!/usr/bin/env bash
# HILS 디스패처 — MODE×APP 을 "검증된 전용 스크립트"로 라우팅.
#   ★롤백 이유★ 한 스크립트로 sim/hil/robot 다 하려다(통합) hil 슬라이더가 깨졌음
#   (로봇 축 처짐 + 슬라이더 안 뜸). 그래서 각 시나리오는 자기 검증된 스크립트로 분리해 둠.
#
#   hil  + slider  → stage3b_slider.sh      (실FPGA + Gazebo + 슬라이더, 검증됨 — 손대지 말 것)
#   robot+ slider  → real_robot_slider.sh   (진짜 로봇 + 슬라이더, 검증됨 — 손대지 말 것)
#   sim  + slider  → 아래 인라인            (mock_fpga + Gazebo + 슬라이더; stage3b 구조 그대로)
#   * + motions/x  → 아래 인라인            (해당 MODE 파이프라인 + 모션 스크립트)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${MODE:-sim}"; APP="${APP:-slider}"

# ★이전 run 의 DDS 공유메모리 찌꺼기 청소★ (컨테이너 root 라 root 소유 파일도 지워짐).
#  --ipc host 로 /dev/shm 을 호스트와 공유 → 안 지우면 누적 찌꺼기가 다음 gazebo 의
#  ros2_control 컨트롤러를 !rclpy.ok() 로 죽임(=로봇 처짐/안움직임). 매 실행 시작에 청소.
rm -f /dev/shm/fastrtps_* /dev/shm/sem.fastrtps_* /dev/shm/fast_datasharing_* 2>/dev/null || true

# ── 검증된 전용 스크립트로 위임 (통합 안 함) ──
if [ "$APP" = slider ]; then
  case "$MODE" in
    hil)   exec bash "$HERE/stage3b_slider.sh" ;;
    robot) exec bash "$HERE/real_robot_slider.sh" ;;
  esac
fi

# ── 그 외(sim 슬라이더 / 모든 MODE 의 모션): 인라인 ──
#   stage3b_slider.sh 와 동일한 "Gazebo → arm_controller active 대기 → 파이프라인" 구조.
#   ★대기 루프 유지★ (빼면 gazebo 준비 전 시작돼 로봇이 축 처짐). 출력은 터미널로(검증본과 동일).
set +u
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
set -u
PB="$(cd "$HERE/.." && pwd)"   # = /pc_bridge
BACKEND="${BACKEND:-gazebo}"; FPGA_IP="${FPGA_IP:-192.168.1.10}"
# ★reflex_pursue 모션은 ikpy(IK) 의존 → 없으면 자동 설치 (컨테이너 --rm 이라 매 실행 확인)
case "${APP:-}" in *reflex_pursue*) python3 -c "import ikpy" 2>/dev/null || { echo "[deps] reflex_pursue: ikpy 설치중..."; pip3 install -q ikpy 2>/dev/null && echo "[deps] ikpy OK"; } ;; esac
PIDS=(); cleanup(){ echo "[hils] cleanup"; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null||true; done; }
trap cleanup EXIT INT TERM

case "$MODE" in
  sim)
    for n in vcan0 vcan1; do ip link show $n >/dev/null 2>&1 || { echo "❌ $n 없음 → HOST: make prep MODE=sim"; exit 1; }; done
    FPGA_TARGET=127.0.0.1; VROBOT_CMD=vcan1; USE_MOCK=1 ;;
  hil)  # (모션 전용; 슬라이더는 위에서 위임됨)
    for n in vcan0 can0; do ip link show $n >/dev/null 2>&1 || { echo "❌ $n 없음 → HOST: make prep MODE=hil"; exit 1; }; done
    FPGA_TARGET=$FPGA_IP; VROBOT_CMD=can0; USE_MOCK=0 ;;
  robot)
    ip link show vcan0 >/dev/null 2>&1 || { echo "❌ vcan0 없음 → HOST: make prep MODE=robot"; exit 1; }
    FPGA_TARGET=$FPGA_IP; USE_MOCK=0; BACKEND=none
    echo ""; echo "  ★★★ 실제 로봇 모드 ★★★ 속도 낮게, E-STOP 손 닿는 곳에. 개루프(피드백X) 주의."; echo "" ;;
  *) echo "MODE 는 sim|hil|robot"; exit 1 ;;
esac

# Gazebo (sim/hil 가상로봇 + gazebo 백엔드일 때) — ★검증된 대기 루프★
if [ "$BACKEND" = gazebo ]; then
  echo "=== Gazebo + ros2_control 기동 (arm_controller active 까지 대기) ==="
  ros2 launch piper_gazebo piper_gazebo.launch.py & PIDS+=($!)
  for i in $(seq 1 40); do
    ros2 control list_controllers 2>/dev/null | grep -q "arm_controller.*active" && { echo "[hils] arm_controller active"; break; }
    sleep 1
  done
fi

echo "=== bridge: vcan0 → $FPGA_TARGET:5000 ==="
python3 $PB/bridge/can_udp_bridge.py --iface vcan0 --fpga-ip "$FPGA_TARGET" --port 5000 & PIDS+=($!)
python3 $PB/tools/reflex_status_node.py & PIDS+=($!)   # ★반사상태 노드: localhost:5001 → /reflex_active (반사인지 모션용. 호스트의 latency-gui가 시리얼[RFX]→5001 로 먹임)
[ "${USE_MOCK}" = 1 ] && { echo "=== mock_fpga ==="; python3 $PB/tools/mock_fpga.py --out-iface vcan1 --port 5000 & PIDS+=($!); }
[ "$BACKEND" = gazebo ] && { echo "=== virtual_robot (cmd=$VROBOT_CMD, gazebo) ==="; python3 $PB/vrobot/virtual_robot.py --cmd-iface $VROBOT_CMD --fb-iface vcan0 --backend gazebo --fb-hz 200 & PIDS+=($!); }
sleep 2

# exit_on_loss: robot 은 단방향 개루프라 false(피드백 없어도 안 죽게), 그 외 false 로 통일(HIL도 피드백 단방향)
echo "=== 컨트롤러 (piper_sdk, vcan0, judge_flag=false) ==="
ros2 run piper piper_single_ctrl --ros-args \
    -p can_port:=vcan0 -p auto_enable:=false -p gripper_exist:=true \
    -p judge_flag:=false -p exit_on_loss:=false & PIDS+=($!)
sleep 4

if [ "$APP" = slider ]; then
  echo "=== 슬라이더 GUI — [Enable] 후 슬라이더 ==="
  python3 $PB/tools/joint_slider_gui_v3.py
else
  echo "=== 모션 실행: $APP ==="
  python3 $PB/$APP   # 따옴표 제거 → APP="motions/x.py --arg v" 로 인자 전달 (경로엔 공백 없음)
  echo "=== 모션 끝 ==="
  [ "$MODE" != robot ] && wait || true
fi
