#!/usr/bin/env bash
# Piper HIL 컨테이너 실행 — ROS2 Humble + Gazebo (호스트 Ubuntu 24.04)
# --network host 로 HIL UDP/SocketCAN을 호스트와 동일하게 사용한다(NAT 없음).
set -euo pipefail

IMAGE="piper-hil:humble"
CONTAINER="piper-hil"
HERE="$(cd "$(dirname "$0")" && pwd)"
WS_DIR="$HERE/ros2_ws"          # 호스트에 영속되는 ROS2 워크스페이스
mkdir -p "$WS_DIR/src"

# Gazebo/rviz GUI 창 허용
xhost +local:root >/dev/null 2>&1 || true

# 이미 떠 있으면 그 컨테이너로 접속
if [ -n "$(docker ps -q -f name=^/${CONTAINER}$)" ]; then
  echo "[run] 실행 중 컨테이너에 접속합니다."
  exec docker exec -it "$CONTAINER" bash
fi

DEV_ARGS=()
[ -e /dev/dri ] && DEV_ARGS+=(--device=/dev/dri)         # iGPU 렌더 가속(있으면)
# USB-CAN/USB-시리얼(Zybo) 패스스루가 필요하면 주석 해제:
# [ -e /dev/ttyUSB0 ] && DEV_ARGS+=(--device=/dev/ttyUSB0)

exec docker run -it --rm \
  --name "$CONTAINER" \
  --network host \
  --ipc host \
  --env DISPLAY="$DISPLAY" \
  --env QT_X11_NO_MITSHM=1 \
  --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
  --volume "$WS_DIR":/root/ros2_ws:rw \
  "${DEV_ARGS[@]}" \
  "$IMAGE" bash
