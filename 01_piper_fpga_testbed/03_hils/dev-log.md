# 03_hils 변경 로그

> **규칙:** 새 환경/시나리오/동작변경이 생기면 기존 파일 in-place 수정 금지 →
> `<이름>_v<숫자>.<확장자>` 복사본 만들어 거기 고치고, 참조(Makefile 등) 갱신, 여기에 항목 추가.
> 한 코드로 다 하려다 동작하던 게 깨지는 걸 방지(예: hils_run.sh를 robot용으로 고치니 hil 슬라이더 깨짐).
>
> 항목 형식: **[날짜] 파일 vN — 무엇을 왜 / 결과**

---

## Baseline (v1, 2026-06-13)
현재 동작 파일들(= v1 기준). 다음 변경부터 `_v2`로 포크.
- `piper_pc_handoff/pc_bridge/tests/hils_run.sh` — MODE(sim/hil/robot)×APP(slider/motion) 통합 런처
- `piper_pc_handoff/pc_bridge/tools/joint_slider_gui.py` — 관절 슬라이더 GUI(속도% 포함)
- `piper_pc_handoff/pc_bridge/motions/{lib,_template,wave}.py` — 동작 템플릿
- `Makefile` — prep/run/slider/motion + 단축어(serial/can-mon/program/docker-fix/gz-kill)

## 변경 이력 (시간순)

### [2026-06-13] ★★★ HIL gazebo+슬라이더 성공 — 진짜 근본원인 = DDS 공유메모리 463개 누적 ★★★
- **최종 진단(로그 traceback):** gazebo 컨트롤러가 `node.get_namespace()`(자기 이름 읽기)조차 `xmlrpc Fault: !rclpy.ok()`로 죽음 = ROS 통신 상태 오염. `/dev/shm` 확인 → `fastrtps_*` 세그먼트 **463개** 누적.
- **누적 이유:** `--ipc host` 라 컨테이너의 /dev/shm = 호스트 /dev/shm. 세그먼트는 **root 소유** → 호스트 사용자(haeun)가 못 지움 → 내가 만든 `rm`(호스트 실행)이 권한없어 **조용히 실패** → 매 run마다 쌓이기만 함 → gazebo 컨트롤러 질식사.
- **수정:** 청소를 **컨테이너 root 로** 실행.
  - `hils_run.sh` 맨 위: 매 실행 시작에 `rm -f /dev/shm/fastrtps_* sem.fastrtps_* fast_datasharing_*` (컨테이너 root → root파일 삭제 가능).
  - `make gz-kill` 도 throwaway root 컨테이너로 삭제(`docker run --rm --ipc host ... rm -f /dev/shm/...`).
  - **증명:** 청소 전 463개 → 후 0개.
- **부수 수정(이 과정에서):** 슬라이더 맨앞 영구유지(`_keep_top`), wait 루프 `timeout 3`+진행echo, 순차 실행(컨트롤러 격리 스폰), virtual_robot 본문 복귀, 슬라이더 2종(HIL=무속도/실로봇=속도%).
- **재발 방지:** hils_run.sh가 **매 실행마다 시작 시 자동 청소** → 더 이상 누적 불가. 사용자가 gz-kill 안 해도 됨.
- **교훈:** 코드만 보고 환경(공유메모리 상태)을 못 봤음. "첫 run만 됨"은 상태누적의 전형적 신호 → 다음엔 환경부터 의심.

## 실증용(robot) vs HIL — 궁극적 차이 (참고)

| | **HIL (MODE=hil)** | **실로봇 (MODE=robot)** |
|---|---|---|
| 목적 | 데모 전 시뮬로 FPGA 루프 검증 | 진짜 팔 구동(실증) |
| 경로 | slider→컨트롤러(vcan0)→bridge→UDP→**FPGA→can0(USB-CAN)→virtual_robot→Gazebo** | slider→컨트롤러(vcan0)→bridge→UDP→**FPGA→물리CAN→진짜 로봇** |
| 필요 IF | vcan0 + **can0(USB-CAN 1M)** | **vcan0 만** (USB-CAN 불필요) |
| gazebo/virtual_robot | **필요**(3D 표시 + can0→gazebo 변환) | **없음**(진짜 로봇이 CAN 장치 그 자체) |
| 피드백 | virtual_robot 이 vcan0 로 피드백 줌 → 컨트롤러가 봄 | **피드백 없음(개루프)** — 우리 FPGA 단방향 |
| `judge_flag` | `false` (vcan0 가상버스라 물리CAN 검사 스킵) | `false` (동일 이유) |
| `exit_on_loss` | (피드백 있으니 무관) | **`false` 필수** — 피드백 없으면 컨트롤러가 "vcan0 loss"로 **꺼져버려** 구동 안 됨. 그래서 끄지 않게 false |
| CAN ACK | can0(USB-CAN)이 물리버스에서 자동 ACK | 진짜 로봇이 물리버스에서 자동 ACK |
| 슬라이더 | `joint_slider_gui.py`(무속도, 100%) | `joint_slider_gui_robot.py`(속도% 저속시작=안전) |

**핵심 한 줄:** HIL은 "can0(USB-CAN)+virtual_robot+gazebo"로 로봇을 **흉내내서 본다**. 실로봇은 그 흉내층이 다 빠지고 **진짜 팔이 CAN 장치**가 된다. 실로봇이 까다로운 건 **피드백이 없어서(개루프) 컨트롤러가 스스로 꺼지려 하는 것**(→ exit_on_loss=false로 막음) + **vcan0 가상버스라 물리검사 스킵**(judge_flag=false) 두 가지.


### [2026-06-13] HIL "로봇 꼬꾸라짐 + 동작 안함" — 컨트롤러 death + virtual_robot 미기동
- **증상:** 슬라이더·gazebo 다 뜨는데 로봇 처지고 안 움직임.
- **로그 진단(/tmp/hils.log):** ① gazebo 컨트롤러들이 `!rclpy.ok()`로 죽음(arm_controller death=처짐). ② `[vrobot]` 줄 0개 = **virtual_robot 미기동**(can0→gazebo 옮기는 핵심이 빠짐=동작 안함).
- **원인①:** 내가 슬라이더를 앞으로 당기며 파이프라인을 gazebo 스폰과 **동시 시작** → 경합으로 컨트롤러 스포너 죽음. → **순차 실행 복원**(gazebo 컨트롤러 격리 기동 후 파이프라인). + 매초 진행상황 echo(사용자가 닫지 않게).
- **원인②(재발 방지):** `--ipc host`라 `/dev/shm` 공유 → 이전 run의 `fastrtps_*` 찌꺼기가 다음 스폰 오염(첫 run만 되던 이유). → **gz-kill이 `/dev/shm/fastrtps_*` 청소**하도록 강화. (찌꺼기 잔존 확인됨.)
- virtual_robot은 순차 본문에 복귀(백그라운드 지연 제거).

### [2026-06-13] HIL 슬라이더 "안 뜸" 최종 원인 2개 — ★둘 다 수정★
- **진단 방법:** Makefile에 `DBG=1`(컨테이너 전출력 /tmp/hils.log tee) + `slider-only`(gazebo 없이 슬라이더만) 추가 → 데이터로 분리.
  - `slider-only` → 슬라이더 **뜸** = 슬라이더/X 정상.
  - 실로봇(gazebo 없음) → **뜸**. HIL(gazebo 있음) → **안 뜸**.
- **원인①(슬라이더):** 내가 넣은 `after(800, -topmost False)` → 0.8초만 맨앞 뒤 해제 → **gazebo가 덮음.** → `joint_slider_gui.py`: 맨앞 **영구 유지**(`_keep_top` 1.5초마다 lift)로 수정. (2분 run에서 에러 0인데 창 없던 게 이걸로 설명=창은 살아있고 덮였던 것.)
- **원인②(도달 실패):** stage3b_slider.sh wait 루프의 `ros2 control list_controllers`가 불안정(가끔 빈 결과/멈춤) → 40초 헛돌다 사용자가 gazebo 닫음 → **슬라이더 단계 도달 못함.** → `timeout 3` + 최대 25초 + **확인 못해도 무조건 진행**으로 수정.
- GPU(amdgpu) 아님 확정(사용자): `LIBGL=1`은 오히려 물리 깨져 로봇 처짐 → 쓰지 말 것.

### [2026-06-13] 슬라이더 2종 분리 — ★HIL 원본 복원★
- **증상:** `make slider MODE=hil` 에 원래 쓰던 **속도조절 없는** 슬라이더가 아니라 실로봇용(속도%)이 뜨고, 그나마 잘 안 돎.
- **원인:** 내가 `joint_slider_gui.py`에 속도% 슬라이더를 **in-place로 추가**(velocity=[0]*6+[speed]) → HIL 원본을 덮어씀. 컨트롤러는 velocity[6]을 MotionCtrl 속도로 해석(원본=velocity 없음→100%, 속도판=20%라 굼떠 "안 도는 것처럼" 보임).
- **복구(버전 규칙):** transcript에서 원본 복원.
  - `tools/joint_slider_gui.py` ← **원본(속도 없음, MotionCtrl 100%)** = HIL/sim 슬라이더. stage3b_slider.sh·sim 인라인이 부름.
  - `tools/joint_slider_gui_robot.py` ← 속도% 판 보존 = **실로봇 전용**(저속 시작 안전). real_robot_slider.sh가 부름.
- 컨트롤러(piper_ctrl_single_node.py) joint_callback: `velocity==[] or all_zeros → MotionCtrl_2(...,100)`, `len==7 → velocity[6]%`. 즉 원본은 100%로 또렷이 움직임.

### [2026-06-13] hils_run.sh — ★통합 폐기, 디스패처로 롤백★ (최종)
- **사용자 지시:** "로봇 실증때 고친 부분 롤백하고, 롤백안한버전을 리얼로봇용 스크립트로 써라."
- **문제:** hils_run.sh로 sim/hil/robot 통합 → hil 슬라이더 깨짐(로봇 축 처짐 + 슬라이더 안 뜸). wait 루프를 두 번 뒤집으며 더 헤맴.
- **롤백:** hils_run.sh를 **얇은 디스패처**로. 검증된 전용 스크립트로 위임:
  - `hil + slider` → `stage3b_slider.sh` (**손 안 댐**, 검증본)
  - `robot + slider` → `real_robot_slider.sh` (**손 안 댐**, 검증본)
  - `sim 슬라이더 / 모션` → 인라인이되 **stage3b의 검증된 wait 루프 구조 그대로**(gazebo 터미널 출력, arm_controller active 대기).
- **결과:** hil/robot 슬라이더는 검증본을 그대로 exec → 통합 때문에 깨질 여지 제거. Makefile/인터페이스(`make slider MODE=hil`)는 그대로.

### [2026-06-13] hils_run.sh — ★wait 루프 제거는 실수, 되돌림★
- **증상(원래):** `make slider MODE=hil` 슬라이더 안 뜸 / Gazebo 닫으면 뜸.
- **내 오판:** wait 루프가 블로킹이라 보고 **제거** → 결과: gazebo 준비 전에 virtual_robot 시작 → **로봇이 잡히지 않아 축 처짐(꼬꾸라짐) + 슬라이더 안 먹음.** (slider canTX는 정상이었음=명령경로 OK, gazebo 유지가 깨진 것)
- **진짜 원인:** 슬라이더 안 뜸 = **쌓인 컨테이너 포트충돌**(gazebo 죽음→arm_controller 로딩 실패→대기 안 끝남). gz-kill/run 자동정리로 해결할 문제였음.
- **되돌림:** `arm_controller active 대기 루프 복원`(+timeout, +gazebo 로그 분리 유지). virtual_robot이 gazebo 준비 뒤 시작 → 로봇 유지됨. 슬라이더는 컨테이너 정리(gz-kill)로 정상 표시.
- (보조 유지) joint_slider_gui.py 창 맨앞으로(`-topmost`).

### [2026-06-13] Makefile — docker 권한 자동 처리 + 컨테이너 누적 정리 (유효)
- **증상:** 터미널마다 `permission denied (docker.sock)`; piper-hil 컨테이너가 쌓여 Gazebo 포트 충돌.
- **수정:** run/sdk-build-ws/gz-kill에 가드(`docker ps` 실패 시 `sg docker -c`로 자동 재실행). run 시작 시 기존 컨테이너 자동 제거. gz-kill 견고화. LIBGL=1(소프트렌더) 옵션.

### [2026-06-13] piper_ctrl_single_node.py — 실로봇용 (참고: 이 파일은 ros2_ws에 있음)
- judge_flag(vcan 물리검사 스킵) + exit_on_loss(피드백 단방향 개루프 허용) 파라미터 추가. 기본값=실기 동작.
