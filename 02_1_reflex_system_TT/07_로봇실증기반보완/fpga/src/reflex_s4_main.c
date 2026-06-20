/* reflex_s4_main.c — 스텝4 PS 앱 (★정상명령 패스스루 + 현재포즈 J5 움츠림 반사 제어채널)
 *   스텝1(패스스루 브리지 + 페이싱)에 ★소프트 반사 트리거★ 추가:
 *     - 제어 UDP(id=0x7F0, data[0]=1 켜기/0 끄기) → cfg_gpio[9] 셋 → PL서 칩 ui_in[0](트리거)에
 *       물리 DIP 와 OR. 물리 DIP 없이도(또는 원격으로) 반사 발동 테스트 가능.
 *   루프: PC 슬라이더 → UDP(5000) → PS → 메일박스 → PL → 칩 → 먹스 → MCP → 로봇.
 *     위험시(트리거) 칩이 정상명령 끊고 현재포즈+움츠림 델타 주입 → 로봇이 J5 만큼 움츠림.
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
#define PACE_US 400        /* ★06_20MHz: 프레임 페이싱(µs). 20MHz는 SPI 느려 파이프라인↑(05@50MHz 222µs보다 큼) → 400 여유. options.config PACE_US 로 튜닝 */
#endif
#ifndef THRESH_CODE
/* ★FSR(XADC) 임계 12비트(0x000~0xFFF). 실제 아날로그=0.55~1.00V 직결(분압X, analog_input_gen.ino).
 *   0x0C29≈0.76V (05 검증값). Due 시리얼에 ≥0.76V 입력시 발동. make build THRESH_CODE=.. 로 재합성없이 튜닝 */
#define THRESH_CODE 0x0C29
#endif
#ifndef FSR_RULE
/* ★FSR 규칙 = 기능 선택(rule2, src=1·prio1·en): 0x5B=움츠림(act3,1회성) / 0x5A=덕포즈(act2,홀드) / 0x79=estop(act1) / 0=비활성.
 *   DIP estop(rule0)은 항상 별도 활성. */
#define FSR_RULE   0x005C
#endif
#ifndef FLINCH_TICKS
/* ★움츠림(act3) 1회성 지속 = 클럭 틱. 10,000,000 = 0.2s@50MHz. make build FLINCH_MS=.. 로 튜닝.
 *   ★틱(ms 아님)이라 칩 클럭 바꿔도 이 값만 조정하면 됨(클럭 상대). */
#define FLINCH_TICKS 10000000
#endif
#ifndef RECOIL_RAW
/* ★현재포즈에 더해질 J5 움츠림 델타(0.001도 단위) → 칩 0x44 RECOIL_DELTA_J5.
 *   17189 = 0.30rad 를 0.001도로 환산(0.30×57295.78). make build RECOIL_RAD=.. 로 튜닝(라디안). */
#define RECOIL_RAW 17189
#endif
#ifndef REFLEX_SPEED
/* ★반사(움츠림)가 주입하는 0x151 속도율(1~100). 100=최대(안전반사는 빠르게). make build REFLEX_SPEED=.. 로 튜닝.
 *   실로봇 move_spd_rate 로 들어가 반사 이동속도 결정(estop은 정지라 무관). */
#define REFLEX_SPEED 100
#endif
#ifndef DEBOUNCE_CYC
/* ★FSR 디바운스 = 클럭 사이클. 트리거가 이만큼 지속돼야 발동(아날로그 노이즈 자가발동 방지).
 *   40000 = 2ms@20MHz. ★사이클(ms 아님)이라 클럭 상대. make build DEBOUNCE_MS=.. 로 튜닝(16비트, 최대 65535≈3.27ms@20MHz). */
#define DEBOUNCE_CYC 40000
#endif
#ifndef CLK_MHZ
#define CLK_MHZ 20         /* ★06 칩 클럭(MHz). 반사지연 사이클→µs 환산용(Task3). options.config CLK_MHZ 로 주입 */
#endif
#ifndef HYST_SHIFT
/* ★슈미트 히스테리시스 시프트: 해제임계 = thr-(thr>>HYST_SHIFT). 1=50%(빡빡)/2=25%(기본)/3=12.5%.
 *   꾹 누르는 동안 1회 락(FSR 노이즈 재발동 방지). make build HYST_SHIFT=.. 로 튜닝(재합성 없이). */
#define HYST_SHIFT 2
#endif
#define CFG_GPIO     0x41200000U    /* [7:0]SPI_DIV [8]enable [9]★소프트 반사트리거 */
#define CMD_LO_GPIO  0x41210000U
#define CMD_HI_GPIO  0x41220000U
#define CMD_ID_GPIO  0x41230000U
#define THR_GPIO     0x41240000U    /* ★FSR 임계 → 칩 thresh2 */
#define RULE_GPIO    0x41250000U    /* ★FSR 규칙(기능 선택) → 칩 rule2 */
#define FLINCH_GPIO  0x41260000U    /* ★움츠림 1회성 지속 틱 → 칩 0x46/0x47 (32비트) */
#define D5_GPIO      0x41270000U    /* ★J5 움츠림 델타 → 칩 0x44 RECOIL_DELTA_J5 */
#define RSPEED_GPIO  0x41280000U    /* ★반사 0x151 속도율 → 칩 0x48 */
#define LAT_GPIO     0x41290000U    /* ★반사지연 측정 입력 (dual): +0=트리거→결정 cyc, +8=트리거→RTS발사 cyc */
#define DEBOUNCE_GPIO 0x412A0000U   /* ★FSR 디바운스 사이클 → 칩 0x49 */
#define REFLEX_GPIO  0x412B0000U    /* ★반사 활성(reflex_active) 1비트 입력 — PC로 /reflex_active 통지용 */
#define HYST_GPIO    0x412C0000U    /* ★슈미트 히스테리시스 시프트 → 칩 0x4A + PL 레이턴시 트리거 */
#define REFLEX_PORT  5001           /* ★반사상태 UDP 포트 (PS→PC). PC의 reflex_status_node 가 수신 */
#define PS_GPIO_BASE 0xE000A000U
#define EMIO_BANK0 2
#define EMIO_BANK1 3

static XGpioPs Gpio;
static u32 g_tog = 0;
static volatile u32 g_sw_trig = 0;          /* ★소프트 반사 트리거 상태 */
static u32 g_last_li = 0;                   /* ★직전 반사지연(트리거→RTS cyc) — 변할 때만 출력 */
static struct udp_pcb *g_pcb = NULL;        /* ★UDP PCB (명령 수신 + 반사상태 송신 공용) */
static ip_addr_t g_pc_ip;                   /* ★PC(브리지) IP — 명령 패킷에서 캡처 */
static volatile u8 g_pc_known = 0;          /* PC IP 확보됨 */
static u32 g_last_ra = 0xFFFFFFFFu;         /* ★직전 reflex_active — 바뀔 때만 PC로 송신 */
static volatile u32 g_ra_edges = 0;         /* ★디버그: reflex_active 0→1 횟수 (반사가 PS까지 왔나 확인) */
static u32 g_reflex_sent = 0;               /* ★udp_sendto 호출 횟수 */
static int g_send_err = -99;                /* ★마지막 udp_sendto 반환값 (0=ERR_OK) */

static void write_cfg(void) {               /* cfg_gpio 갱신 (SPI속도 + enable + 소프트트리거) */
    Xil_Out32(CFG_GPIO, (g_sw_trig << 9) | (1u << 8) | (SPI_DIV_CODE & 0xFF));
}

/* ★전달 대상 CAN id = 브리지 명령집합 COMMAND_IDS_WITH_ESTOP 와 정확히 일치 (누락=무동작).
 *  0x471=enable 필수, 0x151=모드, 0x155~7=관절, 0x150=비상정지. 새 명령 id 면 여기 추가. */
#define NID 7
static const u32 FWD_IDS[NID] = {0x150, 0x151, 0x155, 0x156, 0x157, 0x471, 0x159};  /* ★0x159=그리퍼(GripperCtrl) */
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
    (void)arg; (void)pcb; (void)port;
    if (addr) { g_pc_ip = *addr; g_pc_known = 1; }   /* ★PC(브리지) IP 캡처 → 반사상태 회신용 */
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

/* ★반사 활성상태(reflex_active)를 PC 로 UDP 통지 → reflex_status_node 가 /reflex_active 발행 */
static void send_reflex_status(u8 active)
{
    /* ★이더넷 TX 불가(보드 GEM 송신 문제) → 시리얼로 반사상태 출력. PC의 latency_display가 읽어 토픽화 */
    xil_printf("[RFX]%u\r\n", (unsigned)active);
    g_reflex_sent++;
}

static int start_udp_bridge(void)
{
    g_pcb = udp_new();
    if (!g_pcb) { xil_printf("udp_new 실패\n\r"); return -1; }
    if (udp_bind(g_pcb, IP_ANY_TYPE, UDP_CMD_PORT) != ERR_OK) {
        xil_printf("udp_bind(%d) 실패\n\r", UDP_CMD_PORT); return -1;
    }
    udp_recv(g_pcb, udp_recv_cb, NULL);
    ip_set_option(g_pcb, SOF_BROADCAST);   /* ★브로드캐스트 허용 → 반사 UDP를 ARP 없이 송신 */
    xil_printf("[UDP] %d 바인드 — 명령 페이싱 + 0x7F0 소프트트리거\n\r", UDP_CMD_PORT);
    return 0;
}

int main(void)
{
    ip_addr_t ipaddr, netmask, gw;
    unsigned char mac[6] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };
    echo_netif = &server_netif;
    for (int i=0;i<NID;i++){ tbl_lo[i]=0; tbl_hi[i]=0; tbl_dirty[i]=0; }

    xil_printf("\n\r=== 스텝4: 정상 패스스루 + 현재포즈 J5 움츠림 (estop=DIP, recoil=소프트0x7F0/FSR) ===\n\r");

    XGpioPs_Config *gcfg = XGpioPs_LookupConfig(PS_GPIO_BASE);
    if (gcfg) XGpioPs_CfgInitialize(&Gpio, gcfg, gcfg->BaseAddr);
    write_cfg();
    Xil_Out32(THR_GPIO,    THRESH_CODE  & 0xFFFF); /* ★FSR 임계 → 칩 thresh2 */
    Xil_Out32(RULE_GPIO,   FSR_RULE     & 0xFFFF); /* ★FSR 규칙(기능 선택) → 칩 rule2 */
    Xil_Out32(FLINCH_GPIO, (u32)FLINCH_TICKS);     /* ★움츠림 1회성 지속 틱 → 칩 0x46/0x47 */
    Xil_Out32(D5_GPIO,     (RECOIL_RAW) & 0xFFFF); /* ★J5 움츠림 델타 → 칩 0x44 RECOIL_DELTA_J5 */
    Xil_Out32(RSPEED_GPIO, (REFLEX_SPEED) & 0xFFFF); /* ★반사 0x151 속도율 → 칩 0x48 */
    Xil_Out32(DEBOUNCE_GPIO, (u32)(DEBOUNCE_CYC) & 0xFFFF); /* ★FSR 디바운스 사이클 → 칩 0x49 */
    Xil_Out32(HYST_GPIO,   (u32)(HYST_SHIFT) & 0xFFFF); /* ★슈미트 히스테리시스 시프트 → 칩 0x4A + PL 레이턴시 */
    xil_printf("[CFG] SPI_DIV=%d enable=1, PACE=%dus | FSR rule=0x%02x thr=0x%03x flinch=%u틱 recoilJ5=%d(0.001도) rspeed=%d%% debounce=%ucyc hyst=%d(시프트)\n\r",
               (int)(SPI_DIV_CODE & 0xFF), PACE_US, (unsigned)(FSR_RULE & 0xFF), (unsigned)(THRESH_CODE & 0xFFF), (unsigned)FLINCH_TICKS, (int)RECOIL_RAW, (int)REFLEX_SPEED, (unsigned)(DEBOUNCE_CYC & 0xFFFF), (int)HYST_SHIFT);

    init_platform();
    IP4_ADDR(&ipaddr, 192,168,1,10); IP4_ADDR(&netmask, 255,255,255,0); IP4_ADDR(&gw, 192,168,1,1);
    lwip_init();
    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("xemac_add 실패\n\r"); return -1;
    }
    netif_set_default(echo_netif);
    netif_set_up(echo_netif);
    xil_printf("[LINK] before=%d", netif_is_link_up(echo_netif));
    netif_set_link_up(echo_netif);   /* ★링크 강제 up — JTAG부팅 PHY 지연 시 lwip이 link-down으로 TX 막는 것 회피 */
    xil_printf(" after=%d\n\r", netif_is_link_up(echo_netif));
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

        {   /* ★반사지연: 새 측정(트리거→RTS 변화) 시 즉시 시리얼 출력. cyc→시간 = ÷CLK_MHZ */
            u32 li = Xil_In32(LAT_GPIO + 8);
            if (li != g_last_li) {
                g_last_li = li;
                u32 ld = Xil_In32(LAT_GPIO);
                if (li > 0)
                    xil_printf("[LAT] ★반사지연(트리거 기준): 결정 %u cyc(%u us) -> CAN발사(RTS) %u cyc(%u us). 1cyc=%u ns @%u MHz, 버스도착=+~120us\n\r",
                               ld, ld/CLK_MHZ, li, li/CLK_MHZ, 1000u/CLK_MHZ, CLK_MHZ);
            }
        }

        {   /* ★반사 활성상태(reflex_active) 변화 → PC 로 UDP 통지 (/reflex_active) */
            u32 ra = Xil_In32(REFLEX_GPIO) & 1u;
            if (ra != g_last_ra) { if (ra) g_ra_edges++; g_last_ra = ra; send_reflex_status((u8)ra); }
        }

        if (++spin >= (u32)(1000000u / PACE_US)) {
            spin = 0;
            u32 o0 = XGpioPs_Read(&Gpio, EMIO_BANK0);
            u32 o1 = XGpioPs_Read(&Gpio, EMIO_BANK1);
            xil_printf("[MCP] CANSTAT=0x%02x CNF=%02x/%02x/%02x EFLG=0x%02x TEC=%d | trig=%d udpRX=%d sent=%d ★ra_edges=%u rsent=%u serr=%d\n\r",
                       (o0>>24)&0xFF,(o0>>16)&0xFF,(o0>>8)&0xFF,o0&0xFF,
                       (o1>>24)&0xFF,(o1>>16)&0xFF,(int)g_sw_trig,(int)g_udp_rx,(int)g_sent,
                       (unsigned)g_ra_edges,(unsigned)g_reflex_sent,g_send_err);
        }
    }
    cleanup_platform();
    return 0;
}
