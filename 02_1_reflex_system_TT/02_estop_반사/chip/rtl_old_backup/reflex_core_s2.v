`timescale 1ns / 1ps
//============================================================================
// reflex_core_s2 — 스텝2 반사 결정 코어 (규칙표 + 우선순위 + 디바운스, ★e-stop만)
//----------------------------------------------------------------------------
//  04 reflex_core_c 의 "규칙표 4개 + (XADC 소스선택) + 디바운스 + 우선순위 중재" 를 그대로
//  쓰되, ★행동은 비상정지(action=1)만★ — 포즈 래치·도달은 스텝3·4에서 추가.
//  설정 레지스터(rule/thresh/xadc)는 외부 spi_slave 에서 입력으로 받음.
//  관례: RULE0=DIP 비상정지(prio3, 항상 켬, src=핀). FSR 규칙은 스텝3부터.
//  (스텝2 는 XADC 미연결 → xadc_val=0, src=0 핀만 의미. 구조는 다음 스텝과 호환 유지.)
//============================================================================
module reflex_core_s2 #(
    parameter integer DEBOUNCE = 4,
    parameter integer HB_BIT   = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  danger,          // danger[0]=DIP
    input  wire        arm_enable,
    // 설정 레지스터 (spi_slave)
    input  wire [15:0] control, rule0, rule1, rule2, rule3,
    input  wire [15:0] thresh0, thresh1, thresh2, thresh3, xadc_val,
    // 출력
    output wire        estop_active,
    output reg  [2:0]  action_id,
    output reg         valid,
    output reg         fire,
    output wire        heartbeat
);
    // 규칙 풀기
    wire [2:0] act  [0:3];
    wire       en   [0:3];
    wire [1:0] prio [0:3];
    wire       src  [0:3];
    wire [15:0] thr [0:3];
    assign act[0]=rule0[2:0]; assign en[0]=rule0[3]; assign prio[0]=rule0[5:4]; assign src[0]=rule0[6]; assign thr[0]=thresh0;
    assign act[1]=rule1[2:0]; assign en[1]=rule1[3]; assign prio[1]=rule1[5:4]; assign src[1]=rule1[6]; assign thr[1]=thresh1;
    assign act[2]=rule2[2:0]; assign en[2]=rule2[3]; assign prio[2]=rule2[5:4]; assign src[2]=rule2[6]; assign thr[2]=thresh2;
    assign act[3]=rule3[2:0]; assign en[3]=rule3[3]; assign prio[3]=rule3[5:4]; assign src[3]=rule3[6]; assign thr[3]=thresh3;

    // 위험 원천: 디지털 핀 또는 XADC 임계 비교
    wire [3:0] danger_raw;
    assign danger_raw[0] = src[0] ? (xadc_val >= thr[0]) : danger[0];
    assign danger_raw[1] = src[1] ? (xadc_val >= thr[1]) : danger[1];
    assign danger_raw[2] = src[2] ? (xadc_val >= thr[2]) : danger[2];
    assign danger_raw[3] = src[3] ? (xadc_val >= thr[3]) : danger[3];

    // 2단 동기화 + 디바운스
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

    // 우선순위 중재 (높은 prio 우선, 동률은 낮은 index)
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

    // ★스텝2: 비상정지(action 1)만
    assign estop_active = sel_valid & (sel_action == 3'd1);

    always @(posedge clk) begin
        if (!rst_n) begin valid<=0; fire<=0; action_id<=0; end
        else begin
            valid     <= 1'b1;
            fire      <= estop_active;
            action_id <= estop_active ? 3'd1 : 3'd0;
        end
    end

    reg [HB_BIT:0] hb;
    always @(posedge clk) if (!rst_n) hb <= 0; else hb <= hb + 1'b1;
    assign heartbeat = hb[HB_BIT];
endmodule
