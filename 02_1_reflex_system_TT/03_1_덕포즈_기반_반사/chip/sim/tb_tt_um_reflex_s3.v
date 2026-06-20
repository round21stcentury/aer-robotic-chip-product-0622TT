`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex_s3 — 스텝3 칩 통합 (★정상 패스스루 + estop + 홈포즈 반사 먹스)
//   ① 평상시 정상명령 통과 ② pose 트리거(danger1) → 홈포즈(0x155~7=0) 주입·정상차단
//   ③ estop(dip) 우선(>pose) → 0x150 ④ 해제 → 정상 재개.
//============================================================================
module tb_tt_um_reflex_s3;
    reg clk=0, rst_n=0; always #5 clk=~clk; integer errors=0;
    wire [7:0] uo_out, uio_out, uio_oe; reg [7:0] ui_in, uio_in;
    wire pls_sclk, pls_mosi, pls_csn;
    wire chip_s_miso = uio_out[3];
    wire m_sclk=uio_out[4], m_mosi=uio_out[5], m_csn=uio_out[6];
    wire mcp_miso, mcp_int_n;
    reg m_start, m_rw; reg [6:0] m_addr; reg [15:0] m_wdata; wire [15:0] m_rdata; wire m_busy, m_done;
    reg dip, danger1;
    always @* uio_in = {5'b0, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s3 #(.SEND_DIV(2000), .PROBE_DIV(1500), .RESET_DELAY(200)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );
    spi_master #(.HALF(8)) u_plm (
        .clk(clk), .rst_n(rst_n), .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_s_miso)
    );
    mcp2515_model_v2 u_mcp (.sclk(m_sclk), .mosi(m_mosi), .csn(m_csn), .miso(mcp_miso), .int_n(mcp_int_n));
    // ui_in: [7]arm=1 [3]mcp_miso [2]mcp_int [1]danger1(pose) [0]dip(estop)
    always @* ui_in = {1'b1, 3'b000, mcp_miso, mcp_int_n, danger1, dip};

    task spi_xfer(input rw, input [6:0] a, input [15:0] wd, output [15:0] rd);
        begin @(posedge clk); m_rw=rw; m_addr=a; m_wdata=wd; m_start=1'b1;
              @(posedge clk); m_start=1'b0; wait(m_done); @(posedge clk); rd=m_rdata; end
    endtask
    task load_norm(input [10:0] id, input [15:0] d10, input [15:0] d32, input [15:0] d54, input [15:0] d76);
        reg [15:0] rd;
        begin
            spi_xfer(1'b0,7'h50,{5'b0,id},rd); spi_xfer(1'b0,7'h51,d10,rd); spi_xfer(1'b0,7'h52,d32,rd);
            spi_xfer(1'b0,7'h53,d54,rd); spi_xfer(1'b0,7'h54,d76,rd); spi_xfer(1'b0,7'h55,16'h0001,rd);
        end
    endtask

    reg [15:0] rd; integer txc; reg saw151, sawpose; integer ws;
    initial begin
        m_start=0; m_rw=0; m_addr=0; m_wdata=0; dip=0; danger1=0;
        repeat (10) @(posedge clk); rst_n=1; repeat (10) @(posedge clk);
        $display("== 스텝3: 정상 패스스루 + estop + 홈포즈 반사 ==");
        spi_xfer(1'b1,7'h01,0,rd); if(rd!==16'h0531) begin errors=errors+1; $display("[FAIL] VER=%04h",rd); end else $display("[ ok ] VERSION=0531");
        spi_xfer(1'b1,7'h11,0,rd); if(rd!==16'h001A) begin errors=errors+1; $display("[FAIL] rule1=%04h(0x1A 기대)",rd); end else $display("[ ok ] rule1=0x001A(pose)");
        rd=0; while(!rd[3]) begin spi_xfer(1'b1,7'h20,0,rd); repeat(50)@(posedge clk); end
        $display("초기화 완료");
        repeat (4000) @(posedge clk);

        // ① 평상시: 정상명령 0x155=8877.. 통과
        txc=u_mcp.tx_count;
        load_norm(11'h155, 16'h2211, 16'h4433, 16'h6655, 16'h8877);
        repeat (6000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h155 && u_mcp.last_tx_data===64'h8877_6655_4433_2211)
            $display("[ ok ] (1) 평상시 정상명령 0x155 통과");
        else begin errors=errors+1; $display("[FAIL] (1) id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ② pose 트리거(danger1=1): 정상명령 주입해도 ★0x151 속도(100) + 홈포즈(0)★ 가 나가야 (정상차단)
        danger1=1;
        repeat (10000) @(posedge clk);    // 디바운스 + 포즈 송신
        load_norm(11'h155, 16'h2211, 16'h4433, 16'h6655, 16'h8877);   // 정상명령(차단되어야)
        saw151=0; sawpose=0;
        for (ws=0; ws<14000; ws=ws+1) begin @(posedge clk);
            if (u_mcp.last_tx_id===11'h151 && u_mcp.last_tx_data[23:16]===8'h64) saw151=1;   // 0x151 D2=속도=100
            if ((u_mcp.last_tx_id===11'h155||u_mcp.last_tx_id===11'h156||u_mcp.last_tx_id===11'h157) && u_mcp.last_tx_data===64'h0) sawpose=1;
        end
        if (uo_out[5]===1'b1 && sawpose && saw151)
            $display("[ ok ] (2) pose -> ★0x151 속도=100 + 홈포즈(0) 주입, 정상차단");
        else begin errors=errors+1; $display("[FAIL] (2) gate=%b sawpose=%b saw151=%b",uo_out[5],sawpose,saw151); end

        // ③ estop(dip=1) 우선 (>pose): 0x150
        dip=1;
        repeat (10000) @(posedge clk);
        if (u_mcp.last_tx_id===11'h150 && u_mcp.last_tx_data[7:0]===8'h01)
            $display("[ ok ] (3) estop(dip) 우선 -> 0x150 (pose 무시)");
        else begin errors=errors+1; $display("[FAIL] (3) estop 우선 실패 id=%03h",u_mcp.last_tx_id); end

        // ④ 해제(둘 다 0): 정상 재개. 0x157=A8.. 통과
        dip=0; danger1=0;
        repeat (6000) @(posedge clk);
        txc=u_mcp.tx_count;
        load_norm(11'h157, 16'hA2A1, 16'hA4A3, 16'hA6A5, 16'hA8A7);
        repeat (6000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h157 && u_mcp.last_tx_data===64'hA8A7_A6A5_A4A3_A2A1)
            $display("[ ok ] (4) 해제 후 정상명령 0x157 재개");
        else begin errors=errors+1; $display("[FAIL] (4) 재개 실패 id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ⑤ ★움찔(act3 엣지 1회성): rule2=0x5B(act3,src=1) + thresh2 + flinch 짧게 + xadc 높여 발동
        //    → 홈포즈 잠깐 → flinch_ticks 후 ★자동해제(xadc 계속 높아도) → 센서 내렸다 올리면 재무장
        spi_xfer(1'b0,7'h12,16'h005B,rd);   // rule2 = act3(움찔), src=1, prio1, en
        spi_xfer(1'b0,7'h1A,16'h0100,rd);   // thresh2 작게
        spi_xfer(1'b0,7'h46,16'd20000,rd);  // flinch 지속 = 20000 틱 (lo) — 0x151+홈포즈 사이클 충분히
        spi_xfer(1'b0,7'h47,16'd0,rd);      // flinch (hi)
        repeat(2000)@(posedge clk);
        spi_xfer(1'b0,7'h30,16'h0800,rd);   // ★xadc ≥ thresh2 → act3 상승엣지 → 움찔 시작
        saw151=0; sawpose=0;
        for (ws=0; ws<12000; ws=ws+1) begin @(posedge clk);   // 움찔 중(< 20000틱) 샘플
            if (u_mcp.last_tx_id===11'h151 && u_mcp.last_tx_data[23:16]===8'h64) saw151=1;
            if ((u_mcp.last_tx_id===11'h155||u_mcp.last_tx_id===11'h156||u_mcp.last_tx_id===11'h157) && u_mcp.last_tx_data===64'h0) sawpose=1;
        end
        if (uo_out[5]===1'b1 && sawpose && saw151)
            $display("[ ok ] (5a) 움찔 발동 -> ★0x151 속도=100 + 홈포즈(0), gate=1");
        else begin errors=errors+1; $display("[FAIL] (5a) gate=%b sawpose=%b saw151=%b",uo_out[5],sawpose,saw151); end
        repeat(12000)@(posedge clk);         // flinch_ticks(20000) 경과 → 자동해제 (xadc 여전히 0x800)
        if (uo_out[5]===1'b0)
            $display("[ ok ] (5b) flinch_ticks 후 ★자동해제 (xadc 계속 높음에도 gate=0 → 움찔=1회성)");
        else begin errors=errors+1; $display("[FAIL] (5b) 자동해제 안됨 gate=%b",uo_out[5]); end
        spi_xfer(1'b0,7'h30,16'h0000,rd);   // 센서 뗌 (재무장)
        repeat(2000)@(posedge clk);
        spi_xfer(1'b0,7'h30,16'h0800,rd);   // 다시 올림 → 재발동
        repeat(4000)@(posedge clk);
        if (uo_out[5]===1'b1)
            $display("[ ok ] (5c) 센서 내렸다 올리니 ★재무장+재발동 (gate=1)");
        else begin errors=errors+1; $display("[FAIL] (5c) 재발동 안됨 gate=%b",uo_out[5]); end
        spi_xfer(1'b0,7'h30,16'h0000,rd); spi_xfer(1'b0,7'h12,16'h0000,rd);   // 정리(xadc·rule2 끔)
        repeat(8000)@(posedge clk);

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d",u_mcp.tx_fail_cnt); end

        repeat (50) @(posedge clk);
        if (errors==0) $display("==== PASS: 스텝3 홈포즈 반사 + 패스스루 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #60_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
