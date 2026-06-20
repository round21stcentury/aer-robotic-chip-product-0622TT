# HIL 브리지 FPGA측 — UDP(이더넷) → CAN 빌드/검증 런북

> Phase 1 HIL 루프의 **FPGA 절반**: PC 시뮬이 보낸 13바이트 UDP 패킷을 받아 실제 CAN으로 송출.
> 반환 경로는 (b) 실제 CAN+USB-CAN 확정 → 이 보드는 CAN→UDP 안 함. (계약서 `doc/CAN-이더넷_브리지_계약서.md`)
> 앱 소스: `src/udp_can_main.c` / 검증도구: `tools/udp_can_test.py` + `make hil-*`

---

## 0. 전제 (이미 확인됨)
- ✅ **이더넷 HW는 XSA에 켜져 있음** (`PCW_EN_ENET0=1`, MDIO=MIO52-53). → **Vivado 리빌드 불필요.** `make xsa-verify` ④로 재확인 가능.
- ✅ CAN0 EMIO/클럭 안전망은 CAN 브링업(2026-06-11)에서 검증된 그대로 재사용.
- 트랜시버 배선·종단저항(120Ω 양끝)·GND 공통은 CAN 브링업과 동일 (README.md §3).

---

## 1. Vitis — lwIP 앱 만들기 (★lwip를 BSP에 끌어오는 게 핵심★)

lwIP의 타이머/`xemac_add` 스캐폴딩을 손으로 짜지 않는다. **lwIP 템플릿에서 시작**해서 lwip211 라이브러리가 BSP에 자동으로 붙게 한 뒤, main.c만 우리 것으로 교체한다.

1. **새 Application Component 생성** — 플랫폼 = 기존 `zybo_can_v2_platform` 그대로.
   - 템플릿 = **"lwIP UDP Perf Server"** (UDP 이미 켜짐) 또는 **"lwIP Echo Server"** 중 택1.
   - 이걸 고르면 Vitis가 BSP 도메인에 **lwip211 + emacps 드라이버**를 자동 추가하고, `platform.c`/`platform_config.h`(=`PLATFORM_EMAC_BASEADDR`)/`lwipopts.h`를 생성한다.
2. **main.c 교체** — 템플릿이 만든 `main.c`(echo/perf 로직)를 지우고 우리 **`src/udp_can_main.c` 내용으로 통째 교체.**
   - `platform.c`, `platform_config.h`, `lwipopts.h` 는 **그대로 둔다** (우리 main이 이걸 씀).
3. **BSP 설정 확인** (Echo Server 템플릿을 골랐다면):
   - lwip211 라이브러리 설정에서 **`lwip_udp = true`** 인지 확인 (UDP Perf 템플릿이면 이미 true).
   - `xcanps` 드라이버는 같은 플랫폼이라 이미 있음(CAN 앱이 씀).
4. **Build.**
   - 컴파일 에러로 `platform.h`/`PLATFORM_EMAC_BASEADDR`/`xemac_add` 못 찾으면 → 1번 템플릿에서 시작 안 한 것. 다시.
5. **Run** (JTAG) — Vitis가 비트스트림+elf 프로그래밍. 시리얼(`make serial`)에 아래가 떠야:
   ```
   === Zybo HIL 브리지: UDP5000 → CAN0(1000kbps) ===
   [clk after ] CAN_CLK=0x00100a01 ... (CANbit16=1)
   [CAN] 1000kbps BRPR=9 mode=... → NORMAL 진입성공
   [NET] board=192.168.1.10 gw=192.168.1.100
   [UDP] 5000 포트 바인드 — sim에서 13B 패킷 보내면 CAN으로 송출
   ```

> 정적 IP(192.168.1.10)는 `udp_can_main.c`에 박혀 있음. 바꾸려면 거기 `BOARD_IP_*`/계약서 §1 동시 수정.

---

## 2. PC 쪽 준비

1. **보드와 직결된 이더넷 IF에 정적 IP** (계약서 §1: PC=192.168.1.100):
   ```bash
   sudo ip addr add 192.168.1.100/24 dev <eth_iface>   # 예: enp3s0
   sudo ip link set <eth_iface> up
   ```
2. **USB-CAN(can0) 1Mbps up** — 보드와 같은 물리 CAN 버스에 연결 (ACK 줄 2번째 노드 역할도 겸함):
   ```bash
   make can-up BITRATE=1000000
   ```
3. 종단저항 120Ω 양끝(USB-CAN쪽 + 보드 트랜시버쪽), GND 공통.

---

## 3. ★검증 체인★ (CAN 브링업의 xsa-verify→can-up→send/dump 의 HIL 버전)

순서대로. 각 단계가 PASS여야 다음으로.

| 단계 | 명령 | PASS 기준 |
|---|---|---|
| ⓪ XSA 재확인 | `make xsa-verify` | ④에 ENET0=1, MDIO=1 |
| ① 이더넷 도달 | `make eth-ping` | 3/3 응답 |
| ② **UDP→CAN 바이트 무결** | `make hil-verify` | `✅ PASS` (id/dlc/data 일치) |
| ③ Piper 프레임들 | `make hil-send HIL_ID=0x155 HIL_DATA=...` + `make dump` | candump에 그대로 |
| ④ 레이턴시 | `make hil-latency` | min/median/max 출력 |

또는 한 방에:
```bash
make can-up BITRATE=1000000     # (PC쪽 CAN 먼저)
make hil-check                  # ping → verify 순차
make hil-latency                # 통과하면 레이턴시
```

`hil-verify`가 하는 일: PC에서 `192.168.1.10:5000`으로 13바이트(0x151, `00 01 32...`) UDP 전송 → `candump can0`에서 같은 ID/DLC/데이터 프레임이 나오는지 비교 → PASS/FAIL. **이게 "데이터가 경로 끝까지 일관" + "FPGA 실제 CAN TX 하드웨어 동작"을 한 번에 증명.**

---

## 4. 트러블슈팅

| 증상 | 1순위 의심 |
|---|---|
| `eth-ping` 실패 | PC 정적IP/서브넷, 케이블, 보드 부팅. 보드 시리얼에 `[NET]` 떴나. GEM0_CLK_CTRL(시리얼 `[clk enet]`)이 0이면 ps7_init ENET 클럭 버그 → Vivado에서 ENET 클럭 재확인 |
| ping OK, `hil-verify` 타임아웃 | 보드 시리얼 `[stat] canTX` 증가하나? 안 늘면 UDP는 오는데 CAN송신 실패 → NORMAL 진입/비트레이트(can0도 1M?)/트랜시버 TX-RX 실크반대 |
| canTX 늘지만 candump 안 뜸 | can0 비트레이트≠1M, 종단저항/ACK 노드 없음(BUS-OFF), 물리버스 분리 |
| 데이터는 오는데 ID 뒤집힘 | 엔디언 — 계약서 §2 `can_id` 빅엔디언. 도구/보드 양쪽 점검 |
| 레이턴시 편도 >1ms | gs_usb USB 지연 포함이라 가능 — 결함 아님, 측정값으로 기록 |

---

## 5. 다음 (팀원 합류 후)
- 위 ②까지 = transport+HW 무결성. 그 다음 팀원의 **vcan0→브리지** 와 **가상로봇** 붙여 Gazebo 루프 닫기. (계약서 §7.1/§7.3, `doc/00_핸드오프_README.md`)
