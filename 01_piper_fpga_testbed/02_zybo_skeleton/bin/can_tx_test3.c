/*
 * CTU CAN FD 진단 코드 (Zybo Z7-20, bare-metal)
 * ───────────────────────────────────────────────────────────
 *  USE_LOOPBACK = 1 : 내부 루프백 자가테스트 (보드만, 트랜시버/PC 불필요)
 *                     ILBP(내부루프) + STM(self-ACK) → 코어가 자기 프레임 자기수신
 *  USE_LOOPBACK = 0 : 실제 버스 (트랜시버 + candleLight + candump 필요)
 * ───────────────────────────────────────────────────────────
 *  매 송신마다 진단 출력: RXNE / EWL / ERRTYPE / POS / TEC / REC / TXB1 상태
 *  사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run → 시리얼 확인
 *  레지스터 출처: Linux drivers/net/can/ctucanfd/
 */
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

#define USE_LOOPBACK   1     /* 1=내부 루프백 자가테스트 / 0=실제 버스 */

/* ⚠️ 실제 매크로 이름은 xparameters.h에서 "CAN"/"CTU" 검색해 확인 */
#define CAN_BASE       XPAR_CTU_CAN_FD_0_BASEADDR

/* ---- 레지스터 오프셋 ---- */
#define R_DEVICE_ID    0x00
#define R_MODE         0x04
#define R_STATUS       0x08
#define R_BTR          0x24
#define R_ERR_CNT      0x30   /* REC[8:0], TEC[24:16] */
#define R_TX_STATUS    0x70   /* TX1S[3:0] = 버퍼1 상태 */
#define R_TX_COMMAND   0x74
#define R_ERR_CAPT     0x7C   /* ERR_POS[4:0], ERR_TYPE[7:5] */
#define R_TX_PRIORITY  0x78
#define TXTB1          0x100  /* TX 버퍼1 데이터 시작 */

/* ---- MODE 비트 ---- */
#define MODE_RST       (1u << 0)
#define MODE_STM       (1u << 2)   /* Self-Test: 자기 ACK */
#define MODE_ILBP      (1u << 21)  /* 내부 루프백 */
#define MODE_ENA       (1u << 22)  /* 코어 활성화 */

/* ---- STATUS 비트 ---- */
#define ST_RXNE        (1u << 0)   /* 수신 버퍼 비어있지 않음 = 프레임 받음 */
#define ST_TXNF        (1u << 2)
#define ST_TXS         (1u << 5)
#define ST_EWL         (1u << 6)   /* 에러 경고 */
#define ST_IDLE        (1u << 7)

/* ---- TX_COMMAND ---- */
#define TXCR           (1u << 1)   /* set ready = 송신 */
#define TXB1           (1u << 8)   /* 대상 버퍼1 */

/* ---- 비트타이밍 (50MHz 클럭, 1Mbps): PROP=11 PH1=8 PH2=5 BRP=2 SJW=4 ---- */
#define BTR_1MBPS      ((4u<<27)|(2u<<19)|(5u<<13)|(8u<<7)|11u)   /* 0x2010A40B */
#define BTR_1MBPS  ((2u<<27)|(5u<<19)|(2u<<13)|(3u<<7)|4u)


static inline u32  rd(u32 o)        { return Xil_In32(CAN_BASE + o); }
static inline void wr(u32 o, u32 v) { Xil_Out32(CAN_BASE + o, v); }
static void busy(int n)             { for (volatile int i=0;i<n;i++) {} }

int main(void)
{
    xil_printf("\n\r=== CTU CAN FD 진단 (LOOPBACK=%d) ===\n\r", USE_LOOPBACK);

    /* 0) 코어 인식 */
    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID = 0x%04x  %s\n\r", id, (id == 0xCAFD) ? "OK" : "FAIL");
    if (id != 0xCAFD) { xil_printf("코어 미인식 — 종료\n\r"); return -1; }

    /* 1) 소프트 리셋 → 명시적 해제 (BTR을 리셋 후에 쓰도록) */
    wr(R_MODE, MODE_RST);
    busy(100000);
    wr(R_MODE, 0);                 /* RST 해제, disabled */
    busy(10000);

    /* 2) 설정 (disabled 상태에서) */
    wr(R_TX_PRIORITY, 0x01234567);
    wr(R_BTR, BTR_1MBPS);
    xil_printf("BTR  set=0x%08x readback=0x%08x\n\r", (u32)BTR_1MBPS, rd(R_BTR));

    /* 3) enable */
    u32 mode = MODE_ENA;
#if USE_LOOPBACK
    mode |= MODE_ILBP | MODE_STM;  /* 내부 루프백 + self-ACK */
#endif
    wr(R_MODE, mode);
    busy(10000);
    xil_printf("MODE set=0x%08x readback=0x%08x\n\r", mode, rd(R_MODE));
    xil_printf("STATUS=0x%08x\n\r", rd(R_STATUS));

    xil_printf("--- 송신 시작 (ID=0x123, 8B) ---\n\r");
#if !USE_LOOPBACK
    xil_printf("(PC에서 candump can0)\n\r");
#endif

    /* 4) 반복 송신 + 진단 */
    int n = 0;
    while (1) {
        /* TX 버퍼1에 프레임 작성 */
        wr(TXTB1 + 0x00, 8);                 /* FRAME_FORMAT: DLC=8, 표준 CAN2.0 */
        wr(TXTB1 + 0x04, (0x123u << 18));    /* IDENTIFIER: 표준 base ID */
        wr(TXTB1 + 0x08, 0);                 /* TIMESTAMP_L */
        wr(TXTB1 + 0x0C, 0);                 /* TIMESTAMP_U */
        wr(TXTB1 + 0x10, 0x11223344);        /* data[0..3] */
        wr(TXTB1 + 0x14, 0x55667788);        /* data[4..7] */

        wr(R_TX_COMMAND, TXCR | TXB1);       /* 송신 트리거 */
        busy(1000000);                       /* 송신/루프백 완료 대기 */

        u32 st  = rd(R_STATUS);
        u32 ec  = rd(R_ERR_CAPT);
        u32 cnt = rd(R_ERR_CNT);
        u32 txs = rd(R_TX_STATUS) & 0xF;     /* 버퍼1 상태 */
        xil_printf("#%d ST=0x%08x RXNE=%d EWL=%d | ERRTYPE=%u POS=%u TEC=%u REC=%u TXB1=0x%x\n\r",
            ++n, st, (st & ST_RXNE) ? 1 : 0, (st & ST_EWL) ? 1 : 0,
            (ec >> 5) & 0x7, ec & 0x1F, (cnt >> 16) & 0x1FF, cnt & 0x1FF, txs);

        busy(30000000);                      /* 대략 0.5초 */
    }
    return 0;
}
