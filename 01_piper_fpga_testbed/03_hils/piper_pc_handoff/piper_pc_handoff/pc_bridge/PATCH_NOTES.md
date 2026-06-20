# AgileX piper_ros 수정 내역 (HIL 적응 — 최소·하위호환)

> pc_bridge 자체가 아니라 **piper_ros 컨트롤러 노드**에 가한 변경. 1안 토폴로지에 필수.
> 모두 **가산적 + 기본값 = 기존 실기 동작 그대로**라 can0 실기 사용엔 영향 없음.

## 왜 필요한가
토폴로지 1안에서 컨트롤러(piper_sdk)는 **vcan0**(가상 CAN)에 붙는다. 그런데 piper_sdk는
연결 시 `/sys/class/net/<if>/operstate == "up"` + `bitrate == 1Mbps` 를 검사하는데,
**vcan은 operstate가 영구 "unknown" 이고 bitrate 가 없다**(가상버스라 물리 carrier 개념 부재).
→ 이 물리검사를 통과시킬 방법이 원천적으로 없음.

piper_sdk 는 이를 위해 생성자에 **공개 파라미터 `judge_flag`**(물리검사 on/off)를 제공한다.
AgileX 노드가 이 값을 넘기지 않을 뿐이라, **노드/런치에 ROS 파라미터로 노출**한다.
(몽키패치/`/sys` 위조 같은 우회가 아니라, SDK가 가상버스용으로 의도한 API를 정식 노출.)

## 변경 파일 (src + 빌드된 install 사본 동일 반영)
1. `src/piper_ros/src/piper/piper/piper_ctrl_single_node.py`
   - `declare_parameter('judge_flag', True)`, `declare_parameter('can_auto_init', True)` 추가
   - `C_PiperInterface(can_name=..., judge_flag=self.judge_flag, can_auto_init=self.can_auto_init)`
2. `src/piper_ros/src/piper/launch/start_single_piper.launch.py`
   - `judge_flag`, `can_auto_init` LaunchArgument 추가 (기본 true)

## 사용
- **실기(can0)**: 아무것도 안 바꿔도 됨 (기본 true).
- **vcan0(HIL)**: `judge_flag:=false` 로 실행. `can_auto_init` 은 **true 유지**
  (false 면 버스 자체가 생성 안 돼 ConnectPort 실패 — bitrate 체크는 어차피 judge_flag 안에 있어 false 하나로 충분).

```bash
ros2 run piper piper_single_ctrl --ros-args -p can_port:=vcan0 -p judge_flag:=false
# 또는
ros2 launch piper start_single_piper.launch.py can_port:=vcan0 judge_flag:=false
```

## 되돌리기
`git -C src/piper_ros checkout -- src/piper/piper/piper_ctrl_single_node.py src/piper/launch/start_single_piper.launch.py`
후 `colcon build` (install 사본은 재빌드로 갱신).
