# CAN 프로토콜 인터페이스 계약서 — Piper ↔ FPGA ↔ PC

> **목적**: 팀원(PC/ROS 측 CAN 통신)과 나(FPGA 측)가 **똑같은 프레임 포맷**을 기준으로 구현하기 위한 단일 기준 문서.
> 양쪽이 이 문서를 보고 인코딩/디코딩/스트리밍을 맞춘다. 불일치하면 통합에서 터진다.
> **상태**: 1차 (piper_sdk v0.6.1 / 프로토콜 V2 기준). 실제 로봇 펌웨어로 교차검증 필요.

> ⚠️ **AI 코드 생성 시 — 1차 구현 범위는 §8만.** 아래 ID만 구현하고 나머지는 건드리지 말 것:
> - 명령: **0x151**(모드) + **0x155/0x156/0x157**(관절) + **0x471**(enable)
> - 피드백: **0x2A1**(상태) + **0x2A5/0x2A6/0x2A7**(관절)
> - **제외(추측 금지)**: MIT 0x15A–0x15F(§4, 스케일상수 미확정·로봇손상위험), 0x481–0x486(§7 미확인), Cartesian(0x152–0x154), 그 외 설정/조명 ID.
> - HighSpd current는 **signed**로 처리(§7). 의심값은 §0 소스 파일을 직접 확인.

---

## 0. 단일 진실 공급원 (Single Source of Truth)
- **레포**: `agilexrobotics/piper_sdk` (master), **SDK 버전 0.6.1**
- **프로토콜**: **V2** (펌웨어 **V1.5-2 이상** 필요. V1은 레거시 — 우리는 V2로 통일)
- **근거 소스 파일** (값이 의심되면 항상 여기로):
  - `piper_msgs/msg_v2/can_id.py` — CAN ID 정의(권위)
  - `piper_msgs/msg_v2/arm_id_type_map.py` — ID ↔ 메시지타입/방향
  - `protocol/protocol_v2/piper_protocol_v2.py` — 실제 인코딩/디코딩(엔디안·부호)
  - `piper_msgs/msg_v2/transmit/*`, `.../feedback/*` — 필드 의미·스케일
  - `asserts/V2/INTERFACE_V2.MD` — 인터페이스 문서

> ⚠️ **합의 사항**: 양쪽 다 **SDK v0.6.1 / V2** 를 기준으로 한다. SDK를 올리면 이 문서도 같이 갱신하고 서로 통지.

---

## 1. 버스 레벨 (확정)
| 항목 | 값 |
|---|---|
| 비트레이트 | **1 Mbps** |
| 식별자 | **표준 11-bit** (모든 ID ≤ 0x7FF) |
| 엔디안 | **빅엔디안**(MSB first), 멀티바이트 필드 전부 |
| 부호 | 2의 보수 (signed int16/int32) |
| 프레임 데이터 | 최대 8 byte |

---

## 2. 명령 (Master → Arm) — PC가 생성, FPGA가 송출

| CAN ID | 이름 | 바이트 레이아웃 (빅엔디안) | 단위/비고 |
|---|---|---|---|
| **0x150** | MotionCtrl_1 | B0 비상정지(0x01 정지/0x02 재개); B1 궤적제어; B2 드래그티치; B3 궤적인덱스; B4–5 name_index; B6–7 crc16 | **비상정지** 포함 |
| **0x151** | MotionCtrl_2 (모드제어) | B0 ctrl_mode(0x00 standby/0x01 CAN/0x03 Ethernet/0x07 offline); B1 move_mode(0x00 P/0x01 J/0x02 L/0x03 C/**0x04 M=MIT**/0x05 CPV); B2 속도율 0–100%; B3 mit_mode(0x00 pos-vel/0xAD MIT); B4 잔류시간; B5 설치자세 | **모드·MIT선택·속도%** |
| 0x152 | Cartesian_1 | X int32(B0–3), Y int32(B4–7) | 0.001 mm |
| 0x153 | Cartesian_2 | Z int32(B0–3), RX int32(B4–7) | Z 0.001mm, RX 0.001° |
| 0x154 | Cartesian_3 | RY int32(B0–3), RZ int32(B4–7) | 0.001° |
| **0x155** | JointCtrl_12 | joint_1 int32(B0–3), joint_2 int32(B4–7) | **0.001° / 관절, signed** |
| **0x156** | JointCtrl_34 | joint_3 int32, joint_4 int32 | 0.001° |
| **0x157** | JointCtrl_56 | joint_5 int32, joint_6 int32 | 0.001° |
| **0x159** | GripperCtrl | angle int32(B0–3); effort uint16(B4–5); status(B6: 0x00 disable/0x01 enable/0x03 enable+clr-err); set_zero(B7: 0xAE) | angle 0.001mm, effort 0.001N·m(0–5000) |
| **0x15A–0x15F** | JointMIT_Ctrl J1–J6 | 비트팩(아래 §4) | 관절별 MIT |
| **0x471** | 모터 Enable/Disable | B0 motor_num(1–6 관절/7 그리퍼/0xFF 전체); B1 flag(0x01 disable/0x02 enable) | **enable/disable** |
| 0x470, 0x472, 0x474–0x47A, 0x47D, 0x422, 0x4AF, 0x121 | 설정/조명류 | (마스터-슬레이브·한계·파라미터·펌웨어읽기 등) | 설정 명령. 초기 구현 후순위 |

## 3. 피드백 (Arm → Master) — 로봇이 생성, FPGA가 수신

| CAN ID | 이름 | 바이트 레이아웃 (빅엔디안) | 단위/비고 |
|---|---|---|---|
| **0x2A1** | ArmStatus | B0 ctrl_mode; B1 arm_status(정상/e-stop/무해/특이점/한계); B2 mode_feed; B3 teach; B4 motion(0x00 도달/0x01 미도달); B5 궤적번호; B6 err_low(관절 각도한계 비트); B7 err_high(관절 통신오류 비트) | **상태·에러** |
| 0x2A2 | EndPose_1 | X int32, Y int32 | 0.001 mm |
| 0x2A3 | EndPose_2 | Z int32, RX int32 | Z 0.001mm, RX 0.001° |
| 0x2A4 | EndPose_3 | RY int32, RZ int32 | 0.001° |
| **0x2A5** | JointFeedback_12 | joint_1 int32, joint_2 int32 | **0.001°, signed** |
| **0x2A6** | JointFeedback_34 | joint_3 int32, joint_4 int32 | 0.001° |
| **0x2A7** | JointFeedback_56 | joint_5 int32, joint_6 int32 | 0.001° |
| **0x2A8** | GripperFeedback | angle int32(B0–3); effort int16(B4–5); status(B6 비트필드); B7 예약 | angle 0.001mm, effort 0.001N·m |
| **0x251–0x256** | HighSpd_Feedback J1–J6 | motor_speed int16(B0–1); current int16(B2–3); pos int32(B4–7) | speed 0.001rad/s; current 0.001A; effort=current×(J1–3:1.18125 / J4–6:0.95844) |
| **0x261–0x266** | LowSpd_Feedback J1–J6 | voltage uint16(B0–1, 0.1V); foc_temp int16(B2–3, °C); motor_temp int8(B4, °C); foc_status uint8(B5 비트); bus_current uint16(B6–7, 0.001A) | foc_status: 저전압/과온/과전류/충돌/에러/enable/스톨 비트 |
| 0x481–0x486 | 관절 속도/가속 피드백 | ⚠️ **미확인** (파서에서 디코드 분기 못 찾음) | 소스 직접 확인 필요 |

## 4. MIT 관절 명령 (0x15A–0x15F) 비트 패킹
8바이트, 빅엔디안 비트팩:
- **B0–B1**: pos_ref (16-bit)
- **B2 + B3상위니블**: vel_ref (12-bit)
- **B3하위니블 + B4**: kp (12-bit, 기본 10)
- **B5 + B6상위니블**: kd (12-bit, 기본 0.8)
- **B6하위니블 + B7상위니블**: t_ref (8-bit)
- **B7하위니블**: crc (4-bit)
> ⚠️ pos/vel/kp/kd/torque의 **float↔int 스케일 상수**는 상위 인터페이스에 있고 프로토콜 파일엔 없음 → 소스에서 별도 확인. (잘못 쓰면 로봇 손상 위험, MIT는 고급기능)

---

## 5. ⭐ FPGA 반사 관점에서 중요한 ID

FPGA는 CAN IP로 **프레임을 스트리밍/포워딩**하므로 대부분의 바이트 의미를 파싱할 필요는 없다. 단, **reflex_core가 개입(override/inject)할 ID는 정확히 알아야** 한다:

| 반사 동작 | 써야 할 ID | 방법 |
|---|---|---|
| **비상정지** (가장 단순·안전) | **0x150** B0=0x01 | 위험 감지 시 이 프레임 inject |
| **모터 비활성화** | **0x471** B1=0x01 | 전체(0xFF) 또는 특정 관절 disable |
| **관절 명령 덮어쓰기** | **0x155/0x156/0x157** | PC 명령 대신 안전 목표각 주입 |
| **속도 제한** | **0x151** B2(속도율) | 속도율 낮춰 재발행 |
| (입력) 현재 상태 감시 | 0x2A1, 0x2A5–0x2A7 | 단 200Hz라 반사 트리거엔 느림 → **반사는 PL 직결 센서 사용** |

> 1차 반사는 **0x150 비상정지 inject** 가 가장 단순하고 안전한 시작점. 이후 0x155–0x157 덮어쓰기로 정교화.

---

## 6. 역할 분담 (누가 무엇을 인코딩/디코딩)
| 주체 | 책임 |
|---|---|
| **팀원 (PC/ROS)** | 관절 명령 ↔ CAN 프레임 **인코딩/디코딩** (위 바이트 레이아웃). HIL "가상 로봇" 노드의 CAN↔ROS 변환 |
| **나 (FPGA)** | CAN IP로 프레임 **송수신/스트리밍** + reflex_core가 §5 ID에 **개입**. 바이트 의미는 §5만 알면 됨 |
| **공통** | 본 계약서를 단일 기준으로. 양방향(명령+피드백) 둘 다 구현 |

---

## 7. 미확인/주의 항목 (추측 금지 — 직접 검증)
- **0x481–0x486** (관절 속도/가속 피드백): 메시지 클래스는 있으나 파서 디코드 분기 미발견 → `arm_feedback_joint_vel_acc.py` 직접 확인
- **MIT float 스케일 상수**: 프로토콜 파일에 없음 → 상위 인터페이스 소스 확인
- **HighSpd current 부호**: 메시지 파일은 uint16라지만 파서는 `ConvertToNegative_16bit`(=signed) 사용 → **signed로 처리**
- **Cartesian 회전 단위**(RX/RY/RZ): 0.001° 고신뢰지만 바이트 단위까지 verbatim 확인은 안 됨
- **실제 로봇 펌웨어 버전 확인 필수**: V2는 펌웨어 V1.5-2+, MOVE M(MIT) V1.5-2+, CPV V1.6.5+. 실기 펌웨어가 무엇인지 팀원이 확인해 공유

---

## 8. 합의 체크리스트 (착수 전 둘이 확인)
- [ ] 양쪽 다 **piper_sdk v0.6.1 / 프로토콜 V2** 기준 사용
- [ ] 실제 로봇 **펌웨어 버전** 확인 (V2 호환 여부)
- [ ] 1차 통합 범위 = **명령: 0x151 모드 + 0x155–0x157 관절 + 0x471 enable** / **피드백: 0x2A1 상태 + 0x2A5–0x2A7 관절**
- [ ] 반사 1차 = **0x150 비상정지 inject**
- [ ] HighSpd current = signed 로 통일
- [ ] SDK 버전 올릴 땐 이 문서 갱신 + 상호 통지

---

## 부록. 검증에 바로 쓰기 (golden reference)
PC의 USB-CAN(SocketCAN)으로 이 ID들을 직접 쏘고/받아 FPGA CAN MAC을 검증:
```bash
sudo ip link set can0 up type can bitrate 1000000
# 예: 1번 관절 enable
cansend can0 471#0102....         # B0=01(motor1) B1=02(enable)  ※실제 8바이트 맞춰서
candump can0                       # 0x2A1, 0x2A5~ 피드백 관측
```
> 실제 프레임은 8바이트를 §2~§4 레이아웃대로 채워야 함. 팀원의 piper_sdk 인코딩 결과를 `candump`로 떠서 그대로 비교하면 가장 정확.
