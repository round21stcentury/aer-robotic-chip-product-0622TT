`timescale 1ns / 1ps
//============================================================================
// tt_um_reflex_s3 — 스텝3 칩 (★정상 패스스루 + e-stop + 덕/홈포즈 반사, 먹스 게이트)
//----------------------------------------------------------------------------
//  스텝1(패스스루+먹스) + 스텝2(estop) 위에 ★홈복귀 포즈 반사★ 추가.
//   평상시: PS 정상명령 통과. 위험시: 먹스가 정상 끊고 반사 주입 —
//     · danger[0](DIP) → rule0(act1=estop) → 0x150 주기송신
//     · danger[1](소프트트리거) → rule1(act2=pose) → 홈포즈 0x155~7(전부 0) 순환송신
//   우선순위: estop(prio3) > pose(prio1). reflex_tx_s3 가 둘 중 선택해 tx_* 로.
//  핀맵: ui_in[0]=dip(estop) ui_in[1]=danger1(pose, PL서 소프트트리거).
//============================================================================
module tt_um_reflex_s3 #(
    parameter integer SEND_DIV    = 100000,
    parameter integer PROBE_DIV   = 50000,
    parameter integer RESET_DELAY = 500000
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
    wire dip        = ui_in[0];     // estop 트리거 (DIP SW0)
    wire danger1    = ui_in[1];     // pose 트리거 (PL서 소프트트리거 cfg[9])
    wire mcp_int    = ui_in[2];
    wire m_miso     = ui_in[3];
    wire arm_enable = ui_in[7];

    wire        s_sclk = uio_in[0];
    wire        s_mosi = uio_in[1];
    wire        s_csn  = uio_in[2];
    wire        s_miso, s_miso_oe;
    wire [15:0] control, spi_div;
    wire [10:0] norm_id; wire [63:0] norm_data; wire norm_send;
    wire [15:0] rule0,rule1,rule2,rule3, thresh0,thresh1,thresh2,thresh3, xadc_val;
    wire [15:0] recoil_d1,recoil_d2,recoil_d3,recoil_d4,recoil_d5,recoil_d6;
    wire [15:0] flinch_lo, flinch_hi;    // ★움찔(act3) 1회성 지속 틱 (32비트={hi,lo})
    wire [15:0] reflex_speed;            // ★반사 0x151 속도율 (1~100)

    wire [7:0]  p_canstat,p_canctrl,p_cnf1,p_cnf2,p_cnf3,p_eflg,p_tec,p_rec,p_canintf;

    wire        ic_req,ic_grant,ic_done,ic_active,init_done; wire [2:0] ic_op; wire [6:0] ic_addr; wire [7:0] ic_wdata,ic_wmask; wire [3:0] ic_step;
    wire        tx_req,tx_grant,tx_done_a,tx_active,tx_frame_done; wire [2:0] tx_op; wire [6:0] tx_addr; wire [7:0] tx_wdata,tx_wmask;
    wire        pb_req,pb_grant,pb_done,pb_active,probe_valid; wire [2:0] pb_op; wire [6:0] pb_addr; wire [7:0] pb_wdata,pb_wmask;
    wire        drv_req; wire [2:0] drv_op; wire [6:0] drv_addr; wire [7:0] drv_wdata,drv_wmask;
    wire [7:0]  arb_rdata,drv_rdata; wire drv_busy,drv_done;
    wire        m_sclk,m_mosi,m_csn;

    // ── 반사 코어/포즈생성/송신원 ──
    wire        estop_active, pose_active, valid, fire, heartbeat;
    wire [2:0]  action_id;
    wire        gate_active;
    wire [10:0] pg_id, rfx_id; wire [3:0] pg_dlc, rfx_dlc; wire [63:0] pg_data, rfx_data;
    wire        pg_send, rfx_send;

    // ── 먹스 출력 ──
    wire [10:0] sel_id; wire [3:0] sel_dlc; wire [63:0] sel_data; wire sel_send;

    // status[3]=init_done, [4]=gate_active, [5]=pose_active, [8:6]=action_id
    wire [15:0] status = {7'd0, action_id, pose_active, gate_active, init_done, 3'b000};

    reg init_started, init_start;
    always @(posedge clk) begin
        if (!rst_n) begin init_started<=0; init_start<=0; end
        else begin init_start<=1'b0; if (!init_started) begin init_start<=1'b1; init_started<=1'b1; end end
    end

    spi_slave_full #(.VERSION(16'h0531)) u_slv (
        .clk(clk), .rst_n(rst_n), .sclk(s_sclk), .mosi(s_mosi), .csn(s_csn),
        .miso(s_miso), .miso_oe(s_miso_oe),
        .control(control), .spi_div(spi_div),
        .rule0(rule0), .rule1(rule1), .rule2(rule2), .rule3(rule3),
        .thresh0(thresh0), .thresh1(thresh1), .thresh2(thresh2), .thresh3(thresh3), .xadc_val(xadc_val),
        .recoil_d1(recoil_d1), .recoil_d2(recoil_d2), .recoil_d3(recoil_d3),
        .recoil_d4(recoil_d4), .recoil_d5(recoil_d5), .recoil_d6(recoil_d6),
        .flinch_lo(flinch_lo), .flinch_hi(flinch_hi), .reflex_speed(reflex_speed),
        .norm_id(norm_id), .norm_data(norm_data), .norm_send(norm_send),
        .status(status),
        .canstat(p_canstat), .canctrl(p_canctrl), .cnf1(p_cnf1), .cnf2(p_cnf2), .cnf3(p_cnf3),
        .eflg(p_eflg), .tec(p_tec), .rec(p_rec), .canintf(p_canintf)
    );

    reflex_core_s3 u_core (
        .clk(clk), .rst_n(rst_n),
        .danger({2'b00, danger1, dip}), .arm_enable(arm_enable),
        .control(control), .rule0(rule0), .rule1(rule1), .rule2(rule2), .rule3(rule3),
        .thresh0(thresh0), .thresh1(thresh1), .thresh2(thresh2), .thresh3(thresh3), .xadc_val(xadc_val),
        .flinch_ticks({flinch_hi, flinch_lo}),
        .estop_active(estop_active), .pose_active(pose_active),
        .action_id(action_id), .valid(valid), .fire(fire), .heartbeat(heartbeat)
    );

    reflex_pose_gen_s3 #(.SEND_DIV(SEND_DIV)) u_pgen (
        .clk(clk), .rst_n(rst_n), .pose_active(pose_active), .reflex_speed(reflex_speed[7:0]),
        .reflex_id(pg_id), .reflex_dlc(pg_dlc), .reflex_data(pg_data), .reflex_send(pg_send)
    );

    reflex_tx_s3 #(.SEND_DIV(SEND_DIV)) u_txsrc (
        .clk(clk), .rst_n(rst_n), .estop_active(estop_active), .pose_active(pose_active), .can_ready(init_done),
        .pose_id(pg_id), .pose_dlc(pg_dlc), .pose_data(pg_data), .pose_send(pg_send),
        .tx_id(rfx_id), .tx_dlc(rfx_dlc), .tx_data(rfx_data), .tx_send(rfx_send), .gate_active(gate_active)
    );

    // ★먹스: 평상시 정상명령, 위험시(gate_active) 반사(estop 또는 포즈) 주입
    mcp_tx_mux u_mux (
        .reflex_active(gate_active),
        .normal_id(norm_id), .normal_dlc(4'd8), .normal_data(norm_data), .normal_send(norm_send),
        .reflex_id(rfx_id), .reflex_dlc(rfx_dlc), .reflex_data(rfx_data), .reflex_send(rfx_send),
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
    assign uo_out  = {heartbeat, mcp_rst, gate_active, action_id, fire, valid};
    assign uio_out = {1'b0, m_csn, m_mosi, m_sclk, s_miso, 3'b000};
    assign uio_oe  = {1'b0, 1'b1, 1'b1, 1'b1, s_miso_oe, 3'b000};

    wire _unused = &{1'b0, ena, ui_in[6:4], uio_in[7:3], ic_step, tx_frame_done, probe_valid, drv_req, sel_dlc, pg_dlc,
                     recoil_d1,recoil_d2,recoil_d3,recoil_d4,recoil_d5,recoil_d6};
endmodule
