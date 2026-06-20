# CTU CAN FD 통합 가이드 — Zybo Z7-20

> **목표**: 오픈소스 CAN 컨트롤러 **CTU CAN FD**를 PL에 올리고, PS가 AXI로 제어해 외장 트랜시버로 1Mbps CAN 프레임을 송수신 → `candump`로 검증.
> **선행**: PS 브링업 완료([01_zynq_ps_bringup.md](01_zynq_ps_bringup.md)).
> **독자 가정**: Verilog 알지만 Zynq/Vivado 입문. CTU CAN FD는 VHDL이지만 **블랙박스 IP로 쓰므로 VHDL 안 봐도 됨.**

---

## 0. 통합 구조 (개념)

CTU CAN FD는 **APB 슬레이브**로 패키징돼 있습니다. Zynq PS는 **AXI** 마스터라, 둘 사이에 **AXI→APB 브리지**(Vivado 기본 IP)를 끼웁니다.

```
[PS M_AXI_GP0] → [AXI Interconnect] → [AXI APB Bridge] → [CTU CAN FD (APB)]
                                                              │ can_tx / can_rx
   [FCLK_CLK0 100MHz] ─────────────────────────────────────▶ │ (코어 클럭)
   [IRQ] ◀───────────────────────────────────────────────── │ (선택)
                                                              ▼
                                                   (PL 핀/PMOD) → CAN 트랜시버 → CAN 버스
```
- PS가 AXI로 코어 레지스터를 읽고/써서 **비트타이밍 설정 + 프레임 송수신**
- CAN 비트레이트(1Mbps)는 **코어 클럭(100MHz)에서 프리스케일러 레지스터로** 만듦
- `can_tx/can_rx`는 디지털 신호 → 외장 **CAN 트랜시버**(SN65HVD230)가 물리 CAN_H/L로 변환

> **소스 (단일 진실)**: 업스트림 GitLab `canbus/ctucanfd_ip_core`, GitHub 미러 `Logic-Design-Services/CTU-CAN-FD`.
> 레지스터 맵·비트타이밍·송신 절차는 **레포의 datasheet(PDF)와 `driver/` 레지스터 정의**가 권위. 본 가이드는 통합 흐름, 정확한 레지스터 값은 거기서 확인.

---

## 1. IP 받아서 Vivado 카탈로그에 등록

1. 레포 클론 (깨끗한 터미널에서):
   ```bash
   git clone https://github.com/Logic-Design-Services/CTU-CAN-FD.git
   # 또는 업스트림: git clone https://gitlab.fel.cvut.cz/canbus/ctucanfd_ip_core.git
   ```
2. 패키징된 컴포넌트 위치 확인: `src/component.xml` 이 있는 폴더 (Vivado IP 정의)
3. Vivado → 프로젝트 → **Settings → IP → Repository** → **`+`** → 위 레포(또는 `src/`) 경로 추가
4. **IP Catalog** 에 **CTU CAN FD** 가 뜨면 성공
   - 안 뜨면: 레포의 `synthesis/Vivado/` 안 패키징 스크립트(tcl)로 IP를 먼저 패키징해야 할 수 있음 → README 확인

---

## 2. 블록 디자인에 연결

> ⚠️ **IP 이름 주의**: 카탈로그에서 우리가 쓸 건 **`CTU_CAN_FD`** (오픈코어). `canfd_0`/"CAN FD"는 **Xilinx 유료 LogiCORE**라 다른 것 — 그건 삭제. (CTU 레포를 IP Repository에 등록해야 `CTU_CAN_FD`가 보임)

CTU 코어는 **APB 슬레이브(`s_apb`)** 라서 **AXI APB Bridge** 가 필요하다. 그리고 PS의 M_AXI_GP0(full AXI4)와 브리지(AXI4-Lite)는 **직접 못 잇고** 사이에 **인터커넥트**가 필요하다.

### 2-1. M_AXI_GP0 먼저 켜기 (안 켜면 Connection Automation 배너 안 뜸)
- PS 더블클릭 → **PS-PL Configuration → AXI Non Secure Enablement → GP Master AXI Interface → `M AXI GP0` 체크**
- PS 블록에 `M_AXI_GP0` 포트가 생기는지 확인

### 2-2. 연결 체인
```
PS M_AXI_GP0 ──▶ [AXI SmartConnect] ──▶ AXI APB Bridge(AXI4_LITE) ──▶ (APB_M) ──▶ CTU_CAN_FD(s_apb)
   (AXI4)          (변환, 필수)           (AXI4-Lite)                  (수동연결)
```
- 초록 배너 뜨면 **Run Connection Automation** 으로 AXI 쪽 자동. 안 뜨면 **AXI SmartConnect** 수동 추가:
  - PS `M_AXI_GP0` → SmartConnect `S00_AXI`
  - SmartConnect `M00_AXI` → 브리지 `AXI4_LITE`
  - SmartConnect `aclk`→FCLK_CLK0, `aresetn`→`peripheral_aresetn`
- **브리지 `APB_M` → CTU `s_apb`** 는 **항상 수동** (오토 안 됨)

### 2-3. CTU_CAN_FD 포트 연결표 (실측)
| 포트 | 방향 | 연결 |
|---|---|---|
| `s_apb` | in | 브리지 `APB_M` (수동) |
| `aclk` | in | **FCLK_CLK0 (50MHz)** — 브리지와 동일 클럭 |
| `arstn` | in | proc_sys_reset `peripheral_aresetn` (active-**low**) |
| `scan_enable` | in | **Constant 1-bit = 0** ⚠️ (DFT용, FPGA선 미사용) |
| `CAN_rx` | in | **Make External** → 트랜시버 RXD |
| `timestamp[63:0]` | in | **Constant 64-bit = 0** ⚠️ (지금은 0, 나중에 카운터) |
| `CAN_tx` | out | **Make External** → 트랜시버 TXD |
| `irq` | out | (선택) PS `IRQ_F2P` / 비워둠 |
| `res_n_out` | out | 비워둠 |
> `scan_enable`·`timestamp`는 안 묶으면 Validate 에러. **Add IP → `Constant`(xlconstant)** 로 0 고정.

### 2-4. 주소 할당 (Address Editor) — 빼먹기 쉬움
- 블록디자인 위 **`Address Editor` 탭** → 우클릭 → **Assign All**
- CTU 코어에 PS 주소공간 번지 배정(예: 0x4000_0000~). 이 주소가 XSA→Vitis `xparameters.h`의 `XPAR_..._BASEADDR`로 들어감. **안 하면 소프트웨어가 코어 접근 불가.**

### 2-5. 마무리
- can_tx/can_rx **Make External** 확인 → **Validate Design (F6)** → 오류 없으면 다음(§3 핀/§4 빌드)

---

## 3. 핀 제약 (XDC) + 트랜시버 배선

1. `can_tx`, `can_rx` 를 **Pmod 핀**에 할당 (XDC 제약 파일):
   ```tcl
   # 예시 — 실제 Pmod 핀 번호는 Zybo 마스터 XDC 참고
   set_property -dict {PACKAGE_PIN <핀> IOSTANDARD LVCMOS33} [get_ports can_tx]
   set_property -dict {PACKAGE_PIN <핀> IOSTANDARD LVCMOS33} [get_ports can_rx]
   ```
   - Zybo Z7-20 마스터 XDC를 Digilent에서 받아 Pmod 핀 매핑 확인
2. **외장 CAN 트랜시버**(SN65HVD230) 배선:
   - 보드 `can_tx` → 트랜시버 TXD(D), `can_rx` ← 트랜시버 RXD(R)
   - 트랜시버 3.3V/GND, CAN_H/CAN_L → CAN 버스
   - **120Ω 종단저항** 버스 양 끝에 (트랜시버 모듈에 있으면 OK)

---

## 4. 빌드 → 소프트웨어 → 송신

### 4-1. Vivado: 비트스트림 + XSA
1. **Generate Bitstream** (합성·구현·비트스트림, 수 분)
2. **File → Export → Export Hardware → Include Bitstream** → 새 `.xsa` 저장

### 4-2. Vitis: 플랫폼 갱신
- 하드웨어가 바뀌었으니 **플랫폼의 XSA를 새 것으로 교체**:
  - 플랫폼 컴포넌트 → `vitis-comp.json`/Settings에서 XSA 경로를 새 XSA로 업데이트, 또는 플랫폼 새로 생성
  - **플랫폼 Build** (BSP 재생성) → 그래야 `xparameters.h`에 CAN 코어 주소가 들어감

### 4-3. 레지스터 맵 (CTU CAN FD, Linux 드라이버 기준 — 확인됨)
| 오프셋 | 레지스터 | 비고 |
|---|---|---|
| 0x00 | DEVICE_ID | [15:0]=**0xCAFD**(매직), [31:16]=VERSION |
| 0x04 | MODE/SETTINGS | [15:0]=MODE(RST 등), [31:16]=SETTINGS(**ENA** 등) |
| 0x08 | STATUS | 코어 상태 |
| 0x0C | COMMAND | |
| 0x24 | **BTR** | 비트타이밍: PROP[6:0] PH1[12:7] PH2[18:13] BRP[26:19] SJW[31:27] |
| 0x74 | TX_COMMAND | 버퍼 set-ready/abort |
| 0x78 | TX_PRIORITY | 버퍼 우선순위 |
| 0x100 | TXTB1 데이터 | TX 버퍼1 시작(0x200/0x300/0x400=버퍼2~4) |
**확정값 (Linux 커널 드라이버 소스 기준):**
- MODE(0x04): **RST=bit0, ILBP(내부루프백)=bit21, ENA(활성화)=bit22**, BMM(listen-only)=bit1, FDE=bit4
- BTR: **값을 그대로 씀(−1 인코딩 아님)**
- STATUS(0x08): **RXNE=bit0, TXNF=bit2**, IDLE=bit7
- TX_COMMAND(0x74): TXCR(set-ready)=bit1, 버퍼선택=bit(8+buf) → 버퍼1 ready = **0x102**
- TX버퍼1: 0x100=FRAME_FORMAT(DLC[3:0],IDE=bit6,FDF=bit7), 0x104=IDENTIFIER(표준ID=bit18~28), 0x108/0x10C=timestamp, **0x110~=DATA**
- → 완성 동작 코드: [can_loopback_test.c](can_loopback_test.c) (내부 루프백, 트랜시버 불필요)

### 4-4. 비트타이밍 계산 (50MHz, 1Mbps)
- bit time 1µs = **50클럭**(20ns×50). BRP=1이면 1 TQ=20ns → **50 TQ/bit**
- 샘플포인트 ~80% 예: **SYNC=1, PROP=19, PH1=20, PH2=10, BRP=1, SJW=4** (합 1+19+20+10=50 TQ ✓)
- BTR 조립: `BTR = (SJW<<27)|(BRP<<19)|(PH2<<13)|(PH1<<7)|PROP`
> ⚠️ 필드가 duration-1 인코딩이면 각 값에서 1 빼서 넣어야 함 — datasheet 확인. 헷갈리면 datasheet의 1Mbps 예시값을 그대로 사용.

### 4-5. 소프트웨어 시퀀스 + C 스켈레톤
순서: **DEVICE_ID 확인 → disable → 비트타이밍 → enable → TX 버퍼 쓰기 → 송신 트리거 → 상태 폴링**
```c
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

#define CAN_BASE   XPAR_CTU_CAN_FD_0_BASEADDR  // 실제 이름은 xparameters.h 확인
#define R_DEVICE_ID  0x00
#define R_MODE       0x04   // [15:0]MODE [31:16]SETTINGS(ENA)
#define R_STATUS     0x08
#define R_BTR        0x24
#define R_TX_COMMAND 0x74
#define R_TXTB1      0x100

static inline u32  rd(u32 o){ return Xil_In32(CAN_BASE+o); }
static inline void wr(u32 o,u32 v){ Xil_Out32(CAN_BASE+o,v); }

int main(void){
    // M2: 코어 살아있나 (트랜시버 불필요)
    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID=0x%04x (기대 0xCAFD)\n\r", id);
    if(id != 0xCAFD){ xil_printf("코어 미인식 — AXI/주소 확인\n\r"); return -1; }

    // 1) disable (ENA=0) — 비트타이밍 바꾸려면 disable 상태
    //    SETTINGS_ENA 비트 위치는 datasheet
    // wr(R_MODE, rd(R_MODE) & ~SETTINGS_ENA);

    // 2) 비트타이밍 (50MHz/1Mbps, §4-4)
    // wr(R_BTR, (4<<27)|(1<<19)|(10<<13)|(20<<7)|19);  // duration 인코딩 가정

    // 3) enable (ENA=1)
    // wr(R_MODE, rd(R_MODE) | SETTINGS_ENA);

    // 4) TX 버퍼1에 프레임 쓰기 (포맷은 datasheet)
    //    [0x100]FRAME_FORMAT(DLC,IDE,FDF...) [0x104]IDENTIFIER [...]DATA
    // wr(R_TXTB1+0x0, frame_format);
    // wr(R_TXTB1+0x4, identifier);
    // wr(R_TXTB1+0x8, data_word0); ...

    // 5) 송신: TX_COMMAND에 버퍼1 set-ready
    // wr(R_TX_COMMAND, TXB1_SET_READY);

    // 6) 상태 폴링
    // xil_printf("STATUS=0x%08x\n\r", rd(R_STATUS));
    return 0;
}
```

### 4-6. 단계별 검증
- **M2 (트랜시버 불필요)**: DEVICE_ID=0xCAFD 출력 → **AXI→APB→주소→SW 경로 전부 OK** ★ 첫 목표
- **내부 루프백(self-test)**: MODE의 STM(self-test) 비트 켜면 버스 없이 TX→RX 자기 확인 (datasheet)
- **M3 (트랜시버+candump)**: 실제 프레임 송신 → PC `candump`에 뜸 (§5)

---

## 5. ✅ 검증 — candump (golden reference)

PC에 USB-CAN 연결(깨끗한 터미널):
```bash
sudo ip link set can0 up type can bitrate 1000000
candump can0                       # 보드가 보낸 프레임 관측
cansend can0 123#1122334455667788  # 보드로 프레임 전송 (RX 검증)
```
- **TX 검증**: 보드가 송신 → `candump`에 **똑같은 ID·데이터** 뜨면 OK
- **RX 검증**: PC `cansend` → 보드가 받은 값 `xil_printf`로 출력해 확인
- (FPGA 내부 신호는 **Vivado ILA**로 `can_tx` 비트스트림·FSM 관측 가능)

> 보드 `can_tx`/`can_rx`와 PC USB-CAN이 **같은 물리 CAN 버스**에 있어야 함 (CAN_H↔CAN_H, CAN_L↔CAN_L, 종단 120Ω).

---

## 6. 단계별 마일스톤 (한 번에 다 하려 하지 말 것)
| # | 목표 | 검증 |
|---|---|---|
| M1 | IP 카탈로그 등록 + 블록디자인 Validate 통과 | F6 오류 없음 |
| M2 | 빌드/XSA/플랫폼 + 코어 레지스터 read | 버전 레지스터 등 읽혀짐 |
| M3 | 비트타이밍 설정 + **1프레임 송신** | `candump`에 프레임 뜸 ★ |
| M4 | **수신** | PC `cansend` → 보드가 디코드 출력 |
| M5 | PS 루프백: TX→(버스)→RX 자기 확인 | 보낸 = 받은 |

**M3(첫 송신이 candump에 뜨는 것)** 이 진짜 분기점. 여기까지 가면 CAN 하드웨어 경로가 살아있는 것.

---

## 7. 자주 막히는 지점 (예상)
| 증상 | 조치 |
|---|---|
| IP 카탈로그에 CTU CAN FD 안 뜸 | Repository 경로 재확인, 레포 패키징 tcl 실행 필요할 수 있음 |
| 검색하면 `canfd_0`("CAN FD")만 나옴 | 그건 **Xilinx 유료 LogiCORE**. CTU 레포 등록해야 `CTU_CAN_FD`가 뜸. canfd_0은 삭제 |
| **Connection Automation 초록 배너 안 뜸** | **M_AXI_GP0 미enable**(PS-PL Config에서 켜기) → 마스터 없어서 자동화 대상 없음 |
| **AXI4_LITE를 PS에 수동 드래그가 안 됨** | PS는 full AXI4, 브리지는 AXI4-Lite → **직접 연결 불가**. 사이에 **AXI SmartConnect/Interconnect** 필수 |
| APB↔AXI 연결 안 됨 | Connection Automation은 AXI까지만 — **APB_M → s_apb는 수동** |
| Validate 에러 (scan_enable/timestamp) | 미연결 입력. **Constant(xlconstant) 0** 으로 묶기 |
| 소프트웨어에서 코어 주소 모름 | **Address Editor → Assign All** 빼먹음 |
| candump에 아무것도 안 뜸 | ① 비트레이트(양쪽 1Mbps) ② 트랜시버 전원/배선 ③ 종단 120Ω ④ can_tx/rx 핀 할당 ⑤ 코어 enable·비트타이밍 |
| 프레임 깨짐/에러 | 비트타이밍 세그먼트 설정, 트랜시버 RXD/TXD 방향 |
| `Make External` 후 포트 이름 안 맞음 | XDC의 포트명과 블록도 외부포트명 일치 확인 |

---

## 8. 메모
- 이 코어는 **FPGA·ASIC 양쪽 합성 가능**(원래 CTU 학술 프로젝트). 우리 ASIC 대상은 reflex_core지만, CAN도 오픈 RTL이라 참고 가치 있음.
- 반사 개입(§CAN 계약서 §5)은 이 코어의 TX 버퍼에 **reflex_core가 프레임을 주입**하는 식으로 나중에 설계. 지금은 PS가 정상 송신하는 것부터.
- 정확한 레지스터/비트타이밍은 항상 **레포 datasheet** 기준.
