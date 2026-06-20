# 05_zybo_can_eth — ★현재 활성★ 이더넷 UDP→CAN HIL 브리지

> **보드에 올라가는 펌웨어.** PC가 보낸 13바이트 UDP(:5000)를 받아 lwIP로 수신 →
> XCanPs로 **실제 CAN(1Mbps)** 송신. 이게 HIL 루프의 FPGA 쪽 절반.

## 동작
```
PC --UDP 13B (192.168.1.10:5000)--> [lwIP 수신] --파싱--> [XCanPs] --실제 CAN--> can0/로봇
13B = can_id(BE 4) + dlc(1) + data(8)
```
- 이더넷 HW는 XSA에 이미 켜져 있음(PCW_EN_ENET0). lwIP는 BSP에 lwip220.
- **단방향 주의:** 싸구려 100M 어댑터라 보드→PC 역방향이 죽음 → `make arp-static`(정적 ARP)로 우회. 우리 HIL은 명령 단방향이라 무관.
- **바이트오더:** XCanPs 데이터 레지스터는 **리틀엔디언** → D0를 워드 LSB에 패킹해야 candump 일치.

## 소스 (유지) vs 산출물 (삭제)
**소스 — 손으로 쓴 것, 유지:**
| 파일 | 역할 |
|---|---|
| `src/udp_can_main.c` | ★UDP→CAN 브리지 본체★ (lwIP raw UDP + CAN 송신, RX 조용히 드레인) |
| `src/can_main.c` | CAN 클럭/초기화 (04에서 계승) |
| `build_hil_app.py` | 전체 빌드(플랫폼+lwip220+앱) |
| `rebuild_app.py` | 앱만 재빌드 |
| `Makefile` | program/serial/can/eth/hil 타깃 |
| `tools/program_board.tcl` | JTAG 프로그래밍 |
| `tools/udp_can_test.py` | 송신/검증/레이턴시 |
| `zybo_can.xdc`, `configure_ps_can.tcl` | 제약/PS설정 |
| `README_HIL.md` | ★런북★ |  `zybo_can_v2_vivado/zybo_can_eth.xsa` | ★하드웨어 정의(XSA)★ |

**산출물 — 삭제 가능(~131M, 재생성):**
- `zybo_can_v2_vivado/{*.runs,*.gen,*.cache,*.hw,*.ip_user_files}` (~37M)
- `vitis_ws/.../{export,build,_ide,.Xil}` (~28M), `zybo_can_eth_vitis/.../{export,_ide}` (~12M)
- `hs_err_pid11873.log`(176K, JVM 크래시로그), `tools/__pycache__/`

## ⚠️ 빌드/이식 주의 (스켈레톤 작업 전 필독)
- **빌드 산출물 폴더엔 `/home/haeun/...` 절대경로가 31개 파일에 박혀있다** → 복사하면 깨짐(댕글링).
  → **소스 + XSA만 복사 → `build_hil_app.py`로 vitis_ws를 그 자리에 새로 생성** (경로가 로컬로 잡힘).
- **블록디자인이 built Vivado 프로젝트 안(`design_1.bd`)에만 있다** = 아직 `.tcl`로 export 안 됨.
  → PL을 바꾸려면 Vivado에서 `write_bd_tcl`로 1회 뽑아야 프로젝트 복사 없이 재생성 가능.
- ⚠️ Vitis 워크스페이스가 둘: `vitis_ws/`(스크립트 생성, 활성) vs `zybo_can_eth_vitis/`(GUI, 삭제 가능).

## 명령
```bash
make program     # 보드에 앱 올리기
make serial      # UART 콘솔
make hil-check   # PC→UDP→FPGA→CAN 바이트무결 검증
```
