`timescale 1ns / 1ps
//============================================================================
// reflex_top_s2 — 스텝2 PL 최상위 (e-stop 반사). reflex_top_s1 과 동일 골격, 칩만 s2.
//----------------------------------------------------------------------------
//  칩(tt_um_reflex_s2: reflex_core 로 비상정지 결정) + chip_feeder_s2(설정·되읽기) + spi_master.
//  PS↔PL: cfg_gpio(out 16b)=[7:0]SPI_DIV [8]enable, obs_gpio(in 듀얼32)=MCP 되읽기.
//  MCP SPI 핀 외부(JE). DIP=직접 핀 → 칩 reflex_core.
//============================================================================
module reflex_top_s2 #(
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

    tt_um_reflex_s2 #(.SEND_DIV(SEND_DIV), .PROBE_DIV(PROBE_DIV), .RESET_DELAY(RESET_DELAY)) u_chip (
        .ui_in(chip_ui_in), .uo_out(uo_out),
        .uio_in(chip_uio_in), .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
        .ena(1'b1), .clk(aclk), .rst_n(aresetn)
    );
    assign chip_miso     = chip_uio_out[3];
    assign mcp_sck       = chip_uio_out[4];
    assign mcp_si        = chip_uio_out[5];
    assign mcp_cs        = chip_uio_out[6];
    assign reflex_active = uo_out[5];

    chip_feeder_s2 #(.SAMPLE_DIV(SAMPLE_DIV)) u_feed (
        .clk(aclk), .rst_n(aresetn), .cfg_in(cfg_in),
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
