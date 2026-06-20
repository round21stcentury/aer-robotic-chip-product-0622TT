# 학습 노트 — Docker · ROS2 · Gazebo로 Piper 팔 띄우기

지금까지 한 작업을 처음 보는 사람도 이해할 수 있게 정리한 문서다.
순서는 **Docker(환경) → ROS2(개념) → 팔 제어(실제로 한 것)** 다.

---

## 0. 한눈에 보는 전체 그림

내가 한 일을 한 줄로 요약하면:

> **Ubuntu 24.04 노트북 위에, Docker로 "ROS2 Humble 가상 환경"을 만들고, 그 안에서 Piper 팔 시뮬레이션(Gazebo)을 띄워 움직였다.**

겹겹이 쌓인 구조라 헷갈리기 쉬운데, 층으로 보면 이렇다:

```
[ 내 노트북 = Ubuntu 24.04 ]
   └─ [ Docker 컨테이너 = Ubuntu 22.04 + ROS2 Humble ]   ← 격리된 별도 환경
         └─ [ ROS2 워크스페이스 (ros2_ws) ]              ← Piper 코드가 사는 곳
               └─ [ Gazebo 시뮬레이터 ]                  ← 팔이 보이는 3D 창
                     └─ [ Piper 로봇팔 모델 ]
```

왜 이렇게 했는지가 1장이다.

---

## 1. Docker — "환경을 통째로 담는 상자"

### 1.1 왜 Docker를 썼나
Piper가 공식 지원하는 ROS2 버전은 **Humble**인데, Humble은 **Ubuntu 22.04** 전용이다.
그런데 내 노트북은 **Ubuntu 24.04**다. 24.04에 맞는 ROS2는 Jazzy인데, Piper는 Jazzy를 지원 안 한다.

이 버전 충돌을 푸는 방법이 Docker다.
**Docker는 "Ubuntu 22.04 + ROS2 Humble"이 통째로 들어있는 상자를 내 24.04 위에서 실행**하게 해준다.
내 노트북 OS는 건드리지 않고, 상자 안에서만 22.04인 척하는 것이다.

### 1.2 가장 헷갈리는 3가지 — 이미지 / 컨테이너 / 볼륨

붕어빵으로 비유하면 딱 떨어진다:

| 용어 | 비유 | 정체 | 사라지나? |
|---|---|---|---|
| **이미지(Image)** | 붕어빵 **틀** | "22.04 + ROS2 + Gazebo"가 설치된 설계도. `build.sh`로 한 번 굽는다 | 안 사라짐 (디스크에 저장) |
| **컨테이너(Container)** | 붕어빵 **한 개** | 이미지로 실제로 띄운 실행 인스턴스. `run.sh`로 만든다 | **사라짐** — 나가면(`exit`) 삭제 |
| **볼륨/마운트(Volume)** | 붕어빵에 끼운 **쪽지** | 컨테이너와 내 노트북을 잇는 공유 폴더(`ros2_ws/`) | **안 사라짐** (실제론 노트북 디스크) |

여기서 핵심 직관 하나:

> 컨테이너는 매번 새로 만들어지고 나가면 없어지는 **일회용**이다.
> 그런데 내 작업물(`git clone`한 코드, `colcon build` 결과)은 **볼륨(ros2_ws)에 저장**돼서 노트북에 남는다.
> 그래서 컨테이너를 막 지워도 작업물은 안전하다.

### 1.3 우리 폴더의 파일들

`piper-hil-docker/` 안의 파일이 각각 무슨 역할인지:

| 파일 | 역할 | 어디서 실행 |
|---|---|---|
| [Dockerfile](Dockerfile) | 이미지 설계도. "22.04 베이스 + ROS2 Humble + Gazebo + Piper 도구 설치"를 적어둔 레시피 | (빌드 시 자동) |
| [build.sh](build.sh) | 위 레시피로 이미지를 굽는 명령 (`docker build`) | 노트북(호스트) |
| [run.sh](run.sh) | 이미지로 컨테이너를 띄우고 들어가는 명령 (`docker run`) | 노트북(호스트) |
| [docker-compose.yml](docker-compose.yml) | run.sh와 같은 일을 하는 다른 방식(취향) | 노트북(호스트) |
| [setup-workspace.sh](setup-workspace.sh) | 컨테이너 안에서 Piper 코드 받고 빌드하는 명령 모음 | **컨테이너 안** |
| `ros2_ws/` | 공유 폴더(볼륨). Piper 소스·빌드 결과가 실제로 저장되는 곳 | (마운트) |

### 1.4 run.sh가 켤 때 붙이는 옵션들의 의미

`run.sh`가 컨테이너를 띄울 때 주는 옵션 몇 개는 알아두면 좋다:

- `--network host` : 컨테이너가 노트북의 네트워크를 **그대로** 쓰게 함. 나중에 FPGA(Zybo)와 이더넷/CAN으로 통신할 때 이게 있어야 막힘이 없다.
- `-v .../ros2_ws:/root/ros2_ws` : 위에서 말한 **공유 폴더(볼륨)** 연결. 컨테이너 안 `/root/ros2_ws`는 사실 노트북의 `ros2_ws/`다.
- `-e DISPLAY` + `/tmp/.X11-unix` : Gazebo 같은 **GUI 창을 노트북 화면에** 띄우기 위한 설정. (컨테이너는 원래 화면이 없다)
- `--rm` : 나가면 컨테이너 자동 삭제. (작업물은 볼륨에 있으니 OK)

### 1.5 생명주기 — 켜고 / 끄고 / 다시 켜기

- **들어가기**: `./run.sh`
- **나가기/끄기**: 컨테이너 셸에서 `exit` (컨테이너는 삭제되지만 작업물은 남음)
- **다시 켜기**: 또 `./run.sh` → 코드도 빌드결과도 그대로 → 바로 사용
- **둘째 터미널**: `./run.sh` 한 번 더 (실행 중이면 같은 컨테이너로 자동 접속)

> **최초 1회만** 무겁다(이미지 빌드 + 코드 클론 + colcon build).
> 그 다음부턴 `./run.sh` 하고 바로 일하면 된다.

---

## 2. ROS2 — "로봇 소프트웨어를 레고처럼 조립하는 틀"

### 2.1 ROS2가 뭔가
ROS2(Robot Operating System 2)는 이름과 달리 OS가 아니라, **로봇 프로그램들을 작은 단위로 쪼개고 서로 통신시키는 틀**이다.
큰 프로그램 하나를 짜는 대신, 작은 프로그램(노드) 여러 개를 만들어 메시지로 대화시키는 방식이다.

### 2.2 워크스페이스 구조 — src / build / install / log

`ros2_ws/` 안을 보면 폴더 네 개가 생긴다:

| 폴더 | 내용 |
|---|---|
| `src/` | **내가 받은 소스 코드** (Piper 코드가 여기 `src/piper_ros`로 클론됨) |
| `build/` | 빌드 중간 산출물 (신경 안 써도 됨) |
| `install/` | **빌드 완성품.** 실제로 실행할 때 ROS2가 보는 곳 |
| `log/` | 빌드 로그 |

흐름: **`src`(소스) → `colcon build` → `install`(실행 가능한 완성품)**

### 2.3 패키지(Package)
ROS2의 기본 단위. 하나의 기능 묶음이다.
예를 들어 우리가 띄운 `piper_gazebo`는 "Piper를 Gazebo에 올리는" 패키지다.
패키지 폴더 안엔 보통 이런 게 있다:
- `package.xml` : 패키지 이름·의존성을 적은 명함
- `launch/` : 실행 시나리오 파일들
- `config/` : 설정값(yaml)
- `scripts/` 또는 소스 : 실제 노드 코드

### 2.4 colcon build가 하는 일
`colcon build`는 `src/`의 모든 패키지를 빌드해서 `install/`에 정리한다.
- 파이썬/C++ 코드를 실행 가능한 형태로 배치
- launch·config 파일을 정해진 위치로 복사
- 패키지들끼리 찾을 수 있게 색인 생성

옵션 메모:
- `--symlink-install` : 복사 대신 **링크**로 설치. 코드 고칠 때 매번 다시 빌드 안 해도 되게 함. (대신 우리가 겪은 "실행권한" 문제의 원인이기도 했다 — 4.3 참고)
- `--packages-select <이름>` : 그 패키지만 빌드 (빠름)

### 2.5 ⭐ "경로도 안 줬는데 왜 실행되지?" — 가장 궁금했던 부분

`ros2 launch piper_gazebo piper_gazebo.launch.py` 를 칠 때,
`piper_gazebo`는 **경로가 아니라 "패키지 이름"** 이다. 그런데도 ROS2가 알아서 찾아간다. 왜?

비밀은 이 명령에 있다:
```bash
source install/setup.bash
```

`source`는 **"주소록을 현재 터미널에 등록"** 하는 일을 한다.
구체적으로는 환경변수(`AMENT_PREFIX_PATH` 등)에 `install/` 경로를 집어넣는다.
그러면 ROS2 도구들은 명령을 받을 때 그 환경변수(=주소록)를 뒤져서
**"piper_gazebo라는 이름 → 실제로는 install/piper_gazebo/... 경로"** 를 스스로 알아낸다.

비유하면:
> `ros2 launch piper_gazebo ...` 는 "철수네 집으로 가줘"라고 말하는 것.
> `source`가 미리 **주소록에 "철수네 = 서울시 …"를 등록**해놨기 때문에,
> 나는 풀 주소를 몰라도 ROS2가 알아서 찾아간다.

그래서:
- `source`를 안 하면 → 주소록이 비어서 `package not found` 에러가 난다.
- 우리는 `.bashrc`(셸 켤 때 자동 실행되는 파일)에 `source`를 미리 넣어놨다.
  → **그래서 `./run.sh`로 들어가면 매번 자동으로 주소록이 등록**돼서, 바로 이름만 대고 실행할 수 있다.

핵심 정리:
> **"경로 안 줘도 되는 이유 = source가 환경변수에 install 경로를 등록해둬서, ROS2가 이름으로 위치를 찾기 때문."**

### 2.6 노드 · 토픽 · 액션 — 통신의 3요소

**노드(Node)** : 하나의 작은 프로그램. (예: `arm_controller`, `gazebo`, `robot_state_publisher`)
`ros2 node list`로 지금 돌아가는 노드들을 본다.

**토픽(Topic)** : 노드끼리 **계속 흘려보내는 데이터 통로.** 라디오 방송 같은 단방향 스트림.
- 보내는 쪽(publisher) ── 토픽 ──▶ 받는 쪽(subscriber)
- 예: 우리가 `/arm_controller/joint_trajectory` 토픽에 자세 명령을 흘려보내면 팔이 움직였다.
- `ros2 topic list` (목록), `ros2 topic echo <토픽>` (내용 엿보기), `ros2 topic pub <토픽>` (직접 쏘기)

**액션(Action)** : "오래 걸리는 작업"을 시키고 **진행상황·완료를 돌려받는** 통신.
- 예: `/arm_controller/follow_joint_trajectory` — "이 궤적 따라가" 하고 다 갈 때까지 추적.
- 토픽이 "그냥 던지기"라면, 액션은 "주문하고 결과 받기"에 가깝다.

**메시지 타입(Message type)** : 토픽에 흐르는 데이터의 정해진 형식.
- 예: `trajectory_msgs/msg/JointTrajectory` = "관절 이름들 + 목표 위치 + 시간"이 담긴 양식.

### 2.7 런치(Launch) 파일 — "여러 노드를 한 번에 켜는 스위치"

로봇을 띄우려면 노드가 수십 개 필요하다(시뮬레이터, 컨트롤러들, 상태 발행기 등).
이걸 하나씩 켜면 끔찍하니, **launch 파일** 하나로 한꺼번에 켠다.

우리가 친:
```bash
ros2 launch piper_gazebo piper_gazebo.launch.py
```
이 한 줄이 → Gazebo 실행 + Piper 모델 로드 + 컨트롤러 4개 + 상태 발행기 …를 **전부 한 번에** 켰다.
(그래서 실행하니 노드 목록에 `gazebo`, `arm_controller`, `controller_manager` … 가 우르르 떴던 것.)

---

## 3. ros2_control & 팔 움직이기 — 실제로 본 것

우리가 띄운 Piper는 **ros2_control**이라는 표준 제어 틀을 쓴다. 본 컨트롤러들:

| 컨트롤러 | 정체 | 역할 |
|---|---|---|
| `joint_state_broadcaster` | 상태 방송기 | 현재 관절 각도를 `/joint_states`로 계속 알림 |
| `arm_controller` | JointTrajectoryController | **6축 팔**을 목표 자세로 움직임 |
| `gripper_controller` | JointTrajectoryController | 그리퍼(집게) 제어 |
| `controller_manager` | 관리자 | 위 컨트롤러들을 켜고 끄고 관리 |

### 팔을 움직인 두 가지 방법

**방법 A — rqt 슬라이더(GUI)**
`rqt_joint_trajectory_controller` 창에서 controller manager와 `arm_controller`를 고르고
슬라이더를 끌면 팔이 따라 움직인다. 직관적이라 감 잡기에 좋다.

**방법 B — 명령으로 자세 쏘기**
```bash
ros2 topic pub --once /arm_controller/joint_trajectory trajectory_msgs/msg/JointTrajectory "{
  joint_names: [joint1, joint2, joint3, joint4, joint5, joint6],
  points: [
    { positions: [0.0, 0.3, -0.3, 0.0, 0.5, 0.0], time_from_start: { sec: 2, nanosec: 0 } }
  ]
}"
```
- `joint_names` : 움직일 관절 이름 (순서 중요)
- `positions` : 각 관절 목표 각도(**라디안**)
- `time_from_start` : 그 자세까지 도달할 시간

> 이 `/arm_controller/joint_trajectory` 토픽이 나중에 **"PC가 명령을 만들어 보내는 지점"** 이다.
> 지금은 시뮬이라 ROS 토픽이지만, 실제 시스템에선 같은 자리에 **CAN 신호**가 들어간다. (개념은 같고 출구만 바뀜)

---

## 4. 자주 만난 개념 / 문제

### 4.1 `source` 를 자꾸 하라는 이유
`source`는 "이 터미널에 ROS 주소록 등록"이다. **터미널마다(셸마다) 한 번** 필요하다.
우리는 `.bashrc`에 넣어 자동화해서 신경 안 써도 되게 했다.

### 4.2 빌드는 언제 다시 하나
**소스 코드(`src/`)를 고쳤을 때만** `colcon build`. 그냥 실행만 반복할 땐 빌드 불필요.

### 4.3 "executable not found" — 실행권한 문제 (우리가 겪은 것)
`ros2 launch` 했더니 `joint8_ctrl.py not found` 에러가 났었다.
- 원인: 파일은 있었지만 **실행권한(x 비트)이 없었다.** `--symlink-install`이라 권한 없는 원본을 링크해서, ROS2가 "실행 가능한 파일"로 인식 못 함.
- 해결: 소스에 실행권한 부여 후 재빌드.
  ```bash
  find src/piper_ros -path "*/scripts/*.py" -exec chmod +x {} \;
  colcon build && source install/setup.bash
  ```
- 교훈: 파이썬 노드 스크립트는 **실행권한이 있어야** ROS2가 노드로 인식한다.

---

## 5. 지금까지 친 명령어 총정리

| 명령 | 의미 | 어디서 |
|---|---|---|
| `./build.sh` | 도커 이미지 굽기 (최초 1회) | 호스트 |
| `./run.sh` | 컨테이너 띄우고 들어가기 | 호스트 |
| `git clone -b humble …piper_ros` | Piper 코드 받기 (최초 1회) | 컨테이너 |
| `rosdep install …` | Piper가 필요로 하는 의존 패키지 자동 설치 | 컨테이너 |
| `colcon build` | 소스 → 실행 가능한 완성품으로 빌드 | 컨테이너 |
| `source install/setup.bash` | ROS 주소록을 현재 터미널에 등록 | 컨테이너 |
| `ros2 launch piper_gazebo piper_gazebo.launch.py` | 시뮬+컨트롤러 한 번에 켜기 | 컨테이너 |
| `ros2 topic list` / `node list` | 지금 도는 토픽·노드 보기 | 컨테이너 |
| `ros2 control list_controllers` | 컨트롤러 상태 보기 | 컨테이너 |
| `ros2 topic pub …joint_trajectory …` | 팔에 목표 자세 보내기 | 컨테이너 |
| `exit` | 컨테이너 나가기(끄기) | 컨테이너 |

---

## 6. 용어 미니 사전

- **Docker 이미지** : 환경이 통째로 든 설계도(붕어빵 틀)
- **Docker 컨테이너** : 이미지로 띄운 실행 인스턴스(붕어빵 한 개), 나가면 사라짐
- **볼륨/마운트** : 컨테이너와 호스트가 공유하는 폴더, 작업물이 여기 남음
- **워크스페이스(ros2_ws)** : ROS 코드를 모아 빌드하는 작업 폴더
- **패키지** : ROS 기능 묶음의 기본 단위
- **노드** : 돌아가는 작은 프로그램 하나
- **토픽** : 노드 간 데이터를 흘려보내는 단방향 통로
- **액션** : 오래 걸리는 작업을 시키고 결과를 받는 통신
- **메시지 타입** : 토픽에 흐르는 데이터의 정해진 양식
- **launch 파일** : 노드 여러 개를 한 번에 켜는 스크립트
- **ros2_control** : 로봇 관절 제어 표준 틀
- **colcon** : ROS2 빌드 도구
- **source** : 환경변수(주소록)를 현재 터미널에 등록하는 명령
- **rosdep** : 패키지가 필요로 하는 의존성을 자동 설치해주는 도구

---

## 7. 다음으로 가면 좋은 것

1. **PC 명령 생성기(Python 노드)** : 지금 손으로 친 `topic pub`을 코드로. 정해진 궤적을 반복 재생 → 반사 테스트의 재현성 확보.
2. **HIL 연결** : 그 명령을 ROS 토픽 대신 **CAN 신호**로 내보내 Zybo(FPGA)를 경유시키기.
3. 좌표계·관절 한계·안전 자세 파악 (수동 조작으로 충분히 놀아보며).
