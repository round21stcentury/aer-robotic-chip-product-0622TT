`timescale 1ns / 1ps
//============================================================================
// tb_reflex_top_s4 — 스텝4 PL 통합 시뮬 (reflex_top_s4 ─ MCP 모델 RX 주입)
//   configured + 현재포즈 수신 + FSR→움츠림(0x155=현재+델타) + rule b 해제.
//============================================================================
module tb_reflex_top_s4;
    reg aclk=0, aresetn=0; always #5 aclk=~aclk; integer errors=0;
    reg         dip=0;
    reg  [15:0] cfg_in=16'h0104, thr_in=16'h0800, rule_in=16'h005C;   // rule_in=0x5B=움츠림(act3)
    reg  [15:0] d5_in=16'h3A98, xadc_in=16'h0000;      // ★J5 움츠림 델타=+15000(0.001도)
    reg  [31:0] flinch_in=32'd40000;                    // ★움츠림 1회성 지속(틱). 07: SEND_DIV 키워 4프레임(0x151~157) 다 들어가게
    reg  [15:0] rspeed_in=16'd100;                      // ★반사 이동 속도율(0x151, 1~100)
    wire [31:0] obs0, obs1;
    wire        reflex_active, configured;
    wire [31:0] lat_decision, lat_issued;   // ★반사지연 측정 (트리거→결정 / 트리거→RTS발사, 클럭사이클)
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s4 #(.SPI_HALF(8), .SEND_DIV(8000), .PROBE_DIV(2000), .SAMPLE_DIV(1500), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .dip(dip), .cfg_in(cfg_in), .thr_in(thr_in), .rule_in(rule_in),
        .flinch_in(flinch_in), .d5_in(d5_in), .rspeed_in(rspeed_in), .xadc_val(xadc_in),
        .obs0(obs0), .obs1(obs1), .reflex_active(reflex_active), .configured(configured),
        .lat_decision(lat_decision), .lat_issued(lat_issued),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );
    mcp2515_model_v2 u_mcp (.sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int));

    integer w;
    task inject_wait(input [10:0] id, input [63:0] data);
        begin
            @(posedge aclk); u_mcp.mdl_rx_inject(id, 4'd8, data);
            w=0; while (u_mcp.regs[8'h2C][0]!==1'b0 && w<200000) begin @(posedge aclk); w=w+1; end
            repeat (200) @(posedge aclk);
        end
    endtask

    integer txc; reg signed [31:0] t2; reg saw151, saw_home;
    initial begin
        repeat (10) @(posedge aclk); aresetn=1;
        $display("== 스텝4 PL 통합: reflex_top_s4 ─ MCP 모델 ==");
        while (!configured) @(posedge aclk);
        $display("configured=1");
        repeat (40000) @(posedge aclk);
        if (obs0===32'h0000C080) $display("[ ok ] obs0=0x0000C080 (관측)"); else begin errors=errors+1; $display("[FAIL] obs0=0x%08h",obs0); end

        // ★현재포즈 수신: J5=30000 (0x2A7, lo_joint=j5, big-endian D0~D3)
        inject_wait(11'h2A7, 64'h0000_0000_3075_0000);   // j5=30000(0x7530), j6=0

        // ★FSR → 움츠림: recoil 창에서 0x157 J5=45000(현재+델타) + 0x151 속도=100 둘 다 샘플
        xadc_in=16'h0900; saw151=0; t2=0;
        w=0; while (w<80000 && !(saw151 && t2===32'sd45000)) begin @(posedge aclk); w=w+1;
            if (u_mcp.last_tx_id==11'h151 && u_mcp.last_tx_data[23:16]==8'h64) saw151=1;
            if (u_mcp.last_tx_id==11'h157) t2 = {u_mcp.last_tx_data[7:0], u_mcp.last_tx_data[15:8], u_mcp.last_tx_data[23:16], u_mcp.last_tx_data[31:24]};
        end
        if (reflex_active && t2===32'sd45000) $display("[ ok ] FSR → 움츠림 0x157 J5=45000 (현재30000+델타15000) ★현재포즈");
        else begin errors=errors+1; $display("[FAIL] 움츠림 J5=%0d active=%0d",t2,reflex_active); end
        if (saw151) $display("[ ok ] ★0x151 속도=100 주입 (실로봇 이동속도)");
        else begin errors=errors+1; $display("[FAIL] 0x151 속도 안봄"); end

        // ★반사지연 측정: 트리거(xadc)→결정(reflex_active)→첫 RTS(발사). lat_issued>0 + 결정≤발사
        if (lat_issued > 0 && lat_decision > 0 && lat_decision <= lat_issued)
            $display("[ ok ] ★반사지연: 트리거→결정 %0d cyc, 트리거→RTS(발사) %0d cyc (sim; 실보드는 PS가 µs 출력)", lat_decision, lat_issued);
        else begin errors=errors+1; $display("[FAIL] 반사지연 dec=%0d iss=%0d", lat_decision, lat_issued); end

        // ★1회성 자동해제: xadc 계속 높아도 flinch_ticks(20000) 후 해제 → 송신 정지(움찔식)
        repeat (30000) @(posedge aclk); txc=u_mcp.tx_count; repeat (10000) @(posedge aclk);
        if (u_mcp.tx_count==txc) $display("[ ok ] ★1회성 자동해제 (xadc 계속 높음에도 정지)");
        else begin errors=errors+1; $display("[FAIL] 자동해제 안 됨 (계속 송신중)"); end

        // ★act3(움츠림_덕포즈) 확인: FSR=0x5B → 홈으로 1회성 (현재포즈 무시 → 0x157=0, 45000 아님 = act3/act4 구분)
        xadc_in=16'h0000; rule_in=16'h005B; repeat (14000) @(posedge aclk);   // 재무장 + rule2=0x5B 전파
        xadc_in=16'h0900; saw_home=0;
        w=0; while (w<60000 && !saw_home) begin @(posedge aclk); w=w+1;
            if (u_mcp.last_tx_id==11'h157 && u_mcp.last_tx_data===64'h0) saw_home=1;
        end
        if (saw_home) $display("[ ok ] ★act3(움츠림_덕포즈) FSR=0x5B → 홈 0x157=0 (현재포즈 무시·act4와 구분 확인)");
        else begin errors=errors+1; $display("[FAIL] act3 홈 안봄 last=0x%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end
        xadc_in=16'h0000; repeat (30000) @(posedge aclk);   // 해제

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0"); else begin errors=errors+1; $display("[FAIL] tx_fail=%0d",u_mcp.tx_fail_cnt); end
        if (errors==0) $display("==== PASS: 스텝4 PL 통합 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #60_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
