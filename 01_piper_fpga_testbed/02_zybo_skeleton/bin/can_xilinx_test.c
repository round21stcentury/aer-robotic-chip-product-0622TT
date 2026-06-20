/*
 * Xilinx AXI CAN 송수신 테스트 (Zybo Z7-20, bare-metal)
 * - 실제 버스 (NORMAL 모드): PC USB-CAN ↔ 트랜시버 ↔ FPGA
 * - TX: ID=0x123 8바이트를 ~0.5초마다 송신 → PC candump
 * - RX: PC가 cansend 한 프레임을 받아서 시리얼에 출력
 * - 1Mbps @ can_clk 50MHz
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run
 */
#include "xparameters.h"
#include "xcan.h"
#include "xil_printf.h"

/* ⚠️ 이름은 xparameters.h에서 "CAN" 검색해 확인.
 *  - 구버전 Vitis: XPAR_CAN_0_DEVICE_ID  → XCan_LookupConfig(그 ID)
 *  - 신버전(SDT) : XPAR_XCAN_0_BASEADDR  → XCan_LookupConfig(그 BASEADDR)
 *  아래는 신버전(베이스주소) 기준. 에러나면 위 주석대로 바꾸세요. */
#define CAN_LOOKUP_ARG   XPAR_XCAN_0_BASEADDR

/* 1Mbps @ 50MHz can_clk:
 *   prescaler=5 → TQ=100ns,  10TQ/bit = 1us = 1Mbps
 *   TSEG1=7, TSEG2=2, SJW=2  (샘플포인트 80%)
 *   레지스터엔 (실제값-1)을 씀 */
#define BRPR_VAL   4    /* prescaler = 4+1 = 5  */
#define SJW_VAL    1    /* SJW   = 1+1 = 2 */
#define TS2_VAL    1    /* TSEG2 = 1+1 = 2 */
#define TS1_VAL    6    /* TSEG1 = 6+1 = 7 */

static XCan Can;
static void busy(int n){ for (volatile int i=0;i<n;i++){} }

int main(void)
{
    XCan_Config *Cfg;
    int Status;

    xil_printf("\n\r=== Xilinx AXI CAN 송수신 테스트 (1Mbps) ===\n\r");

    Cfg = XCan_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패 — 매크로 이름 확인\n\r"); return -1; }

    Status = XCan_CfgInitialize(&Can, Cfg, Cfg->BaseAddress);
    if (Status != XST_SUCCESS) { xil_printf("CfgInitialize 실패\n\r"); return -1; }

    /* reset → Config 모드 → 비트타이밍 설정 */
    XCan_Reset(&Can);
    XCan_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCan_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    /* NORMAL 모드 (실제 버스) */
    XCan_EnterMode(&Can, XCAN_MODE_NORMAL);
    while (XCan_GetMode(&Can) != XCAN_MODE_NORMAL) { }
    xil_printf("NORMAL 모드. 송신(0x123) + 수신 대기. PC: candump / cansend\n\r");

    u32 Tx[4], Rx[4];
    int n = 0, t = 0;

    while (1) {
        /* --- 송신: 약 0.5초마다 --- */
        if (++t >= 30) {
            t = 0;
            Tx[0] = XCan_CreateIdValue(0x123, 0, 0, 0, 0); /* 표준 ID 0x123 */
            Tx[1] = XCan_CreateDlcValue(8);                /* 8 바이트 */
            Tx[2] = 0x11223344;                            /* data[0..3] */
            Tx[3] = 0x55667788;                            /* data[4..7] */
            Status = XCan_Send(&Can, Tx);
            if (Status == XST_SUCCESS) xil_printf("TX #%d: ID=0x123 보냄\n\r", ++n);
            else                       xil_printf("TX 실패(FIFO full=ACK 못받음?)\n\r");
        }

        /* --- 수신: 들어온 프레임 출력 --- */
        if (!XCan_IsRxEmpty(&Can)) {
            if (XCan_Recv(&Can, Rx) == XST_SUCCESS) {
                u32 id  = Rx[0] >> XCAN_IDR_ID1_SHIFT;   /* 표준 ID */
                u32 dlc = Rx[1] >> XCAN_DLCR_DLC_SHIFT;
                xil_printf(">>> RX: ID=0x%03x DLC=%d DATA=0x%08x 0x%08x\n\r",
                           (unsigned)id, (unsigned)dlc, Rx[2], Rx[3]);
            }
        }

        busy(1000000);   /* 짧은 폴링 간격 */
    }
    return 0;
}
