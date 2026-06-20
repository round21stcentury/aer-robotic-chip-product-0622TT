# 01_piper_sdk — ROS2 컨트롤러 "두뇌" (Docker)

> **역할:** 관절명령(`/joint_ctrl_single`)을 받아 Piper CAN 프레임(0x155~7)으로 만드는 **ROS2 컨트롤러**와
> Gazebo를 담은 **Docker 환경**. HIL 루프에서 "두뇌" 역할.

## 왜 Docker인가
호스트(Ubuntu 24.04)는 ROS2 **Jazzy**인데 AgileX Piper는 ROS2 **Humble**(Ubuntu 22.04)만 지원.
그래서 Humble 런타임을 컨테이너(`piper-hil:humble`)에 격리한다.

## 구조
```
01_piper_sdk/
└── piper-hil-docker/          ← L2 (상세: piper-hil-docker.md)
    ├── Dockerfile             이미지 레시피 (Humble + Gazebo11 + MoveIt + SocketCAN + piper_sdk)
    ├── build.sh / run.sh      이미지 빌드 / 컨테이너 실행
    ├── setup-workspace.sh     (1회) 컨테이너 안에서 colcon build
    ├── README.md HANDOFF.md study.md   셋업·핸드오프·학습노트
    └── ros2_ws/               ★ROS2 워크스페이스 (03_hils가 마운트해서 씀)★
        └── src/piper_ros/     AgileX piper_ros (humble) + 우리 패치
```

## 핵심 파일 — 패치된 컨트롤러
`ros2_ws/src/piper_ros/src/piper/piper/piper_ctrl_single_node.py`

| 토픽 | 방향 | 뜻 |
|---|---|---|
| `/joint_ctrl_single` | 구독 | 목표 관절각 (슬라이더/모션이 발행) |
| `/enable_flag` | 구독 | 모터 enable |
| `/joint_states_feedback` | 발행 | 실제(또는 가상) 관절 피드백 |

**HIL용 ROS 파라미터 패치** (`start_single_piper.launch.py`에도 노출):
| 파라미터 | 기본 | HIL 설정 | 이유 |
|---|---|---|---|
| `judge_flag` | True | **False** | vcan0는 가상버스 → 물리 CAN 검사 스킵 |
| `can_auto_init` | True | True | SDK가 CAN 자동 초기화 |
| `exit_on_loss` | True | **False**(robot) | 피드백 없어도 컨트롤러가 안 꺼지게(개루프 허용) |

## 연결
- **03_hils/Makefile**이 `WS_DIR = .../01_piper_sdk/piper-hil-docker/ros2_ws`를 컨테이너에 마운트하고 `piper-hil:humble` 이미지를 사용.
- `(1회) make sdk-build-ws`(03_hils)가 이 워크스페이스를 컨테이너 안에서 colcon build.

## 🗑️ 삭제 가능
| 대상 | 회수 | 비고 |
|---|---|---|
| `ros2_ws/{build,install,log}/` | ~11M | `colcon build`로 재생성 |
| `**/__pycache__/` | ~140K | 임포트 시 재생성 |
| `ros2_ws/src/piper_ros/.git/` | 204M | 런타임 불필요(선택, 소스는 유지) |
