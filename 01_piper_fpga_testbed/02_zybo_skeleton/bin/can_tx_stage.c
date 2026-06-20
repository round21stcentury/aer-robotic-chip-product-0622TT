/*
 * CAN phy_tx 단계별 진단 (Zybo Z7-20, PS CAN)
 * - 각 단계마다 ~5초 멈춤. 그동안 트랜시버 TXD(또는 JE1=V12) 전압 측정.
 * - 어느 동작에서 TX가 recessive(High)→dominant(0)로 떨어지는지 핀포인트.
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run → 단계마다 측정
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
static void hold(const char *tag) {
    xil_printf(">>> [%s] 5초간 TX 측정해라. mode=%d SR=0x%08x\n\r",
               tag, XCanPs_GetMode(&Can), (unsigned)XCanPs_GetStatus(&Can));
    for (volatile int i = 0; i < 250000000; i++) { }   /* ~5초 */
}

int main(void)
{
    XCanPs_Config *Cfg;

    xil_printf("\n\r=== CAN phy_tx 단계별 진단 ===\n\r");

    /* 클럭 켜기 */
    Xil_Out32(0xF8000008, 0x0000DF0D);
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));
    Xil_Out32(0xF8000128, Xil_In32(0xF8000128) | (1u << 0));

    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패\n\r"); return -1; }

    /* STAGE 0: CfgInitialize 직전 (컨트롤러 reset 안 함, 펌웨어가 CAN 거의 안 건드림) */
    hold("STAGE0_before_init");

    XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr);   /* 내부에서 reset 수행 */
    /* STAGE 1: reset 직후 — 정상이면 TX=recessive=High여야 함 */
    hold("STAGE1_after_reset");

    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    /* STAGE 2: config 모드 진입 후 */
    hold("STAGE2_config");

    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);
    /* STAGE 3: 비트타이밍 설정 후 (아직 config) */
    hold("STAGE3_after_timing");

    XCanPs_EnterMode(&Can, XCANPS_MODE_NORMAL);
    /* STAGE 4: NORMAL 명령 직후 (진입 성공/실패 무관, 바로 측정) */
    hold("STAGE4_after_normal_cmd");

    /* 이후 SR 계속 관찰 */
    while (1) {
        xil_printf("loop: mode=%d SR=0x%08x\n\r",
                   XCanPs_GetMode(&Can), (unsigned)XCanPs_GetStatus(&Can));
        for (volatile int i = 0; i < 100000000; i++) { }
    }
    return 0;
}
