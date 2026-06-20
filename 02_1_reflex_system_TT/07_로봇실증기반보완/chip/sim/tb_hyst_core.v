`timescale 1ns/1ps
//============================================================================
// tb_hyst_core — ★07 슈미트 히스테리시스 단위시험 (reflex_core_c 직접)
//   06 버그: FSR(XADC) 무필터라 임계 근처 노이즈/크리프로 xadc_val 이 들락날락 →
//            꾹 눌러도 재발동·잠깐풀림. 07: 슈미트(발동 thr, 해제 thr×0.75)로 락 유지.
//   검증: ① 임계밑 미발동 ② 발동 1회 ③ ★꾹 누른 채 노이즈 디더 → 재발동 0 (락)
//         ④ ★진짜 떼면 재무장 → 재발동 (총 2회. 영구고착 아님)
//============================================================================
module tb_hyst_core;
    reg clk=0, rst_n=0;
    reg [15:0] debounce;
    reg [15:0] hyst;
    reg [3:0]  danger;
    reg        arm_enable, reached;
    reg [15:0] control, rule0, rule1, rule2, rule3;
    reg [15:0] thresh0, thresh1, thresh2, thresh3, xadc_val;
    reg [31:0] flinch_ticks;
    wire estop_active, pose_active, pose_mode, pose_freeze;
    wire [2:0] action_id;
    wire valid, fire, heartbeat;

    reflex_core_c dut(
        .clk(clk), .rst_n(rst_n), .debounce(debounce), .hyst(hyst), .danger(danger),
        .arm_enable(arm_enable), .reached(reached),
        .control(control), .rule0(rule0), .rule1(rule1), .rule2(rule2), .rule3(rule3),
        .thresh0(thresh0), .thresh1(thresh1), .thresh2(thresh2), .thresh3(thresh3),
        .xadc_val(xadc_val), .flinch_ticks(flinch_ticks),
        .estop_active(estop_active), .pose_active(pose_active),
        .pose_mode(pose_mode), .pose_freeze(pose_freeze),
        .action_id(action_id), .valid(valid), .fire(fire), .heartbeat(heartbeat)
    );

    always #5 clk = ~clk;

    // pose_active 상승엣지 = 반사 1회 발동
    integer fire_edges = 0;
    reg pose_d = 0;
    always @(posedge clk) begin
        pose_d <= pose_active;
        if (pose_active & ~pose_d) fire_edges = fire_edges + 1;
    end

    integer errors = 0;
    task hold(input [15:0] v, input integer n);
        begin xadc_val = v; repeat(n) @(posedge clk); end
    endtask

    initial begin
        debounce = 16'd4;
        hyst = 16'd2;                  // ★시프트2 = 25% → rel_thr = 1000-(1000>>2) = 750
        danger = 4'd0; arm_enable = 1'b1; reached = 1'b0;
        control = 16'h0001;            // g_en=1
        rule0 = 0; rule1 = 0; rule3 = 0;
        rule2 = 16'h005C;              // ★src=1(XADC), act=4(움츠림_현재), en=1, prio=1 (FSR_RULE 0x5C)
        thresh0=0; thresh1=0; thresh3=0;
        thresh2 = 16'd1000;            // 발동임계 → rel_thr = 1000 - (1000>>2) = 750
        xadc_val = 16'd0;
        flinch_ticks = 32'd200;        // 1회성 짧게(sim)
        rst_n = 1'b0; repeat(10) @(posedge clk);
        rst_n = 1'b1; repeat(10) @(posedge clk);
        $display("== 슈미트 히스테리시스 단위시험 (thr=1000, rel_thr=750) ==");

        // ① 임계 밑 → 미발동
        hold(16'd700, 60);
        if (fire_edges != 0) begin errors=errors+1; $display("[FAIL] (1) 임계밑인데 발동 %0d", fire_edges); end
        else $display("[ ok ] (1) 700(<thr) → 미발동");

        // ② 발동 (임계 이상) → 1회 flinch (자동해제까지 유지)
        hold(16'd1050, 400);
        if (fire_edges != 1) begin errors=errors+1; $display("[FAIL] (2) 발동 1회 기대인데 %0d", fire_edges); end
        else $display("[ ok ] (2) 1050(>=thr) → 발동 1회");

        // ③ ★꾹 누른 채 노이즈 디더: 임계(1000) straddle 하되 rel_thr(750) 위 → 재발동 0
        hold(16'd920,30); hold(16'd1010,30); hold(16'd880,30); hold(16'd990,30);
        hold(16'd800,30); hold(16'd1100,30); hold(16'd760,30); hold(16'd950,30);
        if (fire_edges != 1) begin errors=errors+1; $display("[FAIL] (3) ★꾹누른채 디더로 재발동! %0d회 (=06버그)", fire_edges); end
        else $display("[ ok ] (3) ★꾹 누른 채 노이즈 디더(임계 들락날락) → 재발동 0 (락 유지)");

        // ④ ★진짜 떼기(rel_thr 밑) → 재무장 → 다시 누르면 재발동 (영구고착 아님)
        hold(16'd0, 60);
        hold(16'd1050, 400);
        if (fire_edges != 2) begin errors=errors+1; $display("[FAIL] (4) 재무장 후 재발동 기대(2) 인데 %0d", fire_edges); end
        else $display("[ ok ] (4) ★떼었다 다시 누름 → 재발동(총 2회) — 락 안 걸림");

        if (errors==0) $display("==== PASS: 슈미트 — 꾹 누르면 1회 락, 떼야 재발동 ====");
        else           $display("==== FAIL: 오류 %0d ====", errors);
        $finish;
    end
endmodule
