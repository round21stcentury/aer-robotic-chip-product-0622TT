# 03_hils 변경 로그

> 동작변경은 _v숫자 + 여기 기록. (구버전은 같은 폴더 past/ 로 보관)
> HILS는 설계무관 통신·시뮬 계층 — 반사 설계와 무관한 범용 도구만 손댄다.

## 슬라이더·wave 속도 제어 추가 (2026-06-16)
- 동기: 반사를 넣으면 동작 "도중"에 멈추는지 확인이 안 됨(빠르면 타이밍상 안 보임). 느리게 움직이면 반사가 궤적 중간을 끊는 게 보임 = 보간 흉내.
- **tools/joint_slider_gui_v2.py** (v1→past): HIL 슬라이더에 **속도% 슬라이더 추가**. velocity[6]=속도율(없으면 100%). 낮추면 천천히 → 반사 중간정지 관찰. 참조 tests/stage3b_slider.sh 를 v2로 갱신.
- **motions/wave_v2.py** (wave.py→past): 손인사 도중 **실시간 속도% 슬라이더 창**(별도 스레드, 디스플레이 없으면 SPEED 고정으로 폴백). 모션은 메인스레드(rclpy 시그널 정상). 참조 Makefile 예시를 wave_v2.py 로 갱신.
- **motions/lib.py** (in-place, 하위호환 additive): motion_main 의 speed 가 숫자뿐 아니라 **함수(callable)**도 받게 — 함수면 매 발행마다 호출해 실시간 속도. 기존 숫자 호출 그대로 동작.
- 검증: 파이썬 문법 py_compile 3개 통과. (실제 Gazebo 구동 확인은 사용자 테스트.)
- 사용: `make run MODE=hil APP=slider`(슬라이더에 속도%) / `make run MODE=hil APP=motions/wave_v2.py`(wave 속도창).

## ★HIL RX-피드백 격차 수정 — 반사 칩이 도달플래그를 못 받던 문제 (2026-06-16)
- **증상:** 06 덕포즈 반사 HIL에서 슬라이더는 잘 돌다가(candump can0에 0x155/156 정상) FSR 누르면 올스탑·복귀 안 됨(가끔 부팅부터 올스탑=불안정).
- **원인:** virtual_robot이 피드백(0x2A1 도달/0x2A5~7)을 **vcan0(컨트롤러)로만** 보내고 can0(칩 버스)엔 안 올림.
  → 칩 CTU RX는 can0에 있는데 0x2A1이 can0에 없으니 reached 영원히 0 → 포즈 해제규칙(b: 도달+센서뗌)이 못 풀림
  → reflex_pose 영구 1 → ps_gate 영구 1 → bd OR게이트가 PS_tx 영구 차단. (실로봇은 같은 버스에 0x2A1 쏴서 OK였음.)
- **고침(virtual_robot.py, 추가만):** cmd-iface가 실제 CAN(can*)이면 상태(0x2A1/2A5~7)를 ★그 물리버스에도 브로드캐스트★
  (실로봇처럼). `--status-iface`로 override, 'off'로 끔. vcan 순수sim은 자동 off라 기존 동작 불변. 전용 송신소켓(RX스레드와 분리).
- ★FPGA 재빌드 불필요 — PC측만. HIL 재시작하면 적용. candump can0에 0x2A1/2A5~7 떠야 정상.
- 설계분리: 반사 RTL/설계 안 건드림. virtual_robot "로봇 모델 충실도"(실로봇은 자기 버스에 상태 쏨) 개선이라 반사무관·범용. 07(현재포즈)도 0x2A5~7 can0 필요 → 같이 해결됨.
- 남은 불안정(부팅 올스탑)=XADC VAUX14 floating이 임계 넘는 스퓨리어스 → FSR 연결/N→GND/임계 위로. 이건 HW 위생.
