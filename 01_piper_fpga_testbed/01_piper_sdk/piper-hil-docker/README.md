# Piper HIL Docker 환경 (ROS 2 Humble + Gazebo)

> 호스트 **Ubuntu 24.04(noble)** 에서 ROS 2 **Humble**(=22.04 네이티브)을 컨테이너로 격리 실행.
> `--network host` 라서 추후 **FPGA HIL 연결(UDP/SocketCAN)** 이 네이티브와 동일하게 동작한다.
> 관련 설계: [../기술평가_및_시스템스펙.md](../기술평가_및_시스템스펙.md)

## 구성 파일
| 파일 | 역할 | 실행 위치 |
|---|---|---|
| `Dockerfile` | Humble + Gazebo + MoveIt + CAN 도구 + piper_sdk 이미지 | — |
| `build.sh` | 이미지 빌드 | 호스트 |
| `run.sh` | 컨테이너 실행(X11·host network·디바이스) | 호스트 |
| `docker-compose.yml` | run.sh의 compose 버전(택1) | 호스트 |
| `setup-workspace.sh` | Piper 클론·rosdep·colcon build | **컨테이너 내부** |
| `ros2_ws/` | 호스트에 영속되는 워크스페이스(자동 생성, 마운트됨) | — |

---

## 0. Docker 설치 (Ubuntu 24.04, 최초 1회)
```bash
# 공식 저장소 등록
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# sudo 없이 docker 사용 (재로그인 또는 newgrp 필요)
sudo usermod -aG docker $USER
newgrp docker   # 또는 로그아웃 후 재로그인
docker run --rm hello-world   # 동작 확인
```

## 1. 이미지 빌드 (호스트)
```bash
cd piper-hil-docker
chmod +x *.sh        # 최초 1회
./build.sh           # 수~십수 분 (네트워크/CPU 의존)
```

## 2. 컨테이너 실행 / 종료 (호스트)
```bash
./run.sh             # 들어가기: X11 + --network host + 워크스페이스 마운트
# 또는:  docker compose run --rm piper-hil
```
- **나가기/종료**: 컨테이너 셸에서 `exit` (또는 Ctrl+D). `--rm`이라 나가면 컨테이너는 **자동 삭제**됨(정상 — §아래 "영속성" 참고).
- **두 번째 터미널**에서 같은 컨테이너 접속: 그냥 다시 `./run.sh` (실행 중이면 자동 접속).

> **영속성 (꼭 이해)**: `ros2_ws/`는 호스트 디스크에 마운트돼 있다. 컨테이너를 지워도(=exit)
> 소스·빌드(`build/`,`install/`)는 **호스트에 그대로 남는다**. 또 `.bashrc`에 자동 소싱을 넣어놔서
> 새 셸을 열 때마다 `install/setup.bash`가 **자동 실행**된다.
> ⟹ **최초 1회만 클론+빌드**하면, 이후엔 `./run.sh` 후 곧바로 `ros2 launch ...` 가능.
> (소스를 **수정했을 때만** `colcon build` 다시.)

## 3. Piper 워크스페이스 빌드 (컨테이너 내부, **최초 1회만**)
컨테이너 셸이 뜨면 아래를 순서대로:
```bash
cd /root/ros2_ws
git clone -b humble https://github.com/agilexrobotics/piper_ros.git src/piper_ros
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble
colcon build --symlink-install
source install/setup.bash      # 이번 셸만. 다음부터는 .bashrc가 자동 소싱
```

## 4. Gazebo 시뮬 기동 검증
**런치 파일명 먼저 찾기** (humble 브랜치마다 다를 수 있음):
```bash
find /root/ros2_ws/src/piper_ros -name "*.launch.py" | grep -i gazebo
# 또는 자동완성:  ros2 launch piper_<Tab><Tab>
# 또는 호스트 파일탐색기로  piper-hil-docker/ros2_ws/src/piper_ros/  열어보기
```
찾은 패키지/파일명으로 실행:
```bash
ros2 launch <패키지명> <찾은_파일>.launch.py
```
Gazebo 창이 호스트 화면에 뜨고 Piper 모델이 로드되면 성공.

---

## HIL 연결 시 (나중 단계)
- **이더넷/UDP → Zybo**: `--network host` 라 컨테이너가 호스트 NIC를 그대로 씀 → 추가 설정 없이 동작, NAT 지연 없음.
- **SocketCAN(`can0`, USB-CAN 동글)**: 드라이버 `modprobe` 는 **호스트에서** 수행(컨테이너는 호스트 커널 공유). 이후 컨테이너에서 `ip link`, `candump can0` 로 접근.
  ```bash
  # 호스트에서:
  sudo modprobe can can_raw
  sudo ip link set can0 type can bitrate 1000000   # Piper = 1 Mbps
  sudo ip link set up can0
  ```
- **USB-CAN/USB-시리얼 패스스루**: `run.sh` 의 `--device=/dev/ttyUSB0` 주석 해제.

---

## 트러블슈팅
| 증상 | 조치 |
|---|---|
| Gazebo 창 안 뜸 / `cannot open display` | 호스트에서 `xhost +local:root` 실행. `echo $DISPLAY` 확인 |
| Gazebo 매우 느림 | iGPU: `/dev/dri` 마운트 확인. NVIDIA: `nvidia-container-toolkit` 설치 후 `--gpus all` 추가 |
| `rosdep` 키 미해결 | humble 시뮬이 Ignition 사용 시 → `apt install ros-humble-ros-gz` 후 재빌드 |
| colcon 빌드 에러 | piper_ros humble 브랜치 이슈 확인, 패키지별로 `--packages-select` 로 좁혀 디버그 |
| `executable '*.py' not found on the libexec directory` | 노드 스크립트에 **실행권한 없음**. `--symlink-install`이라 644 소스를 링크해 ros2가 못 찾음. 해결: `find src/piper_ros -path "*/scripts/*.py" -exec chmod +x {} \;` 후 재빌드 |
| `permission denied` (docker) | `sudo usermod -aG docker $USER` 후 재로그인 |

## 메모
- 호스트 24.04 네이티브 ROS2는 **Jazzy**지만 Piper에 jazzy 브랜치가 없어 Humble을 컨테이너로 사용.
- Gazebo flavor(Classic 11 vs Fortress)는 Piper humble 브랜치가 `rosdep`으로 선언한 것에 맞춰 확정됨.

---

## ⭐ 재시작 절차 (도커 종료 후 다시 시작할 때)

> 위 0~3단계(Docker 설치 / 이미지 빌드 / 워크스페이스 클론·빌드)는 **최초 1회만**.
> `exit`로 컨테이너를 껐다가 다시 켤 때는 **아래만** 하면 된다.

### 평소 (소스 수정 없음 — 그냥 다시 켜기)
```bash
cd <…>/piper-hil-docker      # 이 폴더로 이동
./run.sh                     # 컨테이너 진입 (.bashrc가 자동 source → 바로 사용 가능)
ros2 launch piper_gazebo piper_gazebo.launch.py   # 곧바로 실행
```
- **이미지 재빌드 ❌ / 재클론 ❌ / `source` 수동 ❌** — 전부 자동/영속.
- 끝낼 때: 셸에서 `exit` (컨테이너는 `--rm`이라 자동 정리, 작업물 `ros2_ws/`는 호스트에 남음).

### 코드를 수정했을 때만
```bash
./run.sh
cd /root/ros2_ws
colcon build              # 바뀐 패키지만:  colcon build --packages-select <패키지>
source install/setup.bash # 빌드 직후 그 셸에만 반영(다음 셸부턴 .bashrc가 자동)
ros2 launch piper_gazebo piper_gazebo.launch.py
```
> 새 노드 스크립트를 추가했다면 빌드 전에 한 번 더:
> `find src/piper_ros -path "*/scripts/*.py" -exec chmod +x {} \;`

### 두 번째 터미널이 필요할 때 (예: launch + 별도 명령)
```bash
./run.sh        # 실행 중인 컨테이너면 자동으로 그 안으로 접속(docker exec)
```

### 호스트를 재부팅했을 때
- Docker 데몬은 보통 자동 시작. 위 "평소" 절차 그대로.
- (HIL/CAN 사용 중이었다면) SocketCAN은 재부팅 시 사라지므로 호스트에서 다시:
  ```bash
  sudo ip link set can0 type can bitrate 1000000 && sudo ip link set up can0
  ```

### 한눈 요약
| 상황 | 해야 할 것 |
|---|---|
| 그냥 다시 켜기 | `./run.sh` → `ros2 launch …` |
| 소스 수정함 | `./run.sh` → `colcon build` → `source install/setup.bash` |
| 노드 스크립트 추가 | 위 + `chmod +x` (scripts/*.py) |
| 종료 | 셸에서 `exit` |
| 이미지 재빌드 필요? | Dockerfile을 고쳤을 때만 `./build.sh` |
