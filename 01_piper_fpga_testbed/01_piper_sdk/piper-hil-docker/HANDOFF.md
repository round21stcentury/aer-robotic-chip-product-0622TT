# HANDOFF — Piper ROS2/Gazebo 환경 재현 가이드

이 번들만 있으면 **다른 계정·다른 머신에서 동일한 Piper 시뮬레이션 환경**을 처음부터 재현할 수 있다.
환경 자체(ROS2 Humble + Gazebo)는 Docker 이미지로 굽고, Piper 코드는 스크립트가 알아서 받아온다.
배경·개념이 궁금하면 [study.md](study.md), 상세 사용법은 [README.md](README.md)를 본다.

---

## 1. 사전 조건
- **호스트 OS**: Ubuntu 계열 리눅스 (24.04에서 검증. 다른 버전도 Docker만 되면 무방)
- **인터넷 연결** 필요 (이미지 빌드 + Piper 코드 clone 시)
- **GUI 환경** 필요 (Gazebo 창을 띄우려면 X11 데스크톱)
- 디스크 여유 ~수 GB (Docker 이미지 + 빌드 산출물)

> **왜 Docker를 쓰나**: Piper 공식 지원은 ROS2 **Humble**(=Ubuntu 22.04)인데 호스트가 24.04라 직접 안 맞는다.
> Docker로 22.04+Humble 환경을 격리 실행해 이 충돌을 우회한다. 자세한 건 study.md 1장.

---

## 2. 번들에 든 것 / 안 든 것

**들어있음** (이게 전부 — 매우 가볍다):
| 파일 | 역할 |
|---|---|
| `Dockerfile` | 환경 이미지 설계도 (ROS2 Humble + Gazebo + Piper 도구) |
| `build.sh` | 이미지 빌드 |
| `run.sh` | 컨테이너 실행/접속 |
| `docker-compose.yml` | run.sh의 대안 |
| `setup-workspace.sh` | (컨테이너 안) Piper 코드 clone + 빌드 |
| `README.md` | 전체 사용 설명서 |
| `study.md` | 개념 학습 노트 |
| `HANDOFF.md` | 이 문서 |

**안 들어있음** (의도적으로 제외 — 새 계정에서 자동 재생성됨):
- `ros2_ws/src` (Piper 소스) → `setup-workspace.sh`가 git에서 새로 clone
- `ros2_ws/build`, `install`, `log` → `colcon build`로 재생성

> 그래서 번들이 수십 KB로 작다. "환경을 굽는 레시피"만 옮기고, 실제 코드·빌드는 새 자리에서 만든다.

---

## 3. 재현 절차 (순서대로)

### 3-0. 압축 풀기
```bash
tar xzf piper-hil-handoff.tar.gz
cd piper-hil-docker
chmod +x *.sh          # 실행권한 부여
```

### 3-1. Docker 준비
- **같은 머신의 다른 계정**이면 Docker는 이미 깔려 있다. 그 계정을 docker 그룹에만 추가:
  ```bash
  sudo usermod -aG docker $USER
  newgrp docker          # 또는 로그아웃 후 재로그인
  docker run --rm hello-world   # 동작 확인
  ```
- **새 머신**이면 Docker부터 설치 → [README.md](README.md) **0번 항목** 그대로 따라 한다.

### 3-2. 이미지 빌드 (최초 1회, 수~십수 분)
```bash
./build.sh
```

### 3-3. 컨테이너 실행
```bash
./run.sh
```
- Gazebo 창이 안 뜨면 호스트에서 `xhost +local:root` 먼저 실행.

### 3-4. Piper 워크스페이스 빌드 (컨테이너 안, 최초 1회)
컨테이너 셸이 뜨면:
```bash
cd /root/ros2_ws
git clone -b humble https://github.com/agilexrobotics/piper_ros.git src/piper_ros
find src/piper_ros -path "*/scripts/*.py" -exec chmod +x {} \;   # 실행권한(중요)
rosdep install --from-paths src --ignore-src -r -y --rosdistro humble
colcon build --symlink-install
source install/setup.bash
```
> 위 과정을 한 번에 하려면 `setup-workspace.sh` 내용을 그대로 쓰면 된다(같은 명령).
> `chmod` 줄이 빠지면 `ros2 launch` 시 "executable not found"가 난다 — study.md 4.3 참고.

### 3-5. 시뮬 띄우기
```bash
ros2 launch piper_gazebo piper_gazebo.launch.py
```
Gazebo 창에 Piper 팔이 뜨면 성공.

### 3-6. 팔 움직여보기 (새 터미널에서 `./run.sh`로 접속 후)
```bash
ros2 topic pub --once /arm_controller/joint_trajectory trajectory_msgs/msg/JointTrajectory "{
  joint_names: [joint1, joint2, joint3, joint4, joint5, joint6],
  points: [ { positions: [0.0, 0.3, -0.3, 0.0, 0.5, 0.0], time_from_start: { sec: 2 } } ]
}"
```
팔이 움직이면 재현 완료.

---

## 4. 검증 체크포인트
| 단계 | 성공 신호 |
|---|---|
| 3-1 | `hello-world` 컨테이너가 메시지 출력 |
| 3-2 | `docker images`에 `piper-hil:humble` 보임 |
| 3-3 | 컨테이너 셸 프롬프트(`root@...:~/ros2_ws#`) 진입 |
| 3-4 | `colcon build`가 에러 없이 끝, `install/` 생성 |
| 3-5 | Gazebo 창에 Piper 팔 표시 |
| 3-6 | 명령 시 팔이 움직임 |

---

## 5. 자주 막히는 지점
| 증상 | 조치 |
|---|---|
| `permission denied` (docker) | docker 그룹 추가 후 **재로그인** (3-1) |
| Gazebo 창 안 뜸 / `cannot open display` | 호스트에서 `xhost +local:root`, `echo $DISPLAY` 확인 |
| `executable '*.py' not found` | `chmod +x` 누락. 3-4의 find 명령 실행 후 재빌드 |
| `rosdep` 키 미해결 | 시뮬이 Ignition 사용 시 `apt install ros-humble-ros-gz` 후 재빌드 |
| 빌드/clone이 느림·실패 | 인터넷 연결 확인. 사내망이면 프록시 설정 필요할 수 있음 |

---

## 6. 재현 후 일상 사용
최초 1회(3-2~3-4) 끝나면, 그 다음부턴:
```bash
cd piper-hil-docker
./run.sh
ros2 launch piper_gazebo piper_gazebo.launch.py
```
- 코드 수정 시에만 `colcon build` 다시.
- 종료는 셸에서 `exit`.
- 자세한 재시작 규칙은 [README.md](README.md)의 "재시작 절차" 참고.

---

## 7. (참고) 오프라인 재현이 필요하면
인터넷이 없는 환경이면 3-4의 clone이 안 된다. 이때는 원본 머신에서
`ros2_ws/src/piper_ros` 폴더를 따로 복사해 새 머신의 같은 위치에 두면 된다.
(단, `.git`은 빼도 됨. 빌드엔 소스만 있으면 충분.)
```bash
# 원본 머신에서:
tar czf piper-src.tar.gz -C ros2_ws/src piper_ros
# 새 머신에서 ros2_ws/src/ 안에 풀기
```
