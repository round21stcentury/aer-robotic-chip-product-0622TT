# Piper HIL 개발 컨테이너
# 호스트가 Ubuntu 24.04(noble)라 네이티브 ROS2 Humble 불가 →
# jammy(22.04) 기반 osrf/ros:humble 이미지로 Humble 환경을 격리 실행한다.
FROM osrf/ros:humble-desktop-full

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble

# 기본 도구 + SocketCAN 유틸 + Gazebo(Classic 11) + MoveIt + ros2_control
RUN apt-get update && apt-get install -y --no-install-recommends \
      git nano python3-pip python3-colcon-common-extensions \
      can-utils iproute2 iputils-ping net-tools mesa-utils \
      ros-humble-gazebo-ros-pkgs ros-humble-gazebo-ros2-control \
      ros-humble-moveit ros-humble-ros2-control ros-humble-ros2-controllers \
    && rm -rf /var/lib/apt/lists/*
# (대안) Piper humble 시뮬이 Ignition/Fortress를 쓰면 아래를 활성화:
#   RUN apt-get update && apt-get install -y ros-humble-ros-gz && rm -rf /var/lib/apt/lists/*
#   → 보통은 setup-workspace.sh의 rosdep가 알아서 끌어온다.

# Piper Python SDK + python-can
RUN pip3 install --no-cache-dir piper_sdk python-can

# rosdep 캐시
RUN rosdep update

# 진입 시 자동 소싱 (전역 + 워크스페이스)
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc && \
    echo "[ -f /root/ros2_ws/install/setup.bash ] && source /root/ros2_ws/install/setup.bash" >> /root/.bashrc

WORKDIR /root/ros2_ws
CMD ["bash"]
