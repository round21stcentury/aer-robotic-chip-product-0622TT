`timescale 1ns / 1ps
//============================================================================
// tb_reflex_top_s1 — 스텝1 PL 통합 시뮬 (reflex_top_s1 ─ MCP 모델)
//----------------------------------------------------------------------------
//  PL 최상위가 ① 부팅 자동설정 후 configured=1, ② 칩 MCP 되읽기를 obs0/obs1 로
//  PS GPIO 에 노출(=관측성), ③ DIP ON 시 reflex_active 게이트가 서는지 확인.
//   obs0 기대 = {CANSTAT=00, CNF1=00, CNF2=C0, CNF3=80} = 0x0000C080
//   obs1 기대 = {EFLG=00, TEC=00, REC=00, CANINTF=00}   = 0x00000000
//============================================================================
module tb_reflex_top_s1;
    reg aclk=0, aresetn=0;
    always #5 aclk = ~aclk;

    integer errors=0;
    reg         dip=0;
    reg  [15:0] cfg_in = 16'h0104;     // enable(bit8)=1, SPI_DIV=4
    wire [31:0] obs0, obs1;
    wire        reflex_active, configured;
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s1 #(.SPI_HALF(8), .SEND_DIV(3000), .PROBE_DIV(1500), .SAMPLE_DIV(1500), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .dip(dip), .cfg_in(cfg_in),
        .obs0(obs0), .obs1(obs1), .reflex_active(reflex_active), .configured(configured),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );

    mcp2515_model_v2 u_mcp (
        .sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int)
    );

    task chk32(input [8*16:1] label, input [31:0] got, input [31:0] exp);
        begin
            if (got!==exp) begin errors=errors+1; $display("[FAIL] %0s = 0x%08h (기대 0x%08h)", label, got, exp); end
            else $display("[ ok ] %0s = 0x%08h", label, got);
        end
    endtask

    integer txc0;
    initial begin
        repeat (10) @(posedge aclk);
        aresetn=1;
        $display("== 스텝1 PL 통합: reflex_top_s1 ─ MCP 모델 ==");

        // configured 대기
        while (!configured) @(posedge aclk);
        $display("configured=1 (PL 자동설정 끝)");

        // 되읽기 obs 가 갱신되도록 대기 (몇 SAMPLE 주기)
        repeat (30000) @(posedge aclk);

        chk32("obs0(CANSTAT/CNF)", obs0, 32'h0000C080);
        chk32("obs1(EFLG/TEC/REC/INTF)", obs1, 32'h00000000);

        // DIP ON → 게이트 + 송신
        txc0 = u_mcp.tx_count;
        dip = 1;
        repeat (12000) @(posedge aclk);
        if (reflex_active) $display("[ ok ] DIP ON → reflex_active=1");
        else begin errors=errors+1; $display("[FAIL] DIP ON 인데 reflex_active=0"); end
        if (u_mcp.tx_count > txc0) $display("[ ok ] 버스 송신 증가 (%0d→%0d)", txc0, u_mcp.tx_count);
        else begin errors=errors+1; $display("[FAIL] 송신 안 늘어남"); end
        if (u_mcp.last_tx_id===11'h150) $display("[ ok ] 송신 ID=0x150");
        else begin errors=errors+1; $display("[FAIL] 송신 ID=0x%03h", u_mcp.last_tx_id); end

        dip = 0;
        repeat (10) @(posedge aclk);
        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d", u_mcp.tx_fail_cnt); end

        if (errors==0) $display("==== PASS: 스텝1 PL 통합 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end

    initial begin
        #30_000_000;
        $display("==== FAIL: 타임아웃 ====");
        $finish;
    end
endmodule
