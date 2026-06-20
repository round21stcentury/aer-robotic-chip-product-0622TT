# 03_hils — HILS 통합 (Zybo 실제 FPGA ↔ 팀원 pc_bridge)

> 두 절반을 붙이는 곳. **나(FPGA측)** = `02_zybo_skeleton/05_zybo_can_eth` 의 보드 앱(UDP→CAN).
> **팀원(PC측)** = `piper_pc_handoff/pc_bridge` (브리지 + 가상로봇 + 코덱 + 모션 + 슬라이더).
> 경계면 = 이더넷 위 **13바이트 UDP 패킷** (192.168.1.10:5000).
> 작업 순서: `make` (가이드).

> ⚠️ **설계 무관 경계 — 함부로 고치지 말 것.** 이 폴더는 통신 연결 + 모드별 시뮬레이션만 합니다.
> 반사 설계(`02_reflex_system_dev/<01|A|B|C>`)를 바꿔도 여기는 안 건드립니다. FPGA는 블랙박스로 봅니다.
> 보드에 비트스트림/앱을 올리는 **프로그래밍(`make program`)은 각 반사 설계 폴더에서** 합니다
> (예: `cd 02_reflex_system_dev/02_rs_A_can_in_pl && make program`).
> 여기 `FPGA=05_zybo_can_eth`는 설계무관 통신 베이스입니다.

---

## 인터페이스 — 딱 두 단계: `prep` + `run`

```bash
make prep MODE=sim|hil|robot                # (sudo) 인터페이스 셋업 (한 번)
make run  MODE=sim|hil|robot APP=<무엇을>    # 실행 (Docker)
```

- **MODE = 명령을 어디로 보낼지**

  | MODE | 경로 | 필요 |
  |---|---|---|
  | `sim` | mock_fpga + 가상로봇 (FPGA 없음) | 하드웨어 0 (개발/연습) |
  | `hil` | 실제 FPGA + USB-CAN + Gazebo | 보드 program + USB-CAN |
  | `robot` | 실제 FPGA + **진짜 로봇** | 보드 program + 로봇 |

- **APP = 무엇을 실행할지**
  - `slider` — 슬라이더 GUI 로 직접 조종
  - `motions/<파일>.py` — 동작 스크립트 (경로 그대로). 인자가 있으면 따옴표로 감싼다.

```bash
make run MODE=sim   APP=slider                       # 시뮬 슬라이더
make run MODE=hil   APP=slider                       # 실FPGA+Gazebo 슬라이더
make run MODE=robot APP=slider                       # ★진짜 로봇★ 슬라이더
make run MODE=hil   APP=motions/back_and_forth.py    # 좌우 왕복
make run MODE=hil   APP='motions/mobius.py --period 5'  # 뫼비우스 (인자는 따옴표)
make run MODE=robot APP=motions/reflex_pursue.py     # ★반사인지 추적 (아래 반사 토픽 필요)
```

> `make` (가이드) / `make help` (전체 명령) 으로 항상 최신 사용법을 본다.

---

## 통합 토폴로지 (실제 FPGA 버전)

```
[컨트롤러 piper_single_ctrl]                       ┌── 실제 Zybo FPGA ──┐
   │ 명령 프레임 (0x155-7 관절, 0x159 그리퍼)        │ lwIP UDP5000 수신   │
   ▼ vcan0                                          │   → XCanPs CAN 송신 │
[bridge] 명령ID만 → 13B UDP ──이더넷──> 192.168.1.10:5000 ─┘  물리 CAN
                                                              │ (USB-CAN can0 수신)
[가상로봇] ◀── 피드백 vcan0 ◀── backend ◀── can0 명령 디코드 ◀┘
```

- **명령 경로**: 컨트롤러 → vcan0 → bridge → **이더넷/UDP** → **실제 FPGA** → 물리 CAN → can0
- **반환 경로**: USB-CAN(can0) → 가상로봇 → 피드백 → vcan0 → 컨트롤러  (robot 모드는 개루프=피드백 없음)
- 팀원 구성의 `mock_fpga` 자리에 **우리 실제 Zybo**가 들어간 것 (sim 모드만 mock_fpga 사용).

### 디스패처 (`tests/hils_run.sh`)
`make run` 은 도커 안에서 `hils_run.sh` 를 띄우고, 이 디스패처가 MODE×APP 을 라우팅한다.

- `APP=slider` 이고 `MODE=hil` → 검증된 전용 스크립트 `tests/stage3b_slider.sh` 로 exec
- `APP=slider` 이고 `MODE=robot` → 검증된 전용 스크립트 `tests/real_robot_slider.sh` 로 exec
- 그 외(= sim 슬라이더 / 모든 MODE 의 **모션**) → **인라인 경로**:
  `(gazebo 대기) → can_udp_bridge → reflex_status_node → (sim: mock_fpga) → virtual_robot → piper_single_ctrl(gripper_exist=true) → 모션 .py`
  > ★슬라이더를 통합하지 않고 전용 스크립트로 분리한 이유: 예전에 한 스크립트로 다 하려다 hil 슬라이더가 깨졌음(로봇 처짐·슬라이더 안 뜸). 검증본은 손대지 말 것.

---

## 그리퍼 동작 (0x159 GripperCtrl)  — 2026-06-20

- 컨트롤러(`piper_single_ctrl`)가 **0x159 GripperCtrl** 을 내보내려면 `gripper_exist:=true` 가 필요하다.
- 슬라이더 경로 검증 스크립트 `tests/real_robot_slider.sh` · `tests/stage3b_slider.sh` 가
  `gripper_exist:=false` 였던 걸 **`true` 로 고침** (인라인 `hils_run.sh` 는 이미 true).
- 슬라이더 GUI(`tools/joint_slider_gui_robot.py`, `..._v3.py`)에 **그리퍼 슬라이더**(`position[6]`, 0~0.07 m = 0~70 mm) 추가.
- `piper/ids.py` 에 `GRIPPER_CTRL = 0x159` 정의 (명령 ID 분류에 포함).
- ⚠️ 그리퍼는 슬라이더에서 **[Enable] 을 누른 상태**(`auto_enable:=false`)에서만 0x159 가 나간다.

---

## 반사 토픽 체인 (`/reflex_active`)  — 2026-06-20

`reflex_pursue.py` 같은 **반사-인지 모션**이 반사를 실제로 받으려면 이 체인이 떠 있어야 한다.
(FPGA 이더넷 TX 가 죽어 UDP 로 반사를 못 받으므로 **시리얼로 우회**한다.)

```
PS 시리얼 [RFX]0/1
   → latency_display.py  (호스트, ../../02_1_reflex_system_TT/06_로봇실증용. 유일한 시리얼 리더)
        ├ 반사 지연 GUI 표시
        └ localhost:5001 로 forward
   → reflex_status_node.py  (컨테이너, make run 시 hils_run.sh 가 자동 실행)
        └ /reflex_active (Bool) 발행
```

- `reflex_status_node` 는 **`make run` 시 자동 실행**된다.
- 단, **호스트 다른 터미널**에서 시리얼 리더(latency-gui)를 따로 켜야 반사가 토픽으로 흐른다:
  ```bash
  cd ../../02_1_reflex_system_TT/06_로봇실증용 && make latency-gui
  ```

---

## 모션 / 핸드오프 파일을 APP 으로 추가해 `make` 하는 법

동료 핸드오프(thief tar 등)로 받은 모션 `.py` 파일을 그냥 **`motions/` 폴더에 넣으면 바로 APP 으로 실행**된다.

1. 받은 모션 파일을 `piper_pc_handoff/pc_bridge/motions/` 에 복사한다.
2. `make run MODE=<sim|hil|robot> APP=motions/<파일>.py` 로 실행한다.
   ```bash
   make run MODE=robot APP=motions/reflex_pursue.py
   make run MODE=hil   APP='motions/mobius.py --period 5'   # 인자는 따옴표
   ```
3. 디스패처 규칙(위 "디스패처" 참고): 모션은 항상 **인라인 경로**로 간다
   (브리지 + 컨트롤러 `gripper_exist:=true` + `reflex_status_node` 자동 + 모션 실행).
   `APP=slider` + `hil/robot` 만 전용 검증 스크립트로 빠지므로, 모션은 신경 쓸 필요 없다.

### 의존성 / 환경
- `reflex_pursue.py` 처럼 **ikpy(IK) 가 필요한 모션은 `hils_run.sh` 가 자동 설치**한다
  (컨테이너 `--rm` 이라 매 실행 확인 → 없으면 `pip3 install ikpy`).
- URDF 는 컨테이너 안에 있다 (`/root/ros2_ws/src/piper_ros/.../piper_*_description.urdf`).
- 그리퍼를 쓰는 모션은 `gripper_exist:=true` 가 인라인 경로에 이미 들어가 있다.

### 반사-인지 모션을 실제로 반사 받게 하려면
`reflex_pursue.py` 같은 반사-인지 모션은 위 **반사 토픽 체인**이 필요하다.
`make run` 외에 **호스트에서 `make latency-gui`(06_로봇실증용) 를 같이 켜야** `/reflex_active` 가 흐른다.

### 모션 파일이 따라야 할 인터페이스
- **발행**
  - `/joint_ctrl_single` (`JointState`) — `position[0:6]`=관절각(rad), `position[6]`=그리퍼(m),
    `velocity[6]`=속도율(%). ※ `velocity[6]` 안 채우면 100%(위험), 실로봇은 낮게.
  - `/enable_flag` (`Bool`) — 모터 enable (계속 True 유지).
- **구독 (반사-인지 모션만)**
  - `/reflex_active` (`Bool`) — 반사 들어오면 발행 중지·현재각 hold.
  - `/joint_states_feedback` (`JointState`) — 로봇 실제 현재각 (정지 판정·복귀용).
- **템플릿**
  - `motions/_template.py` — 일반 모션 (POSES 시퀀스만 채우면 `motion_main()` 이 발행 처리).
  - `motions/reflex_aware_template.py` — 반사-인지 모션 (RUNNING/REFLEX/SETTLING/RESUMING 상태머신).
  - 함께 온 예시: `back_and_forth.py`(좌우왕복) · `mobius.py`(figure-8+트위스트) · `reflex_pursue.py`(반사인지 추적).
  - 설명: `motions/반사연동_트래젝토리_가이드.md`.

---

## 보드 없이 / 코덱만 검증 (참고)
- PC 단독: `make prep MODE=sim` → `make run MODE=sim APP=slider` (mock_fpga + 가상로봇).
- 코덱 단위테스트(root 불필요): `python3 piper_pc_handoff/pc_bridge/tests/test_frames.py`
  (브리지·가상로봇의 1·2·3단계 상세는 `piper_pc_handoff/pc_bridge/README.md`).

## 단축어
`serial`(보드 UART) · `can-mon`(CAN상태) · `program`(보드 올리기) · `docker-fix`(도커 권한) ·
`gz-kill`(가제보/컨테이너 정리 + DDS shm 청소) · `down`(vcan 정리). 변수: `BACKEND`, `FPGA_IP`, `ZYBO_TTY`, `LIBGL=1`, `DBG=1`.

## 미해결 (통합 시 확인)
- 실기 로봇 **펌웨어 버전** V2/V1.5-2+ (계약서 §8).
- 가상로봇 단위변환·피드백 ID는 piper_sdk 미러 — `pc_bridge/README.md` "확정값" 참조.
