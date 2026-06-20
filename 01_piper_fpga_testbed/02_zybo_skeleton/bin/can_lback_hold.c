/*
 * CAN 루프백 고정 — phy_tx 측정용 (Zybo Z7-20, PS CAN)
 * - 루프백(CEN=1, enable) 진입 후 그대로 멈춤. 모드 안 바꿈.
 * - 이 상태에서 트랜시버 TXD(또는 JE1=V12) 전압 측정:
 *     High(~3.3V) → enable하면 phy_tx가 recessive로 풀림 (정상). 문제는 NORMAL 진입.
 *     0V         → enable해도 TX가 0 → 핀/라우팅/극성 문제.
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run → TX 측정
 */
#include "xparameters.h"
#include "xcanps.h"
#include "xil_io.h"
#include "xil_printf.h"

#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_BASEADDR
#define BRPR_VAL   9
#define SJW_VAL    1
#define TS2_VAL    1
#define TS1_VAL    6

static XCanPs Can;

int main(void)
{
    XCanPs_Config *Cfg;

    xil_printf("\n\r=== CAN 루프백 고정 (phy_tx 측정) ===\n\r");

    Xil_Out32(0xF8000008, 0x0000DF0D);
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));
    Xil_Out32(0xF8000128, Xil_In32(0xF8000128) | (1u << 0));

    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패\n\r"); return -1; }
    XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr);

    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    XCanPs_EnterMode(&Can, XCANPS_MODE_LOOPBACK);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_LOOPBACK) { }

    xil_printf(">>> LOOPBACK 고정됨. mode=%d SR=0x%08x\n\r",
               XCanPs_GetMode(&Can), (unsigned)XCanPs_GetStatus(&Can));
    xil_printf(">>> 지금 TX(트랜시버 TXD / JE1) 전압 측정해라. 모드 안 바꾸고 대기.\n\r");

    while (1) { }   /* 루프백 상태로 영원히 정지 — 측정용 */
    return 0;
}
