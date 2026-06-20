/*
 * Zynq PS 내장 CAN — 루프백 자가테스트 (Zybo Z7-20, bare-metal)
 * - 트랜시버/PC 불필요. 컨트롤러 내부 루프백으로 송신→수신 자기확인.
 * - XCanPs = PS CAN 정식 드라이버 (하드 실리콘)
 * - 비트타이밍 값은 XCanPs 예제 기본값. 루프백은 TX/RX가 같은 타이밍이라
 *   클럭과 무관하게 동작함(자기일치). 실버스 1Mbps는 통과 후 클럭 맞춰 재계산.
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run
 */
#include "xparameters.h"
#include "xcanps.h"
#include "xil_printf.h"

/* ⚠️ xparameters.h에서 "XCANPS" 검색해 확인:
 *  - 구버전: XPAR_XCANPS_0_DEVICE_ID  → LookupConfig(그 ID)
 *  - 신버전(SDT): XPAR_XCANPS_0_BASEADDR → LookupConfig(그 BASEADDR) */
#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_DEVICE_ID

/* XCanPs 예제 기본 비트타이밍 (루프백엔 값 무관) */
#define BRPR_VAL   29
#define SJW_VAL    3
#define TS2_VAL    2
#define TS1_VAL    15

static XCanPs Can;

int main(void)
{
    XCanPs_Config *Cfg;
    u32 Tx[4], Rx[4];

    xil_printf("\n\r=== Zynq PS CAN 루프백 자가테스트 ===\n\r");

    Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("LookupConfig 실패 — 매크로 이름 확인\n\r"); return -1; }
    if (XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("CfgInitialize 실패\n\r"); return -1;
    }

    /* config 모드 → 비트타이밍 설정 */
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    /* LOOPBACK 모드 (내부 루프백, 외부 핀/버스 불필요) */
    XCanPs_EnterMode(&Can, XCANPS_MODE_LOOPBACK);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_LOOPBACK) { }
    xil_printf("LOOPBACK 모드 진입.\n\r");

    /* 프레임 작성: ID=0x123, 표준, 8바이트 */
    Tx[0] = XCanPs_CreateIdValue(0x123, 0, 0, 0, 0);
    Tx[1] = XCanPs_CreateDlcValue(8);
    Tx[2] = 0x11223344;
    Tx[3] = 0x55667788;

    /* 송신 (FIFO 여유 생길 때까지) */
    while (XCanPs_Send(&Can, Tx) != XST_SUCCESS) { }
    xil_printf("송신 완료. 수신 대기...\n\r");

    /* 수신 (루프백이라 자기 프레임이 돌아옴) */
    while (XCanPs_Recv(&Can, Rx) != XST_SUCCESS) { }

    u32 id = Rx[0] >> XCANPS_IDR_ID1_SHIFT;   /* 표준 ID */
    xil_printf(">>> 수신: ID=0x%03x DATA=0x%08x 0x%08x\n\r",
               (unsigned)id, Rx[2], Rx[3]);

    if (id == 0x123 && Rx[2] == 0x11223344 && Rx[3] == 0x55667788)
        xil_printf(">>> ★ 성공! PS CAN 송수신 동작 확인 (루프백)\n\r");
    else
        xil_printf(">>> 데이터 불일치 — 확인 필요\n\r");

    while (1) { }
    return 0;
}
