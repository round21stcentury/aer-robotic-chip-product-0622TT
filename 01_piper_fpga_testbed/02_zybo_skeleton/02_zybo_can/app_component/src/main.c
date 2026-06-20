/*
 * Zynq PS 내장 CAN — 실제 버스 송수신 (Zybo Z7-20, bare-metal)
 * ─────────────────────────────────────────────────────────────
 * 경로: FPGA(PS CAN) → CAN 트랜시버 → USB-to-CAN → PC
 * - NORMAL 모드: 실제 CAN 버스로 송출 (루프백 아님)
 * - TX: ID=0x123, 8바이트를 약 0.5초마다 송신 → PC에서 candump
 * - RX: PC가 cansend한 프레임을 받아 시리얼로 출력
 * - 125kbps @ can_clk 100MHz (IO PLL 100MHz 직결)
 * ─────────────────────────────────────────────────────────────
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run
 */
#include "xparameters.h"
#include "xcanps.h"
#include "xil_io.h"
#include "xil_printf.h"

/* ⚠️ 루프백이 동작한 그 매크로 그대로 쓰면 됨.
 * - 구버전: XPAR_XCANPS_0_DEVICE_ID
 * - 신버전(SDT): XPAR_XCANPS_0_BASEADDR */
#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_BASEADDR

/* ---- 비트타이밍: can_clk 100MHz, 125kbps ----
 * bit_rate = can_clk / ((BRPR+1) * (1 + (TS1+1) + (TS2+1)))
 * (BRPR+1)=80, TQ/bit = 1 + 7 + 2 = 10  → 100MHz/(80*10) = 125kbps
 * 샘플포인트 = (1+7)/10 = 80%
 * ↑ 레지스터엔 "실제값-1": TSEG1=7→TS1=6, TSEG2=2→TS2=1, SJW=2→SJW=1 */
#define BRPR_VAL   79   /* prescaler = 79+1 = 80  → 125kbps */
#define SJW_VAL    1    /* SJW   = 1+1 = 2 */
#define TS2_VAL    1    /* TSEG2 = 1+1 = 2 */
#define TS1_VAL    6    /* TSEG1 = 6+1 = 7 */

static XCanPs Can;
static void busy(int n) { for (volatile int i = 0; i < n; i++) {} }

int main(void)
{
    XCanPs_Config *Cfg;
    u32 Tx[4], Rx[4];
    int n = 0, t = 0;

    xil_printf("\n\r=== Zynq PS CAN 실버스 송수신 (125kbps) ===\n\r");

    /* CAN0 클럭 강제로 켜기 및 분주비 수정 (IO PLL 100MHz 1:1 패스스루) */
    Xil_Out32(0xF8000008, 0x0000DF0D);                          /* SLCR unlock */
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));   /* CAN0 APER(레지스터) 클럭 켜기 */
    Xil_Out32(0xF800015C, 0x00100101);                          /* CAN_CLK_CTRL: IO PLL(100MHz) ÷ (1×1) = 100MHz, ACT0=1 */

    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패 — 매크로 이름 확인\n\r"); return -1; }
    if (XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("CfgInitialize 실패\n\r"); return -1;
    }

    /* ★ 진단: CAN 기준클럭 레지스터 실제값 출력 (0x00100101이 찍혀야 정상) */
    xil_printf("CAN_CLK_CTRL(0xF800015C) = 0x%08x  [bit0=ACT, [13:8]=DIV0, [25:20]=DIV1]\n\r",
               Xil_In32(0xF800015C));

    /* config 모드 → 비트타이밍 설정 */
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    /* ★ 1단계: LOOPBACK 먼저 시도 (클럭이 제대로 들어가는지 최종 마일스톤 확인) */
    XCanPs_EnterMode(&Can, XCANPS_MODE_LOOPBACK);
    {
        int to = 2000000;
        while (XCanPs_GetMode(&Can) != XCANPS_MODE_LOOPBACK && --to > 0) { }
        u8 m = XCanPs_GetMode(&Can);
        xil_printf("[1] LOOPBACK 시도: mode=%d (LBACK=%d) SR=0x%08x %s\n\r",
                   m, XCANPS_MODE_LOOPBACK, XCanPs_GetStatus(&Can),
                   (m == XCANPS_MODE_LOOPBACK) ? "→ 성공(클럭 완벽히 살아있음)" : "→ 실패(클럭 설정 재확인 필요)");
    }

    /* ★ 2단계: NORMAL 시도 */
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_EnterMode(&Can, XCANPS_MODE_NORMAL);
    {
        int to = 2000000;
        while (XCanPs_GetMode(&Can) != XCANPS_MODE_NORMAL && --to > 0) { }
        u8 m = XCanPs_GetMode(&Can);
        xil_printf("[2] NORMAL 시도: mode=%d (NORMAL=%d) SR=0x%08x %s\n\r",
                   m, XCANPS_MODE_NORMAL, XCanPs_GetStatus(&Can),
                   (m == XCANPS_MODE_NORMAL) ? "→ 진입성공" : "→ 진입실패 (phy_rx 전압/결선 확인)");
        xil_printf("PC:  candump can0   /   cansend can0 456#DEADBEEFCAFEBABE\n\r");
    }

    while (1) {
        /* --- 송신: 약 0.5초마다 + 에러카운터 진단 --- */
        if (++t >= 30) {
            t = 0;
            Tx[0] = XCanPs_CreateIdValue(0x123, 0, 0, 0, 0);  /* 표준 ID 0x123 */
            Tx[1] = XCanPs_CreateDlcValue(8);                 /* 8 바이트 */
            Tx[2] = 0x11223344;                               /* data[0..3] */
            Tx[3] = 0x55667788;                               /* data[4..7] */
            int sent = (XCanPs_Send(&Can, Tx) == XST_SUCCESS);

            u8 Rec = 0, Tec = 0;
            XCanPs_GetBusErrorCounter(&Can, &Rec, &Tec);
            u32 esr = XCanPs_GetBusErrorStatus(&Can);
            xil_printf("TX #%d %s | TEC=%d REC=%d ESR=0x%x SR=0x%08x\n\r",
                       ++n, sent ? "보냄" : "FIFOfull",
                       Tec, Rec, esr, XCanPs_GetStatus(&Can));
            XCanPs_ClearBusErrorStatus(&Can, esr);
        }

        /* --- 수신: 들어온 프레임 출력 --- */
        if (XCanPs_Recv(&Can, Rx) == XST_SUCCESS) {
            u32 id = Rx[0] >> XCANPS_IDR_ID1_SHIFT;           /* 표준 ID */
            xil_printf(">>> RX: ID=0x%03x DATA=0x%08x 0x%08x\n\r",
                       (unsigned)id, Rx[2], Rx[3]);
        }

        busy(1000000);   /* 짧은 폴링 간격 */
    }
    return 0;
}