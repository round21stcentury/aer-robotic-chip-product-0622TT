`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex_s1 — 스텝1 칩 전체 통합 시뮬
//----------------------------------------------------------------------------
//  실물 HIL 토폴로지를 시뮬로 재현:
//    PL spi_master ─SPI─ 칩(tt_um_reflex_s1) ─SPI─ mcp2515_model_v2
//  검증 항목(스텝1 합격 기준의 시뮬 대응):
//   1) 칩이 MCP 를 ★설정★ 했나: 되읽기 CNF1/2/3=00/C0/80, CANSTAT OPMOD=000(정상).
//   2) DIP ON → 칩이 0x150(B0=01) 을 ★송신★(model tx_count 증가, last_tx_id=0x150).
//   3) DIP OFF → 송신 멈춤.
//   4) ★PS 프로그래밍 가능한 SPI 속도★: SPI_DIV(0x03) 써넣고 되읽기 일치 + 통신 유지.
//   5) tx_fail_cnt==0 (잘못된 모드에서 송신 시도 없음 = 설정 순서 정상).
//============================================================================
module tb_tt_um_reflex_s1;
    reg clk=0, rst_n=0;
    always #5 clk = ~clk;        // 100MHz? -> 10ns. (분주는 상대적이라 무관)

    integer errors=0;

    // ── 칩 ──
    wire [7:0] uo_out, uio_out, uio_oe;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;

    // PL master 핀
    wire pls_sclk, pls_mosi, pls_csn;
    wire chip_s_miso = uio_out[3];      // 칩 슬레이브 MISO
    // 칩→MCP 핀
    wire m_sclk = uio_out[4];
    wire m_mosi = uio_out[5];
    wire m_csn  = uio_out[6];
    wire mcp_miso, mcp_int_n;

    // PL master
    reg         m_start, m_rw;
    reg  [6:0]  m_addr;
    reg  [15:0] m_wdata;
    wire [15:0] m_rdata;
    wire        m_busy, m_done;

    // uio_in: [2]csn [1]mosi [0]sclk (PL 마스터 구동). ui_in: [0]dip [2]mcp_int [3]m_miso [7]arm
    always @* begin
        uio_in = {5'b0, pls_csn, pls_mosi, pls_sclk};
    end

    tt_um_reflex_s1 #(.SEND_DIV(3000), .PROBE_DIV(1500), .RESET_DELAY(200)) dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(1'b1), .clk(clk), .rst_n(rst_n)
    );

    spi_master #(.HALF(8)) u_plm (
        .clk(clk), .rst_n(rst_n),
        .start(m_start), .rw(m_rw), .addr(m_addr), .wdata(m_wdata),
        .rdata(m_rdata), .busy(m_busy), .done(m_done),
        .sclk(pls_sclk), .mosi(pls_mosi), .csn(pls_csn), .miso(chip_s_miso)
    );

    mcp2515_model_v2 u_mcp (
        .sclk(m_sclk), .mosi(m_mosi), .csn(m_csn), .miso(mcp_miso), .int_n(mcp_int_n)
    );

    // 칩 입력 결선: ui_in[3]=mcp_miso, ui_in[2]=mcp_int_n
    reg dip_r=0, arm_r=1;
    always @* ui_in = {arm_r, 3'b000, mcp_miso, mcp_int_n, 1'b0, dip_r};

    // ── PL master 트랜잭션 태스크 ──
    task spi_xfer(input rw, input [6:0] a, input [15:0] wd, output [15:0] rd);
        begin
            @(posedge clk); m_rw=rw; m_addr=a; m_wdata=wd; m_start=1'b1;
            @(posedge clk); m_start=1'b0;
            wait (m_done);
            @(posedge clk);
            rd = m_rdata;
        end
    endtask

    task chk16(input [8*20:1] label, input [15:0] got, input [15:0] exp);
        begin
            if (got!==exp) begin errors=errors+1; $display("[FAIL] %0s = 0x%04h (기대 0x%04h)", label, got, exp); end
            else $display("[ ok ] %0s = 0x%04h", label, got);
        end
    endtask

    reg [15:0] rd;
    integer txc_before, txc_after;

    initial begin
        m_start=0; m_rw=0; m_addr=0; m_wdata=0;
        repeat (10) @(posedge clk);
        rst_n=1;
        repeat (10) @(posedge clk);
        $display("== 스텝1: MCP 제어기 실증 (칩-MCP 통합 시뮬) ==");

        // 0) 통신 확인: ID_MAGIC, VERSION
        spi_xfer(1'b1, 7'h00, 16'h0, rd); chk16("ID_MAGIC", rd, 16'hCAFD);
        spi_xfer(1'b1, 7'h01, 16'h0, rd); chk16("VERSION",  rd, 16'h0501);

        // 1) 초기화 완료 대기 (status[4]=init_done)
        rd=0;
        while (!rd[4]) begin spi_xfer(1'b1, 7'h20, 16'h0, rd); repeat(50) @(posedge clk); end
        $display("초기화 완료 (status=0x%04h)", rd);

        // probe 가 한 바퀴 돌도록 대기
        repeat (4000) @(posedge clk);

        // 1') ★관측: 칩이 되읽은 MCP 설정값 확인 (모델이 설정모드에서만 받았어야 함)
        spi_xfer(1'b1, 7'h23, 16'h0, rd); chk16("MCP CNF1(0x2A)", rd, 16'h0000);
        spi_xfer(1'b1, 7'h24, 16'h0, rd); chk16("MCP CNF2(0x29)", rd, 16'h00C0);
        spi_xfer(1'b1, 7'h25, 16'h0, rd); chk16("MCP CNF3(0x28)", rd, 16'h0080);
        spi_xfer(1'b1, 7'h21, 16'h0, rd);
        if ((rd[7:5])!==3'b000) begin errors=errors+1; $display("[FAIL] CANSTAT OPMOD != 정상 (0x%04h)", rd); end
        else $display("[ ok ] CANSTAT 정상모드 (0x%04h)", rd);

        // 2) DIP ON → 송신 시작
        txc_before = u_mcp.tx_count;
        dip_r = 1;
        repeat (12000) @(posedge clk);     // 여러 프레임 주기 경과
        txc_after = u_mcp.tx_count;
        if (txc_after > txc_before) $display("[ ok ] DIP ON → 송신 %0d→%0d 회 (증가)", txc_before, txc_after);
        else begin errors=errors+1; $display("[FAIL] DIP ON 인데 송신 안 늘어남 (%0d→%0d)", txc_before, txc_after); end
        // 무엇이 나갔나
        if (u_mcp.last_tx_id!==11'h150) begin errors=errors+1; $display("[FAIL] 송신 ID=0x%03h (기대 0x150)", u_mcp.last_tx_id); end
        else $display("[ ok ] 송신 ID=0x150");
        if (u_mcp.last_tx_data[7:0]!==8'h01) begin errors=errors+1; $display("[FAIL] 비상정지 B0=0x%02h (기대 0x01)", u_mcp.last_tx_data[7:0]); end
        else $display("[ ok ] 비상정지 페이로드 B0=0x01");

        // 3) DIP OFF → 송신 멈춤
        //    ★진행 중이던 한 프레임(시퀀스 ~2500클럭)은 끝까지 나간다(정상). 그게 다 빠질
        //      때까지 충분히 기다린 뒤(드레인) 카운트를 고정하고, 그 후 안 늘어남을 본다.
        dip_r = 0;
        repeat (6000) @(posedge clk);      // 디바운스 + 진행 프레임 드레인
        txc_before = u_mcp.tx_count;
        repeat (12000) @(posedge clk);
        if (u_mcp.tx_count == txc_before) $display("[ ok ] DIP OFF → 송신 멈춤 (%0d 유지)", txc_before);
        else begin errors=errors+1; $display("[FAIL] DIP OFF 인데 송신 계속 (%0d→%0d)", txc_before, u_mcp.tx_count); end

        // 4) ★PS 프로그래밍 가능한 SPI 속도: SPI_DIV 변경 + 되읽기 + 통신 유지
        spi_xfer(1'b0, 7'h03, 16'h0006, rd);   // 반주기 6 으로 변경
        spi_xfer(1'b1, 7'h03, 16'h0, rd); chk16("SPI_DIV readback", rd, 16'h0006);
        spi_xfer(1'b1, 7'h00, 16'h0, rd); chk16("ID after spd chg", rd, 16'hCAFD);
        // 속도 바꾼 뒤에도 DIP 송신 동작
        dip_r=1; repeat (16000) @(posedge clk);
        if (u_mcp.tx_count > txc_before) $display("[ ok ] SPI 속도 변경 후에도 송신 동작 (tx=%0d)", u_mcp.tx_count);
        else begin errors=errors+1; $display("[FAIL] 속도 변경 후 송신 안 됨"); end
        dip_r=0;

        // 5) 잘못된 모드 송신 없었나
        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0 (설정 순서 정상, 모드 오류 송신 없음)");
        else begin errors=errors+1; $display("[FAIL] tx_fail_cnt=%0d (정상모드 아닐 때 송신 시도!)", u_mcp.tx_fail_cnt); end

        repeat (50) @(posedge clk);
        if (errors==0) $display("==== PASS: 스텝1 MCP 제어기 실증 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("[FAIL] 타임아웃");
        $display("==== FAIL: 타임아웃 ====");
        $finish;
    end
endmodule
