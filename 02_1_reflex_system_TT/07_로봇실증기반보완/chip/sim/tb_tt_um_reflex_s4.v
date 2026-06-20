`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex_s4 — 스텝4 칩 통합 (★정상 패스스루 + 현재포즈 움츠림 반사 먹스)
//   ① 현재포즈 RX 수신 ② 평상시 정상명령 통과 ③ 움츠림 트리거(danger1)→0x155 j2=현재+델타
//      +정상차단 ④ 해제=센서뗌+도달(rule b) → 정상 재개.
//   트리거=소프트(danger1, rule1=0x1B src=0 digital). 델타=recoil_d2=+15000(SPI).
//============================================================================
module tb_tt_um_reflex_s4;
    reg clk=0, rst_n=0; always #5 clk=~clk; integer errors=0;
    wire [7:0] uo_out, uio_out, uio_oe; reg [7:0] ui_in, uio_in;
    wire pls_sclk, pls_mosi, pls_csn;
    wire chip_s_miso = uio_out[3];
    wire m_sclk=uio_out[4], m_mosi=uio_out[5], m_csn=uio_out[6];
    wire mcp_miso, mcp_int_n;
    reg m_start, m_rw; reg [6:0] m_addr; reg [15:0] m_wdata; wire [15:0] m_rdata; wire m_busy, m_done;
    reg dip_r=0, danger1_r=0, arm_r=1;
    always @* uio_in = {5'b0, pls_csn, pls_mosi, pls_sclk};

    tt_um_reflex_s4 #(.SEND_DIV(3000), .PROBE_DIV(2000), .RESET_DELAY(200)) dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );
    spi_master #(.HALF(8)) u_plm (
        .clk(clk), .rst_n(rst_n), .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_s_miso)
    );
    mcp2515_model_v2 u_mcp (.sclk(m_sclk), .mosi(m_mosi), .csn(m_csn), .miso(mcp_miso), .int_n(mcp_int_n));
    // ui_in: [7]arm [3]mcp_miso [2]mcp_int [1]danger1(움츠림 트리거) [0]dip(estop)
    always @* ui_in = {arm_r, 3'b000, mcp_miso, mcp_int_n, danger1_r, dip_r};

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
    integer w;
    task inject_wait(input [10:0] id, input [63:0] data);
        begin
            @(posedge clk); u_mcp.mdl_rx_inject(id, 4'd8, data);
            w=0; while (u_mcp.regs[8'h2C][0]!==1'b0 && w<200000) begin @(posedge clk); w=w+1; end
            repeat (200) @(posedge clk);
        end
    endtask

    reg [15:0] rd; integer txc; reg signed [31:0] t2;
    initial begin
        m_start=0; m_rw=0; m_addr=0; m_wdata=0;
        repeat (10) @(posedge clk); rst_n=1; repeat (10) @(posedge clk);
        $display("== 스텝4: 정상 패스스루 + 현재포즈 움츠림 (칩 통합) ==");
        spi_xfer(1'b1,7'h01,0,rd); if(rd!==16'h0542) begin errors=errors+1; $display("[FAIL] VER=%04h",rd); end else $display("[ ok ] VERSION=0542");
        spi_xfer(1'b1,7'h11,0,rd); if(rd!==16'h001C) begin errors=errors+1; $display("[FAIL] rule1=%04h(0x1C 기대)",rd); end else $display("[ ok ] rule1=0x001C(소프트→움츠림_현재)");
        rd=0; while(!rd[3]) begin spi_xfer(1'b1,7'h20,0,rd); repeat(50)@(posedge clk); end
        $display("초기화 완료");
        repeat (5000) @(posedge clk);

        // 델타 + ★움츠림 1회성 타이머(sim용 짧게=20000틱) 프로그래밍
        spi_xfer(1'b0,7'h41,16'h3A98,rd);          // RECOIL_DELTA_J2 = +15000
        spi_xfer(1'b0,7'h46,16'h4E20,rd);          // ★FLINCH_LO=20000 (1회성 지속, sim용 짧게)
        spi_xfer(1'b0,7'h47,16'h0000,rd);          // FLINCH_HI=0
        // 현재 포즈 수신: 0x2A5 j1=0, j2=30000 → idata=0x3075_0000_0000_0000. 그리고 미도달(0x2A1 D4=1)
        inject_wait(11'h2A5, 64'h3075_0000_0000_0000);
        inject_wait(11'h2A1, 64'h0000_0001_0000_0000);

        // ② 평상시(danger1=0): 정상명령 0x155=8877.. 통과
        txc=u_mcp.tx_count;
        load_norm(11'h155, 16'h2211, 16'h4433, 16'h6655, 16'h8877);
        repeat (8000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h155 && u_mcp.last_tx_data===64'h8877_6655_4433_2211)
            $display("[ ok ] (2) 평상시 정상명령 0x155 통과");
        else begin errors=errors+1; $display("[FAIL] (2) id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ③ 움츠림 트리거(danger1=1): 발동 즉시 게이트 닫힘 확인 후, 0x155 J2=45000(현재+델타) 확인
        danger1_r=1;
        repeat (1000) @(posedge clk);                  // ★발동+디바운스(recoil 명백히 활성) — 게이트 먼저
        if (uo_out[5]===1'b1) $display("[ ok ]   gate_active=1 (발동·정상 차단중)");
        else begin errors=errors+1; $display("[FAIL] gate_active=0"); end
        txc=u_mcp.tx_count;
        w=0; while (!(u_mcp.tx_count>txc && u_mcp.last_tx_id==11'h155) && w<300000) begin @(posedge clk); w=w+1; end
        t2 = {u_mcp.last_tx_data[39:32], u_mcp.last_tx_data[47:40], u_mcp.last_tx_data[55:48], u_mcp.last_tx_data[63:56]};
        if (u_mcp.last_tx_id===11'h155 && t2===32'sd45000)
            $display("[ ok ] (3) 움츠림 -> 0x155 J2=45000 (현재30000+델타15000) ★현재포즈 기반");
        else begin errors=errors+1; $display("[FAIL] (3) J2=%0d (45000 기대) id=%03h data=%016h",t2,u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ③b ★1회성 자동해제: danger1 계속 1이어도 flinch_ticks(20000) 후 해제 → 정상 재개 (움찔식)
        repeat (30000) @(posedge clk);            // > flinch_ticks
        txc=u_mcp.tx_count;
        load_norm(11'h157, 16'hA2A1, 16'hA4A3, 16'hA6A5, 16'hA8A7);
        repeat (8000) @(posedge clk);
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id===11'h157 && u_mcp.last_tx_data===64'hA8A7_A6A5_A4A3_A2A1)
            $display("[ ok ] (3b) ★1회성 자동해제(danger1 계속 1인데도) → 정상 0x157 재개");
        else begin errors=errors+1; $display("[FAIL] (3b) 자동해제 안됨 id=%03h data=%016h",u_mcp.last_tx_id,u_mcp.last_tx_data); end

        // ④ ★재무장: 센서 내렸다(0) 다시 올리면(1) 또 움츠림 (현재포즈 재래치 → J2=45000)
        danger1_r=0; repeat (3000) @(posedge clk);
        danger1_r=1; txc=u_mcp.tx_count;
        w=0; while (!(u_mcp.tx_count>txc && u_mcp.last_tx_id==11'h155) && w<300000) begin @(posedge clk); w=w+1; end
        t2 = {u_mcp.last_tx_data[39:32], u_mcp.last_tx_data[47:40], u_mcp.last_tx_data[55:48], u_mcp.last_tx_data[63:56]};
        if (u_mcp.last_tx_id===11'h155 && t2===32'sd45000)
            $display("[ ok ] (4) ★센서 내렸다 올리니 재무장+재발동 (J2=45000)");
        else begin errors=errors+1; $display("[FAIL] (4) 재무장 실패 J2=%0d id=%03h",t2,u_mcp.last_tx_id); end
        danger1_r=0; repeat (30000) @(posedge clk);   // 해제(다음 검사 위해)

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d", u_mcp.tx_fail_cnt); end

        repeat (50) @(posedge clk);
        if (errors==0) $display("==== PASS: 스텝4 현재포즈 움츠림 + 패스스루 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #80_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
