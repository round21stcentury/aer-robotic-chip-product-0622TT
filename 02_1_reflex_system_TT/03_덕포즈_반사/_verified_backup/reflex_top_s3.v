`timescale 1ns / 1ps
//============================================================================
// reflex_top_s3 — 스텝3 PL 최상위 (★정상명령 패스스루 + estop + 홈포즈 반사)
//----------------------------------------------------------------------------
//  스텝2(reflex_top_s2) 와 동일 패스스루 경로 + ★반사 트리거 2종을 칩에 전달★.
//   PS(이더넷) → chip_feeder_s3 → SPI → 칩(tt_um_reflex_s3) → 먹스 → MCP → 로봇.
//   ★estop 트리거 = 물리 DIP(SW0) → 칩 ui_in[0]=danger[0] → rule0(act1=estop).
//   ★pose  트리거 = 소프트(cfg_in[9], PS 제어 UDP 0x7F0) → 칩 ui_in[1]=danger[1] → rule1(act2=pose).
//      (물리 FSR(XADC) 는 향후 — 지금은 소프트 트리거로 포즈 발동.)
//  + cfg(SPI속도/enable/소프트포즈트리거), EMIO 관측. MCP 핀 외부(JE).
//============================================================================
module reflex_top_s3 #(
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

    tt_um_reflex_s3 #(.SEND_DIV(SEND_DIV), .PROBE_DIV(PROBE_DIV), .RESET_DELAY(RESET_DELAY)) u_chip (
        .ui_in(chip_ui_in), .uo_out(uo_out),
        .uio_in(chip_uio_in), .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
        .ena(1'b1), .clk(aclk), .rst_n(aresetn)
    );
    assign chip_miso = chip_uio_out[3];
    assign mcp_sck   = chip_uio_out[4];
    assign mcp_si    = chip_uio_out[5];
    assign mcp_cs    = chip_uio_out[6];

    chip_feeder_s3 #(.SAMPLE_DIV(SAMPLE_DIV)) u_feed (
        .clk(aclk), .rst_n(aresetn), .cfg_in(cfg_in),
        .cmd_lo(cmd_lo), .cmd_hi(cmd_hi), .cmd_id(cmd_id),
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

    wire _unused = &{1'b0, uo_out, chip_uio_out[7], chip_uio_out[2:0], chip_uio_oe};
endmodule
