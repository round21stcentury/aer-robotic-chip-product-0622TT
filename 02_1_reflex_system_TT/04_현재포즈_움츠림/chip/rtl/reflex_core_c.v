`timescale 1ns / 1ps
//============================================================================
// reflex_core_c — C단계 반사 결정 코어 (규칙표 + 우선순위 + e-stop/홈/움츠림)
//----------------------------------------------------------------------------
//  reflex_core_tt_v3 의 "규칙표 4개 + XADC 임계 + 디바운스 + 우선순위 중재" 를 그대로
//  쓰되(설정 레지스터는 외부 spi_slave_v4 에서 입력으로 받음), 선택된 action_id 에 따라
//  세 가지 반사 행동을 분기한다:
//    action 1 = 비상정지 : 즉시 발사, 센서 떼면 바로 풀림 (rule a). estop_active.
//    action 2 = 홈복귀   : 절대 목표(현재 무시). 유지 후 도달+센서뗌에 해제 (rule b).
//    action 3 = 움츠림   : 현재+델타 목표. 유지 후 도달+센서뗌에 해제 (rule b).
//  우선순위 중재(높은 prio 우선)가 백스톱: 여러 규칙이 동시에 켜져도 하나만 고른다.
//  (프로그래밍 관례: RULE0=DIP비상정지 prio3 항상, RULE1~3=FSR 중 하나만.)
//
//  출력:
//    estop_active : action 1 활성(즉시·유지 없음).
//    pose_active  : action 2/3 유지 래치(=포즈 게이트).
//    pose_mode    : 0=홈(절대), 1=움츠림(상대) — reflex_pose_gen 모드.
//============================================================================
module reflex_core_c #(
    parameter integer DEBOUNCE = 4,
    parameter integer HB_BIT   = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  danger,         // 디지털 위험 입력(danger[0]=DIP)
    input  wire        arm_enable,
    input  wire        reached,         // 로봇 도달(pose_status_decode)
    // 설정 레지스터 (spi_slave_v4)
    input  wire [15:0] control, rule0, rule1, rule2, rule3,
    input  wire [15:0] thresh0, thresh1, thresh2, thresh3, xadc_val,
    input  wire [31:0] flinch_ticks,     // ★act3(움츠림) 1회성 지속 틱 (PS가 클럭상대로 설정)
    // 출력
    output wire        estop_active,
    output wire        pose_active,
    output wire        pose_mode,
    output reg  [2:0]  action_id,
    output reg         valid,
    output reg         fire,
    output wire        heartbeat
);
    // ── 규칙 풀기 ──
    wire [2:0] act  [0:3];
    wire       en   [0:3];
    wire [1:0] prio [0:3];
    wire       src  [0:3];
    wire [15:0] thr [0:3];
    assign act[0]=rule0[2:0]; assign en[0]=rule0[3]; assign prio[0]=rule0[5:4]; assign src[0]=rule0[6]; assign thr[0]=thresh0;
    assign act[1]=rule1[2:0]; assign en[1]=rule1[3]; assign prio[1]=rule1[5:4]; assign src[1]=rule1[6]; assign thr[1]=thresh1;
    assign act[2]=rule2[2:0]; assign en[2]=rule2[3]; assign prio[2]=rule2[5:4]; assign src[2]=rule2[6]; assign thr[2]=thresh2;
    assign act[3]=rule3[2:0]; assign en[3]=rule3[3]; assign prio[3]=rule3[5:4]; assign src[3]=rule3[6]; assign thr[3]=thresh3;

    // ── 위험 원천: 디지털 핀 또는 XADC 임계 비교 ──
    wire [3:0] danger_raw;
    assign danger_raw[0] = src[0] ? (xadc_val >= thr[0]) : danger[0];
    assign danger_raw[1] = src[1] ? (xadc_val >= thr[1]) : danger[1];
    assign danger_raw[2] = src[2] ? (xadc_val >= thr[2]) : danger[2];
    assign danger_raw[3] = src[3] ? (xadc_val >= thr[3]) : danger[3];

    // ── 2단 동기화 + 디바운스 ──
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

    // ── 우선순위 중재 (높은 prio 우선, 동률은 낮은 index) ──
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

    // ── 행동 분기: e-stop(즉시) / 홈복귀(act2, 도달기반 유지) / ★움츠림(act3, 1회성 타이머) ──
    wire is_estop_now  = sel_valid & (sel_action == 3'd1);
    wire is_home_now   = sel_valid & (sel_action == 3'd2);   // 홈복귀(절대), 도달+센서뗌 해제(rule b)
    wire is_recoil_sel = sel_valid & (sel_action == 3'd3);   // ★움츠림(현재+델타), 1회성 타이머 해제

    // act2 홈복귀: 유지 래치 (도달기반 rule b)
    reg  pose_latch;
    always @(posedge clk) begin
        if (!rst_n)            pose_latch<=1'b0;
        else if (is_estop_now) pose_latch<=1'b0;             // e-stop 우선
        else if (is_home_now)  pose_latch<=1'b1;
        else if (reached)      pose_latch<=1'b0;             // 센서뗌 + 도달 → 해제 (b)
    end

    // ★act3 움츠림: FSR 상승엣지 1회 발동 → flinch_ticks 동안 현재+델타 유지 → 자동해제 → 센서 내려야 재무장.
    //   "현재 자세에서 J5 만큼 홱 움츠렸다 복귀"(움찔과 동일한 1회성, 목표만 홈 대신 현재+델타).
    reg  recoil_d, flinch_run, flinch_done;
    reg  [31:0] fcnt;
    always @(posedge clk) begin
        if (!rst_n) begin recoil_d<=0; flinch_run<=0; flinch_done<=0; fcnt<=0; end
        else begin
            recoil_d <= is_recoil_sel;
            if (is_estop_now) flinch_run<=1'b0;                                                  // e-stop 우선
            else if (is_recoil_sel & ~recoil_d & ~flinch_done) begin flinch_run<=1'b1; fcnt<=0; end  // 상승엣지 → 시작
            else if (flinch_run) begin
                if (fcnt >= flinch_ticks) begin flinch_run<=1'b0; flinch_done<=1'b1; end          // 만료 → 자동해제+래치
                else fcnt <= fcnt + 1'b1;
            end
            if (~is_recoil_sel) flinch_done<=1'b0;            // 센서 내리면 재무장
        end
    end

    assign estop_active = is_estop_now;
    assign pose_active  = pose_latch | flinch_run;            // 홈(유지) 또는 움츠림(1회성) 동안 포즈 구동
    assign pose_mode    = flinch_run;                         // ★1=움츠림(현재+델타), 0=홈복귀

    // ── 텔레메트리 출력(등록) ──
    always @(posedge clk) begin
        if (!rst_n) begin valid<=0; fire<=0; action_id<=0; end
        else begin
            valid <= 1'b1;
            if (is_estop_now)    begin fire<=1'b1; action_id<=3'd1; end
            else if (flinch_run) begin fire<=1'b1; action_id<=3'd3; end   // 움츠림
            else if (pose_latch) begin fire<=1'b1; action_id<=3'd2; end   // 홈
            else                 begin fire<=sel_valid; action_id<= sel_valid ? sel_action : 3'd0; end
        end
    end

    // ── heartbeat ──
    reg [HB_BIT:0] hb;
    always @(posedge clk) if (!rst_n) hb <= 0; else hb <= hb + 1'b1;
    assign heartbeat = hb[HB_BIT];
endmodule
