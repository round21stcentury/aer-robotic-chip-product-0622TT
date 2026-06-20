# 03_hils — HIL 통합 "지휘소"

> **역할:** 01_piper_sdk(컨트롤러)·02_zybo_skeleton(FPGA)·팀원 PC브리지를 묶어
> `make` 한 줄로 HIL 루프를 돌리는 **통합 런처**. MODE×APP 조합으로 sim/hil/robot을 한 경로로.

## 구조
```
03_hils/
├── Makefile                 ★진입점★ prep / run / slider / motion + 단축어
├── README.md                사용법
├── dev-log.md               ★버전·디버깅 이력★ (실증vsHIL 차이, DDS찌꺼기 사건 등)
├── piper_pc_handoff.tar.gz  팀원 원본 핸드오프(이미 풀림 → 삭제 가능)
└── piper_pc_handoff/        [상세: piper_pc_handoff/piper_pc_handoff.md]
    ├── pc_bridge/           브리지·가상로봇·GUI·모션·CAN코덱·단계테스트
    ├── docs/                CAN/브리지 계약서
    └── reference/piper_sdk  참고용 SDK 사본
```

## 사용법 (MODE × APP)
```bash
make prep MODE=sim|hil|robot                # (sudo) 인터페이스 셋업
make run  MODE=sim|hil|robot APP=slider     # 슬라이더 GUI로 조종
make run  MODE=.. APP=motions/<파일>.py      # 동작 스크립트 실행 (인자는 따옴표)
```
| MODE | 명령이 어디로 | 필요 |
|---|---|---|
| `sim` | mock_fpga + 가상로봇 (FPGA 없음) | 없음 |
| `hil` | 실제 FPGA + USB-CAN + Gazebo | 보드 program + USB-CAN |
| `robot` | 실제 FPGA + **진짜 로봇** | 보드 program + 로봇 |

> 핸드오프로 받은 모션 `.py` 는 `pc_bridge/motions/` 에 넣으면 바로 `APP=motions/그파일.py` 로 실행됨.
> 자세한 모션-APP 추가법·인터페이스·반사 토픽 체인 = `README.md`.

## ⭐ 실행 흐름 (`make run MODE=hil APP=slider`)
```
Makefile(run→_run) → docker run → hils_run.sh(디스패처)
   ├ /dev/shm DDS 찌꺼기 청소
   └ exec stage3b_slider.sh:
       gazebo → arm_controller 대기 → can_udp_bridge.py → virtual_robot.py
       → piper_single_ctrl(gripper_exist=true) → joint_slider_gui_v3.py
```
> `hils_run.sh`는 디스패처: `hil/robot + slider`는 검증된 전용 스크립트로 exec, sim/모션만 인라인.
> 모션(인라인)은 `reflex_status_node`(반사 토픽)도 자동으로 함께 띄움.

## 2026-06-20 변경
- **그리퍼**: 슬라이더 스크립트(stage3b/real_robot)도 `gripper_exist:=true` 로 통일 → `position[6]` 슬라이더가 0x159 발신. (단 [Enable] 누른 상태에서만)
- **모션**: `motions/reflex_pursue.py`(반사인지 추적, ikpy 자동설치) 추가. `back_and_forth`·`mobius` 동봉.
- **반사 토픽**: FPGA TX 죽어 시리얼 우회 — PS `[RFX]` → 호스트 `latency_display.py` → localhost:5001 → `reflex_status_node` → `/reflex_active`. 반사인지 모션 쓸 땐 호스트에서 `make latency-gui`(06_로봇실증용) 도 같이 켤 것.

## 단축어
`serial`(보드 UART) · `can-mon`(CAN상태) · `program`(보드올리기) · `docker-fix`(권한) · `gz-kill`(가제보/컨테이너 정리+DDS청소) · `slider-only`(가제보 없이 슬라이더만 진단) · `DBG=1`(전출력 /tmp/hils.log)

## 연결
- `WS_DIR → 01_piper_sdk/.../ros2_ws` (컨테이너 마운트), `DOCKER_IMG → piper-hil:humble`
- `FPGA → 02_zybo_skeleton/05_zybo_can_eth` (program/serial/can 위임)

## 🗑️ 삭제 가능
`piper_pc_handoff.tar.gz`(이미 풀림), `pc_bridge/*/__pycache__/`.
