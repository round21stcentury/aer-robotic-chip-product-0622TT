# Zynq PS 브링업 가이드 — Zybo Z7-20

> **목표**: Zybo Z7-20의 ARM 프로세서(PS)를 켜서 "Hello World"를 시리얼로 찍는 것까지.
> 이게 되면 PS + DDR + UART가 살아있다는 뜻이고, 다음 단계(PL에 CAN MAC 추가)의 토대가 된다.
> **독자 가정**: Verilog는 안다. Zynq/Vivado는 처음.

---

## 0. 먼저 — 개념 정리 (Verilog 하던 사람이 헷갈리는 지점)

### PS 브링업은 "RTL을 짜는 게 아니다"
가장 큰 인식 전환: **PS(Processing System)는 이미 실리콘에 박힌 하드 ARM Cortex-A9 코어**다.
너가 Verilog로 CPU를 만드는 게 아니라, **이미 있는 CPU를 GUI로 "설정"** 하는 작업이다.
→ 이 단계에서 Verilog는 거의 안 쓴다. (Verilog는 나중에 PL에 CAN MAC 만들 때 쓴다.)

### PS vs PL
| | PS (Processing System) | PL (Programmable Logic) |
|---|---|---|
| 정체 | 하드 ARM 듀얼코어 + DDR컨트롤러 + 이더넷 등 | 우리가 Verilog로 채우는 FPGA 패브릭 |
| 작업 방식 | **설정(config)** | **RTL 설계** |
| 이번 단계 | ✅ 여기 | (다음 단계) |

PS와 PL은 칩 안에서 **AXI 버스**로 연결된다. 나중에 PS가 AXI로 PL(우리 CAN MAC)에 명령을 보낸다.

### MIO / EMIO (자주 나오는 용어)
- **MIO**: PS 전용 핀. DDR·UART·이더넷 등이 여기 붙는다. (PL 안 거침)
- **EMIO**: PS 신호를 PL로 끌어내는 통로. (PS의 주변장치를 PL 핀으로 빼고 싶을 때)

### 전체 흐름 (도구 2개)
```
[Vivado]  하드웨어 설계(PS 설정 + PL) → XSA 파일로 내보냄
              │  (XSA = 하드웨어 명세 핸드오프)
              ▼
[Vitis]   XSA를 받아 C 코드 작성 → 보드에 올려 실행(JTAG)
```
- **Vivado**: 하드웨어(블록디자인, 비트스트림) 담당
- **Vitis**: 소프트웨어(C 앱, 부팅, 디버그) 담당
- **XSA(Xilinx Shell Archive)**: 둘 사이 핸드오프 파일. 주소맵·비트스트림이 들어있어 SW가 HW를 안다.

---

## 1. 준비물

### 하드웨어
- Zybo Z7-20 보드
- **micro-USB 케이블** (보드의 `PROG/UART` 포트 — 이 하나로 JTAG 다운로드 + UART 콘솔 둘 다 됨. FTDI 칩이 겸함)
- (선택) micro-SD — 나중에 독립 부팅용. 지금 JTAG 개발엔 불필요.

### 부트 모드 점퍼 (중요)
- 보드의 **JP5 점퍼**를 **JTAG** 위치로. (개발 중엔 JTAG로 올리고 디버그)
- 나중에 SD카드 독립 부팅 시 SD로 변경.

### 소프트웨어 (무료)
- **Vivado ML Standard Edition** — XC7Z020 라이선스 비용 **0원** (예전 WebPACK). AMD 계정만 만들면 됨.
- **Vitis** (Vivado 설치 시 같이 선택 설치 가능)
- 버전: 최근 안정 버전(예: 2024.x~2025.1) 아무거나. Zynq-7000은 전 버전 지원.

### Digilent 보드파일 설치 (꼭 먼저)
보드파일이 있어야 Vivado에서 "Zybo Z7-20"을 골라 자동 설정을 받을 수 있다.
1. Digilent `vivado-boards` GitHub에서 최신 zip 다운로드
2. `new/board_files/` 안의 폴더들을 전부 복사
3. Vivado 설치 경로의 `<버전>/data/boards/board_files/` 에 붙여넣기
   - Linux: `/opt/Xilinx/Vivado/<버전>/data/boards/board_files/`
   - Windows: `C:/Xilinx/Vivado/<버전>/data/boards/board_files/`
4. Vivado 재시작 → 프로젝트 생성 시 보드 목록에 Zybo Z7-20이 보이면 성공.

---

## 2. Vivado — 하드웨어 만들기

### 2-1. 프로젝트 생성
1. Vivado → **Create Project** → 이름 지정(예: `zybo_ps_bringup`)
2. Project type: **RTL Project** (소스 없음으로 시작 OK)
3. **Boards** 탭에서 **Zybo Z7-20** 선택 → Finish
   - (보드를 고르면 XC7Z020 + DDR·이더넷 핀 설정을 프리셋으로 받는다)

### 2-2. 블록 디자인에 Zynq PS 올리기
1. 좌측 Flow Navigator → **IP INTEGRATOR → Create Block Design** (이름: `system`)
2. 다이어그램 빈 곳 우클릭 → **Add IP** → `ZYNQ7 Processing System` 검색해 추가
3. 상단에 뜨는 초록 배너 **Run Block Automation** 클릭 → OK
   - 이게 핵심: Zybo 보드 프리셋을 적용해 **DDR3, UART, 이더넷, 클럭(FCLK), MIO**를 자동 구성해준다.

### 2-3. 설정 확인 (더블클릭으로 PS 설정 창 열기)
보드 프리셋이 대부분 맞춰주지만, 다음을 확인:
- **UART**: MIO 48-49 (UART1)에 enable 돼 있는지 → 콘솔 출력에 필요
- **DDR**: 설정돼 있는지 (DDR3, Zybo는 1GB)
- **Ethernet (GEM0)**: 나중에 호스트 PC와 UDP 통신에 필요 — 켜져 있는지 확인 (지금 당장은 안 써도 됨)
- **FCLK_CLK0**: PL에 줄 클럭. 기본 100MHz면 됨 (나중에 CAN MAC가 이 클럭 사용)

> 지금은 PL이 비어있어도 된다. PS만 살리는 게 목표.

### 2-3b. ⚠️ AXI 클럭 연결 (안 하면 래퍼 생성 실패)
보드 프리셋이 `M_AXI_GP0`(PS↔PL용 AXI 마스터)를 켜놓는데, 그 클럭 입력이 연결 안 돼 있으면
래퍼 생성 시 이런 오류가 난다:
```
[BD 41-758] clock pins are not connected to a valid clock source:
  /processing_system7_0/M_AXI_GP0_ACLK
```
**해결 (선 하나)**: PS의 **`FCLK_CLK0`** 출력을 **`M_AXI_GP0_ACLK`** 입력에 드래그로 연결 → **F6**(Validate Design)으로 확인.
- (대안) Hello World만이면 PS 더블클릭 → PS-PL Configuration → AXI Non Secure Enablement → **M AXI GP0 체크 해제**.
- 단 나중에 CAN MAC를 AXI로 붙일 때 GP0가 필요하니 **연결하는 쪽을 권장**.

### 2-4. 래퍼 생성 & 비트스트림
1. Sources 패널에서 `system.bd` 우클릭 → **Create HDL Wrapper** → "let Vivado manage" → OK
2. (PL이 비었으면 비트스트림 없이도 PS 부팅 가능하지만, 한 번 만들어두면 깔끔)
   Flow Navigator → **Generate Bitstream** → 합성·구현·비트스트림까지 자동 진행 (수 분)

### 2-5. 하드웨어 내보내기 (XSA)
1. 메뉴 **File → Export → Export Hardware**
2. PL을 안 쓰면 **"Without Bitstream"**, 비트스트림 만들었으면 **"Include Bitstream"** 선택
3. `.xsa` 파일 저장 위치 기억 → 이걸 Vitis가 받는다.

---

## 3. Vitis — 소프트웨어 올리기

### 3-0. 먼저 — Vitis의 머릿속 구조 (개념부터)

Vivado가 **하드웨어**를 만들었다면, Vitis는 그 위에 올릴 **소프트웨어(C 코드)**를 만든다.
Vitis에는 두 종류의 "컴포넌트"가 있고, 이걸 구분 못 하면 계속 헷갈린다.

#### 플랫폼 컴포넌트 vs 애플리케이션 컴포넌트
| | **Platform Component** | **Application Component** |
|---|---|---|
| 정체 | 내 보드 전용 **토대/환경** | 그 위에서 도는 **내 프로그램** |
| 입력 | XSA (Vivado가 준 하드웨어 명세) | 플랫폼 + 내 C 코드 |
| 담는 것 | **BSP**(드라이버) + **도메인**(런타임) + **FSBL**(부트로더) | `main()`, 내 로직 |
| 개수 | 하드웨어당 1개 (거의 안 바뀜) | 한 플랫폼 위에 **여러 개** 가능 |

**비유**: 플랫폼 = "이 PC에 깔린 OS + 드라이버 + 라이브러리", 애플리케이션 = "그 위에서 돌리는 프로그램".
하드웨어는 잘 안 바뀌고 코드는 자주 고치니까, **플랫폼은 한 번 굽고 앱만 빠르게 반복**하려고 둘로 나눈 것.

#### 같이 알아야 할 용어
- **BSP (Board Support Package)** : 내 하드웨어 전용 **드라이버 라이브러리**. Vitis가 XSA를 보고 자동 생성한다.
  → 내가 UART 드라이버를 안 짜도 `xil_printf()`를 바로 쓸 수 있는 이유가 이것. BSP가 미리 만들어줬다.
- **도메인(Domain)** : 플랫폼 안의 **런타임 환경**. standalone(OS 없음) / FreeRTOS / Linux 중 택. 우린 지금 standalone.
- **FSBL (First Stage Boot Loader)** : 전원 켜질 때 **PS를 초기화**(클럭·DDR·MIO 세팅)하고 내 앱을 올려주는 부팅 코드. Vitis가 자동 생성.
- **ELF** : 컴파일된 내 프로그램 실행 파일. 이게 보드의 DDR에 올라가 실행된다.

#### 전체 그림
```
XSA ──▶ [Platform Component]  : BSP + 도메인 + FSBL  (토대, 1번 만듦)
              ▲
   내 C코드 ──┴──▶ [Application Component] : main() → 빌드 → ELF  (자주 반복)
                                              │ JTAG로 보드에 다운로드
                                              ▼
                                         Zybo에서 실행 → UART로 출력
```

---

### 3-1. 플랫폼 컴포넌트 만들기 — "내 보드 전용 SDK 굽기"

> **지금 하는 일**: Vivado가 준 XSA를 읽어서, 이 Zybo 하드웨어에 딱 맞는 드라이버(BSP)·부트로더(FSBL)·런타임(도메인)을 갖춘 토대를 만든다. 앱은 다음 단계.

1. Vitis 실행 → **Create Platform Component**
2. 이름/위치 (예: `zybo_platform`) → Next
3. **"Hardware Design"** 선택
   - *Hardware Design* = 내 XSA로 플랫폼 **새로 생성** ← **이거**
   - *Existing Platform* = 이미 만들어진 기성 플랫폼 재사용 (해당 없음)
4. **Browse** → Vivado에서 export한 **`.xsa`** 선택 ← XSA를 여기서 넘긴다
5. Flow/Target: **Hardware** (실제 보드)  ↔  *Emulation*(QEMU 시뮬, 지금 불필요)
6. OS: **standalone**(베어메탈, OS 없이 main() 직접 실행), Processor: **ps7_cortexa9_0**(PS의 0번 ARM 코어)
7. **Advanced options: 기본값 그대로 Finish**
   - 기본값이 FSBL·도메인·BSP를 알아서 생성한다. Hello World엔 손댈 것 없음.
8. 생성 후 **플랫폼을 한 번 빌드**(Build)해야 BSP가 실제로 컴파일된다.
   → 이게 끝나면 "이 보드용 드라이버 라이브러리"가 준비된 것.

### 3-2. 애플리케이션 컴포넌트 만들기 — Hello World

> **지금 하는 일**: 위 플랫폼(토대) 위에 올릴 실제 프로그램을 만든다. 이 앱은 플랫폼의 BSP를 가져다 `xil_printf`로 UART에 글자를 찍는다.

> ⚠️ 새 Vitis(Unified IDE)에선 **"Create Application Component" 마법사 안에 템플릿 목록이 없다.**
> Classic Vitis와 달리 템플릿이 **Welcome 탭 → Examples**로 옮겨졌다. (여기서 많이 헤맨다)

**방법 1 — 템플릿(Examples)에서**
1. 상단 **Welcome** 탭 → **Get Started** 아래 **Examples** 클릭
2. (처음이면 예제 저장소 다운로드 물어봄 → 받기)
3. 목록에서 **Hello World** (standalone) 선택
4. **"Create Application Component from Template"** 클릭
5. 마법사: Name(예: `hello_world`) → **Hardware**(만든 `zybo_platform` 선택) → **Domain**(기본 standalone) → Summary → **Finish**

**방법 2 — 빈 앱 + 코드 직접 (가장 확실)**
Examples가 안 뜨거나 다운로드가 막히면 이게 더 빠르다:
1. **Create Application Component** → 이름 → 플랫폼 선택 → 도메인 선택 → Finish (빈 앱 생성)
2. `src/` 안에 `helloworld.c` 만들고:
```c
#include <stdio.h>
#include "xil_printf.h"   // BSP가 제공하는 경량 printf. UART로 출력됨

int main(void)
{
    xil_printf("Hello World\n\r");  // \r\n: 시리얼 터미널 줄바꿈
    return 0;
}
```
- `xil_printf`는 **플랫폼 BSP가 제공**하는 함수다. 내가 UART를 직접 건드리지 않아도 이 한 줄이 UART로 나간다.
- `platform.c` 같은 추가 파일 없이도 컴파일된다 (그게 standalone BSP의 기본 제공이라).

### 3-3. 빌드 — C 코드를 ELF로

앱을 **Build**하면:
- 내 `helloworld.c`가 ARM용으로 컴파일되고
- 플랫폼의 **BSP(드라이버)와 링크**되어
- **ELF 실행 파일** 하나가 만들어진다. (이게 보드에 올라갈 최종 산출물)

> 빌드 순서 주의: **플랫폼 빌드 → 앱 빌드.** 플랫폼(BSP)이 먼저 컴파일돼 있어야 앱이 거기 링크된다.

### 3-4. 보드 연결 & 시리얼 터미널 — 출력을 볼 창

`xil_printf`가 찍는 글자는 **UART → FIXED_IO(MIO 핀) → 보드의 USB-UART 칩 → micro-USB → PC**로 들어온다.
그걸 PC에서 보려면 시리얼 터미널이 필요하다.

1. Zybo에 micro-USB 연결(PROG/UART 포트), 전원 ON, **JP5 = JTAG** 확인
2. **포트 찾기** (Linux):
   ```bash
   ls /dev/ttyUSB*      # 보통 ttyUSB0, ttyUSB1 둘 나옴
   ```
   - `ttyUSB0` = JTAG (Vitis용), **`ttyUSB1` = UART (콘솔, 이걸 연다)**
   - 확실히: `dmesg | grep ttyUSB` (나중 잡힌 게 보통 UART)
3. **권한** (안 하면 Permission denied):
   ```bash
   sudo usermod -aG dialout $USER   # 후 재로그인. 급하면 명령에 sudo
   ```
4. **터미널 열기** (택1, Baud **115200** 8N1):
   ```bash
   screen /dev/ttyUSB1 115200       # 종료: Ctrl+A → K → y
   # 또는
   picocom /dev/ttyUSB1 -b 115200   # 종료: Ctrl+A → Ctrl+X  (apt install picocom)
   ```
   - Vitis 내장: 하단 **Serial Terminal** 탭 → `+` → Port `/dev/ttyUSB1`, Baud 115200
   - ⚠️ 같은 포트를 두 프로그램이 동시에 못 엶. 하나만.
5. **순서**: 터미널 **먼저 열고** → Vitis **Run** → 출력 확인. (Hello World는 한 번 찍고 끝나니 놓치면 다시 Run)

### 3-5. Run — 보드에 올려 실행

앱 우클릭 → **Run**. 이때 Vitis가 내부적으로 하는 일:
```
① JTAG로 보드 연결
② PS 초기화 (ps7_init: 클럭·DDR·MIO 세팅 — FSBL이 하는 일과 동일)
③ (PL을 쓰면) 비트스트림을 FPGA에 다운로드
④ 내 앱 ELF를 DDR에 올리고 main()부터 실행
```
> 그래서 "경로·부팅을 내가 안 짰는데 도는" 이유 = ②의 PS 초기화 루틴을 Vitis가 자동으로 넣어주기 때문.

### 3-6. ✅ 검증 체크포인트
시리얼 터미널에 **`Hello World`** 가 찍히면:
> PS 코어 + DDR + UART가 정상 동작 → **브링업 성공.**
> (PS 초기화 → 코드 실행 → UART 출력까지 전 경로가 살아있다는 증거)

---

## 4. 자주 막히는 지점
| 증상 | 원인/조치 |
|---|---|
| 보드 목록에 Zybo Z7-20 없음 | 보드파일 설치 누락 (1장). 경로·Vivado 재시작 확인 |
| `[BD 41-758] M_AXI_GP0_ACLK ... not connected` | AXI 클럭 미연결. `FCLK_CLK0` → `M_AXI_GP0_ACLK` 연결 (2-3b) |
| `[PSU-1/2/3] DDR_DQS_TO_CLK_DELAY ... negative value` | **경고일 뿐, 무시.** Zybo 보드 실측 PCB 스큐값이라 음수가 정상. **양수로 고치지 말 것** (DDR 캘리브레이션 깨짐) |
| Run Block Automation이 DDR/이더넷 설정 안 함 | 프로젝트 생성 시 보드(Zybo)가 아니라 칩만 골랐을 때. 보드로 다시 |
| 시리얼에 아무것도 안 뜸 | Baud(115200) 확인, 포트 번호 확인, JP5=JTAG 확인 |
| JTAG 인식 안 됨 | USB 케이블/드라이버(FTDI), 보드 전원, 케이블이 PROG/UART 포트인지 |
| `cable not found` | Vivado/Vitis가 보드를 못 봄 → USB 재연결, 권한(Linux: udev rules) |
| `Could not find ARM device` / `Non JTAG bootmode` | **JP5(부트모드)를 JTAG로** → **SW4 전원 OFF→ON(점퍼 변경은 전원 재투입해야 적용)** → PGOOD(LD13) LED 켜짐 확인 → 다시 Run |
| Vitis `cannot recognize the workspace version` | 다른 버전 메타데이터. **Update 클릭하면 안전**(메타데이터만 갱신, 소스·XSA 무관). 예방: Vitis 워크스페이스를 **전용 빈 폴더**로(Vivado 프로젝트/XSA 폴더와 분리) |
| `'xil_printf.h' file not found` | **플랫폼(BSP) 미빌드.** `xil_printf.h`는 BSP가 생성. **플랫폼 컴포넌트 먼저 Build → 그다음 앱 Build.** 그래도 안 되면 앱이 플랫폼/도메인에 연결됐는지 확인 |
| `SRE module mismatch` / `command-not-found` 트레이스백 | Xilinx 환경이 셸 오염(번들 파이썬). 실제 의미는 "그 명령어 미설치". **apt·screen 등 시스템 명령은 Xilinx 환경 없는 새 터미널**에서. 확인: `which python3`이 `/usr/bin/python3`여야 함 |

---

## 5. 다음 단계 (브링업 이후)
브링업이 끝나면 본 프로젝트 방향으로:
1. **FreeRTOS + lwIP** : 베어메탈 Hello World → RTOS 올리고 이더넷으로 **UDP 수신** (호스트 PC 명령 받기). 스펙상 PS는 RTOS 기반.
2. **PL에 `can_mac` 추가** : 여기서부터 **Verilog 본격 시작**. PL에 CAN 컨트롤러를 만들고 AXI로 PS와 연결.
3. **AXI 브리지** : PS가 받은 명령을 AXI로 PL의 CAN MAC에 전달 → 외장 트랜시버로 CAN 송출.

> 팀원의 CAN 통신과 맞물리는 지점이 2~3번이다. **CAN 프레임 포맷 인터페이스 계약**(Piper SDK 기준)을 그 전에 공유해두면 통합이 매끄럽다.

---

## 6. 용어 미니 사전
- **PS** : 하드 ARM 프로세서부 (설정 대상)
- **PL** : FPGA 패브릭 (Verilog로 채움)
- **MIO/EMIO** : PS 전용 핀 / PS 신호를 PL로 빼는 통로
- **AXI** : PS-PL을 잇는 온칩 버스
- **블록 디자인** : IP를 GUI로 연결하는 Vivado 설계 방식
- **Block Automation** : 보드 프리셋을 자동 적용해주는 버튼
- **XSA** : Vivado→Vitis 하드웨어 핸드오프 파일
- **FSBL** : First Stage Boot Loader (Vitis가 자동 생성, 부팅 초기화 담당)
- **베어메탈(standalone)** : OS 없이 도는 단일 C 프로그램
- **FCLK** : PS가 PL에 공급하는 클럭
