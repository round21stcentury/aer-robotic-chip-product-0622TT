`timescale 1ns / 1ps
//============================================================================
// reflex_top_s4 — 스텝4 PL 최상위 (★최종: 현재포즈 움츠림). RX 는 칩이 MCP 로 직접 수신.
//----------------------------------------------------------------------------
//  칩(tt_um_reflex_s4) + chip_feeder_s4(설정·델타·XADC·되읽기) + spi_master.
//  PS↔PL GPIO: cfg(SPI속도/enable), thr(FSR임계), rule(FSR규칙=움츠림), delta(J2·J3), obs(관측).
//  현재포즈·도달은 칩이 MCP2515 RX 로 버스에서 직접 받음(PL 안 거침).
//============================================================================
module reflex_top_s4 #(
    parameter integer SPI_HALF    = 8,
    parameter integer SEND_DIV    = 100000,
    parameter integer PROBE_DIV   = 50000,
    parameter integer SAMPLE_DIV  = 50000,
    parameter integer RESET_DELAY = 500000
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        dip,
    input  wire [15:0] cfg_in,
    input  wire [15:0] thr_in,
    input  wire [15:0] rule_in,
    input  wire [15:0] d2_in,              // 움츠림 델타 J2
    input  wire [15:0] d3_in,              // 움츠림 델타 J3
    input  wire [15:0] xadc_val,
    output wire [31:0] obs0,
    output wire [31:0] obs1,
    output wire        reflex_active,
    output wire        configured,
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
    wire [7:0] chip_ui_in  = {1'b1, 3'b000, mcp_so, mcp_int, 1'b0, dip};
    wire [7:0] chip_uio_in = {5'b00000, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s4 #(.SEND_DIV(SEND_DIV), .PROBE_DIV(PROBE_DIV), .RESET_DELAY(RESET_DELAY)) u_chip (
        .ui_in(chip_ui_in), .uo_out(uo_out),
        .uio_in(chip_uio_in), .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
        .ena(1'b1), .clk(aclk), .rst_n(aresetn)
    );
    assign chip_miso     = chip_uio_out[3];
    assign mcp_sck       = chip_uio_out[4];
    assign mcp_si        = chip_uio_out[5];
    assign mcp_cs        = chip_uio_out[6];
    assign reflex_active = uo_out[5];

    chip_feeder_s4 #(.SAMPLE_DIV(SAMPLE_DIV)) u_feed (
        .clk(aclk), .rst_n(aresetn), .cfg_in(cfg_in), .thr_in(thr_in), .rule_in(rule_in),
        .d2_in(d2_in), .d3_in(d3_in), .xadc_val(xadc_val),
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
