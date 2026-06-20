`timescale 1ns / 1ps
//============================================================================
// tt_um_reflex_s1 — 스텝1 칩 최상위 (★정상명령 패스스루 + 먹스 골격, 반사 없음)
//----------------------------------------------------------------------------
//  목표(정정): "PC 로봇 정상명령이 FPGA(PS→PL→SPI→칩→MCP)를 타고 패스스루 되는가" 검증.
//  데이터 흐름:
//    PS(이더넷 lwIP) → PL(chip_feeder) → SPI → 칩 spi_slave_full 정상레지스터(0x50~0x55)
//    → mcp_tx_mux(게이트=reflex_active, 스텝1은 0 → 정상 통과) → mcp_tx_send → MCP → CAN.
//  ★먹스를 스텝1부터 넣어, 스텝2~4 에서 reflex_active 만 올리면 정상명령을 끊고 반사 주입.
//  + MCP 되읽기 관측(mcp_probe) + PS 프로그래밍 SPI 속도. 반사 트리거(DIP/FSR)는 스텝2~4.
//  핀맵: 04 v5 호환.
//============================================================================
module tt_um_reflex_s1 #(
    parameter integer PROBE_DIV   = 50000,
    parameter integer RESET_DELAY = 500000   // MCP 리셋 후 안정화 지연(클럭). 합성=10ms
)(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire mcp_int    = ui_in[2];
    wire m_miso     = ui_in[3];
    wire arm_enable = ui_in[7];

    // ── SPI 슬레이브(PL 마스터) ──
    wire        s_sclk = uio_in[0];
    wire        s_mosi = uio_in[1];
    wire        s_csn  = uio_in[2];
    wire        s_miso, s_miso_oe;
    wire [15:0] control, spi_div;
    // 정상 프레임(PL 적재)
    wire [10:0] norm_id; wire [63:0] norm_data; wire norm_send;
    // (반사 설정 레지스터는 스텝1 미사용 — 슬레이브 출력만 받고 안 씀)
    wire [15:0] rule0,rule1,rule2,rule3, thresh0,thresh1,thresh2,thresh3, xadc_val;
    wire [15:0] recoil_d1,recoil_d2,recoil_d3,recoil_d4,recoil_d5,recoil_d6;

    // ── MCP 되읽기 ──
    wire [7:0]  p_canstat,p_canctrl,p_cnf1,p_cnf2,p_cnf3,p_eflg,p_tec,p_rec,p_canintf;

    // ── 드라이버/중재기 ──
    wire        ic_req,ic_grant,ic_done,ic_active,init_done; wire [2:0] ic_op; wire [6:0] ic_addr; wire [7:0] ic_wdata,ic_wmask; wire [3:0] ic_step;
    wire        tx_req,tx_grant,tx_done_a,tx_active,tx_frame_done; wire [2:0] tx_op; wire [6:0] tx_addr; wire [7:0] tx_wdata,tx_wmask;
    wire        pb_req,pb_grant,pb_done,pb_active,probe_valid; wire [2:0] pb_op; wire [6:0] pb_addr; wire [7:0] pb_wdata,pb_wmask;
    wire        drv_req; wire [2:0] drv_op; wire [6:0] drv_addr; wire [7:0] drv_wdata,drv_wmask;
    wire [7:0]  arb_rdata,drv_rdata; wire drv_busy,drv_done;
    wire        m_sclk,m_mosi,m_csn;

    // ── 먹스 (스텝1: 반사 없음 → gate=0, 반사입력 0) ──
    wire        reflex_active = 1'b0;
    wire [10:0] sel_id; wire [3:0] sel_dlc; wire [63:0] sel_data; wire sel_send;

    wire [15:0] status = {12'd0, init_done, reflex_active, 2'b00};

    reg init_started, init_start;
    always @(posedge clk) begin
        if (!rst_n) begin init_started<=0; init_start<=0; end
        else begin init_start<=1'b0; if (!init_started) begin init_start<=1'b1; init_started<=1'b1; end end
    end

    spi_slave_full #(.VERSION(16'h0511)) u_slv (
        .clk(clk), .rst_n(rst_n), .sclk(s_sclk), .mosi(s_mosi), .csn(s_csn),
        .miso(s_miso), .miso_oe(s_miso_oe),
        .control(control), .spi_div(spi_div),
        .rule0(rule0), .rule1(rule1), .rule2(rule2), .rule3(rule3),
        .thresh0(thresh0), .thresh1(thresh1), .thresh2(thresh2), .thresh3(thresh3), .xadc_val(xadc_val),
        .recoil_d1(recoil_d1), .recoil_d2(recoil_d2), .recoil_d3(recoil_d3),
        .recoil_d4(recoil_d4), .recoil_d5(recoil_d5), .recoil_d6(recoil_d6),
        .norm_id(norm_id), .norm_data(norm_data), .norm_send(norm_send),
        .status(status),
        .canstat(p_canstat), .canctrl(p_canctrl), .cnf1(p_cnf1), .cnf2(p_cnf2), .cnf3(p_cnf3),
        .eflg(p_eflg), .tec(p_tec), .rec(p_rec), .canintf(p_canintf)
    );

    // ★먹스: 정상(슬레이브) vs 반사(없음). 스텝1은 정상 통과.
    mcp_tx_mux u_mux (
        .reflex_active(reflex_active),
        .normal_id(norm_id), .normal_dlc(4'd8), .normal_data(norm_data), .normal_send(norm_send),
        .reflex_id(11'd0), .reflex_dlc(4'd0), .reflex_data(64'd0), .reflex_send(1'b0),
        .sel_id(sel_id), .sel_dlc(sel_dlc), .sel_data(sel_data), .sel_send(sel_send)
    );

    mcp_init #(.RESET_DELAY(RESET_DELAY)) u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start), .grant(ic_grant), .seq_active(ic_active),
        .req(ic_req), .op(ic_op), .addr(ic_addr), .wdata(ic_wdata), .wmask(ic_wmask),
        .rdata(arb_rdata), .busy(drv_busy), .done(ic_done), .init_done(init_done), .step(ic_step)
    );

    mcp_tx_send u_tx (
        .clk(clk), .rst_n(rst_n),
        .send(sel_send & init_done), .id(sel_id), .dlc(sel_dlc), .data(sel_data),
        .grant(tx_grant), .seq_active(tx_active),
        .req(tx_req), .op(tx_op), .addr(tx_addr), .wdata(tx_wdata), .wmask(tx_wmask),
        .rdata(arb_rdata), .busy(drv_busy), .done(tx_done_a), .tx_done(tx_frame_done)
    );

    mcp_probe #(.PROBE_DIV(PROBE_DIV)) u_probe (
        .clk(clk), .rst_n(rst_n), .init_done(init_done), .grant(pb_grant), .seq_active(pb_active),
        .req(pb_req), .op(pb_op), .addr(pb_addr), .wdata(pb_wdata), .wmask(pb_wmask),
        .rdata(arb_rdata), .busy(drv_busy), .done(pb_done),
        .canstat(p_canstat), .canctrl(p_canctrl), .cnf1(p_cnf1), .cnf2(p_cnf2), .cnf3(p_cnf3),
        .eflg(p_eflg), .tec(p_tec), .rec(p_rec), .canintf(p_canintf), .probe_valid(probe_valid)
    );

    mcp_arb4 u_arb (
        .clk(clk), .rst_n(rst_n),
        .c0_active(ic_active), .c0_req(ic_req), .c0_op(ic_op), .c0_addr(ic_addr), .c0_wdata(ic_wdata), .c0_wmask(ic_wmask), .c0_grant(ic_grant), .c0_done(ic_done),
        .c1_active(tx_active), .c1_req(tx_req), .c1_op(tx_op), .c1_addr(tx_addr), .c1_wdata(tx_wdata), .c1_wmask(tx_wmask), .c1_grant(tx_grant), .c1_done(tx_done_a),
        .c2_active(1'b0), .c2_req(1'b0), .c2_op(3'd0), .c2_addr(7'd0), .c2_wdata(8'd0), .c2_wmask(8'd0), .c2_grant(), .c2_done(),
        .c3_active(pb_active), .c3_req(pb_req), .c3_op(pb_op), .c3_addr(pb_addr), .c3_wdata(pb_wdata), .c3_wmask(pb_wmask), .c3_grant(pb_grant), .c3_done(pb_done),
        .rdata(arb_rdata),
        .req(drv_req), .op(drv_op), .addr(drv_addr), .wdata(drv_wdata), .wmask(drv_wmask),
        .drv_rdata(drv_rdata), .drv_busy(drv_busy), .drv_done(drv_done)
    );

    spi_master_mcp_v2 u_drv (
        .clk(clk), .rst_n(rst_n), .half_div(spi_div[7:0]),
        .req(drv_req), .op(drv_op), .addr(drv_addr), .wdata(drv_wdata), .wmask(drv_wmask),
        .rdata(drv_rdata), .busy(drv_busy), .done(drv_done),
        .m_sclk(m_sclk), .m_mosi(m_mosi), .m_csn(m_csn), .m_miso(m_miso)
    );

    wire mcp_rst = 1'b1;
    assign uo_out  = {init_done, mcp_rst, reflex_active, 3'b000, 1'b0, init_done};
    assign uio_out = {1'b0, m_csn, m_mosi, m_sclk, s_miso, 3'b000};
    assign uio_oe  = {1'b0, 1'b1, 1'b1, 1'b1, s_miso_oe, 3'b000};

    wire _unused = &{1'b0, ena, ui_in[6:4], ui_in[1:0], uio_in[7:3], ic_step, tx_frame_done, probe_valid, drv_req, sel_dlc,
                     rule0,rule1,rule2,rule3, thresh0,thresh1,thresh2,thresh3, xadc_val,
                     recoil_d1,recoil_d2,recoil_d3,recoil_d4,recoil_d5,recoil_d6, arm_enable};
endmodule
