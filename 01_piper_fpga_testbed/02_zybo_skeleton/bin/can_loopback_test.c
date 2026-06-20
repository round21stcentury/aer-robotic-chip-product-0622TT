/*
 * CTU CAN FD 내부 루프백 테스트 (Zybo Z7-20, bare-metal)
 * - 트랜시버/버스 불필요 (MODE.ILBP = 내부 루프백)
 * - DEVICE_ID 확인 → 비트타이밍(50MHz,1Mbps) → enable → 프레임 송신 → RXNE로 회신 확인
 * 레지스터 값 출처: Linux 커널 drivers/net/can/ctucanfd/
 *
 * 사용법: 앱 컴포넌트 src/helloworld.c 의 내용을 이걸로 통째 교체 → Build → Run
 */
#include "xil_io.h"
#include "xparameters.h"
#include "xil_printf.h"

/* ⚠️ 실제 매크로 이름은 xparameters.h에서 "CTU"/"CAN" 검색해 확인 */
#define CAN_BASE       XPAR_CTU_CAN_FD_0_BASEADDR

/* ---- 레지스터 오프셋 ---- */
#define R_DEVICE_ID    0x00
#define R_MODE         0x04
#define R_STATUS       0x08
#define R_BTR          0x24
#define R_TX_COMMAND   0x74
#define R_TX_PRIORITY  0x78
#define TXTB1          0x100   /* TX 버퍼1 베이스 */

/* ---- MODE 비트 ---- */
#define MODE_RST       (1u << 0)
#define MODE_ILBP      (1u << 21)  /* 내부 루프백: 버스 없이 자기 송수신 */
#define MODE_ENA       (1u << 22)  /* 코어 활성화 */

/* ---- STATUS 비트 ---- */
#define ST_RXNE        (1u << 0)   /* 수신 버퍼 비어있지 않음 = 프레임 도착 */
#define ST_TXNF        (1u << 2)   /* TX 버퍼 쓰기 가능 */

/* ---- TX_COMMAND ---- */
#define TXCR           (1u << 1)   /* set ready = 송신 트리거 */
#define TXB1           (1u << 8)   /* 대상 = 버퍼1 */

/* ---- FRAME_FORMAT_W 비트 (offset 0x00) ---- */
#define FFW_IDE        (1u << 6)   /* 0=표준(11bit), 1=확장 */
#define FFW_FDF        (1u << 7)   /* 0=CAN2.0, 1=CAN FD */
/* DLC = bits[3:0] */

/* ---- IDENTIFIER_W: 표준 11bit ID는 bits[28:18] ---- */
#define ID_BASE_SHIFT  18

static inline u32  rd(u32 o)        { return Xil_In32(CAN_BASE + o); }
static inline void wr(u32 o, u32 v) { Xil_Out32(CAN_BASE + o, v); }

int main(void)
{
    xil_printf("\n\r=== CTU CAN FD 내부 루프백 테스트 ===\n\r");

    /* 0) DEVICE_ID 확인 (코어 인식) */
    u32 id = rd(R_DEVICE_ID) & 0xFFFF;
    xil_printf("DEVICE_ID = 0x%04x  %s\n\r", id, (id == 0xCAFD) ? "OK" : "FAIL");
    if (id != 0xCAFD) { xil_printf("코어 미인식 — 종료\n\r"); return -1; }

    /* 1) 소프트 리셋 → 회복 대기 */
    wr(R_MODE, MODE_RST);
    for (volatile int i = 0; i < 100000; i++) { }
    for (int t = 0; t < 1000 && (rd(R_DEVICE_ID) & 0xFFFF) != 0xCAFD; t++) { }

    /* 2) TX 우선순위 (드라이버 기본값) */
    wr(R_TX_PRIORITY, 0x01234567);

    /* 3) 비트타이밍 50MHz/1Mbps: PROP=11 PH1=8 PH2=5 BRP=2 SJW=4
     *    → 1+11+8+5 = 25 TQ, TQ=2클럭(40ns), 25*40=1000ns=1Mbps, 샘플포인트 80%
     *    (CTU는 값 그대로 씀, -1 안 함)                                       */
    u32 PROP = 11, PH1 = 8, PH2 = 5, BRP = 2, SJW = 4;
    u32 btr = (SJW << 27) | (BRP << 19) | (PH2 << 13) | (PH1 << 7) | PROP;
    wr(R_BTR, btr);
    xil_printf("BTR = 0x%08x\n\r", btr);

    /* 4)+5) 내부 루프백 ON + 코어 활성화 */
    wr(R_MODE, MODE_ILBP | MODE_ENA);
    for (volatile int i = 0; i < 10000; i++) { }

    /* 6) TX 버퍼1에 프레임 작성: ID=0x123, 표준, DLC=8(8바이트) */
    u32 dlc = 8;
    u32 ffw = (dlc & 0xF);                 /* IDE=0,FDF=0 → 표준 CAN2.0 */
    wr(TXTB1 + 0x00, ffw);                 /* FRAME_FORMAT_W */
    wr(TXTB1 + 0x04, (0x123u << ID_BASE_SHIFT)); /* IDENTIFIER_W (base ID) */
    wr(TXTB1 + 0x08, 0);                   /* TIMESTAMP_L (0=즉시 송신) */
    wr(TXTB1 + 0x0C, 0);                   /* TIMESTAMP_U */
    wr(TXTB1 + 0x10, 0xDEADBEEF);          /* DATA_1_4 (byte0..3) */
    wr(TXTB1 + 0x14, 0x12345678);          /* DATA_5_8 (byte4..7) */

    /* 7) 송신 트리거: 버퍼1 set-ready (= 0x102) */
    wr(R_TX_COMMAND, TXCR | TXB1);

    /* 8) 루프백 회신 확인: RXNE가 서면 프레임이 돌아온 것 */
    int ok = 0;
    for (volatile int i = 0; i < 2000000; i++) {
        if (rd(R_STATUS) & ST_RXNE) { ok = 1; break; }
    }
    xil_printf("STATUS = 0x%08x\n\r", rd(R_STATUS));
    if (ok) xil_printf(">>> 성공: 프레임이 내부 루프백으로 수신됨! TX/RX 동작 OK\n\r");
    else    xil_printf(">>> 실패: RXNE 안 뜸 — 비트타이밍/모드/필터 확인\n\r");

    /* === 실제 버스 테스트(M3)로 갈 때 ===
     * - 위 4)+5)에서 MODE_ILBP 빼기:  wr(R_MODE, MODE_ENA);
     * - 트랜시버 배선 + PC에서:  candump can0
     *   → ID 0x123, 데이터(바이트순서 확인 필요)가 떠야 함                 */
    return 0;
}
