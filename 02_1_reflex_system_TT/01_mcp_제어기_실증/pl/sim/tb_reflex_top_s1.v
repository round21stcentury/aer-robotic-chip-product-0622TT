`timescale 1ns / 1ps
//============================================================================
// tb_reflex_top_s1 — 스텝1 PL 통합 시뮬 (★정상명령 패스스루: 메일박스→칩→MCP)
//   PS GPIO 메일박스(cmd_lo/hi/id)를 TB 가 구동(=PS lwIP 역할). reflex_top_s1 ─ MCP 모델.
//   검증: configured + obs(관측) + 메일박스 프레임이 칩 거쳐 MCP 로 중계됨.
//============================================================================
module tb_reflex_top_s1;
    reg aclk=0, aresetn=0; always #5 aclk=~aclk; integer errors=0;
    reg  [15:0] cfg_in = 16'h0104;     // enable + SPI_DIV 4
    reg  [31:0] cmd_lo=0, cmd_hi=0, cmd_id=0;
    wire [31:0] obs0, obs1;
    wire        configured;
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s1 #(.SPI_HALF(8), .PROBE_DIV(1500), .SAMPLE_DIV(1500), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .cfg_in(cfg_in),
        .cmd_lo(cmd_lo), .cmd_hi(cmd_hi), .cmd_id(cmd_id),
        .obs0(obs0), .obs1(obs1), .configured(configured),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );
    mcp2515_model_v2 u_mcp (.sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int));

    // PS lwIP 흉내: 프레임 한 장을 메일박스에 적재 (lo/hi 먼저, id+토글 마지막)
    reg tog=0;
    task send_frame(input [10:0] id, input [31:0] d_lo, input [31:0] d_hi);
        begin
            @(posedge aclk); cmd_lo<=d_lo; cmd_hi<=d_hi;
            @(posedge aclk); tog=~tog; cmd_id<={tog, 20'd0, id};   // ★토글 마지막
            repeat (8000) @(posedge aclk);                          // 릴레이(6 SPI 쓰기) 시간
        end
    endtask

    integer txc;
    initial begin
        repeat (10) @(posedge aclk); aresetn=1;
        $display("== 스텝1 PL 통합: 정상명령 패스스루 (reflex_top_s1 ─ MCP) ==");
        while (!configured) @(posedge aclk);
        $display("configured=1");
        repeat (30000) @(posedge aclk);
        if (obs0===32'h0000C080) $display("[ ok ] obs0=0x0000C080 (MCP 설정 관측)");
        else begin errors=errors+1; $display("[FAIL] obs0=0x%08h",obs0); end

        // 프레임1: id=0x155, data D0..D7 = 11 22 33 44 55 66 77 88
        txc=u_mcp.tx_count;
        send_frame(11'h155, 32'h44332211, 32'h88776655);
        if (u_mcp.tx_count>txc) $display("[ ok ] 메일박스 프레임 → MCP 중계 (tx %0d→%0d)",txc,u_mcp.tx_count);
        else begin errors=errors+1; $display("[FAIL] 중계 안 됨"); end
        if (u_mcp.last_tx_id===11'h155 && u_mcp.last_tx_data===64'h8877_6655_4433_2211)
            $display("[ ok ] id=0x155 data=88..11 정확 전달");
        else begin errors=errors+1; $display("[FAIL] id=0x%03h data=0x%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // 프레임2: id=0x156 (연속 스트림)
        txc=u_mcp.tx_count;
        send_frame(11'h156, 32'h04030201, 32'h08070605);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h156) $display("[ ok ] 두번째 0x156 중계");
        else begin errors=errors+1; $display("[FAIL] 두번째 중계 문제"); end

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0"); else begin errors=errors+1; $display("[FAIL] tx_fail=%0d",u_mcp.tx_fail_cnt); end
        if (errors==0) $display("==== PASS: 스텝1 PL 정상명령 패스스루 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #40_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
