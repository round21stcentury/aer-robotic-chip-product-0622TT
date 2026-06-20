/*
 * CTU CAN FD 송신 + 진단 (Zybo Z7-20, bare-metal)
 * - 개선: 소프트리셋을 "명시적으로 해제(wr MODE=0)" 후 BTR 설정 → 리셋 중 BTR 날아감 방지
 * - 레지스터 되읽기로 코어 상태 확인 (BTR/MODE/STATUS)
 * - ID=0x123 8바이트 반복 송신
 * 사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run → 시리얼 확인
 */
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

/* ⚠️ 실제 매크로 이름은 xparameters.h에서 "CAN"/"CTU" 검색해 확인 */
#define CAN_BASE       XPAR_CTU_CAN_FD_0_BASEADDR

/* ---- 레지스터 오프셋 ---- */
#define R_DEVICE_ID    0x00
#define R_MODE         0x04
#define R_STATUS       0x08
#define R_BTR          0x24
#define R_TX_COMMAND   0x74
#define R_TX_PRIORITY  0x78
#define TXTB1          0x100

/* ---- MODE 비트 ---- */
#define MODE_RST       (1u << 0)
#define MODE_ILBP      (1u << 21)
#define MODE_STM       (1u << 2)
#define MODE_ENA       (1u << 22)

/* ---- STATUS 비트 ---- */
#define ST_RXNE        (1u << 0)
#define ST_TXNF        (1u << 2)
#define ST_TXS         (1u << 5)
#define ST_EWL         (1u << 6)
#define ST_IDLE        (1u << 7)

/* ---- TX_COMMAND ---- */
#define TXCR           (1u << 1)
#define TXB1           (1u << 8)

/* ---- 비트타이밍 (50MHz 클럭 기준) ----
 *   1Mbps:   BRP=2,  PROP=11 PH1=8 PH2=5 SJW=4  → 0x2010A40B
 *   125kbps: BRP=16, PROP=11 PH1=8 PH2=5 SJW=4  → 0x2080A40B
 */
#define BTR_1MBPS   ((4u<<27)|(2u<<19)|(5u<<13)|(8u<<7)|11u)
#define BTR_125K    ((4u<<27)|(16u<<19)|(5u<<13)|(8u<<7)|11u)
#define BTR_VALUE   BTR_1MBPS   /* 테스트할 속도 선택 */

static inline u32  rd(u32 o)        { return Xil_In32(CAN_BASE + o); }
static inline void wr(u32 o, u32 v) { Xil_Out32(CAN_BASE + o, v); }
static void busy(int n)             { for (volatile int i=0;i<n;i++) {} }

int main(void)
{
    xil_printf("\n\r=== CTU CAN FD 송신 + 진단 ===\n\r");

    /* 0) 코어 인식 */
    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID = 0x%04x  %s\n\r", id, (id == 0xCAFD) ? "OK" : "FAIL");
    if (id != 0xCAFD) { xil_printf("코어 미인식 — 종료\n\r"); return -1; }

    /* 1) 소프트 리셋 → 명시적 해제 (BTR을 리셋 후에 쓰도록) */
    wr(R_MODE, MODE_RST);
    busy(100000);
    wr(R_MODE, 0);            /* RST 해제, disabled 상태 */
    busy(10000);

    /* 2) 설정 (disabled 상태에서) */
    wr(R_TX_PRIORITY, 0x01234567);
    wr(R_BTR, BTR_VALUE);
    xil_printf("BTR  set = 0x%08x / readback = 0x%08x\n\r", (u32)BTR_VALUE, rd(R_BTR));

    /* 3) enable (실제 버스: ILBP/STM 없음) */
    wr(R_MODE, MODE_ENA);
    busy(10000);
    xil_printf("MODE readback = 0x%08x (ENA=bit22=0x400000)\n\r", rd(R_MODE));
    xil_printf("STATUS        = 0x%08x\n\r", rd(R_STATUS));
    xil_printf("  (EWL=bit6=0x40 이면 에러, IDLE=bit7=0x80, TXNF=bit2=0x04)\n\r");

    xil_printf("송신 시작 (ID=0x123, 8바이트). PC: candump can0\n\r");

    /* 4) 반복 송신 */
    int n = 0;
    while (1) {
        wr(TXTB1 + 0x00, 8);                 /* FRAME_FORMAT: DLC=8, 표준 CAN2.0 */
        wr(TXTB1 + 0x04, (0x123u << 18));    /* IDENTIFIER: 표준 base ID */
        wr(TXTB1 + 0x08, 0);
        wr(TXTB1 + 0x0C, 0);
        wr(TXTB1 + 0x10, 0x11223344);        /* data[0..3] */
        wr(TXTB1 + 0x14, 0x55667788);        /* data[4..7] */

        wr(R_TX_COMMAND, TXCR | TXB1);       /* 송신 트리거 */
        xil_printf("송신 #%d (STATUS=0x%08x)\n\r", ++n, rd(R_STATUS));

        busy(30000000);                      /* 대략 0.5초 */
    }
    return 0;
}
