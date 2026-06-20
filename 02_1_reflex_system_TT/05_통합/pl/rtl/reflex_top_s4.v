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
    parameter integer SPI_HALF    = 8,
    parameter integer SEND_DIV    = 50000,    // ★반사 송신 주기(1ms). 65536 미만이라 16비트 카운터도 안전(divcnt는 32비트로 고침)
    parameter integer PROBE_DIV   = 50000,
    parameter integer SAMPLE_DIV  = 50000,
    parameter integer RESET_DELAY = 500000
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [15:0] cfg_in,             // [7:0]SPI_DIV [8]enable [9]★소프트 pose 트리거
    input  wire [31:0] cmd_lo,
    input  wire [31:0] cmd_hi,
    input  wire [31:0] cmd_id,             // [31]토글 [10:0]id
    input  wire        dip,                // ★물리 DIP estop 트리거(SW0)
    // ── ★XADC 트리거 (xadc_val=xadc_reader, thr_in/rule_in=PS GPIO). 임계 1개·규칙 1개(FSR 기능 선택) ──
    input  wire [15:0] xadc_val,           // XADC 현재값(12비트) — BD 의 xadc_reader 출력
    input  wire [15:0] thr_in,             // FSR 임계 (PS GPIO, 기본 0x0C29≈0.76V)
    input  wire [15:0] rule_in,            // ★FSR 규칙 선택 (PS GPIO: 0x79 estop / 0x5A 덕포즈 / 0x5B 움찔)
    input  wire [31:0] flinch_in,          // ★움찔(act3) 1회성 지속 틱 (PS GPIO, 클럭상대)
    input  wire [15:0] d5_in,          // ★J5 움츠림 델타 (PS GPIO, RECOIL_RAD→0.001도, 칩 0x44)
    input  wire [15:0] rspeed_in,          // ★반사 0x151 속도율 (PS GPIO, 1~100, 기본 100=최대)
    output wire        reflex_active,       // ★반사 활성(gate_active) — 관측/상태
    output wire [31:0] obs0,
    output wire [31:0] obs1,
    output wire        configured,
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
    wire [7:0] chip_ui_in  = {1'b1, 3'b000, mcp_so, mcp_int, cfg_in[9], dip};
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
        .xadc_val(xadc_val), .thr_in(thr_in), .rule_in(rule_in), .flinch_in(flinch_in), .d5_in(d5_in), .rspeed_in(rspeed_in),
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

    wire _unused = &{1'b0, uo_out[7:6], uo_out[4:0], chip_uio_out[7], chip_uio_out[2:0], chip_uio_oe};
endmodule
