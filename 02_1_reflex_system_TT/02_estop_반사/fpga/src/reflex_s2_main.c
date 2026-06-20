/* reflex_s2_main.c — 스텝2 PS 앱 (★정상명령 패스스루 + 반사 소프트트리거 제어채널)
 *   스텝1(패스스루 브리지 + 페이싱)에 ★소프트 반사 트리거★ 추가:
 *     - 제어 UDP(id=0x7F0, data[0]=1 켜기/0 끄기) → cfg_gpio[9] 셋 → PL서 칩 ui_in[0](트리거)에
 *       물리 DIP 와 OR. 물리 DIP 없이도(또는 원격으로) 반사 발동 테스트 가능.
 *   루프: PC 슬라이더 → UDP(5000) → PS → 메일박스 → PL → 칩 → 먹스 → MCP → 로봇.
 *     위험시(트리거) 칩이 정상명령 끊고 0x150 e-stop 주입 → 로봇 정지.
 */
#include <stdio.h>
#include "xparameters.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xgpiops.h"
#include "sleep.h"
#include "lwip/init.h"
#include "lwip/udp.h"
#include "lwip/pbuf.h"

#define UDP_CMD_PORT  5000
#define PKT_LEN       13
#define CTRL_TRIG_ID  0x7F0U       /* ★소프트 반사트리거 제어 UDP id (data[0]=1켜기/0끄기) */

#ifndef SPI_DIV_CODE
#define SPI_DIV_CODE 4
#endif
#ifndef PACE_US
#define PACE_US 300        /* 프레임 간 페이싱(µs) > 파이프라인 222µs → splice 손상 0 (스텝1 검증) */
#endif
#define CFG_GPIO     0x41200000U    /* [7:0]SPI_DIV [8]enable [9]★소프트 반사트리거 */
#define CMD_LO_GPIO  0x41210000U
#define CMD_HI_GPIO  0x41220000U
#define CMD_ID_GPIO  0x41230000U
#define PS_GPIO_BASE 0xE000A000U
#define EMIO_BANK0 2
#define EMIO_BANK1 3

static XGpioPs Gpio;
static u32 g_tog = 0;
static volatile u32 g_sw_trig = 0;          /* ★소프트 반사 트리거 상태 */

static void write_cfg(void) {               /* cfg_gpio 갱신 (SPI속도 + enable + 소프트트리거) */
    Xil_Out32(CFG_GPIO, (g_sw_trig << 9) | (1u << 8) | (SPI_DIV_CODE & 0xFF));
}

/* ★전달 대상 CAN id = 브리지 명령집합 COMMAND_IDS_WITH_ESTOP 와 정확히 일치 (누락=무동작).
 *  0x471=enable 필수, 0x151=모드, 0x155~7=관절, 0x150=비상정지. 새 명령 id 면 여기 추가. */
#define NID 6
static const u32 FWD_IDS[NID] = {0x150, 0x151, 0x155, 0x156, 0x157, 0x471};
static volatile u32 tbl_lo[NID], tbl_hi[NID];
static volatile u8  tbl_dirty[NID];
static int fwd_idx(u32 id) {
    for (int i = 0; i < NID; i++) if (FWD_IDS[i] == id) return i;
    return -1;
}

/* lwip(SDT) */
static struct netif server_netif;
struct netif *echo_netif;
extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
void tcp_fasttmr(void);
void tcp_slowtmr(void);

static volatile u32 g_udp_rx = 0, g_sent = 0, g_drop_len = 0;

static void udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                        const ip_addr_t *addr, u16_t port)
{
    (void)arg; (void)pcb; (void)addr; (void)port;
    if (p == NULL) return;
    g_udp_rx++;
    if (p->tot_len >= PKT_LEN) {
        u8 b[PKT_LEN];
        pbuf_copy_partial(p, b, PKT_LEN, 0);
        u32 id = (((u32)b[0]<<24)|((u32)b[1]<<16)|((u32)b[2]<<8)|(u32)b[3]) & 0x7FF;
        if (id == CTRL_TRIG_ID) {            /* ★소프트 반사 트리거 (테스트/원격) — 메일박스로 안 보냄 */
            g_sw_trig = (b[5] != 0);
            write_cfg();
        } else {
            int idx = fwd_idx(id);
            if (idx >= 0) {
                tbl_lo[idx] = (u32)b[5]  | ((u32)b[6]<<8)  | ((u32)b[7]<<16)  | ((u32)b[8]<<24);
                tbl_hi[idx] = (u32)b[9]  | ((u32)b[10]<<8) | ((u32)b[11]<<16) | ((u32)b[12]<<24);
                tbl_dirty[idx] = 1;
            }
        }
    } else g_drop_len++;
    pbuf_free(p);
}

/* 한 프레임을 메일박스에 (lo/hi 먼저, ★DSB로 데이터 커밋 보장★, id+토글 마지막). */
static void send_mailbox(u32 id, u32 lo, u32 hi)
{
    Xil_Out32(CMD_LO_GPIO, lo);
    Xil_Out32(CMD_HI_GPIO, hi);
    __asm__ volatile ("dsb sy" ::: "memory");
    g_tog ^= 1u;
    Xil_Out32(CMD_ID_GPIO, (g_tog << 31) | (id & 0x7FF));
    __asm__ volatile ("dsb sy" ::: "memory");
    g_sent++;
}

static int start_udp_bridge(void)
{
    struct udp_pcb *pcb = udp_new();
    if (!pcb) { xil_printf("udp_new 실패\n\r"); return -1; }
    if (udp_bind(pcb, IP_ANY_TYPE, UDP_CMD_PORT) != ERR_OK) {
        xil_printf("udp_bind(%d) 실패\n\r", UDP_CMD_PORT); return -1;
    }
    udp_recv(pcb, udp_recv_cb, NULL);
    xil_printf("[UDP] %d 바인드 — 명령 페이싱 + 0x7F0 소프트트리거\n\r", UDP_CMD_PORT);
    return 0;
}

int main(void)
{
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac[6] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
    echo_netif = &server_netif;
    for (int i=0;i<NID;i++){ tbl_lo[i]=0; tbl_hi[i]=0; tbl_dirty[i]=0; }

    xil_printf("\n\r=== 스텝2: 정상 패스스루 + e-stop 반사 (트리거=DIP|소프트0x7F0) ===\n\r");

    XGpioPs_Config *gcfg = XGpioPs_LookupConfig(PS_GPIO_BASE);
    if (gcfg) XGpioPs_CfgInitialize(&Gpio, gcfg, gcfg->BaseAddr);
    write_cfg();
    xil_printf("[CFG] SPI_DIV=%d enable=1 trig=0, PACE=%dus\n\r", (int)(SPI_DIV_CODE & 0xFF), PACE_US);

    init_platform();
    IP4_ADDR(&ipaddr, 192,168,1,10); IP4_ADDR(&netmask, 255,255,255,0); IP4_ADDR(&gw, 192,168,1,1);
    lwip_init();
    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("xemac_add 실패\n\r"); return -1;
    }
    netif_set_default(echo_netif);
    netif_set_up(echo_netif);
    xil_printf("[NET] board=192.168.1.10 port=%d\n\r", UDP_CMD_PORT);
    if (start_udp_bridge() != 0) return -1;

    u32 rr = 0, spin = 0;

    while (1) {
        if (TcpFastTmrFlag) { tcp_fasttmr(); TcpFastTmrFlag = 0; }
        if (TcpSlowTmrFlag) { tcp_slowtmr(); TcpSlowTmrFlag = 0; }
        xemacif_input(echo_netif);

        for (u32 k = 0; k < NID; k++) {
            u32 idx = (rr + k) % NID;
            if (tbl_dirty[idx]) {
                tbl_dirty[idx] = 0;
                send_mailbox(FWD_IDS[idx], tbl_lo[idx], tbl_hi[idx]);
                rr = (idx + 1) % NID;
                break;
            }
        }
        usleep(PACE_US);

        if (++spin >= (u32)(1000000u / PACE_US)) {
            spin = 0;
            u32 o0 = XGpioPs_Read(&Gpio, EMIO_BANK0);
            u32 o1 = XGpioPs_Read(&Gpio, EMIO_BANK1);
            xil_printf("[MCP] CANSTAT=0x%02x CNF=%02x/%02x/%02x EFLG=0x%02x TEC=%d | trig=%d udpRX=%d sent=%d\n\r",
                       (o0>>24)&0xFF,(o0>>16)&0xFF,(o0>>8)&0xFF,o0&0xFF,
                       (o1>>24)&0xFF,(o1>>16)&0xFF,(int)g_sw_trig,(int)g_udp_rx,(int)g_sent);
        }
    }
    cleanup_platform();
    return 0;
}
