/*
 * CTU CAN FD 실제 버스 송신 테스트 (Zybo Z7-20, bare-metal)
 * - 루프백 아님. 트랜시버 + 실제 CAN 버스 + PC USB-CAN(candump) 필요.
 * - ID=0x123 8바이트 프레임을 ~0.5초마다 반복 송신 → PC candump에서 관측
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 통째 교체 → Build → Run
 */
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

/* ⚠️ 실제 매크로 이름은 xparameters.h에서 "CAN"/"CTU" 검색해 확인 */
#define CAN_BASE       XPAR_CTU_CAN_FD_0_BASEADDR

#define R_DEVICE_ID    0x00
#define R_MODE         0x04
#define R_STATUS       0x08
#define R_BTR          0x24
#define R_TX_COMMAND   0x74
#define R_TX_PRIORITY  0x78
#define TXTB1          0x100

#define MODE_RST       (1u << 0)
#define MODE_ENA       (1u << 22)   /* 루프백/셀프테스트 없음 = 실제 버스 */
#define TXCR           (1u << 1)    /* set ready = 송신 */
#define TXB1           (1u << 8)    /* 대상 버퍼1 */

static inline u32  rd(u32 o)        { return Xil_In32(CAN_BASE + o); }
static inline void wr(u32 o, u32 v) { Xil_Out32(CAN_BASE + o, v); }

int main(void)
{
    xil_printf("\n\r=== CAN 실제 버스 송신 테스트 ===\n\r");

    /* 0) 코어 확인 */
    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID = 0x%04x  %s\n\r", id, (id == 0xCAFD) ? "OK" : "FAIL");
    if (id != 0xCAFD) { xil_printf("코어 미인식 — 종료\n\r"); return -1; }

    /* 1) 소프트 리셋 */
    wr(R_MODE, MODE_RST);
    for (volatile int i = 0; i < 100000; i++) { }
    for (int t = 0; t < 1000 && (rd(R_DEVICE_ID) & 0xFFFF) != 0xCAFD; t++) { }

    /* 2) TX 우선순위 */
    wr(R_TX_PRIORITY, 0x01234567);

    /* 3) 비트타이밍 50MHz/1Mbps (PROP=11 PH1=8 PH2=5 BRP=2 SJW=4) */
    wr(R_BTR, (4u << 27) | (2u << 19) | (5u << 13) | (8u << 7) | 11u);

    /* 4) enable — 실제 버스 모드 (루프백 OFF) */
    wr(R_MODE, MODE_ENA);
    for (volatile int i = 0; i < 10000; i++) { }

    xil_printf("송신 시작 (ID=0x123, 8바이트). PC에서 candump can0 확인.\n\r");

    /* 5) 반복 송신 */
    int n = 0;
    while (1) {
        /* 프레임 작성: ID=0x123, 표준, DLC=8 */
        wr(TXTB1 + 0x00, 8);                 /* FRAME_FORMAT: DLC=8, 표준 CAN2.0 */
        wr(TXTB1 + 0x04, (0x123u << 18));    /* IDENTIFIER: 표준 base ID */
        wr(TXTB1 + 0x08, 0);                 /* TIMESTAMP_L (즉시) */
        wr(TXTB1 + 0x0C, 0);                 /* TIMESTAMP_U */
        wr(TXTB1 + 0x10, 0x11223344);        /* data[0..3] */
        wr(TXTB1 + 0x14, 0x55667788);        /* data[4..7] */

        wr(R_TX_COMMAND, TXCR | TXB1);       /* 송신 트리거 */
        xil_printf("송신 #%d (STATUS=0x%08x)\n\r", ++n, rd(R_STATUS));

        for (volatile int d = 0; d < 30000000; d++) { }  /* 대략 0.5초 대기 */
    }
    return 0;
}
