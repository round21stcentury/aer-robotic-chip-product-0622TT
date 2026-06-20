`timescale 1ns / 1ps
//============================================================================
// tb_tt_um_reflex — 1단계 토폴로지 검증 테스트벤치
//----------------------------------------------------------------------------
//  PL(또는 별도 FPGA)이 칩에게 할 일을 흉내낸다.
//   1) SPI로 ID_MAGIC(0xCAFD)을 읽어 연결 확인
//   2) SPI로 SCRATCH에 값을 쓰고 다시 읽어 쓰기 경로 확인
//   3) 위험 입력을 넣어 fire/action_id가 병렬 신호로 나오는지 확인
//============================================================================
module tb_tt_um_reflex;
    // 칩 핀
    reg        clk = 0, rst_n = 0, ena = 1;
    reg  [7:0] ui_in = 8'h00;
    wire [7:0] uo_out;
    wire [7:0] uio_out, uio_oe;

    // tb가 구동하는 SPI 입력
    reg  sclk = 0, mosi = 0, csn = 1;
    wire [7:0] uio_in = {5'b00000, csn, mosi, sclk}; // uio[0]=sclk,[1]=mosi,[2]=csn
    wire miso = uio_out[3];

    integer errors = 0;

    tt_um_reflex dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #5 clk = ~clk;                 // 100MHz (주기 10ns)
    localparam SCLK_HALF = 40;            // SCLK 반주기 40ns = 칩 clk의 4배 → 8배 오버샘플

    // SPI 한 번 전송 (Mode 0). r=1 읽기, r=0 쓰기.
    task spi_xfer(input r, input [6:0] a, input [15:0] wd, output [15:0] rd);
        integer i; reg [23:0] mo; reg [15:0] ri;
        begin
            mo = {r, a, wd}; ri = 16'h0; csn = 0;
            for (i = 0; i < 24; i = i + 1) begin
                mosi = mo[23-i];               // SCLK가 낮을 때 비트 제시
                #SCLK_HALF; sclk = 1;          // 상승: 슬레이브가 MOSI 샘플
                if (i >= 8) ri = {ri[14:0], miso};  // 데이터 16비트는 상승에 MISO 샘플
                #SCLK_HALF; sclk = 0;          // 하강: 슬레이브가 다음 MISO 준비
            end
            #SCLK_HALF; csn = 1; mosi = 0;
            rd = ri; #(SCLK_HALF*2);
        end
    endtask

    reg [15:0] rd;
    initial begin
        rst_n = 0; ui_in = 8'h00; repeat (10) @(posedge clk);
        rst_n = 1; repeat (10) @(posedge clk);
        ui_in[7] = 1'b1;                       // arm_enable

        // 1) ID 읽기
        spi_xfer(1'b1, 7'h00, 16'h0000, rd);
        if (rd !== 16'hCAFD) begin errors=errors+1; $display("[FAIL] ID_MAGIC=%h (기대 CAFD)", rd); end
        else                  $display("[ OK ] ID_MAGIC=%h", rd);

        // 2) SCRATCH 쓰기 후 읽기
        spi_xfer(1'b0, 7'h02, 16'hBEEF, rd);
        spi_xfer(1'b1, 7'h02, 16'h0000, rd);
        if (rd !== 16'hBEEF) begin errors=errors+1; $display("[FAIL] SCRATCH=%h (기대 BEEF)", rd); end
        else                  $display("[ OK ] SCRATCH 쓰기/읽기=%h", rd);

        // 3) 위험 입력 → 반사 출력
        @(posedge clk); ui_in[0] = 1'b1;
        repeat (30) @(posedge clk);
        if (uo_out[1] !== 1'b1)      begin errors=errors+1; $display("[FAIL] fire가 안 섰다"); end
        else if (uo_out[4:2]!==3'd1) begin errors=errors+1; $display("[FAIL] action_id=%0d (기대 1)", uo_out[4:2]); end
        else                         $display("[ OK ] 위험 → fire=1, action_id=%0d (uo_out=%b)", uo_out[4:2], uo_out);

        ui_in[0] = 1'b0;
        repeat (30) @(posedge clk);
        if (uo_out[1] !== 1'b0) begin errors=errors+1; $display("[FAIL] 위험 해제 후에도 fire가 섰다"); end
        else                    $display("[ OK ] 위험 해제 → fire=0");

        if (errors == 0) $display("\n==== PASS: TT 스켈레톤 토폴로지 검증 통과 (SPI + 병렬 반사) ====");
        else             $display("\n==== FAIL: 오류 %0d개 ====", errors);
        $finish;
    end

    initial begin #2000000; $display("[FAIL] 타임아웃"); $finish; end
endmodule
