/*
 * Zybo Z7-20 — HIL 브리지 FPGA측 절반: UDP(이더넷) → PS CAN0(EMIO) 송신
 * ─────────────────────────────────────────────────────────────────────
 *  목적(Phase 1 HIL): PC 시뮬이 보낸 13바이트 UDP 패킷 1개 = CAN 프레임 1개를
 *                     받아서 PS CAN0로 실제 버스에 송신한다. (CAN-이더넷_브리지_계약서 §2/§6)
 *
 *  ★이 파일은 Vitis "lwIP Echo Server" 템플릿 앱의 main.c를 대체한다.★
 *   - 템플릿(SDT 플로우)이 제공하는 것 활용: platform.c(타이머/인터럽트는 init_platform이 처리),
 *     platform_config.h(PLATFORM_EMAC_BASEADDR), xemac_add/xemacif_input, lwip220 BSP.
 *   - ★SDT 주의: platform_enable_interrupts()는 호출하지 않는다(SDT에선 init_platform이 처리).
 *     platform.c가 전역 echo_netif를 참조하므로 여기서 정의한다.
 *   - 우리가 더한 것: ① CAN 클럭 안전망+init (can_main.c 검증본 재사용)
 *                     ② UDP 5000 바인드 + 수신 콜백에서 13바이트→CAN 송신
 *
 *  반환 경로는 (b) 실제 CAN+USB-CAN으로 확정 → 이 보드는 CAN→UDP를 하지 않는다.
 *  네트워크(계약서 §1 확정값): 보드 192.168.1.10 / 마스크 255.255.255.0
 *  명령 포트: UDP 5000.  (BSP에 DHCP가 켜져 있어도 dhcp_start를 호출 안 해 정적 IP 유지)
 */

#include <stdio.h>
#include "xparameters.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"
#include "xil_printf.h"
#include "lwip/init.h"
#include "lwip/udp.h"
#include "lwip/pbuf.h"

/* ── CAN ── */
#include "xcanps.h"
#include "xil_io.h"

/* ───────────────────────── 네트워크 설정 (계약서 §1 확정값) ───────────────────────── */
#define UDP_CMD_PORT  5000        /* sim → FPGA 명령 포트 */
#define PKT_LEN       13          /* can_id(4) + dlc(1) + data(8) */

/* ───────────────────────── CAN 설정 (can_main.c 검증본과 동일) ───────────────────────── */
#define CAN_LOOKUP_ARG   XPAR_XCANPS_0_BASEADDR
#define BITRATE_KBPS  1000        /* Piper 1Mbps. (1000/500/250/125) */
#define BRPR_VAL  (100000 / (BITRATE_KBPS * 10) - 1)   /* 1000k:9 */
#define SJW_VAL    1              /* SJW=2  */
#define TS2_VAL    1              /* TSEG2=2 */
#define TS1_VAL    6              /* TSEG1=7, 샘플포인트 80% */

/* 클럭 안전망: Vivado 2025.2 ps7_init이 CAN 클럭/APER 안 켜는 버그 대비 */
#define FORCE_CAN_CLK   1
#define CAN_CLK_100MHZ  0x00100A01u   /* IO PLL(1000) ÷10 = 100MHz, CLKACT0=1 */

static XCanPs Can;

/* lwip(SDT) 관례: server_netif 저장소 + echo_netif 포인터 (platform.c가 echo_netif를 extern 참조) */
static struct netif server_netif;
struct netif *echo_netif;

/* platform.c(SDT)의 타이머 ISR이 세팅하는 플래그 */
extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
void tcp_fasttmr(void);
void tcp_slowtmr(void);

/* 관찰용 카운터 (콜백에서 갱신, 메인 루프에서 출력) */
static volatile u32 g_udp_rx   = 0;
static volatile u32 g_can_tx   = 0;
static volatile u32 g_drop_len = 0;
static volatile u32 g_drop_full= 0;
static volatile u32 g_can_rx   = 0;   /* 받은 CAN 프레임 수(로봇 피드백 등). 출력은 안 함 */

/* ─────────────────────────────── 클럭 자가진단/안전망 ─────────────────────────────── */
static void clock_safety_net(void)
{
    xil_printf("[clk before] CAN_CLK=0x%08x APER=0x%08x (CANbit16=%d)\n\r",
               (unsigned)Xil_In32(0xF8000128), (unsigned)Xil_In32(0xF800012C),
               (int)((Xil_In32(0xF800012C) >> 16) & 1));
    xil_printf("[clk enet ] GEM0_CLK_CTRL(0xF8000140)=0x%08x\n\r",
               (unsigned)Xil_In32(0xF8000140));

    Xil_Out32(0xF8000008, 0x0000DF0D);                         /* SLCR unlock */
    Xil_Out32(0xF800012C, Xil_In32(0xF800012C) | (1u << 16));  /* CAN0 APER 클럭 */
#if FORCE_CAN_CLK
    Xil_Out32(0xF8000128, CAN_CLK_100MHZ);                     /* CAN ref 100MHz 강제 */
#endif
    xil_printf("[clk after ] CAN_CLK=0x%08x APER=0x%08x (CANbit16=%d)\n\r",
               (unsigned)Xil_In32(0xF8000128), (unsigned)Xil_In32(0xF800012C),
               (int)((Xil_In32(0xF800012C) >> 16) & 1));
}

/* ─────────────────────────────── CAN init → NORMAL ─────────────────────────────── */
static int can_init_normal(void)
{
    XCanPs_Config *Cfg = XCanPs_LookupConfig(CAN_LOOKUP_ARG);
    if (Cfg == NULL) { xil_printf("CAN LookupConfig 실패\n\r"); return -1; }
    if (XCanPs_CfgInitialize(&Can, Cfg, Cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("CAN CfgInitialize 실패 (APER 클럭 확인)\n\r"); return -1;
    }
    XCanPs_EnterMode(&Can, XCANPS_MODE_CONFIG);
    while (XCanPs_GetMode(&Can) != XCANPS_MODE_CONFIG) { }
    XCanPs_SetBaudRatePrescaler(&Can, BRPR_VAL);
    XCanPs_SetBitTiming(&Can, SJW_VAL, TS2_VAL, TS1_VAL);

    XCanPs_EnterMode(&Can, XCANPS_MODE_NORMAL);
    {
        int to = 2000000;
        while (XCanPs_GetMode(&Can) != XCANPS_MODE_NORMAL && --to > 0) { }
        u8 m = XCanPs_GetMode(&Can);
        xil_printf("[CAN] %dkbps BRPR=%d mode=%d SR=0x%08x %s\n\r",
                   BITRATE_KBPS, BRPR_VAL, m, (unsigned)XCanPs_GetStatus(&Can),
                   (m == XCANPS_MODE_NORMAL) ? "→ NORMAL 진입성공" : "→ 진입실패(phy_rx/클럭 확인)");
        if (m != XCANPS_MODE_NORMAL) return -1;
    }
    return 0;
}

/* 13바이트 패킷 → CAN 송신. (계약서 §2 레이아웃, 빅엔디언) */
static void send_can_frame(const u8 *pkt)
{
    u32 can_id = ((u32)pkt[0] << 24) | ((u32)pkt[1] << 16) |
                 ((u32)pkt[2] << 8)  |  (u32)pkt[3];        /* 빅엔디언 */
    u8  dlc    = pkt[4];
    if (dlc > 8) dlc = 8;

    u32 Tx[4];
    Tx[0] = XCanPs_CreateIdValue(can_id & 0x7FF, 0, 0, 0, 0);  /* 11비트 표준 */
    Tx[1] = XCanPs_CreateDlcValue(dlc);
    /* ★XCanPs 데이터 레지스터는 리틀엔디언: 버스 D0가 워드의 LSB로 나간다.
     *  (빅엔디언으로 넣으면 32비트 워드 단위로 뒤집혀 candump에서 바이트가 어긋남) */
    Tx[2] = (u32)pkt[5] | ((u32)pkt[6] << 8) | ((u32)pkt[7] << 16) | ((u32)pkt[8] << 24);
    Tx[3] = (u32)pkt[9] | ((u32)pkt[10]<< 8) | ((u32)pkt[11]<< 16) | ((u32)pkt[12]<< 24);

    int retry = 200;
    while (XCanPs_Send(&Can, Tx) != XST_SUCCESS) {
        if (--retry <= 0) { g_drop_full++; return; }
    }
    g_can_tx++;
}

/* ─────────────────────────────── lwIP UDP 수신 콜백 ─────────────────────────────── */
static void udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                        const ip_addr_t *addr, u16_t port)
{
    (void)arg; (void)pcb; (void)addr; (void)port;
    if (p == NULL) return;

    g_udp_rx++;
    if (p->tot_len >= PKT_LEN) {
        u8 buf[PKT_LEN];
        pbuf_copy_partial(p, buf, PKT_LEN, 0);
        send_can_frame(buf);
    } else {
        g_drop_len++;
    }
    pbuf_free(p);
}

static int start_udp_bridge(void)
{
    struct udp_pcb *pcb = udp_new();
    if (!pcb) { xil_printf("udp_new 실패\n\r"); return -1; }
    if (udp_bind(pcb, IP_ANY_TYPE, UDP_CMD_PORT) != ERR_OK) {
        xil_printf("udp_bind(%d) 실패\n\r", UDP_CMD_PORT); return -1;
    }
    udp_recv(pcb, udp_recv_cb, NULL);
    xil_printf("[UDP] %d 포트 바인드 — sim에서 13B 패킷 보내면 CAN으로 송출\n\r", UDP_CMD_PORT);
    return 0;
}

/* ─────────────────────────────── 메인 ─────────────────────────────── */
int main(void)
{
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac[6] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

    echo_netif = &server_netif;

    xil_printf("\n\r=== Zybo HIL 브리지: UDP%d → CAN0(%dkbps) ===\n\r", UDP_CMD_PORT, BITRATE_KBPS);

    /* CAN 먼저 (NORMAL 못 들어가도 네트워크는 올려 디버깅 계속) */
    clock_safety_net();
    if (can_init_normal() != 0)
        xil_printf("CAN 초기화 실패 — 네트워크는 그래도 올림\n\r");

    init_platform();                 /* SDT: 타이머/인터럽트 설정 (platform_enable_interrupts 대체) */

    IP4_ADDR(&ipaddr,  192, 168, 1, 10);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw,      192, 168, 1, 1);   /* 직결이라 GW 미사용(동일 서브넷) */

    lwip_init();
    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("xemac_add 실패\n\r");
        return -1;
    }
    netif_set_default(echo_netif);
    /* ★SDT: platform_enable_interrupts() 호출 안 함 (init_platform이 처리) */
    netif_set_up(echo_netif);

    xil_printf("[NET] board=192.168.1.10  port=%d  (정적 IP, DHCP 미사용)\n\r", UDP_CMD_PORT);

    if (start_udp_bridge() != 0) return -1;

    /* ── 메인 루프 ── */
    u32 spin = 0, last_print = 0;
    while (1) {
        if (TcpFastTmrFlag) { tcp_fasttmr(); TcpFastTmrFlag = 0; }
        if (TcpSlowTmrFlag) { tcp_slowtmr(); TcpSlowTmrFlag = 0; }
        xemacif_input(echo_netif);   /* 수신 패킷 → lwip → udp_recv_cb */

        /* ★CAN RX는 조용히 비우기만 (출력 X)★
         * 실제 로봇은 피드백을 폭주시키는데, 프레임마다 xil_printf(UART 115200)하면
         * 그 출력이 루프를 막아 들어오는 UDP 명령 처리를 굶긴다 → 명령이 안 나감.
         * 우리는 UDP→CAN 단방향이라 수신 내용을 쓸 일이 없으니 비우고 카운트만. */
        u32 Rx[4];
        while (XCanPs_Recv(&Can, Rx) == XST_SUCCESS) { g_can_rx++; }

        if (++spin >= 2000000) {
            spin = 0;
            u32 sum = g_udp_rx + g_can_tx + g_drop_len + g_drop_full;
            if (sum != last_print) {
                last_print = sum;
                u8 Rec = 0, Tec = 0;
                XCanPs_GetBusErrorCounter(&Can, &Rec, &Tec);
                /* xil_printf는 %lu 미지원 → %d로 (카운터는 작음) */
                xil_printf("[stat] udpRX=%d canTX=%d canRX=%d dropLEN=%d dropFULL=%d | TEC=%d REC=%d SR=0x%08x\n\r",
                           (int)g_udp_rx, (int)g_can_tx, (int)g_can_rx, (int)g_drop_len, (int)g_drop_full,
                           Tec, Rec, (unsigned)XCanPs_GetStatus(&Can));
            }
        }
    }

    cleanup_platform();
    return 0;
}
