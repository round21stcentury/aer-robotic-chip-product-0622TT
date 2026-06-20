/*
 * CTU CAN FD — BTR_FD 추가 버전 (Zybo Z7-20, bare-metal)
 * ★ 핵심 수정: BTR_FD(데이터 비트타이밍) 레지스터를 씀.
 *   공식 드라이버는 클래식 CAN이어도 BTR_FD를 항상 쓴다. 0이면 프로토콜 에러.
 *
 *  USE_LOOPBACK=1 : 내부 루프백 자가테스트 (보드만) — 수정 효과 빠른 확인
 *  USE_LOOPBACK=0 : 실제 버스 (트랜시버 + PC candump/cansend)
 *  사용법: 앱 src/helloworld.c 내용을 이걸로 교체 → Build → Run
 */
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

#define USE_LOOPBACK   1     /* 먼저 1로 확인(보드만) → 되면 0(실버스) */

#define CAN_BASE       XPAR_CTU_CAN_FD_0_BASEADDR   /* xparameters.h 확인 */

/* ---- 레지스터 오프셋 ---- */
#define R_DEVICE_ID    0x00
#define R_MODE         0x04
#define R_STATUS       0x08
#define R_BTR          0x24
#define R_BTR_FD       0x28   /* ★ 데이터 비트타이밍 (빠뜨렸던 것) */
#define R_ERR_CNT      0x30
#define R_TX_STATUS    0x70
#define R_TX_COMMAND   0x74
#define R_ERR_CAPT     0x7C
#define R_TX_PRIORITY  0x78
#define TXTB1          0x100

/* ---- MODE 비트 ---- */
#define MODE_RST       (1u << 0)
#define MODE_STM       (1u << 2)
#define MODE_ILBP      (1u << 21)
#define MODE_ENA       (1u << 22)

/* ---- STATUS 비트 ---- */
#define ST_RXNE        (1u << 0)
#define ST_EWL         (1u << 6)

/* ---- TX_COMMAND ---- */
#define TXCR           (1u << 1)
#define TXB1           (1u << 8)

/* ---- 비트타이밍 (50MHz, 1Mbps): PROP=11 PH1=8 PH2=5 BRP=2 SJW=4 ---- */
#define BTR_NOMINAL    ((4u<<27)|(2u<<19)|(5u<<13)|(8u<<7)|11u)   /* 0x2010A40B */
/* ---- BTR_FD: 안 쓰지만 "유효한 값"이 있어야 함. 데이터필드는 폭이 좁음
 *   SJW_FD[31:27] BRP_FD[26:19] PH2_FD[17:13] PH1_FD[11:7] PROP_FD[5:0]   */
#define BTR_FD_VAL     ((2u<<27)|(2u<<19)|(4u<<13)|(4u<<7)|5u)

static inline u32  rd(u32 o)        { return Xil_In32(CAN_BASE + o); }
static inline void wr(u32 o, u32 v) { Xil_Out32(CAN_BASE + o, v); }
static void busy(int n)             { for (volatile int i=0;i<n;i++){} }

int main(void)
{
    xil_printf("\n\r=== CTU CAN FD (BTR_FD 추가, LOOPBACK=%d) ===\n\r", USE_LOOPBACK);

    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID = 0x%04x  %s\n\r", id, (id==0xCAFD)?"OK":"FAIL");
    if (id != 0xCAFD) return -1;

    /* 리셋 → 명시적 해제 */
    wr(R_MODE, MODE_RST);  busy(100000);
    wr(R_MODE, 0);         busy(10000);

    /* 설정 (disabled 상태) — ★ BTR 과 BTR_FD 둘 다 */
    wr(R_TX_PRIORITY, 0x01234567);
    wr(R_BTR,    BTR_NOMINAL);
    wr(R_BTR_FD, BTR_FD_VAL);      /* ★ 이게 빠졌었음 */
    xil_printf("BTR=0x%08x BTR_FD=0x%08x\n\r", rd(R_BTR), rd(R_BTR_FD));

    /* enable */
    u32 mode = MODE_ENA;
#if USE_LOOPBACK
    //mode |= MODE_ILBP | MODE_STM;
    mode |= MODE_STM;
#endif
    wr(R_MODE, mode);  busy(10000);
    xil_printf("MODE=0x%08x STATUS=0x%08x\n\r", rd(R_MODE), rd(R_STATUS));
    xil_printf("--- 송신 시작 (ID=0x123, 8B) ---\n\r");

    int n = 0;
    while (1) {
        wr(TXTB1 + 0x00, 8);
        wr(TXTB1 + 0x04, (0x123u << 18));
        wr(TXTB1 + 0x08, 0);
        wr(TXTB1 + 0x0C, 0);
        wr(TXTB1 + 0x10, 0x11223344);
        wr(TXTB1 + 0x14, 0x55667788);
        wr(R_TX_COMMAND, TXCR | TXB1);
        busy(1000000);

        u32 st  = rd(R_STATUS);
        u32 ec  = rd(R_ERR_CAPT);
        u32 cnt = rd(R_ERR_CNT);
        u32 txs = rd(R_TX_STATUS) & 0xF;
        xil_printf("#%d ST=0x%08x RXNE=%d EWL=%d | ERRTYPE=%u TEC=%u TXB1=0x%x\n\r",
            ++n, st, (st&ST_RXNE)?1:0, (st&ST_EWL)?1:0,
            (ec>>5)&0x7, (cnt>>16)&0x1FF, txs);
        busy(30000000);
    }
    return 0;
}
