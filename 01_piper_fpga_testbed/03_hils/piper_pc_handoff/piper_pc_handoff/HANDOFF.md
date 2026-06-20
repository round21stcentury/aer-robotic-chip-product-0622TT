# 결과 핸드오프 — PC 측 CAN-이더넷 브리지 + 가상로봇

> 원본 `docs/00_원본_핸드오프_README.md`("무엇을 만들어라")의 **PC 측 절반을 구현·검증한 결과** 문서.
> 대상: FPGA 담당자 / 팀원 / 미래의 나. 작성: 2026-06-13.
> **이 파일이 진입점.** 이 폴더 하나만 받으면 됨.

---

## 패키지 구성 (이 폴더 = 전달물 전체)

```
piper_pc_handoff/
├── HANDOFF.md                 ← 지금 이 파일 (진입점)
├── docs/                      ← 계약서 + 원본 핸드오프 (경계면 규격)
│   ├── 00_원본_핸드오프_README.md
│   ├── CAN_프로토콜_계약서.md          (프레임 정의)
│   └── CAN-이더넷_브리지_계약서.md      (13B UDP 운반 규격)
├── pc_bridge/                 ← ★구현물★ (실행법 = pc_bridge/README.md)
│   ├── README.md              실행/검증 절차
│   ├── PATCH_NOTES.md         piper_ros 노드 수정 내역·이유·되돌리기
│   ├── piper/                 코덱·ID·SocketCAN 래퍼
│   ├── bridge/                CAN→UDP 브리지
│   ├── vrobot/                가상로봇(kinematic/gazebo 백엔드)
│   ├── tools/                 mock_fpga
│   ├── setup/                 vcan/can brings-up
│   └── tests/                 골든벡터·1·2·3a·3b
└── reference/
    └── piper_sdk/             piper_sdk v0.6.1 권위 소스(코덱 레퍼런스·골든벡터 재생성)
```

> 경로는 모두 **이 폴더 기준 상대경로**. 어디에 풀어도 됨.

---

## 0. 한 줄 요약

시뮬의 Piper 명령(절대 관절각)을 **13바이트 UDP로 FPGA에 보내고, FPGA가 실제 CAN으로 되쏜 걸 USB-CAN으로 받아 루프를 닫는 PC 측 절반**을 구현했다. 경계면(13B UDP)·경로분리(명령=FPGA, 피드백=실제CAN)는 계약서 그대로. **코덱은 piper_sdk 실코드와 양방향 교차검증 통과.**

---

## 1. 상태

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | transport+HW 무결성 (13B/빅엔디언 그대로 도착) | ✅ sim 통과 |
| 2 | 왕복 레이턴시 측정 | ✅ sim 측정 (아래 §3) |
| 3a | piper_sdk 루프 코덱 양방향 교차검증 (Gazebo 불필요) | ✅ 통과 |
| 3b | Gazebo 3D 루프 | 🟡 스크립트 준비됨, 디스플레이 환경에서 실행 필요 |
| — | 실제 FPGA+USB-CAN 결선 레이턴시 재측정 | ⛔ 하드웨어 대기 |
| — | reflex(0x150 inject 등) | ⛔ 1차 범위 밖 (FPGA 담당) |

---

## 2. 무엇을 만들었나 (`pc_bridge/`)

| 파일 | 역할 |
|---|---|
| `piper/frames.py` | 코덱: 0x151/155-7/471 + 0x2A1/2A5-7 enc·dec, 13B UDP 팩, 단위변환 |
| `piper/ids.py` | CAN ID 상수 + 명령/피드백 방향 분류 (브리지 필터 근거) |
| `piper/caniface.py` | raw SocketCAN 래퍼 (python-can/ROS 의존성 0) |
| `bridge/can_udp_bridge.py` | vcan0 **명령만** → 13B UDP → FPGA (즉시, 피드백 이중차단) |
| `vrobot/virtual_robot.py` | 명령버스 디코드 → 백엔드 → 피드백 인코드 → vcan0 (200Hz) |
| `vrobot/backend_kinematic.py` | 운동학 echo (의존성 0; 1·2·3a용) |
| `vrobot/backend_gazebo.py` | 기존 piper_gazebo 직결 (`/arm_controller/joint_trajectory`↔`/joint_states`) |
| `tools/mock_fpga.py` | UDP→CAN. FPGA 없이 PC 단독 검증 |
| `setup/setup_can.sh`, `setup/run_sim_bringup.sh` | vcan/can brings-up, 1·2단계 자동 |
| `tests/*` | 코덱 골든벡터, 1단계, 레이턴시, 3a, 3b 스크립트 |

실행법 = `pc_bridge/README.md`. SDK 노드 수정 내역 = `pc_bridge/PATCH_NOTES.md`.

---

## 3. 검증 증거

**코덱 (test_frames.py)** — piper_sdk `ConvertToList_*` 실코드 출력(골든벡터)과 바이트 동일:
- 0x155 joint(1000,-2000) → `000003E8FFFFF830` ✅, 13B UDP 0x155 → `00000155 08 000003E8FFFFF830` ✅

**레이턴시 (2단계, sim 루프백)**: n=200, **손실 0**, 왕복 median 0.249ms / p99 0.408ms / max 0.439ms.
> ⚠️ 이 수치는 **localhost+vcan 소프트웨어 루프백**. 실제 gs_usb USB 왕복+FPGA 지연은 빠져 있음 → 실기 결선 후 재측정 대상(계약서 §4·§5-2, "느린 건 결함 아님").

**3a (piper_sdk 양방향 wire 교차검증)**: 컨트롤러(piper_sdk, vcan0)에 관절 명령 발행 → 전 경로 통과 → 피드백 복귀:

| 관절 | 명령(rad) | 피드백(rad) |
|---|---|---|
| j1 | 0.20 | 0.19999546 |
| j2 | -0.30 | -0.299984468 |
| j3 | 0.40 | 0.39999092 |
| j5 | 0.10 | 0.099989008 |
| j6 | -0.15 | -0.150000956 |

오차 ~5e-5 rad = piper_ros 자체 비대칭 계수(57324.84 vs 0.017444) 반올림. **즉 piper_sdk 인코딩(0x155-7) → 우리 디코딩 → 재인코딩(0x2A5-7) → piper_sdk 디코딩 전 구간 바이트 정합** = 계약서 §부록 골든 레퍼런스 충족.

---

## 4. 핵심 결정·발견

1. **토폴로지 1안 실증**: 컨트롤러는 `C_PiperInterface(can_name=can_port)` 단일 인터페이스. `can_port:=vcan0`만 주면 됨 — SDK 다중인터페이스 패치 불필요.
2. **브리지·가상로봇 = 커스텀 Python**, raw SocketCAN(의존성 0). mock_fpga 포함해 FPGA 없이 단독 검증 가능.
3. **⚠️ piper_sdk vcan 비호환 (중요)**: piper_sdk가 `/sys/class/net/<if>/operstate=="up"`+`bitrate==1Mbps`를 검사하는데 **vcan은 operstate=unknown/bitrate없음**이라 거부. → SDK가 가상버스용으로 제공하는 공개 파라미터 `judge_flag=False`를 **컨트롤러 노드+launch에 ROS 파라미터로 정식 노출**(기본 True=실기 불변). 변경내역 `pc_bridge/PATCH_NOTES.md`. **실기에서도 컨트롤러는 vcan0를 쓰므로 이 적응은 sim 한정이 아니라 1안 필수.**
4. **단위계수**(piper_ros 미러): 명령 rad→0.001° `×57324.840764`, 피드백 0.001°→rad `×0.017444/1000`.
5. **프레임 의미**: CAN엔 항상 **절대 목표 관절각(명령) ↔ 현재 상태(피드백 200Hz)**가 흐름. 현재→목표 보간/제어는 로봇 MCU(실기) 또는 ros2_control JTC(sim)가 담당, piper_sdk·브리지·FPGA는 보간 안 함.

---

## 5. FPGA 담당자에게 (경계면 재확인)

PC 측은 계약서를 그대로 지켰습니다:
- **명령 경로만** FPGA로: `192.168.1.10:5000`, **정확히 13바이트** = `can_id`(빅엔디언 4B)+`dlc`(1B)+`data[8]`, payload **재해석 없이 통과**.
- **피드백은 FPGA로 안 보냄** (UDP 5001 미사용). 반환은 실제 CAN→USB-CAN.
- 브리지는 **명령 ID만 송신**(0x151/155-7/471), 피드백 ID(≥0x2A1)는 이중 차단.
- mock_fpga(`pc_bridge/tools/mock_fpga.py`)가 당신 절반의 참조 동작(UDP→CAN 그대로)입니다. 붙일 때 mock 자리에 실제 FPGA, `--fpga-ip 192.168.1.10`으로 교체.
- reflex가 건드릴 ID = **0x150 e-stop / 0x155-7 관절 / 0x151 속도 / 0x471 enable** (프로토콜 §5). 명령 경로에서 가로채면 됨.

---

## 6. 남은 일

1. **3b Gazebo 3D 루프**: `pc_bridge/tests/stage3b_gazebo_loop.sh` 준비됨. 디스플레이 환경에서 실행(`pc_bridge/README.md` §3b). Docker 내 GL/X 변수 있을 수 있음 — 안 뜨면 gzserver 헤드리스 폴백.
2. **실기 결선 레이턴시·손실 재측정**: mock_fpga→실제 FPGA, return-iface→can0로 동일 도구(`pc_bridge/tests/latency_probe.py`) 재실행.
3. **실기 펌웨어 버전 확인**: V2/V1.5-2+ 호환 (`docs/CAN_프로토콜_계약서.md` §8).
4. **reflex / MIT / Cartesian**: 1차 범위 밖. 확장 시 `reference/piper_sdk/` 권위 소스 기준.

---

## 7. 참조

- 계약서: `docs/CAN_프로토콜_계약서.md`(프레임), `docs/CAN-이더넷_브리지_계약서.md`(13B UDP)
- 원본 핸드오프(무엇을 만들어라): `docs/00_원본_핸드오프_README.md`
- piper_sdk 권위 소스: `reference/piper_sdk/` — 코덱 레퍼런스·골든벡터 재생성
- SDK/노드 수정: `pc_bridge/PATCH_NOTES.md`
- 실행: `pc_bridge/README.md`
