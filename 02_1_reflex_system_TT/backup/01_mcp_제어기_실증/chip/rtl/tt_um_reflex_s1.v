`timescale 1ns / 1ps
//============================================================================
// tt_um_reflex_s1 — 스텝1 칩 최상위 (MCP 제어기 실증, 최소 격리)
//----------------------------------------------------------------------------
//  목표: "칩이 MCP2515 를 SPI 로 몰아 ① 제대로 설정하고 ② 실제 버스에 0x150 을 쏘는가"
//        를 ★가장 단순한 경로★ 로만 검증 + ★MCP 되읽기로 관측★.
//  블록: spi_slave_s1(설정·되읽기 노출) + mcp_init(설정) + estop_tx_src(DIP 트리거)
//        + mcp_tx_send(프레임 적재·RTS) + mcp_probe(MCP 되읽기) + mcp_arb4(중재)
//        + spi_master_mcp_v2(★런타임 속도 드라이버).
//  ★없음: reflex_core·FSR·움츠림·RX·정상명령먹스 (스텝2~4에서 하나씩 추가).
//
//  핀맵 (04 v5 와 호환 — HILS/보드 핀 그대로):
//    ui_in[0]=dip(DIP) [2]=mcp_int [3]=m_miso [7]=arm_enable      (1,4~6 여유)
//    uo_out[0]=valid(init_done) [1]=fire(gate) [4:2]=action_id [5]=gate [6]=mcp_rst [7]=heartbeat
//    uio[0]=s_sclk(in) [1]=s_mosi(in) [2]=s_csn(in) [3]=s_miso(out)
//        [4]=m_sclk(out) [5]=m_mosi(out) [6]=m_csn(out) [7]=여유
//============================================================================
module tt_um_reflex_s1 #(
    parameter integer SEND_DIV    = 100000,  // 0x150 송신 주기(클럭). 시뮬은 작게 override
    parameter integer PROBE_DIV   = 50000,   // MCP 되읽기 주기(클럭)
    parameter integer RESET_DELAY = 500000   // MCP 리셋 후 안정화 지연(클럭). 합성=10ms, 시뮬은 작게
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
    // ── 핀 ──
    wire dip        = ui_in[0];
    wire mcp_int    = ui_in[2];
    wire m_miso     = ui_in[3];
    wire arm_enable = ui_in[7];

    // ── SPI 슬레이브(PL 마스터) ──
    wire        s_sclk = uio_in[0];
    wire        s_mosi = uio_in[1];
    wire        s_csn  = uio_in[2];
    wire        s_miso, s_miso_oe;
    wire [15:0] control, spi_div;

    // ── MCP 되읽기 값(probe → slave) ──
    wire [7:0]  p_canstat, p_canctrl, p_cnf1, p_cnf2, p_cnf3, p_eflg, p_tec, p_rec, p_canintf;

    // ── 드라이버/중재기 배선 ──
    wire        ic_req, ic_grant, ic_done, ic_active, init_done;
    wire [2:0]  ic_op; wire [6:0] ic_addr; wire [7:0] ic_wdata, ic_wmask; wire [3:0] ic_step;
    wire        tx_req, tx_grant, tx_done_a, tx_active, tx_frame_done;
    wire [2:0]  tx_op; wire [6:0] tx_addr; wire [7:0] tx_wdata, tx_wmask;
    wire        pb_req, pb_grant, pb_done, pb_active, probe_valid;
    wire [2:0]  pb_op; wire [6:0] pb_addr; wire [7:0] pb_wdata, pb_wmask;
    wire        drv_req; wire [2:0] drv_op; wire [6:0] drv_addr; wire [7:0] drv_wdata, drv_wmask;
    wire [7:0]  arb_rdata, drv_rdata; wire drv_busy, drv_done;
    wire        m_sclk, m_mosi, m_csn;

    // ── e-stop 트리거(DIP) ──
    wire        gate_active, tx_send;
    wire [10:0] tx_id; wire [3:0] tx_dlc; wire [63:0] tx_data;

    // ── 텔레메트리/상태 ──
    wire [2:0]  action_id = gate_active ? 3'd1 : 3'd0;       // 스텝1: 비상정지(1)만
    wire [15:0] status = {11'd0, init_done, gate_active, action_id};

    // ── 부팅 초기화 원샷 ──
    reg init_started, init_start;
    always @(posedge clk) begin
        if (!rst_n) begin init_started<=0; init_start<=0; end
        else begin
            init_start <= 1'b0;
            if (!init_started) begin init_start<=1'b1; init_started<=1'b1; end
        end
    end

    // ── heartbeat ──
    reg [23:0] hb;
    always @(posedge clk) if (!rst_n) hb<=0; else hb<=hb+1'b1;

    spi_slave_s1 u_slv (
        .clk(clk), .rst_n(rst_n), .sclk(s_sclk), .mosi(s_mosi), .csn(s_csn),
        .miso(s_miso), .miso_oe(s_miso_oe),
        .control(control), .spi_div(spi_div),
        .status(status),
        .canstat(p_canstat), .canctrl(p_canctrl), .cnf1(p_cnf1), .cnf2(p_cnf2), .cnf3(p_cnf3),
        .eflg(p_eflg), .tec(p_tec), .rec(p_rec), .canintf(p_canintf)
    );

    mcp_init #(.RESET_DELAY(RESET_DELAY)) u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start), .grant(ic_grant), .seq_active(ic_active),
        .req(ic_req), .op(ic_op), .addr(ic_addr), .wdata(ic_wdata), .wmask(ic_wmask),
        .rdata(arb_rdata), .busy(drv_busy), .done(ic_done), .init_done(init_done), .step(ic_step)
    );

    estop_tx_src #(.SEND_DIV(SEND_DIV)) u_estop (
        .clk(clk), .rst_n(rst_n), .dip(dip & arm_enable & control[0]), .can_ready(init_done),
        .gate_active(gate_active),
        .tx_id(tx_id), .tx_dlc(tx_dlc), .tx_data(tx_data), .tx_send(tx_send)
    );

    mcp_tx_send u_tx (
        .clk(clk), .rst_n(rst_n),
        .send(tx_send), .id(tx_id), .dlc(tx_dlc), .data(tx_data),
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
        // c0 = init
        .c0_active(ic_active), .c0_req(ic_req), .c0_op(ic_op), .c0_addr(ic_addr), .c0_wdata(ic_wdata), .c0_wmask(ic_wmask), .c0_grant(ic_grant), .c0_done(ic_done),
        // c1 = tx
        .c1_active(tx_active), .c1_req(tx_req), .c1_op(tx_op), .c1_addr(tx_addr), .c1_wdata(tx_wdata), .c1_wmask(tx_wmask), .c1_grant(tx_grant), .c1_done(tx_done_a),
        // c2 = rx (스텝1 비활성)
        .c2_active(1'b0), .c2_req(1'b0), .c2_op(3'd0), .c2_addr(7'd0), .c2_wdata(8'd0), .c2_wmask(8'd0), .c2_grant(), .c2_done(),
        // c3 = probe
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

    // ── 출력 핀 ──
    wire mcp_rst = 1'b1;     // 소프트웨어 리셋 사용 → 하드웨어 리셋선 비활성(하이)
    assign uo_out  = {hb[23], mcp_rst, gate_active, action_id, gate_active, init_done};
    assign uio_out = {1'b0, m_csn, m_mosi, m_sclk, s_miso, 3'b000};
    assign uio_oe  = {1'b0, 1'b1, 1'b1, 1'b1, s_miso_oe, 3'b000};

    wire _unused = &{1'b0, ena, ui_in[6:4], ui_in[1], uio_in[7:3], ic_step, tx_frame_done, probe_valid, drv_req};
endmodule
