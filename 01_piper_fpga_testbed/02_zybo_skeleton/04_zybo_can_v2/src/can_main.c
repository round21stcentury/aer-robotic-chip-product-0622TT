/*
 * Zybo Z7-20 — PS CAN0 (EMIO) 실버스 송수신 + 클럭 자가진단
 * ─────────────────────────────────────────────────────────────
 *  v2: v1에서 확정된 원인(ps7_init이 CAN 클럭/APER 안 켬, ref클럭 ÷105) 대비.
 *   - 시작 시 CAN_CLK_CTRL / APER 상태 출력해서 클럭이 제대로인지 스스로 확인
 *   - ps7_init이 또 안 켜도 앱이 SLCR로 직접 켜는 안전망 포함
 *   - NORMAL 모드 무한대기 대신 시간제한+상태출력
 *  사용법: 앱 src에 넣고 Build → Run
 */
#include "xparameters.h"
#include "xcanps.h"
#include "xil_io.h"
#include "xil_printf.h"

#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_BASEADDR

/* ── 비트레이트 선택 (can_clk=100MHz 기준) ── */
#define BITRATE_KBPS  1000   /* 1000 / 500 / 250 / 125 중 선택 */

/* bit_rate = 100MHz / ((BRPR+1)×10비트타임)  →  1000k:9, 500k:19, 250k:39, 125k:79 */
#define BRPR_VAL  (100000 / (BITRATE_KBPS * 10) - 1)
#define SJW_VAL    1       /* SJW=2  */
#define TS2_VAL    1       /* TSEG2=2 */
#define TS1_VAL    6       /* TSEG1=7, 샘플포인트 80% */

/* ── 클럭 안전망: ps7_init이 CAN 클럭 안 켜는 버그 대비 ──
 *  - APER(레지스터) 클럭 bit16: 안 켜지면 CfgInitialize에서 멈춤 → 무조건 켬
 *  - ref 클럭: ps7_init이 ÷105(0x00700F01 = 9.524MHz)로 잘못 잡음 → 100MHz로 강제.
 *    아래 0x00100A01 = IO PLL ÷10 = 100MHz.
 *    ※ IO PLL=1000MHz 는 이 보드 설계에서 확인됨 (PCW_IOPLL_FBDIV=30, 33.333×30). */
#define FORCE_CAN_CLK   1
#define CAN_CLK_100MHZ  0x00100A01u   /* IO PLL(1000) ÷10 = 100MHz, CLKACT0=1 (확인됨) */

static XCanPs Can;
static void busy(int n) { for (volatile int i = 0; i < n; i++) {} }

int main(void)
{
    XCanPs_Config *Cfg;
    u32 Tx[4], Rx[4];
    int n = 0, t = 0;

    xil_printf("\n\r=== Zybo PS CAN v2 (%d kbps, BRPR=%d) ===\n\r", BITRATE_KBPS, BRPR_VAL);

    /* ── 클럭 자가진단 (덮어쓰기 전) ── */
    xil_printf("[before] CAN_CLK_CTRL=0x%08x  APER=0x%08x  (APER bit16=%d)\n\r",
               (unsigned)Xil_In32(0xF8000128), (unsigned)Xil_In32(0xF800012C),
               (int)((Xil_In32(0xF800012C) >> 16) & 1));

    /* ── 클럭 안전망 ── */
    Xil_Out32(0xF8000008, 0x0000DF0D);                          /* SLCR unlock */
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));   /* CAN0 APER 클럭 켜기 */
#if FORCE_CAN_CLK
    Xil_Out32(0xF8000128, CAN_CLK_100MHZ);                      /* ref 클럭 100MHz 강제 */
#endif
    xil_printf("[after ] CAN_CLK_CTRL=0x%08x  APER=0x%08x  (APER bit16=%d)\n\r",
               (unsigned)Xil_In32(0xF8000128), (unsigned)Xil_In32(0xF800012C),
               (int)((Xil_In32(0xF800012C) >> 16) & 1));

    /* ── 컨트롤러 init ── */
    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패\n\r"); return -1; }
    if (XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("CfgInitialize 실패 (APER 클럭 확인)\n\r"); return -1;
    }

    /* ── config 모드 → 비트타이밍 ── */
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    /* ── NORMAL 진입 (시간제한 + 상태출력) ── */
    XCanPs_EnterMode(&Can, XCANPS_MODE_NORMAL);
    {
        int to = 2000000;
        while (XCanPs_GetMode(&Can) != XCANPS_MODE_NORMAL && --to > 0) { }
        u8 m = XCanPs_GetMode(&Can);
        xil_printf("[NORMAL] mode=%d SR=0x%08x %s\n\r",
                   m, (unsigned)XCanPs_GetStatus(&Can),
                   (m == XCANPS_MODE_NORMAL) ? "→ 진입성공" : "→ 진입실패(phy_rx/클럭 확인)");
    }
    xil_printf("PC: cansend can0 456#DEADBEEF  /  candump can0\n\r");

    /* ── 송수신 루프 ── */
    while (1) {
        if (++t >= 30) {              /* 약 0.5초마다 송신 */
            t = 0;
            Tx[0] = XCanPs_CreateIdValue(0x123, 0, 0, 0, 0);
            Tx[1] = XCanPs_CreateDlcValue(8);
            Tx[2] = 0x11223344;
            Tx[3] = 0x55667788;
            int sent = (XCanPs_Send(&Can, Tx) == XST_SUCCESS);
            u8 Rec = 0, Tec = 0;
            XCanPs_GetBusErrorCounter(&Can, &Rec, &Tec);
            xil_printf("TX #%d %s | TEC=%d REC=%d SR=0x%08x\n\r",
                       ++n, sent ? "보냄" : "FIFOfull", Tec, Rec,
                       (unsigned)XCanPs_GetStatus(&Can));
        }
        if (XCanPs_Recv(&Can, Rx) == XST_SUCCESS) {
            u32 id = Rx[0] >> XCANPS_IDR_ID1_SHIFT;
            xil_printf(">>> RX: ID=0x%03x DATA=0x%08x 0x%08x\n\r",
                       (unsigned)id, Rx[2], Rx[3]);
        }
        busy(1000000);
    }
    return 0;
}
