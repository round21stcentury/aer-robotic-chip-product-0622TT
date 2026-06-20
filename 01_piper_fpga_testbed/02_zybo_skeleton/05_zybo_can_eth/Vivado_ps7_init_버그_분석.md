# Vivado 2025.2 ps7_init 생성 버그 — 전말 분석

> **한 줄 요약:** PS7의 CAN 클럭 설정이 디자인 파일 3곳(BD·XCI·hwh)에는 전부 올바르게
> 반영됐지만, 정작 **부팅 초기화 코드(ps7_init)에만 공장 디폴트 분주값(÷105)이 생성되는**
> Vivado 2025.2의 버그를 확인했다. 설정도 Tcl도 문제를 못 고쳤고, 최종적으로는
> **앱(C 코드)이 부팅 직후 SLCR 레지스터를 직접 덮어쓰는 방식**으로 해결했다.
> 발견일: 2026-06-11, 환경: Vivado v2025.2 (lin64), Zybo Z7-20 보드 프리셋.

---

## 1. 배경: PS7 설정은 어떤 경로로 하드웨어에 도달하는가

이 버그를 이해하려면 먼저 "GUI에서 체크박스를 누르면 무슨 일이 생기는지"를 알아야 한다.

```
GUI/Tcl 설정
   ↓ (PCW_* 파라미터로 저장)
블록디자인(.bd) ──→ PS7 IP 인스턴스(.xci)
   ↓ generate_target                       ↓
   ├── 비트스트림(.bit)     ← PL 배선: EMIO 라우팅, 핀 위치     [하드웨어 그 자체]
   ├── hwh                  ← 하드웨어 "설명서" (Vitis가 읽음)   [메타데이터]
   └── ps7_init.tcl / .c    ← 부팅 시 레지스터 초기화 스크립트   [소프트웨어!]
   ↓ Export Hardware
  XSA (위 셋을 zip으로 묶은 것) → Vitis 플랫폼 → FSBL이 부팅 때 ps7_init 실행
```

핵심 통찰: **ps7_init은 하드웨어가 아니다.** 부팅 때 한 번 실행되는 "레지스터에 값 쓰기 스크립트"일 뿐이다. 클럭 분주비 같은 PS 설정은 비트스트림에 박히는 게 아니라 이 스크립트가 SLCR(System Level Control Register)에 써 넣는다. — 이 사실이 나중에 탈출구가 된다.

### 문제의 레지스터 2개

| 주소 | 이름 | 역할 | 목표값 |
|---|---|---|---|
| 0xF800012C | APER_CLK_CTRL | 주변장치 **레지스터 버스** 클럭 게이트. CAN0=bit16. 꺼져 있으면 CAN 레지스터 접근 자체가 멈춤(`CfgInitialize` 행) | bit16=1 |
| 0xF8000128 | CAN_CLK_CTRL | CAN 기준클럭 생성: 소스(bits5:4, 00=IO PLL) ÷DIV0(bits13:8) ÷DIV1(bits25:20), CLKACT0(bit0) | 100MHz가 되는 아무 조합 |

---

## 2. 문제 1 — v1의 설정 실수 (사용자 영역, Tcl/GUI로 해결됨)

v1 XSA를 해부해서 찾은 잘못된 설정들. 이건 버그가 아니라 **설정 누락**이고, v2에서 GUI/Tcl로 정상 해결됐다:

| 항목 | v1 (잘못) | v2 조치 | 결과 |
|---|---|---|---|
| `PCW_EN_EMIO_CAN0` | 0 (EMIO 비활성) | CAN0 체크 + I/O=EMIO | ✅ hwh=1, 비트스트림에 라우팅 반영, 핀 V12/W16 배치 확인 |
| APER bit16 | 0 (레지스터 클럭 꺼짐) | CAN0 enable에 연동돼 자동 해결 | ✅ ps7_init이 `0xF800012C ← 0x01ED044D` (bit16=1) 정상 생성 |
| CAN 클럭 소스/주파수 | External / 미설정 | Clock Config: IO PLL, 100MHz | ⚠️ **파라미터는 반영, ps7_init은 미반영 → 문제 2** |

### 이때 사용한 Tcl (적용된 것들)

```tcl
# PS7 CAN0 활성 + EMIO + 클럭 설정
set_property -dict [list \
  CONFIG.PCW_CAN0_PERIPHERAL_ENABLE   {1} \
  CONFIG.PCW_CAN0_CAN0_IO             {EMIO} \
  CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC   {IO PLL} \
  CONFIG.PCW_CAN0_PERIPHERAL_FREQMHZ  {100} \
] [get_bd_cells processing_system7_0]

# 빈 PS7 블록디자인의 단골 에러(M_AXI_GP0_ACLK 미연결) 해결
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
```

`get_property`로 재확인하면 전부 설정대로 나온다. 여기까지는 정상.

---

## 3. 문제 2 — Vivado 2025.2의 ps7_init 생성 버그 (툴 영역, 못 고침)

### 3-1. 증상: 같은 시각에 생성된 파일끼리 모순

`generate_target` 직후 디스크의 생성물을 비교하면 (둘 다 동일 타임스탬프):

| 파일 | CAN 클럭 내용 | 판정 |
|---|---|---|
| **hwh / XCI / BD** | `PCW_CAN_PERIPHERAL_CLKSRC="IO PLL"`, `DIVISOR0=5, DIVISOR1=2`, `PCW_ACT_CAN_PERIPHERAL_FREQMHZ=100.000000` | ✅ 1000÷(5×2)=100MHz, 완벽 |
| **ps7_init.tcl** | `mask_write 0XF8000128 0x03F03F01 0x00700F01` | ❌ 디코드: SRCSEL=IO PLL, **DIV0=15, DIV1=7 → ÷105 → 9.524MHz** |
| hwh의 개별 실효값 | `PCW_ACT_CAN0_PERIPHERAL_FREQMHZ=23.8095` | ❌ 100이어야 하는데 수수께끼의 23.8095 |

즉 **설계 데이터는 전부 100MHz인데, 부팅 코드만 9.524MHz를 쓴다.**

### 3-2. 결정적 단서: 23.8095의 정체

23.8095 MHz = **2500 ÷ 105**. ÷105는 CAN_CLK_CTRL의 공장 디폴트 분주(15×7)이고, 2500MHz는 PS7 내부 모델의 IO PLL 기본 가정값이다. 즉 `ACT_CAN0`(개별 컨트롤러 실효 주파수)는 **한 번도 재계산되지 않은 공장 디폴트 그대로**다. 공용 CAN 클럭(`ACT_CAN`)은 100.000000으로 제대로 재계산됐는데, **개별(CAN0) 계산 엔진만 디폴트에서 멈춰 있고**, ps7_init의 CAN_CLK_CTRL 값은 그 멈춘 엔진을 따라간다 — 이게 버그의 메커니즘으로 추정된다.

### 3-3. 시도했지만 실패한 것들 (전부 Tcl)

| 시도 | 명령 | 결과 |
|---|---|---|
| 개별 CLKSRC/FREQ 직접 설정 | `set_property CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC {IO PLL}` + `FREQMHZ {100}` | 파라미터는 바뀜(`get_property` 확인). **ps7_init 불변** |
| 강제 재생성 | `reset_target all` + `generate_target all [get_files design_1.bd]` | 파일은 재생성됨(타임스탬프 갱신). **내용 불변** |
| IP 캐시 배제 | `config_ip_cache -disable_cache` 후 재생성 | **불변** (캐시 문제 아님 확정) |
| 허용값 조회 | `list_property_value CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC ...` | **빈 출력** — enum 목록 자체가 없는 내부 파라미터. 단서 끊김 |

여기서 시간 손절. 근거: 어차피 탈출구가 있다(§4).

### 3-4. 보너스 발견: v1 근본원인 중 하나는 허상이었다

ps7_init **전체**에 `CAN_MIOCLK_CTRL(0xF8000130)` 쓰기가 한 줄도 없다. 이 레지스터의 리셋값은 0 = "내부 생성 클럭(CAN_REF) 사용"이다. 따라서 v1 때 지목했던 `PCW_CAN0_PERIPHERAL_CLKSRC=External`은 **레지스터에 반영조차 안 되는 장식용 파라미터**였고, 하드웨어는 처음부터 늘 내부 클럭을 쓰고 있었다. v1의 진짜 킬러는 ① APER 꺼짐(접근 불가)과 ② 내부 클럭이 9.524MHz였던 것, 둘뿐이다. — "GUI 파라미터 이름만 보고 추론하지 말고 레지스터 쓰기를 직접 확인하라"는 교훈.

---

## 4. 그런데 왜 결국 잘 됐는가 — 책임 분담표

최종 동작의 비밀은 **잘못된 부분이 하필 '소프트웨어로 덮어쓸 수 있는 영역'에만 있었다**는 것이다:

| 구성 요소 | 만든 주체 | 상태 | C로 대체 가능? |
|---|---|---|---|
| EMIO 라우팅 (CAN0 tx/rx → PL 패브릭 → V12/W16 핀) | **비트스트림** | ✅ Vivado가 정상 생성 | ❌ 불가능 (하드웨어 배선) — 이게 틀렸으면 답 없었음 |
| APER bit16 (레지스터 클럭) | ps7_init | ✅ 정상 생성 | ✅ 가능 (안전망이 어차피 중복으로 켬) |
| CAN_CLK_CTRL 분주 (÷105→÷10) | ps7_init | ❌ **버그로 디폴트 생성** | ✅ **가능 — 여기서 C가 해결** |
| XCanPs 비트타이밍 (BRPR/TS1/TS2) | 원래부터 앱 책임 | — | (해당 없음) |

원리: SLCR은 그냥 메모리 맵 레지스터다. ps7_init(FSBL이 부팅 때 실행)이 잘못된 값을 쓰더라도, **그 뒤에 실행되는 앱이 같은 주소에 올바른 값을 쓰면 마지막 값이 이긴다.** 하드웨어는 레지스터의 "현재 값"만 따른다.

```
부팅 타임라인:
FSBL: ps7_init 실행 → CAN_CLK_CTRL=0x00700F01 (9.524MHz, 잘못)   ← 버그 구간
  ↓
앱(can_main.c) 시작:
  [before] 출력  → 0x00700F01 확인 (버그의 물증 확보)
  SLCR 직접 쓰기 → 0x00100A01 (100MHz, 올바름)                    ← 교정
  [after] 출력   → 0x00100A01 확인 (교정 증명)
  ↓
XCanPs 초기화/비트타이밍/NORMAL → 이 시점엔 클럭이 이미 100MHz    ← 정상 동작
```

---

## 5. C 코드(안전망)가 정확히 한 일

`src/can_main.c`의 해당 부분 (XCanPs_CfgInitialize **이전**에 실행되는 것이 핵심):

```c
/* ① 진단: 부팅 직후 레지스터 원본 출력 — 버그가 재현되는지 매 부팅마다 확인 */
xil_printf("[before] CAN_CLK_CTRL=0x%08x APER=0x%08x (APER bit16=%d)\n\r",
           Xil_In32(0xF8000128), Xil_In32(0xF800012C), (Xil_In32(0xF800012C)>>16)&1);

/* ② SLCR 잠금 해제 — 시스템 레지스터는 쓰기 보호되어 있다 */
Xil_Out32(0xF8000008, 0x0000DF0D);

/* ③ APER bit16 강제 ON — 지금은 ps7_init이 켜주지만, 방어적으로 중복 수행.
      (이게 꺼져 있으면 ④는커녕 CAN 레지스터 읽기에서 시스템이 멈춘다 → 순서 중요) */
Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));

/* ④ CAN_REF 클럭 교정: 0x00100A01 = SRCSEL:IO PLL, DIV0=10, DIV1=1, CLKACT0=1
      → 1000MHz ÷ 10 = 100MHz  (Vivado 계산식 ÷5×÷2와 다르지만 결과 동일 — 아무거나 OK) */
Xil_Out32(0xF8000128, 0x00100A01);

/* ⑤ 증명: 교정 후 값 출력 */
xil_printf("[after ] CAN_CLK_CTRL=0x%08x ...\n\r", Xil_In32(0xF8000128));
```

설계 의도 정리:

- **①⑤(진단 출력)이 절반의 가치다.** 실제 첫 실행 로그 `[before] 0x00700F01 → [after] 0x00100A01`은 "버그가 존재하고, 교정이 작동한다"를 매 부팅마다 증명한다. 안전망이 조용히 동작하면 나중에 누군가 지워버린다.
- **③이 ④보다 먼저여야 한다.** APER가 꺼진 상태에서 CAN 블록을 건드리면 버스가 행 걸린다 (v1의 `CfgInitialize` 멈춤이 정확히 이 증상).
- ②~④는 **idempotent**(여러 번 실행해도 안전)하다. ps7_init이 미래 버전에서 고쳐져도 충돌하지 않는다.

---

## 6. 운영상 주의사항 (미래의 나에게)

1. **이 XSA를 다시 export해도 버그는 그대로다.** 앱 안전망을 제거하면 안 된다. 제거 가능 조건: `[before]`가 `0x00100A01`(또는 100MHz 조합)으로 나오는 Vivado 버전 확인 후.
2. **앱 시작 전에 CAN을 쓰는 설계 금지.** FSBL 직후~앱 진입 전 구간은 CAN_REF가 9.524MHz다. FSBL 단계에서 CAN을 써야 하는 날이 오면 ps7_init.tcl을 수동 패치하거나 FSBL 훅에 같은 교정을 넣어야 한다.
3. **Vivado 버전업 시 재검증 1분 컷:**
   ```bash
   unzip -p <새>.xsa ps7_init.tcl | grep 0XF8000128
   # 0x00700F01 (÷105) 이면 버그 잔존 → 안전망 유지
   # 0x00200501 (÷5×÷2) 류면 수정됨 → 안전망은 그래도 무해하니 둬도 됨
   ```
4. 같은 메커니즘의 버그가 **다른 주변장치 클럭**(SDIO, SPI 등 개별 CLKSRC 갖는 것들)에도 있을 수 있다. 새 주변장치 브링업 시 ps7_init의 해당 CLK_CTRL 라인을 반드시 grep으로 확인할 것.

## 7. 요약 (3줄)

1. **문제:** Vivado 2025.2가 PS7 CAN 클럭 설정(100MHz)을 BD/XCI/hwh엔 반영하면서 ps7_init에는 공장 디폴트(÷105=9.524MHz)를 생성. Tcl 재설정·강제 재생성·캐시 배제 모두 무효 (생성기 내부의 개별 CAN 클럭 재계산이 멈춰 있음 — `ACT_CAN0=23.8095=2500/105`가 물증).
2. **Tcl이 해결한 것:** EMIO 활성/핀 라우팅(비트스트림), APER 클럭, M_AXI_GP0_ACLK — 즉 "소프트웨어로 못 고치는 것들"은 전부 Vivado에서 해결됨.
3. **C가 해결한 것:** ps7_init이 잘못 쓴 CAN_CLK_CTRL을 부팅 직후 SLCR 직접 쓰기로 교정(0x00100A01=100MHz) + [before]/[after] 출력으로 매 부팅 자가 검증. "ps7_init은 스크립트일 뿐, 레지스터는 마지막에 쓴 자가 이긴다"가 탈출구였다.
