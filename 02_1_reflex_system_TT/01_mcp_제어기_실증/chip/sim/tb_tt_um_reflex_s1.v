`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex_s1 — 스텝1 칩 통합 시뮬 (★정상명령 패스스루)
//   PL master ─ 칩(tt_um_reflex_s1) ─ MCP 모델.
//   검증: ① 초기화·되읽기(관측) ② 칩 정상레지스터(0x50~0x55)에 프레임 적재+트리거 →
//        칩이 그 프레임을 MCP 로 중계(게이트=0 → 정상통과) ③ id/data 그대로 전달.
//============================================================================
module tb_tt_um_reflex_s1;
    reg clk=0, rst_n=0; always #5 clk=~clk; integer errors=0;
    wire [7:0] uo_out, uio_out, uio_oe; reg [7:0] ui_in, uio_in;
    wire pls_sclk, pls_mosi, pls_csn;
    wire chip_s_miso = uio_out[3];
    wire m_sclk=uio_out[4], m_mosi=uio_out[5], m_csn=uio_out[6];
    wire mcp_miso, mcp_int_n;
    reg m_start, m_rw; reg [6:0] m_addr; reg [15:0] m_wdata; wire [15:0] m_rdata; wire m_busy, m_done;
    always @* uio_in = {5'b0, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s1 #(.PROBE_DIV(1500), .RESET_DELAY(200)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );
    spi_master #(.HALF(8)) u_plm (
        .clk(clk), .rst_n(rst_n), .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_s_miso)
    );
    mcp2515_model_v2 u_mcp (.sclk(m_sclk), .mosi(m_mosi), .csn(m_csn), .miso(mcp_miso), .int_n(mcp_int_n));
    // ui_in: [7]arm=1 [3]mcp_miso [2]mcp_int (DIP 없음)
    always @* ui_in = {1'b1, 3'b000, mcp_miso, mcp_int_n, 2'b00};

    task spi_xfer(input rw, input [6:0] a, input [15:0] wd, output [15:0] rd);
        begin @(posedge clk); m_rw=rw; m_addr=a; m_wdata=wd; m_start=1'b1;
              @(posedge clk); m_start=1'b0; wait(m_done); @(posedge clk); rd=m_rdata; end
    endtask
    task chk16(input [8*18:1] label, input [15:0] got, input [15:0] exp);
        begin if (got!==exp) begin errors=errors+1; $display("[FAIL] %0s=0x%04h (기대 0x%04h)",label,got,exp); end
              else $display("[ ok ] %0s=0x%04h",label,got); end
    endtask

    reg [15:0] rd; integer txc;
    initial begin
        m_start=0; m_rw=0; m_addr=0; m_wdata=0;
        repeat (10) @(posedge clk); rst_n=1; repeat (10) @(posedge clk);
        $display("== 스텝1: 정상명령 패스스루 (칩 통합 시뮬) ==");
        spi_xfer(1'b1,7'h00,0,rd); chk16("ID_MAGIC",rd,16'hCAFD);
        spi_xfer(1'b1,7'h01,0,rd); chk16("VERSION",rd,16'h0511);

        rd=0; while(!rd[3]) begin spi_xfer(1'b1,7'h20,0,rd); repeat(50)@(posedge clk); end
        $display("초기화 완료 (status=0x%04h)", rd);
        repeat (4000) @(posedge clk);
        // 관측: MCP 설정 되읽기
        spi_xfer(1'b1,7'h23,0,rd); chk16("MCP CNF1",rd,16'h0000);
        spi_xfer(1'b1,7'h24,0,rd); chk16("MCP CNF2",rd,16'h00C0);
        spi_xfer(1'b1,7'h25,0,rd); chk16("MCP CNF3",rd,16'h0080);

        // ★정상 프레임 적재(0x50~0x54) + 트리거(0x55). id=0x155, data=11 22 33 44 55 66 77 88
        spi_xfer(1'b0,7'h50,16'h0155,rd);   // NORM_ID
        spi_xfer(1'b0,7'h51,16'h2211,rd);   // {D1,D0}=22,11
        spi_xfer(1'b0,7'h52,16'h4433,rd);   // {D3,D2}=44,33
        spi_xfer(1'b0,7'h53,16'h6655,rd);   // {D5,D4}=66,55
        spi_xfer(1'b0,7'h54,16'h8877,rd);   // {D7,D6}=88,77
        txc=u_mcp.tx_count;
        spi_xfer(1'b0,7'h55,16'h0001,rd);   // ★NORM_SEND 트리거
        repeat (6000) @(posedge clk);       // 칩이 MCP 로 중계할 시간

        if (u_mcp.tx_count>txc) $display("[ ok ] 정상프레임 → MCP 중계 (tx %0d→%0d)",txc,u_mcp.tx_count);
        else begin errors=errors+1; $display("[FAIL] 중계 안 됨"); end
        if (u_mcp.last_tx_id===11'h155) $display("[ ok ] 중계 ID=0x155 (정상명령 그대로)");
        else begin errors=errors+1; $display("[FAIL] ID=0x%03h (0x155 기대)",u_mcp.last_tx_id); end
        if (u_mcp.last_tx_data===64'h8877_6655_4433_2211) $display("[ ok ] 중계 데이터=88..11 (정확)");
        else begin errors=errors+1; $display("[FAIL] 데이터=0x%016h (8877665544332211 기대)",u_mcp.last_tx_data); end

        // 한 번 더 (연속 명령 스트림 흉내)
        spi_xfer(1'b0,7'h50,16'h0156,rd);
        spi_xfer(1'b0,7'h51,16'hBBAA,rd); spi_xfer(1'b0,7'h52,16'hDDCC,rd);
        spi_xfer(1'b0,7'h53,16'h0000,rd); spi_xfer(1'b0,7'h54,16'h0000,rd);
        txc=u_mcp.tx_count;
        spi_xfer(1'b0,7'h55,16'h0001,rd);
        repeat (6000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h156) $display("[ ok ] 두번째 프레임 0x156 중계");
        else begin errors=errors+1; $display("[FAIL] 두번째 중계 문제 id=0x%03h",u_mcp.last_tx_id); end

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0 (정상모드 송신)");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d",u_mcp.tx_fail_cnt); end

        repeat (50) @(posedge clk);
        if (errors==0) $display("==== PASS: 스텝1 정상명령 패스스루 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #25_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
