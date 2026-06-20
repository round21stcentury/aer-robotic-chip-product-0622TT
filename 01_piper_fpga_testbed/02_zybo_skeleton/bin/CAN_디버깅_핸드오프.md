# Zynq PS CAN 실버스 통신 디버깅 — 컨텍스트 핸드오프

> 다른 AI/사람에게 넘기기 위한 전체 맥락 정리. 현재 **미해결**. 아래에 셋업, 목표,
> 되는 것/안 되는 것, 수집한 측정 데이터, 배제된 가설, 핵심 미해결 질문을 모두 담음.

---

## 1. 하드웨어 & 목표
- **보드:** Digilent Zybo Z7-20 (Zynq-7000 XC7Z020), bare-metal (Vitis Unified IDE)
- **CAN:** Zynq **PS 내장 CAN0** (하드 실리콘), 드라이버 = **XCanPs**
- **라우팅:** CAN0를 **EMIO**로 PL 핀에 내보냄
  - `CAN0_PHY_TX_0` → **V12** (Pmod **JE 1번핀**)
  - `CAN0_PHY_RX_0` → **W16** (Pmod **JE 2번핀**)
- **외장 트랜시버:** "망고 Cx CAN Transceiver" 모듈 (devicemart no=32280). 칩 모델 미확인, VCC 3.3V 정상. Rs핀은 모듈 내부 처리(헤더에 없음).
- **상대 노드:** PC + USB-to-CAN 어댑터 (candleLight/gs_usb, SocketCAN)
- **목표:** FPGA(PS CAN) ↔ 트랜시버 ↔ USB-CAN ↔ PC 간 **실제 버스 송수신**. 클래식 CAN 2.0, **1 Mbps**, 11비트 표준 ID.
- **최종 용도:** Piper 6-DOF 로봇암 HIL. PC(ROS sim)→이더넷→FPGA→CAN→로봇. (이 문서는 그 중 CAN 물리계층 brought-up 단계)

## 2. 비트타이밍 (can_clk 100MHz, 1Mbps)
```
bit_rate = can_clk / ((BRPR+1) * (1 + (TS1+1) + (TS2+1)))
(BRPR+1)=10, TQ/bit = 1+7+2 = 10 → 100MHz/(10*10) = 1Mbps, 샘플포인트 80%
XCanPs 레지스터값(실제-1): BRPR=9, SJW=1, TS2=1, TS1=6
```

---

## 3. 되는 것 ✅
1. **비트스트림 로드 정상** — DONE LED 켜짐, "include bitstream" + "program device" 확인, 수동 program도 함.
2. **시리얼(UART) 정상.**
3. **CfgInitialize 멈춤 → 해결됨.** 원래 첫 CAN 레지스터 접근(reset)에서 hang. 원인 = ps7_init이 CAN 클럭(APER+ref)을 안 켬. **SLCR로 직접 켜서 해결:**
   ```c
   Xil_Out32(0xF8000008, 0x0000DF0D);                        // SLCR unlock
   Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u<<16));   // CAN0 APER(레지스터) 클럭
   Xil_Out32(0xF8000128, Xil_In32(0xF8000128) | (1u<<0));    // CAN0 기준 클럭
   ```
4. **내부 LOOPBACK 모드 동작.** `XCanPs_EnterMode(LOOPBACK)` 성공: mode=4, **SR=0x00000092** (LBACK+BIDLE). → 컨트롤러 코어·클럭은 살아있음.
5. **CAN_CLK_CTRL = 0x00700F01** — DIV0=15, SRC=0(IO PLL), CLKACT=1. 클럭 정상 구성.

## 4. 안 되는 것 ❌ — 핵심 증상
- **NORMAL 모드 진입 실패.** `EnterMode(NORMAL)` 후에도 컨트롤러가 **CONFIG에 머묾**:
  - `mode=1`(CONFIG), **SR=0x00000001** (CONFIG 비트만 set)
  - **TEC=0, REC=0, ESR=0** — 에러 전혀 없음 = 버스에 합류조차 안 함
  - TX FIFO에 프레임 쌓다가 결국 FIFO full (전송이 안 나감)
- PC candump에 아무것도 안 뜸. (당연 — 송신 자체가 안 됨)

## 5. ★결정적 측정 데이터 (전압)★
같은 측정점(트랜시버 TXD/RXD ≈ FPGA V12/W16), idle 상태:

| 상태 | TX (phy_tx, V12) | RX (phy_rx, W16) | 해석 |
|---|---|---|---|
| **펌웨어 X** (비트스트림만 로드) | **~2V** (붕 뜸) | **3V** | FPGA가 TX 미구동(고임피던스), **버스는 recessive 정상** |
| **펌웨어 O** (CONFIG에 멈춘 상태) | **0V** (dominant) | **0V** | 펌웨어가 phy_tx를 0으로 박음 → 버스 jam → RX도 0 |
| **펌웨어 O, STAGE0** (CAN 레지스터 건드리기 전, SLCR 클럭만 켠 직후) | **0V** | — | **CAN을 설정하기도 전에 이미 TX=0.** 단계별로 안 변함 |

**→ 결론적 관찰: PS 펌웨어가 도는 순간(ps7_init/CAN클럭 활성화 시점) 이미 phy_tx가 0(dominant)으로 떨어지고, 그게 버스를 jam해서 RX=0 → 컨트롤러가 idle(recessive)을 못 봐서 CONFIG를 영원히 못 벗어나는 deadlock으로 보임.**

## 6. 배제된 가설 (확인 완료)
- ❌ **핀 배정 오류** — Digilent Zybo-Z7 마스터 XDC 대조: V12=je[0]=JE1, W16=je[1]=JE2. 물리 배선(TX→JE1, RX→JE2)과 **일치**.
- ❌ **Vivado 포트 이름 불일치** — 실제 포트명 `CAN0_PHY_TX_0/RX_0` = XDC와 일치, V12/W16 배정됨. Critical warning은 **DDR DQS 스큐 4개뿐**(무해, 항상 뜸).
- ❌ **비트스트림 미로드** — DONE 켜짐.
- ❌ **클럭 죽음** — 루프백 동작 + CAN_CLK_CTRL 정상.
- ❌ **트랜시버 불량** — 펌웨어 없을 때 RX=3V 깨끗하게 나옴(버스 recessive 정상). 트랜시버는 TXD 입력을 충실히 반영 중.
- ❌ **TX/RX 배선 스왑** — 스왑 테스트 시 변화 없음.
- ❌ **5V 트랜시버 과전압** — VCC 3.3V 정상.

## 7. ★핵심 미해결 질문★
1. **Zynq-7000 PS CAN의 EMIO `phy_tx` 출력이 CONFIG/reset 상태에서 0(dominant)으로 구동되는 게 정상인가?** (그렇다면 단독/2노드 버스에서 자기 TX가 버스를 jam해 NORMAL 진입을 막는 deadlock 발생)
2. **이 deadlock을 어떻게 깨고 NORMAL에 진입시키나?** (소프트 시퀀스? 특정 레지스터? ACF? 외부 개입?)
3. 혹은 위 관찰이 다른 원인(예: phy_tx가 실제로 V12까지 출력 안 됨 — 측정은 트랜시버에서 했고 보드 JE1 직접 측정은 미완료)인가?

## 8. 다음에 할 미완료 테스트
- **`can_lback_hold.c`** (작성됨): 루프백에 영구 정지 후 **TX 전압 측정**.
  - TX=High면 → enable(CEN=1)하면 phy_tx가 recessive로 풀림 → 컨트롤러·핀 정상, 문제는 NORMAL 진입 deadlock.
  - TX=0이면 → enable해도 TX=0 → phy_tx가 핀까지 출력 안 됨(BD 라우팅/극성) 의심.
- **JE1(V12) 보드 헤더에서 직접 측정** (지금까지 트랜시버 핀에서 쟀음) — 보드핀↔트랜시버 사이 단선 배제용.
- **RX 강제 recessive 테스트**: 트랜시버 RXD선 빼고 W16(phy_rx)을 3.3V에 1kΩ로 묶어 deadlock 강제 해제 후 NORMAL 진입/ TX 거동 확인.

## 9. 관련 파일 (`01_piper_fpga_testbed/02_zybo_skeleton/`)
- `can_ps_bus.c` — 실버스 송수신(NORMAL) + 진단 출력 (현재 메인, NORMAL 진입 실패)
- `can_tx_stage.c` — 단계별 phy_tx 측정 (STAGE0~4)
- `can_lback_hold.c` — 루프백 고정 측정용 (미실행)
- `can_ps_test.c` — 초기 루프백 자가테스트
- `01_zynq_ps_bringup.md`, `02_ctu_canfd_integration.md` — 셋업 가이드
- 상위: `CAN_프로토콜_계약서.md` (Piper CAN 프레임), `CAN-이더넷_브리지_계약서.md` (HIL 브리지 규격)

## 10. 환경
- Vivado/Vitis (Unified IDE, SDT 플로우 — `XPAR_XCANPS_0_BASEADDR` 사용)
- XCanPs 드라이버, bare-metal standalone
- can_clk 100MHz (Vivado Clock Config)
- CAN0 base 0xE0008000

---
### 핵심 한 줄
**LOOPBACK(내부)은 되는데 NORMAL(실버스)이 안 됨. 펌웨어 실행 순간 phy_tx가 0(dominant)으로 박혀 버스를 jam → RX=0 → CONFIG를 못 벗어나는 deadlock. 핀·배선·클럭·비트스트림·트랜시버·포트명 전부 정상 확인됨. 남은 건 "Zynq PS CAN이 CONFIG에서 TX를 dominant로 잡는가, 어떻게 NORMAL로 깨고 들어가는가".**
