#!/usr/bin/env bash
# ── 컨테이너 "내부"에서 최초 1회 실행 ──
# Piper humble 브랜치 클론 → 의존성(rosdep) → colcon 빌드
set -euo pipefail
source /opt/ros/humble/setup.bash
cd /root/ros2_ws

if [ ! -d src/piper_ros ]; then
  echo "[setup] piper_ros (humble) 클론..."
  git clone -b humble https://github.com/agilexrobotics/piper_ros.git src/piper_ros
fi

echo "[setup] rosdep 의존성 해소 (Gazebo flavor 등 자동)..."
apt-get update
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble || \
  echo "⚠️  일부 rosdep 키 미해결 — 로그 확인 후 수동 설치 필요할 수 있음"

echo "[setup] 파이썬 노드 스크립트 실행권한 부여..."
# AgileX 리포의 scripts/*.py 는 실행권한(x)이 빠져 있어,
# --symlink-install 시 ros2 launch가 "executable not found"를 낸다. 미리 +x.
find src/piper_ros -path "*/scripts/*.py" -exec chmod +x {} \;

echo "[setup] colcon build..."
colcon build --symlink-install

echo "✅ 빌드 완료.  다음 명령으로 환경 적용:"
echo "    source /root/ros2_ws/install/setup.bash"
