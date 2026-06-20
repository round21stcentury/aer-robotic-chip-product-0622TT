/*
 * Zynq PS 내장 CAN — 실제 버스 송수신 (Zybo Z7-20, bare-metal)
 * ─────────────────────────────────────────────────────────────
 *  경로: FPGA(PS CAN) → CAN 트랜시버 → USB-to-CAN → PC
 *  - NORMAL 모드: 실제 CAN 버스로 송출 (루프백 아님)
 *  - TX: ID=0x123, 8바이트를 약 0.5초마다 송신 → PC에서 candump
 *  - RX: PC가 cansend한 프레임을 받아 시리얼로 출력
 *  - 1Mbps @ can_clk 100MHz
 * ─────────────────────────────────────────────────────────────
 *  사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run
 */
#include "xparameters.h"
#include "xcanps.h"
#include "xil_io.h"
#include "xil_printf.h"

/* ⚠️ 루프백이 동작한 그 매크로 그대로 쓰면 됨.
 *  - 구버전: XPAR_XCANPS_0_DEVICE_ID
 *  - 신버전(SDT): XPAR_XCANPS_0_BASEADDR  ← 루프백 될 때 이걸로 바꿨으면 유지 */
#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_BASEADDR

/* ---- 비트타이밍: can_clk 100MHz, 125kbps ----
 *   bit_rate = can_clk / ((BRPR+1) * (1 + (TS1+1) + (TS2+1)))
 *   (BRPR+1)=80, TQ/bit = 1 + 7 + 2 = 10  → 100MHz/(80*10) = 125kbps
 *   샘플포인트 = (1+7)/10 = 80% (1Mbps 때랑 동일, prescaler만 8배)
 *   ↑ 레지스터엔 "실제값-1": TSEG1=7→TS1=6, TSEG2=2→TS2=1, SJW=2→SJW=1
 *   (1Mbps로 되돌리려면 BRPR_VAL을 9로) */
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

    xil_printf("\n\r=== Zynq PS CAN 실버스 송수신 (1Mbps) ===\n\r");

    /* CAN0 클럭 강제로 켜기 (루프백에서 효과 본 3줄, 그대로 유지) */
    Xil_Out32(0xF8000008, 0x0000DF0D);                          /* SLCR unlock */
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));   /* CAN0 APER(레지스터) 클럭 */
    Xil_Out32(0xF8000128, Xil_In32(0xF8000128) | (1u << 0));    /* CAN0 기준 클럭 */

    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패 — 매크로 이름 확인\n\r"); return -1; }
    if (XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("CfgInitialize 실패\n\r"); return -1;
    }

    /* ★ 진단: CAN 기준클럭 레지스터 실제값 (분주=0이면 클럭 0Hz = 死) */
    xil_printf("CAN_CLK_CTRL(0xF8000128) = 0x%08x  [bit0=ACT, [13:8]=DIV0, [5:4]=SRC]\n\r",
               Xil_In32(0xF8000128));

    /* config 모드 → 비트타이밍 설정 */
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    /* ★ 1단계: LOOPBACK 먼저 시도 (버스/트랜시버 불필요) — 클럭 살았는지 판별 */
    XCanPs_EnterMode(&Can, XCANPS_MODE_LOOPBACK);
    {
        int to = 2000000;
        while (XCanPs_GetMode(&Can) != XCANPS_MODE_LOOPBACK && --to > 0) { }
        u8 m = XCanPs_GetMode(&Can);
        xil_printf("[1] LOOPBACK 시도: mode=%d (LBACK=%d) SR=0x%08x %s\n\r",
                   m, XCANPS_MODE_LOOPBACK, XCanPs_GetStatus(&Can),
                   (m == XCANPS_MODE_LOOPBACK) ? "→ 성공(클럭 살아있음)" : "→ 실패(can_clk 0Hz 확정)");
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
                   (m == XCANPS_MODE_NORMAL) ? "→ 진입성공" : "→ 진입실패");
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
