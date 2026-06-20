`timescale 1ns / 1ps
//============================================================================
// reflex_top_s4 — 스텝4 PL 최상위 (★정상명령 패스스루 + estop + 현재포즈 움츠림)
//----------------------------------------------------------------------------
//  스텝2(reflex_top_s2) 와 동일 패스스루 경로 + ★반사 트리거 2종을 칩에 전달★.
//   PS(이더넷) → chip_feeder_s4 → SPI → 칩(tt_um_reflex_s4) → 먹스 → MCP → 로봇.
//   ★estop 트리거 = 물리 DIP(SW0) → 칩 ui_in[0]=danger[0] → rule0(act1=estop).
//   ★pose  트리거(2종, 둘 다 홈포즈):
//      ① 소프트 = cfg_in[9](PS UDP 0x7F0) → 칩 ui_in[1]=danger[1] → rule1(act2,src=0).
//      ② ★FSR(XADC) = xadc_val>=thr_in → 칩 rule2(act2,src=1). chip_feeder_s4 가 rule_in/thr_in/xadc_val 적재.
//         (xadc_val = BD 의 xadc_reader(VAUX14) 출력. thr_in/rule_in = PS GPIO, 런타임 튜닝.)
//  + cfg(SPI속도/enable/소프트포즈트리거), EMIO 관측. MCP 핀 외부(JE). XADC 입력 JXADC(N15/N16).
//============================================================================
module reflex_top_s4 #(
    parameter integer SPI_HALF    = 4,        // ★20MHz: PL↔칩 SPI = 20/(2×4)=2.5MHz (05@50MHz는 8=3.125MHz). 06_로봇실증용
    parameter integer SEND_DIV    = 20000,    // ★반사 송신 주기 1ms@20MHz (05@50MHz는 50000). 클럭상대 스케일. <65536 안전
    parameter integer PROBE_DIV   = 20000,    // ★되읽기 주기 1ms@20MHz
    parameter integer SAMPLE_DIV  = 20000,    // ★XADC 샘플 주기 1ms@20MHz
    parameter integer RESET_DELAY = 200000    // ★MCP 발진안정 10ms@20MHz (05@50MHz는 500000)
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [15:0] cfg_in,             // [7:0]SPI_DIV [8]enable [9]★소프트 pose 트리거
    input  wire [31:0] cmd_lo,
    input  wire [31:0] cmd_hi,
    input  wire [31:0] cmd_id,             // [31]토글 [10:0]id
    input  wire        dip,                // ★물리 DIP estop 트리거(SW0) → 칩 danger[0] → rule0(freeze)
    input  wire        dip2,               // ★물리 DIP 덕포즈복귀 트리거(SW1) → 칩 danger[3] → rule3(덕포즈·레벨홀드)
    // ── ★XADC 트리거 (xadc_val=xadc_reader, thr_in/rule_in=PS GPIO). 임계 1개·규칙 1개(FSR 기능 선택) ──
    input  wire [15:0] xadc_val,           // XADC 현재값(12비트) — BD 의 xadc_reader 출력
    input  wire [15:0] thr_in,             // FSR 임계 (PS GPIO, 기본 0x0C29≈0.76V)
    input  wire [15:0] rule_in,            // ★FSR 규칙 선택 (PS GPIO: 0x79 estop / 0x5A 덕포즈 / 0x5B 움찔)
    input  wire [31:0] flinch_in,          // ★움찔(act3) 1회성 지속 틱 (PS GPIO, 클럭상대)
    input  wire [15:0] d5_in,          // ★J5 움츠림 델타 (PS GPIO, RECOIL_RAD→0.001도, 칩 0x44)
    input  wire [15:0] rspeed_in,          // ★반사 0x151 속도율 (PS GPIO, 1~100, 기본 100=최대)
    input  wire [15:0] debounce_in,        // ★FSR 디바운스 사이클 (PS GPIO, 기본 40000=2ms@20MHz). 칩 0x49
    input  wire [15:0] hyst_in,            // ★슈미트 히스테리시스 시프트 (PS GPIO, 기본 2=25%). 칩 0x4A + PL 레이턴시 트리거
    output wire        reflex_active,       // ★반사 활성(gate_active) — 관측/상태
    output wire [31:0] obs0,
    output wire [31:0] obs1,
    output wire        configured,
    output wire [31:0] lat_decision,   // ★반사지연(06): 트리거→reflex_active 사이클(디바운스 결정시간)
    output wire [31:0] lat_issued,     // ★반사지연(06): 트리거→첫 RTS 사이클(=CAN 프레임 발사). PS가 ÷CLK_MHZ→µs
    // ── MCP2515 외부 핀 ──
    output wire        mcp_sck,
    output wire        mcp_si,
    input  wire        mcp_so,
    output wire        mcp_cs,
    input  wire        mcp_int
);
    wire        m_start, m_rw, m_busy, m_done;
    wire [6:0]  m_addr;
    wire [15:0] m_wdata, m_rdata;
    wire        pls_sclk, pls_mosi, pls_csn, chip_miso;

    wire [7:0] uo_out, chip_uio_out, chip_uio_oe;
    //  ui_in: [7]arm=1 [3]mcp_so [2]mcp_int [1]danger1=pose(cfg[9]) [0]dip=estop(SW0)
    wire [7:0] chip_ui_in  = {1'b1, 2'b00, dip2, mcp_so, mcp_int, cfg_in[9], dip};  // ★[4]=dip2(덕포즈)
    wire [7:0] chip_uio_in = {5'b00000, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s4 #(.SEND_DIV(SEND_DIV), .PROBE_DIV(PROBE_DIV), .RESET_DELAY(RESET_DELAY)) u_chip (
        .ui_in(chip_ui_in), .uo_out(uo_out),
        .uio_in(chip_uio_in), .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
        .ena(1'b1), .clk(aclk), .rst_n(aresetn)
    );
    assign chip_miso = chip_uio_out[3];
    assign mcp_sck   = chip_uio_out[4];
    assign mcp_si    = chip_uio_out[5];
    assign mcp_cs    = chip_uio_out[6];
    assign reflex_active = uo_out[5];   // status[4]=gate_active → uo_out[5]

    chip_feeder_s4 #(.SAMPLE_DIV(SAMPLE_DIV)) u_feed (
        .clk(aclk), .rst_n(aresetn), .cfg_in(cfg_in),
        .cmd_lo(cmd_lo), .cmd_hi(cmd_hi), .cmd_id(cmd_id),
        .xadc_val(xadc_val), .thr_in(thr_in), .rule_in(rule_in), .flinch_in(flinch_in), .d5_in(d5_in), .rspeed_in(rspeed_in), .debounce_in(debounce_in), .hyst_in(hyst_in),
        .m_start(m_start), .m_rw(m_rw), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_busy(m_busy), .m_done(m_done), .m_rdata(m_rdata),
        .obs0(obs0), .obs1(obs1), .configured(configured)
    );

    spi_master #(.HALF(SPI_HALF)) u_spim (
        .clk(aclk), .rst_n(aresetn),
        .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_miso)
    );

    // ════════════════════════════════════════════════════════════════════
    // ★반사 지연 측정 (06_로봇실증용) — 트리거 → reflex_active(결정) → 첫 RTS(=CAN 프레임 발사)
    //   칩→MCP SPI(chip_uio_out[6]=cs,[4]=sck,[5]=mosi)는 칩이 aclk 동기 구동 → 수동 스니핑.
    //   MCP RTS 명령(0x80~0x87)=TXB 프레임 전송요청 = "반사 프레임이 MCP 로 발사된 순간".
    //   결과(클럭 사이클) → lat_gpio 로 PS 가 읽어 ÷CLK_MHZ 해 µs. (버스 실송신 +~120µs@1Mbps 8B)
    //   ※수동 관측뿐 → 칩(TT 설계) 동작 무영향.
    wire mcp_sck_o = chip_uio_out[4];
    wire mcp_si_o  = chip_uio_out[5];
    wire mcp_cs_o  = chip_uio_out[6];
    reg  sck_d; reg [7:0] cmd_sh; reg [3:0] cmd_bits; reg cmd_first; reg rts_pulse;
    always @(posedge aclk) begin
        if (!aresetn) begin sck_d<=1'b0; cmd_sh<=8'd0; cmd_bits<=4'd0; cmd_first<=1'b1; rts_pulse<=1'b0; end
        else begin
            sck_d <= mcp_sck_o; rts_pulse <= 1'b0;
            if (mcp_cs_o) begin cmd_bits<=4'd0; cmd_first<=1'b1; end           // CS high: 트랜잭션 리셋
            else if (~sck_d & mcp_sck_o) begin                                // SCK 상승(MCP 샘플엣지, MSB first)
                cmd_sh <= {cmd_sh[6:0], mcp_si_o};
                if (cmd_bits == 4'd7) begin
                    cmd_bits <= 4'd0;
                    if (cmd_first) begin
                        cmd_first <= 1'b0;
                        if ((({cmd_sh[6:0], mcp_si_o}) & 8'hF8) == 8'h80) rts_pulse <= 1'b1;  // 첫바이트=RTS 0x8x
                    end
                end else cmd_bits <= cmd_bits + 4'd1;
            end
        end
    end
    reg  trig_d, ra_d; reg [31:0] lat_cyc, lat_dec_r, lat_iss_r; reg lat_run, got_dec, got_iss;
    // ★07: 레이턴시 트리거의 FSR 부분도 슈미트 히스테리시스 (칩 reflex_core 와 동일 75% 해제점).
    //   06: 생 비교라 FSR 노이즈가 임계 들락날락 → 매 재교차마다 lat 카운터 재시작 → 123µs 같은 쓰레기값.
    //   07: 한번 켜지면 thr×0.75 밑으로 떨어져야 꺼짐 → 한 번 누름 = 한 번 측정 = 깨끗한 지연.
    reg  xadc_hi_lat;
    wire [3:0]  sh_lat     = (hyst_in[3:0] == 4'd0) ? 4'd1 : hyst_in[3:0];   // 칩과 동일 클램프(락방지)
    wire [15:0] rel_thr_lat = thr_in - (thr_in >> sh_lat);
    always @(posedge aclk) begin
        if (!aresetn)                     xadc_hi_lat <= 1'b0;
        else if (xadc_val >= thr_in)      xadc_hi_lat <= 1'b1;
        else if (xadc_val <  rel_thr_lat) xadc_hi_lat <= 1'b0;
    end
    wire trig_raw = dip | cfg_in[9] | xadc_hi_lat;            // estop/소프트/★FSR(슈미트) 어느 트리거든 시작
    wire ra_now   = uo_out[5];                                 // reflex_active(gate_active)
    always @(posedge aclk) begin
        if (!aresetn) begin trig_d<=1'b0; ra_d<=1'b0; lat_cyc<=32'd0; lat_dec_r<=32'd0; lat_iss_r<=32'd0; lat_run<=1'b0; got_dec<=1'b0; got_iss<=1'b0; end
        else begin
            trig_d <= trig_raw; ra_d <= ra_now;
            if (trig_raw & ~trig_d & ~lat_run) begin lat_run<=1'b1; lat_cyc<=32'd0; got_dec<=1'b0; got_iss<=1'b0; end  // 트리거 상승→시작·재무장
            else if (lat_run) begin
                lat_cyc <= lat_cyc + 32'd1;
                if (ra_now & ~ra_d & ~got_dec) begin got_dec<=1'b1; lat_dec_r<=lat_cyc; end                  // 결정(reflex_active 상승)
                if (rts_pulse & ra_now & ~got_iss) begin got_iss<=1'b1; lat_iss_r<=lat_cyc; lat_run<=1'b0; end // 첫 RTS(발사)→래치·종료
                else if (lat_cyc >= 32'd200000) lat_run<=1'b0;                                                // ★10ms 상한(실반사 ~2ms): 결정만 나고 발사(RTS) 없는 가짜트리거도 리셋 → 9만µs 쓰레기값 방지
            end
        end
    end
    assign lat_decision = lat_dec_r;
    assign lat_issued   = lat_iss_r;

    wire _unused = &{1'b0, uo_out[7:6], uo_out[4:0], chip_uio_out[7], chip_uio_out[2:0], chip_uio_oe};
endmodule
