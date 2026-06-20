# Zybo Z7-20 PS CAN 새 프로젝트 (v2)

> 목표: Zynq PS 내장 CAN0를 **EMIO**로 빼서 외장 트랜시버 통해 실제 CAN 버스 통신.
> v1에서 며칠 헤맨 **진짜 원인을 실제 XSA에서 확정**하고, 그걸 피해서 처음부터 제대로.

---

## v1 실패 원인 (기존 XSA `ps7_init`/`system.hwh`에서 확정)
| 발견 | 결과 |
|---|---|
| `PCW_EN_EMIO_CAN0 = 0` | CAN0 EMIO 비활성 → phy_tx/rx 포트가 제대로 안 생김 → NORMAL 진입 불가 |
| `PCW_CAN0_PERIPHERAL_CLKSRC = External` | CAN 클럭 소스가 External(잘못) → IO PLL이어야 함 |
| `APER_CLK_CTRL bit16 = 0` | ps7_init이 CAN **레지스터 클럭** 안 켬 → `CfgInitialize` 멈춤 |
| `CAN_CLK_CTRL = 0x00700F01` (÷105) | ref 클럭 ~9.5MHz → 비트레이트 10배 어긋남 |

**핵심: PS CAN 설정 자체가 잘못돼 있었음.** 트랜시버(망고 Cx, TX/RX 실크 반대)도 한몫했지만 그건 Due로 검증 끝(정상). 이제 PS 설정만 똑바로.

---

## 1. Vivado — PS CAN 설정 (★여기가 전부★)

### 1-1. 프로젝트 생성
- Create Project → 보드 **Zybo Z7-20** 선택 (보드파일 설치돼 있어야 함)
- Create Block Design → **ZYNQ7 Processing System** 추가
- **Run Block Automation** (보드 프리셋 적용 — DDR/MIO/클럭 자동)

### 1-2. CAN0 켜기 (PS7 더블클릭 → 설정)
**Peripheral I/O Pins** 또는 **MIO Configuration**:
- **CAN 0** 체크 → I/O 를 **EMIO** 로 선택  ← (MIO 아님! EMIO여야 PL핀으로 나감)

**Clock Configuration → IO Peripheral Clocks**:
- **CAN** 항목: 소스 = **IO PLL** (★External 아님★), 주파수 = **100 MHz**
  - 100MHz면 IO PLL(1000) ÷10 → 깔끔. (÷105 같은 이상한 값 나오면 주파수 다시)

### 1-3. EMIO 포트 빼기 (★phy_rx 빠뜨리지 말 것★)
- 블록디자인에서 PS7의 **`CAN_0`** 인터페이스 핀 우클릭 → **Make External**
  - **인터페이스 통째로** (개별 phy_tx/phy_rx 따로 말고) → tx/rx 방향 자동으로 맞음
- 외부 포트 `CAN_0_0` 생기고, 그 안에 `CAN_0_0_phy_tx`(출력) + `CAN_0_0_phy_rx`(입력) 둘 다 있어야 함
- **확인:** I/O Ports 탭에서 phy_rx **방향 = Input** 인지 꼭 봐

### 1-4. 마무리
- Create HDL Wrapper
- 제약파일 `zybo_can.xdc` 추가 (이 폴더에 있음 — 포트 이름이 다르면 맞춰 수정)
- **Generate Bitstream**
- **File → Export → Export Hardware → ★Include bitstream★** → XSA

### 1-5. 검증 (Vivado 단계에서)
- ps7_init.tcl 열어서 `0XF800012C`(APER) 라인 확인 → **bit16이 1**이어야 (CAN 레지스터 클럭 켜짐)
- `0XF8000128`(CAN_CLK_CTRL) → ÷105(0x00700F01) 아니어야. 100MHz면 보통 `0x00100A01`(÷10) 류

---

## 2. Vitis — 앱
- XSA로 Platform 새로 생성 → app `src/can_main.c` 넣고 빌드 → Run
- 앱이 시작 시 `CAN_CLK_CTRL`, APER 상태를 출력해서 클럭이 제대로인지 스스로 확인함
- 안전망: ps7_init이 또 클럭 안 켜도 앱이 SLCR로 직접 켜게 해둠

## 3. 배선 (트랜시버 — 망고 Cx는 실크 TX/RX 반대!)
```
FPGA phy_tx (V12/JE1)  →  트랜시버 실크 "RX"  (= 실제 TXD 입력)
FPGA phy_rx (W16/JE2)  ←  트랜시버 실크 "TX"  (= 실제 RXD 출력)
FPGA 3.3V/GND → 트랜시버 VCC/GND
트랜시버 CANH/CANL → 상대 노드, 양끝 120Ω, GND 공통
```

## 4. 테스트 상대 = Due (이미 검증됨)
- Due: `due_can_2node.ino` 를 `CAN_BPS_125K` 로 (또는 1M)
- 둘 다 같은 비트레이트
- **성공:** FPGA 시리얼 `[NORMAL] 진입성공` + 서로 RX 프레임 출력

---

## 파일
- `README.md` — 이 문서
- `zybo_can.xdc` — CAN EMIO 핀 제약 (JE1=V12 tx, JE2=W16 rx)
- `configure_ps_can.tcl` — PS7 CAN0 설정 Tcl (GUI 대신 붙여넣기용, 선택)
- `src/can_main.c` — bare-metal 앱 (클럭 자가진단 + NORMAL 송수신)

## 비트레이트 메모 (can_clk=100MHz 기준)
| 속도 | BRPR | TS1 | TS2 | SJW |
|---|---|---|---|---|
| 1 Mbps | 9 | 6 | 1 | 1 |
| 125 kbps | 79 | 6 | 1 | 1 |
( bit_rate = 100MHz / ((BRPR+1) × (1+(TS1+1)+(TS2+1))) )
