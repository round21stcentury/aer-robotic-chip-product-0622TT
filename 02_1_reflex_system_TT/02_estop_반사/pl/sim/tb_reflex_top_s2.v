`timescale 1ns / 1ps
//============================================================================
// tb_reflex_top_s2 — 스텝2 PL 통합 시뮬 (reflex_top_s2 ─ MCP 모델)
//   configured + obs 되읽기(관측) + DIP→reflex_active+0x150 송신 확인.
//============================================================================
module tb_reflex_top_s2;
    reg aclk=0, aresetn=0;
    always #5 aclk = ~aclk;
    integer errors=0;
    reg         dip=0;
    reg  [15:0] cfg_in = 16'h0104;
    wire [31:0] obs0, obs1;
    wire        reflex_active, configured;
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s2 #(.SPI_HALF(8), .SEND_DIV(3000), .PROBE_DIV(1500), .SAMPLE_DIV(1500), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .dip(dip), .cfg_in(cfg_in),
        .obs0(obs0), .obs1(obs1), .reflex_active(reflex_active), .configured(configured),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );
    mcp2515_model_v2 u_mcp (.sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int));

    task chk32(input [8*12:1] label, input [31:0] got, input [31:0] exp);
        begin if (got!==exp) begin errors=errors+1; $display("[FAIL] %0s=0x%08h (기대 0x%08h)",label,got,exp); end
              else $display("[ ok ] %0s=0x%08h",label,got); end
    endtask
    integer txc0;
    initial begin
        repeat (10) @(posedge aclk); aresetn=1;
        $display("== 스텝2 PL 통합: reflex_top_s2 ─ MCP 모델 ==");
        while (!configured) @(posedge aclk);
        $display("configured=1");
        repeat (30000) @(posedge aclk);
        chk32("obs0(CANSTAT/CNF)", obs0, 32'h0000C080);
        chk32("obs1(EFLG..INTF)", obs1, 32'h00000000);
        txc0=u_mcp.tx_count; dip=1; repeat (12000) @(posedge aclk);
        if (reflex_active) $display("[ ok ] DIP ON → reflex_active=1");
        else begin errors=errors+1; $display("[FAIL] reflex_active=0"); end
        if (u_mcp.tx_count>txc0 && u_mcp.last_tx_id===11'h150) $display("[ ok ] 0x150 송신 (%0d→%0d)",txc0,u_mcp.tx_count);
        else begin errors=errors+1; $display("[FAIL] 송신 문제 id=0x%03h",u_mcp.last_tx_id); end
        dip=0; repeat (10) @(posedge aclk);
        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0"); else begin errors=errors+1; $display("[FAIL] tx_fail=%0d",u_mcp.tx_fail_cnt); end
        if (errors==0) $display("==== PASS: 스텝2 PL 통합 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #30_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
