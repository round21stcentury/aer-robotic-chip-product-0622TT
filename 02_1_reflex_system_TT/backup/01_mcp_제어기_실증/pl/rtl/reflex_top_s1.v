`timescale 1ns / 1ps
//============================================================================
// reflex_top_s1 — 스텝1 PL 최상위: 칩(tt_um_reflex_s1)을 PL에 올리고 MCP 핀을 밖으로
//----------------------------------------------------------------------------
//  HIL 토폴로지의 PL 부분: PS ─AXI GPIO─ PL(이 모듈) ─SPI─ 칩 ─SPI─ MCP2515.
//  PL 이 하는 일:
//   - 칩을 PL 패브릭에 올림 (DIP=직접 핀, arm=1).
//   - chip_feeder_s1 + spi_master 가 칩 SPI 슬레이브를 프로그래밍(SPI속도·enable)
//     + MCP 되읽기 값을 주기적으로 읽어 PS GPIO(입력)에 노출.
//   - 칩의 MCP2515 SPI 마스터 핀(SCK/SI/SO/CS) + INT 를 외부 FPGA 핀으로 (Pmod JE).
//  ★MCP 하드웨어 RST 핀 없음 — 칩 mcp_init 이 SPI 소프트웨어 리셋(0xC0).
//============================================================================
module reflex_top_s1 #(
    parameter integer SPI_HALF   = 8,        // PL→칩 SPI (칩 슬레이브 오버샘플 위해 ≥6)
    parameter integer SEND_DIV    = 100000,  // 0x150 송신 주기(클럭)
    parameter integer PROBE_DIV   = 50000,   // 칩 내부 MCP 되읽기 주기
    parameter integer SAMPLE_DIV  = 50000,   // PL→PS 노출 갱신 주기
    parameter integer RESET_DELAY = 500000   // MCP 리셋 후 안정화 지연(클럭)
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        dip,                  // DIP 비상정지 (직접 핀)
    input  wire [15:0] cfg_in,               // PS AXI GPIO: [7:0]=SPI_DIV, [8]=enable
    output wire [31:0] obs0,                 // PS AXI GPIO(입력): {CANSTAT,CNF1,CNF2,CNF3}
    output wire [31:0] obs1,                 // PS AXI GPIO(입력): {EFLG,TEC,REC,CANINTF}
    output wire        reflex_active,        // 게이트(상태/LED)
    output wire        configured,           // 칩 설정 끝
    // ── MCP2515 외부 핀 (→ 트랜시버 모듈) ──
    output wire        mcp_sck,              // JE1
    output wire        mcp_si,               // JE2
    input  wire        mcp_so,               // JE3
    output wire        mcp_cs,               // JE4
    input  wire        mcp_int               // JE7
);
    wire        m_start, m_rw, m_busy, m_done;
    wire [6:0]  m_addr;
    wire [15:0] m_wdata, m_rdata;
    wire        pls_sclk, pls_mosi, pls_csn, chip_miso;

    wire [7:0] uo_out, chip_uio_out, chip_uio_oe;
    //  ui_in: [7]arm=1 [3]mcp_so(=m_miso) [2]mcp_int [0]dip
    wire [7:0] chip_ui_in  = {1'b1, 3'b000, mcp_so, mcp_int, 1'b0, dip};
    //  uio_in(슬레이브): [2]csn [1]mosi [0]sclk
    wire [7:0] chip_uio_in = {5'b00000, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s1 #(.SEND_DIV(SEND_DIV), .PROBE_DIV(PROBE_DIV), .RESET_DELAY(RESET_DELAY)) u_chip (
        .ui_in(chip_ui_in), .uo_out(uo_out),
        .uio_in(chip_uio_in), .uio_out(chip_uio_out), .uio_oe(chip_uio_oe),
        .ena(1'b1), .clk(aclk), .rst_n(aresetn)
    );
    assign chip_miso     = chip_uio_out[3];
    assign mcp_sck       = chip_uio_out[4];
    assign mcp_si        = chip_uio_out[5];
    assign mcp_cs        = chip_uio_out[6];
    assign reflex_active = uo_out[5];

    chip_feeder_s1 #(.SAMPLE_DIV(SAMPLE_DIV)) u_feed (
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
