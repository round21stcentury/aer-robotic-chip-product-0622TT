`timescale 1ns / 1ps
//============================================================================
// reflex_core_s3 — 스텝3 반사 결정 코어 (e-stop + 홈복귀, ★해제=센서only rule a)
//----------------------------------------------------------------------------
//  스텝2(estop만) 에 ★홈복귀(action 2)★ 를 더한다. 트리거는 FSR(XADC) — 규칙 src=XADC,
//  위험 = (xadc_val >= thresh). 해제는 ★센서 떼면 즉시(rule a)★ — 도달(RX)은 스텝4.
//  그래서 pose_active 는 래치 없이 "포즈 규칙이 선택된 동안" 유지(센서 추종).
//  우선순위 중재: DIP estop(prio3) > FSR(prio1) — 둘 다면 estop 이 이기고 pose=0.
//  설정 레지스터(rule/thresh/xadc)는 외부 spi_slave 에서.
//============================================================================
module reflex_core_s3 #(
    parameter integer DEBOUNCE = 4,
    parameter integer HB_BIT   = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  danger,          // danger[0]=DIP
    input  wire        arm_enable,
    input  wire [15:0] control, rule0, rule1, rule2, rule3,
    input  wire [15:0] thresh0, thresh1, thresh2, thresh3, xadc_val,
    input  wire [31:0] flinch_ticks,    // ★act3(움찔) 1회성 지속 틱 (PS가 클럭상대로 설정)
    output wire        estop_active,
    output wire        pose_active,
    output reg  [2:0]  action_id,
    output reg         valid,
    output reg         fire,
    output wire        heartbeat
);
    wire [2:0] act  [0:3];
    wire       en   [0:3];
    wire [1:0] prio [0:3];
    wire       src  [0:3];
    wire [15:0] thr [0:3];
    assign act[0]=rule0[2:0]; assign en[0]=rule0[3]; assign prio[0]=rule0[5:4]; assign src[0]=rule0[6]; assign thr[0]=thresh0;
    assign act[1]=rule1[2:0]; assign en[1]=rule1[3]; assign prio[1]=rule1[5:4]; assign src[1]=rule1[6]; assign thr[1]=thresh1;
    assign act[2]=rule2[2:0]; assign en[2]=rule2[3]; assign prio[2]=rule2[5:4]; assign src[2]=rule2[6]; assign thr[2]=thresh2;
    assign act[3]=rule3[2:0]; assign en[3]=rule3[3]; assign prio[3]=rule3[5:4]; assign src[3]=rule3[6]; assign thr[3]=thresh3;

    wire [3:0] danger_raw;
    assign danger_raw[0] = src[0] ? (xadc_val >= thr[0]) : danger[0];
    assign danger_raw[1] = src[1] ? (xadc_val >= thr[1]) : danger[1];
    assign danger_raw[2] = src[2] ? (xadc_val >= thr[2]) : danger[2];
    assign danger_raw[3] = src[3] ? (xadc_val >= thr[3]) : danger[3];

    wire [3:0] danger_stable;
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_db
            reg [1:0] sync;
            reg [15:0] cnt;
            reg        stable;
            always @(posedge clk) begin
                if (!rst_n) begin sync <= 0; cnt <= 0; stable <= 0; end
                else begin
                    sync <= {sync[0], danger_raw[gi]};
                    if (sync[1] == stable)        cnt <= 0;
                    else if (cnt >= DEBOUNCE) begin stable <= sync[1]; cnt <= 0; end
                    else                          cnt <= cnt + 1'b1;
                end
            end
            assign danger_stable[gi] = stable;
        end
    endgenerate

    wire g_en = control[0] & arm_enable;
    wire [3:0] cand = { g_en & en[3] & danger_stable[3],
                        g_en & en[2] & danger_stable[2],
                        g_en & en[1] & danger_stable[1],
                        g_en & en[0] & danger_stable[0] };

    reg [2:0] sel_action;
    reg [1:0] sel_prio;
    reg       sel_valid;
    always @* begin
        sel_action = 3'd0; sel_prio = 2'd0; sel_valid = 1'b0;
        if (cand[3] && (!sel_valid || prio[3] >= sel_prio)) begin sel_action=act[3]; sel_prio=prio[3]; sel_valid=1; end
        if (cand[2] && (!sel_valid || prio[2] >= sel_prio)) begin sel_action=act[2]; sel_prio=prio[2]; sel_valid=1; end
        if (cand[1] && (!sel_valid || prio[1] >= sel_prio)) begin sel_action=act[1]; sel_prio=prio[1]; sel_valid=1; end
        if (cand[0] && (!sel_valid || prio[0] >= sel_prio)) begin sel_action=act[0]; sel_prio=prio[0]; sel_valid=1; end
    end

    // ★estop(1) + 덕포즈(2, 레벨/추종) + ★움찔(3, 엣지 1회성)
    assign estop_active = sel_valid & (sel_action == 3'd1);

    // ★움찔(act3): FSR 상승엣지에 1회 발동 → flinch_ticks 동안 홈포즈 → 자동해제 → 센서 내려야 재무장.
    //   현재포즈 RX 없이 "홈으로 홱 움찔했다 복귀"를 만든다(스텝4 RX 우회).
    wire act3_sel = sel_valid & (sel_action == 3'd3);
    reg  act3_d, flinch_run, flinch_done;
    reg [31:0] fcnt;
    always @(posedge clk) begin
        if (!rst_n) begin act3_d<=0; flinch_run<=0; flinch_done<=0; fcnt<=0; end
        else begin
            act3_d <= act3_sel;
            if (act3_sel & ~act3_d & ~flinch_done) begin flinch_run<=1'b1; fcnt<=0; end   // 상승엣지 → 1회성 시작
            else if (flinch_run) begin
                if (fcnt >= flinch_ticks) begin flinch_run<=1'b0; flinch_done<=1'b1; end  // 만료 → 자동해제+래치
                else fcnt <= fcnt + 1'b1;
            end
            if (~act3_sel) flinch_done <= 1'b0;     // 센서 내리면 재무장(다음 엣지에 또 움찔)
        end
    end
    // 덕포즈(act2, 레벨) 또는 움찔(act3, 1회성) 동안 홈포즈 구동
    assign pose_active  = (sel_valid & (sel_action == 3'd2)) | flinch_run;

    always @(posedge clk) begin
        if (!rst_n) begin valid<=0; fire<=0; action_id<=0; end
        else begin
            valid     <= 1'b1;
            fire      <= sel_valid;
            action_id <= sel_valid ? sel_action : 3'd0;
        end
    end

    reg [HB_BIT:0] hb;
    always @(posedge clk) if (!rst_n) hb <= 0; else hb <= hb + 1'b1;
    assign heartbeat = hb[HB_BIT];
endmodule
