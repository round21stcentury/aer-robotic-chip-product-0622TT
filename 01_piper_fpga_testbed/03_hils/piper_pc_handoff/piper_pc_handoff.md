# piper_pc_handoff — 팀원 PC 브리지 + 가상로봇 + 테스트

> 팀원이 넘긴 **PC측 HIL 부품**. 외부 의존성 0(stdlib + raw SocketCAN).
> 03_hils/Makefile이 이 안의 스크립트들을 실행해 HIL 루프를 돌린다.

## 구조
```
piper_pc_handoff/
├── pc_bridge/          ★실제 동작 코드★
│   ├── bridge/
│   │   └── can_udp_bridge.py     vcan0 CAN ↔ 13B UDP(:5000) 변환 (PC↔FPGA)
│   ├── vrobot/
│   │   ├── virtual_robot.py      can0 명령 → 백엔드 구동 + 피드백(0x2A5~7)→vcan0
│   │   ├── backend_gazebo.py     Gazebo 3D 백엔드
│   │   └── backend_kinematic.py  3D 없는 운동학 백엔드
│   ├── tools/
│   │   ├── joint_slider_gui.py        ★HIL/sim 슬라이더(속도조절 없음=100%)★
│   │   ├── joint_slider_gui_robot.py  ★실로봇 슬라이더(속도% 저속시작)★
│   │   └── mock_fpga.py               sim용 FPGA 대역(UDP→vcan1)
│   ├── motions/        lib.py(헬퍼) · _template.py · wave.py(손인사) — /joint_ctrl_single 발행
│   ├── piper/          CAN 코덱 패키지: ids.py · frames.py · caniface.py (인코딩/디코딩)
│   ├── setup/          setup_can.sh(vcan/can 셋업) · run_sim_bringup.sh
│   └── tests/          ★실행 스크립트★ (아래)
├── docs/               CAN/브리지 계약서(02.../bin/doc 사본)
└── reference/piper_sdk 참고용 SDK 사본
```

## tests/ — 무엇이 언제 실행되나
| 파일 | 역할 |
|---|---|
| **hils_run.sh** | ★컨테이너 진입점/디스패처★ — MODE×APP을 검증 스크립트로 위임 + DDS 청소 |
| **stage3b_slider.sh** | ★hil+slider★ — gazebo+bridge+virtual_robot+컨트롤러+슬라이더 |
| **real_robot_slider.sh** | ★robot+slider★ — bridge+컨트롤러+슬라이더 (가제보/가상로봇 없음) |
| stage3a_*.sh / stage3b_*.sh | 단계별 검증(자동자세/실FPGA/가제보루프) |
| bringup1_send_0x155.py | 0x155 바이트무결 검증 |
| latency_probe.py | 왕복 레이턴시 측정 |
| test_frames.py | CAN 코덱 골든벡터 단위테스트(의존성0) |

> `make slider MODE=hil` → `hils_run.sh` → `stage3b_slider.sh` → 위 파이프라인.
> 전체 흐름은 [../03_hils.md](../03_hils.md) / [../../00_전체구조.md](../../00_전체구조.md) 참고.

## 🗑️ 삭제 가능
`pc_bridge/*/__pycache__/` (vrobot·motions·tools·piper). 소스/스크립트는 전부 유지.
