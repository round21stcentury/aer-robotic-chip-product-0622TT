`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex_s2 — 스텝2 칩 통합 시뮬 (★정상 패스스루 + e-stop 반사 먹스)
//   검증: ① 평상시(dip=0) 정상명령 통과 ② dip=1 → 0x150 e-stop 주입
//        ③ dip=1 중 정상명령 트리거해도 ★차단(먹스가 무시)★ ④ dip=0 → 정상 재개.
//============================================================================
module tb_tt_um_reflex_s2;
    reg clk=0, rst_n=0; always #5 clk=~clk; integer errors=0;
    wire [7:0] uo_out, uio_out, uio_oe; reg [7:0] ui_in, uio_in;
    wire pls_sclk, pls_mosi, pls_csn;
    wire chip_s_miso = uio_out[3];
    wire m_sclk=uio_out[4], m_mosi=uio_out[5], m_csn=uio_out[6];
    wire mcp_miso, mcp_int_n;
    reg m_start, m_rw; reg [6:0] m_addr; reg [15:0] m_wdata; wire [15:0] m_rdata; wire m_busy, m_done;
    reg dip;                                       // ★반사 트리거
    always @* uio_in = {5'b0, pls_csn, pls_mosi, pls_sclk};

    // SEND_DIV 작게(반사 송신 빠르게), PROBE/RESET 작게
    tt_um_reflex_s2 #(.SEND_DIV(2000), .PROBE_DIV(1500), .RESET_DELAY(200)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );
    spi_master #(.HALF(8)) u_plm (
        .clk(clk), .rst_n(rst_n), .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_s_miso)
    );
    mcp2515_model_v2 u_mcp (.sclk(m_sclk), .mosi(m_mosi), .csn(m_csn), .miso(mcp_miso), .int_n(mcp_int_n));
    // ui_in: [7]arm=1 [3]mcp_miso [2]mcp_int [1]danger1=0 [0]dip(트리거)
    always @* ui_in = {1'b1, 3'b000, mcp_miso, mcp_int_n, 1'b0, dip};

    task spi_xfer(input rw, input [6:0] a, input [15:0] wd, output [15:0] rd);
        begin @(posedge clk); m_rw=rw; m_addr=a; m_wdata=wd; m_start=1'b1;
              @(posedge clk); m_start=1'b0; wait(m_done); @(posedge clk); rd=m_rdata; end
    endtask
    // 정상프레임 적재 + 송신 트리거
    task load_norm(input [10:0] id, input [15:0] d10, input [15:0] d32, input [15:0] d54, input [15:0] d76);
        reg [15:0] rd;
        begin
            spi_xfer(1'b0,7'h50,{5'b0,id},rd); spi_xfer(1'b0,7'h51,d10,rd); spi_xfer(1'b0,7'h52,d32,rd);
            spi_xfer(1'b0,7'h53,d54,rd); spi_xfer(1'b0,7'h54,d76,rd); spi_xfer(1'b0,7'h55,16'h0001,rd);
        end
    endtask

    reg [15:0] rd; integer txc;
    initial begin
        m_start=0; m_rw=0; m_addr=0; m_wdata=0; dip=0;
        repeat (10) @(posedge clk); rst_n=1; repeat (10) @(posedge clk);
        $display("== 스텝2: 정상 패스스루 + e-stop 반사 (칩 통합) ==");
        spi_xfer(1'b1,7'h00,0,rd); if(rd!==16'hCAFD) begin errors=errors+1; $display("[FAIL] MAGIC=%04h",rd); end else $display("[ ok ] MAGIC");
        spi_xfer(1'b1,7'h01,0,rd); if(rd!==16'h0521) begin errors=errors+1; $display("[FAIL] VERSION=%04h",rd); end else $display("[ ok ] VERSION=0521");
        rd=0; while(!rd[3]) begin spi_xfer(1'b1,7'h20,0,rd); repeat(50)@(posedge clk); end
        $display("초기화 완료");
        repeat (4000) @(posedge clk);

        // ① 평상시(dip=0): 정상명령 0x155 통과
        txc=u_mcp.tx_count;
        load_norm(11'h155, 16'h2211, 16'h4433, 16'h6655, 16'h8877);
        repeat (6000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h155 && u_mcp.last_tx_data===64'h8877_6655_4433_2211)
            $display("[ ok ] (1) 평상시 정상명령 0x155 통과");
        else begin errors=errors+1; $display("[FAIL] (1) 정상통과 실패 id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ② dip=1 → e-stop 0x150 주입
        dip=1;
        repeat (8000) @(posedge clk);    // 디바운스 + SEND_DIV
        if (u_mcp.last_tx_id===11'h150 && u_mcp.last_tx_data[7:0]===8'h01)
            $display("[ ok ] (2) 트리거 -> e-stop 0x150(B0=01) 주입");
        else begin errors=errors+1; $display("[FAIL] (2) e-stop 안 나옴 id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end
        if (uo_out[5]===1'b1) $display("[ ok ]   gate_active(uo[5])=1 (정상 차단중)");
        else begin errors=errors+1; $display("[FAIL] gate_active=0"); end

        // ③ dip=1 중 정상명령 0x156 트리거 → ★차단(먹스 무시), last_tx_id 여전히 0x150
        load_norm(11'h156, 16'hBBAA, 16'hDDCC, 16'h0000, 16'h0000);
        repeat (8000) @(posedge clk);
        if (u_mcp.last_tx_id===11'h150)
            $display("[ ok ] (3) 트리거 중 정상명령 0x156 ★차단★ (last id 여전히 0x150)");
        else begin errors=errors+1; $display("[FAIL] (3) 차단 실패 — 정상명령이 샘 id=%03h",u_mcp.last_tx_id); end

        // ④ dip=0 → 정상 재개. 0x157 통과
        dip=0;
        repeat (3000) @(posedge clk);
        txc=u_mcp.tx_count;
        load_norm(11'h157, 16'hA2A1, 16'hA4A3, 16'hA6A5, 16'hA8A7);
        repeat (6000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h157 && u_mcp.last_tx_data===64'hA8A7_A6A5_A4A3_A2A1)
            $display("[ ok ] (4) 해제 후 정상명령 0x157 재개");
        else begin errors=errors+1; $display("[FAIL] (4) 재개 실패 id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d",u_mcp.tx_fail_cnt); end

        repeat (50) @(posedge clk);
        if (errors==0) $display("==== PASS: 스텝2 e-stop 반사 + 패스스루 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #40_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
