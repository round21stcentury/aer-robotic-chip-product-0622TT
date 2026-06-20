/* reflex_s1_main.c — 스텝1 PS 앱 (★정상명령 패스스루 브리지 + ★레이트 페이싱)
 *   루프: PC 슬라이더 → 이더넷 UDP(5000) → 이 PS(lwIP) → ★GPIO 메일박스★ → PL → SPI → 칩
 *         → MCP2515 → CAN → USB-CAN(can0) → virtual_robot → Gazebo.
 *   ★핵심 수정(움찔/flailing 원인=프레임 드롭): PS가 ID별 최신값만 기억하고 ★PACE_US 마다
 *     한 프레임씩★ 보냄. 칩 송신시간(~128µs)보다 느리게 페이싱 → 칩 드롭 0, 메일박스 덮어쓰기 0.
 *     슬라이더가 6관절(0x155/6/7)을 연달아 쏴도, 최신값을 칩 페이스로 차근차근 전달 → 부드럽게 추종.
 *   + cfg GPIO(SPI속도/enable) + EMIO 로 MCP 되읽기 관측.
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

#ifndef SPI_DIV_CODE
#define SPI_DIV_CODE 4
#endif
#ifndef PACE_US
#define PACE_US 300        /* ★프레임 간 페이싱(µs). 파이프라인(릴레이+적재+MCP송신=222µs)보다 커야
                            *  다음 TXB0 적재가 이전 MCP 송신 끝난 뒤 시작 → splice 손상 0.
                            *  150 이면 끝바이트 겹침손상(2026-06-18 HIL 실측). 300 검증됨. */
#endif
#define CFG_GPIO     0x41200000U
#define CMD_LO_GPIO  0x41210000U
#define CMD_HI_GPIO  0x41220000U
#define CMD_ID_GPIO  0x41230000U
#define PS_GPIO_BASE 0xE000A000U
#define EMIO_BANK0 2
#define EMIO_BANK1 3

static XGpioPs Gpio;
static u32 g_tog = 0;

/* ★전달 대상 CAN id = 브리지 최대 명령집합 COMMAND_IDS_WITH_ESTOP 와 ★정확히 일치★.
 *  브리지(can_udp_bridge.py)가 FPGA로 보내는 건 SCOPE_COMMAND_IDS(={0x151,155,156,157,471})
 *  또는 --estop 시 +0x150. 이 6개를 다 전달 → 브리지가 보내는 어떤 명령도 누락 0.
 *  ★0x471(enable) 필수 — 빠지면 virtual_robot.set_targets 가 enabled=False 라 로봇이 안 움직임
 *    (HIL "명령은 can0에 오는데 로봇 가만"의 원인. 2026-06-18 규명). 0x151=모드, 0x155~7=관절,
 *    0x150=비상정지(--estop). 새 명령 id 가 생기면 ★반드시 여기 추가★(누락=무동작). */
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

/* 13바이트 패킷 → ID별 최신 테이블에 저장(여기선 메일박스 안 씀; 메인루프가 페이싱해서 보냄) */
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
        int idx = fwd_idx(id);
        if (idx >= 0) {
            tbl_lo[idx] = (u32)b[5]  | ((u32)b[6]<<8)  | ((u32)b[7]<<16)  | ((u32)b[8]<<24);
            tbl_hi[idx] = (u32)b[9]  | ((u32)b[10]<<8) | ((u32)b[11]<<16) | ((u32)b[12]<<24);
            tbl_dirty[idx] = 1;
        }
    } else g_drop_len++;
    pbuf_free(p);
}

/* 한 프레임을 메일박스에 (lo/hi 먼저, ★DSB로 데이터 커밋 보장★, id+토글 마지막).
 * cmd_lo/hi/id 는 서로 다른 AXI GPIO 슬레이브라 A9 posted write 가 슬레이브간 순서를
 * 보장 안 함 → 토글이 데이터보다 먼저 PL 에 도착하면 PL 이 새 id+이전 데이터 래치(섞임).
 * DSB 가 데이터 쓰기 완료를 기다린 뒤 토글을 쓰게 해 순서를 강제 → 섞임 방지. */
static void send_mailbox(u32 id, u32 lo, u32 hi)
{
    Xil_Out32(CMD_LO_GPIO, lo);
    Xil_Out32(CMD_HI_GPIO, hi);
    __asm__ volatile ("dsb sy" ::: "memory");   /* ★데이터가 토글보다 먼저 도착 보장 */
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
    xil_printf("[UDP] %d 바인드 — ID별 최신값 %dµs 페이싱 → 칩 → MCP\n\r", UDP_CMD_PORT, PACE_US);
    return 0;
}

int main(void)
{
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac[6] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
    echo_netif = &server_netif;
    for (int i=0;i<NID;i++){ tbl_lo[i]=0; tbl_hi[i]=0; tbl_dirty[i]=0; }

    xil_printf("\n\r=== 스텝1: 정상명령 패스스루 + 페이싱 (eth→PS→PL→SPI→칩→MCP) ===\n\r");

    XGpioPs_Config *gcfg = XGpioPs_LookupConfig(PS_GPIO_BASE);
    if (gcfg) XGpioPs_CfgInitialize(&Gpio, gcfg, gcfg->BaseAddr);
    Xil_Out32(CFG_GPIO, (1u << 8) | (SPI_DIV_CODE & 0xFF));
    xil_printf("[CFG] SPI_DIV=%d enable=1, PACE=%dus\n\r", (int)(SPI_DIV_CODE & 0xFF), PACE_US);

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
        xemacif_input(echo_netif);            /* UDP → udp_recv_cb → 테이블 갱신 */

        /* ★페이싱: dirty 한 프레임 하나 라운드로빈 송신(최신값) 후 PACE_US 쉼.
         *   usleep(BSP 타이머)로 칩 송신(~128µs)보다 느리게 → 드롭0. */
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

        /* 가끔만 관측 출력 (약 1초마다 — usleep PACE_US 기준 루프수) */
        if (++spin >= (u32)(1000000u / PACE_US)) {
            spin = 0;
            u32 o0 = XGpioPs_Read(&Gpio, EMIO_BANK0);
            u32 o1 = XGpioPs_Read(&Gpio, EMIO_BANK1);
            xil_printf("[MCP] CANSTAT=0x%02x CNF=%02x/%02x/%02x EFLG=0x%02x TEC=%d REC=%d INTF=0x%02x | udpRX=%d sent=%d\n\r",
                       (o0>>24)&0xFF,(o0>>16)&0xFF,(o0>>8)&0xFF,o0&0xFF,
                       (o1>>24)&0xFF,(o1>>16)&0xFF,(o1>>8)&0xFF,o1&0xFF,
                       (int)g_udp_rx,(int)g_sent);
        }
    }
    cleanup_platform();
    return 0;
}
