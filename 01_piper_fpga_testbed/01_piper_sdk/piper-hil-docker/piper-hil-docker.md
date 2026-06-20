# piper-hil-docker — Humble 컨테이너 + piper_ros 워크스페이스

> ROS2 Humble 런타임을 격리한 Docker 이미지(`piper-hil:humble`)와, 그 안에서 도는
> 패치된 `piper_ros` 워크스페이스. **03_hils가 이 ros2_ws를 마운트해서 컨트롤러로 사용.**

## 파일
| 파일 | 역할 |
|---|---|
| `Dockerfile` | 이미지 레시피: Ubuntu22.04 + ROS2 Humble + Gazebo11 + MoveIt + SocketCAN + `piper_sdk`/`python-can` |
| `build.sh` | 호스트에서 `docker build -t piper-hil:humble .` |
| `run.sh` | `docker run --network host` + X11 + `ros2_ws` 마운트 (실행 중이면 재사용) |
| `docker-compose.yml` | run.sh의 YAML 버전 |
| `setup-workspace.sh` | (1회, 컨테이너 안) clone + rosdep + colcon build |
| `README.md` | 셋업 단계별 가이드(한국어) |
| `HANDOFF.md` | 다른 PC/계정 재현용 최소 가이드 |
| `study.md` | 학습노트(Docker/ROS2/컨트롤 개념) |

## ros2_ws 레이아웃
```
ros2_ws/
├── src/piper_ros/        AgileX piper_ros (humble) + 패치
│   └── src/
│       ├── piper/            컨트롤러 노드(piper_ctrl_single_node.py) ★패치 위치★
│       ├── piper_description/ URDF·메시·RViz
│       ├── piper_msgs/        커스텀 메시지
│       ├── piper_sim/         piper_gazebo(.launch) ★Gazebo★
│       └── piper_moveit/      MoveIt 설정
├── build/ install/ log/  ← colcon 산출물 (삭제 가능, 재생성)
```

## 핵심 패치
- **`piper_ctrl_single_node.py`**: `judge_flag`/`can_auto_init`/`exit_on_loss` 파라미터 추가. joint_callback이 `enable_flag`에만 의존(피드백 없어도 명령 송신) → 우리 단방향 FPGA와 호환.
- **`start_single_piper.launch.py`**: 위 파라미터를 launch 인자로 노출.
- **`piper_sim/piper_gazebo/launch/.../piper_gazebo.launch.py`**: HIL의 Gazebo 3D.

## 🗑️ 삭제 가능
`ros2_ws/{build,install,log}/`(~11M, `colcon build` 재생성), `**/__pycache__/`, (선택) `src/piper_ros/.git/`(204M).
