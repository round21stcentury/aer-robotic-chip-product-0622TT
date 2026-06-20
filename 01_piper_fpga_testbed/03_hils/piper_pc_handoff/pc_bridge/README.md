# pc_bridge — PC 측 CAN-이더넷 브리지 + 가상로봇

핸드오프(`00_핸드오프_README.md`)와 두 계약서의 **PC 측 절반**을 구현한다.
경계면 = 이더넷 위 **13바이트 UDP 패킷 1개**. 반환 경로는 실제 CAN(can0)이라 UDP 5001 수신부는 없다.

## 토폴로지 (1안 — piper_sdk 패치 0)
```
[컨트롤러 piper_sdk] --cmd--> vcan0 --[bridge]--> UDP:5000 --> [FPGA/mock] --> 물리CAN/vcan1
                                                                              |
[컨트롤러]   <--feedback-- vcan0 <--[virtual_robot]--  can0/vcan1 <------------+
```
- 컨트롤러는 `vcan0` 하나만 (`can_port:=vcan0`로 launch). 가상로봇은 명령버스(can0/vcan1) 하나만.
- 브리지는 vcan0의 **명령 ID만** FPGA로 (피드백 ≥차단). 가상로봇 피드백은 vcan0 직행.

## 구성
| 파일 | 역할 |
|---|---|
| `piper/frames.py` | ★코덱: 0x151/155-7/471 + 0x2A1/2A5-7 enc·dec, 13B UDP 팩, 단위변환. piper_sdk 골든벡터로 검증 |
| `piper/ids.py` | CAN ID 상수 + 명령/피드백 방향 분류 (브리지 필터 근거) |
| `piper/caniface.py` | raw SocketCAN 래퍼 (python-can 불필요) |
| `bridge/can_udp_bridge.py` | vcan0 명령 → 13B UDP → FPGA (즉시, 버퍼링 없음) |
| `vrobot/virtual_robot.py` | can0 명령 디코드 → 백엔드 → 피드백 인코드 → vcan0 |
| `vrobot/backend_kinematic.py` | 백엔드A: 운동학 echo (의존성 0, 1·2단계용) |
| `vrobot/backend_gazebo.py` | 백엔드B: `/arm_controller/joint_trajectory` ↔ `/joint_states` (3단계) |
| `tools/mock_fpga.py` | UDP5000 → CAN 재전송. FPGA 없이 PC 단독 검증 |
| `setup/setup_can.sh` | vcan0/vcan1(sim) 또는 can0 gs_usb(hw) brings-up |
| `tests/test_frames.py` | 코덱 단위테스트 + piper_sdk 골든벡터 |
| `tests/bringup1_send_0x155.py` | 1단계: 13B/엔디언 그대로 도착 검증 |
| `tests/latency_probe.py` | 2단계: 왕복 레이턴시 측정 |

## 확정값 (계약서)
- FPGA `192.168.1.10`, PC `192.168.1.100`, 명령 UDP **5000**
- CAN: 클래식 2.0 / 11비트 / **1 Mbps** / 빅엔디언 / 관절 signed int32 0.001°
- 단위: 명령 rad→0.001° `×57324.840764`, 피드백 0.001°→rad `×0.017444/1000` (piper_sdk 미러)

## 실행 — 코덱 검증 (root 불필요)
```bash
python3 tests/test_frames.py        # ✅ 골든벡터 통과
```

## 실행 — 1단계 transport+HW (sim, root 필요)
```bash
# 터미널1
sudo bash setup/setup_can.sh sim
# 터미널2
python3 bridge/can_udp_bridge.py --iface vcan0 --fpga-ip 127.0.0.1 --verbose
# 터미널3
python3 tools/mock_fpga.py --out-iface vcan1 --verbose
# 터미널4
python3 tests/bringup1_send_0x155.py --return-iface vcan1   # → ✅ 바이트 그대로 도착
```
> sim 모드에선 mock_fpga가 같은 PC라 `--fpga-ip 127.0.0.1`. 실제 FPGA 통합 시 `192.168.1.10`.

## 실행 — 2단계 레이턴시
```bash
python3 tests/latency_probe.py --return-iface vcan1 --n 200
```

## 실행 — 3a단계 piper_sdk 루프 교차검증 (Gazebo 불필요) ✅ 통과
실제 piper_sdk ↔ 우리 코덱을 양방향(0x151/155-7 ↔ 0x2A1/2A5-7)으로 wire 검증.
```bash
# host: vcan0/vcan1 (sudo)
sudo bash setup/setup_can.sh sim
# 컨테이너에서 (network host + pc_bridge·ros2_ws 마운트):
docker run --rm --network host \
  -v /home/sihun/workspace/pc_bridge:/pc_bridge \
  -v <...>/ros2_ws:/root/ros2_ws \
  piper-hil:humble bash /pc_bridge/tests/stage3a_piper_in_loop.sh
# → 발행 관절각이 joint_states_feedback 으로 ~일치 복귀하면 OK
```
> ⚠️ 컨트롤러는 vcan0 에서 `judge_flag:=false` 필요. 이유·변경내역 = `PATCH_NOTES.md`.

## 실행 — 3b단계 Gazebo 3D 루프 (컨테이너, 디스플레이 필요)
```bash
ros2 launch piper_gazebo piper_gazebo.launch.py          # Gazebo + ros2_control
python3 vrobot/virtual_robot.py --cmd-iface vcan1 --fb-iface vcan0 --backend gazebo
ros2 launch piper start_single_piper.launch.py can_port:=vcan0 judge_flag:=false auto_enable:=false
# bridge + mock_fpga(--out-iface vcan1) 또는 실제 FPGA 가 vcan0→vcan1/can0 명령경로 담당
```

## 미해결 (통합 시 확인)
- 실기 로봇 **펌웨어 버전** V2/V1.5-2+ 호환 (계약서 §8).
- 코덱 권위 레퍼런스: `../reference/piper_sdk/` (docker 이미지에서 추출). 골든벡터 재생성도 여기 기준.
