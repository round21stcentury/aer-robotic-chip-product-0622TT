`timescale 1ns / 1ps
//============================================================================
// spi_slave — 동기 오버샘플 SPI 슬레이브 (Mode 0: CPOL=0, CPHA=0)
//----------------------------------------------------------------------------
//  SPI 핀(sclk/mosi/csn)을 SCLK로 클럭하지 않고, 칩 clk로 2단 동기화한 뒤
//  엣지를 검출해서 처리한다. 이렇게 하면 칩 전체가 하나의 clk로 도므로
//  TinyTapeout 하드닝에 유리하다. (칩 clk가 SCLK보다 최소 8배 빨라야 안전.)
//
//  프레임: CS_n를 내린 뒤, 8비트 명령 {rw, addr[6:0]}(MSB 먼저) + 16비트 데이터.
//    rw=1 읽기: 명령 뒤 16클럭 동안 슬레이브가 MISO로 reg[addr]를 내보낸다.
//    rw=0 쓰기: 명령 뒤 16비트를 reg[addr]에 적는다.
//
//  레지스터(1단계 최소): 0x00 ID_MAGIC(읽기), 0x01 VERSION(읽기), 0x02 SCRATCH(읽기/쓰기)
//============================================================================
module spi_slave #(
    parameter [15:0] ID_MAGIC = 16'hCAFD,   // 살아있음 확인용 (CTU의 0xCAFD와 같은 방식)
    parameter [15:0] VERSION  = 16'h0100
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,
    input  wire mosi,
    input  wire csn,
    output reg  miso,
    output wire miso_oe    // CS_n를 내린 동안만 MISO를 구동
);
    // ── 2단 동기화 ──
    reg [1:0] sclk_s, mosi_s, csn_s;
    reg       sclk_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            sclk_s <= 2'b00; mosi_s <= 2'b00; csn_s <= 2'b11; sclk_d <= 1'b0;
        end else begin
            sclk_s <= {sclk_s[0], sclk};
            mosi_s <= {mosi_s[0], mosi};
            csn_s  <= {csn_s[0],  csn};
            sclk_d <= sclk_s[1];
        end
    end
    wire sclk_rise = sclk_s[1] & ~sclk_d;
    wire sclk_fall = ~sclk_s[1] & sclk_d;
    wire csn_active = ~csn_s[1];
    assign miso_oe = csn_active;

    // ── 수신/송신 상태 ──
    reg [22:0] rx;
    reg [4:0]  bitcnt;
    reg        rw;
    reg [6:0]  addr;
    reg [15:0] tx;
    reg        sending;
    reg [15:0] scratch;

    wire [7:0]  cmd_now  = {rx[6:0],  mosi_s[1]};   // 8번째 상승엣지에서의 명령 8비트
    wire [15:0] data_now = {rx[14:0], mosi_s[1]};   // 24번째 상승엣지에서의 데이터 16비트

    always @(posedge clk) begin
        if (!rst_n) begin
            rx <= 0; bitcnt <= 0; rw <= 0; addr <= 0; tx <= 0;
            sending <= 0; miso <= 0; scratch <= 16'h0000;
        end else if (!csn_active) begin
            bitcnt <= 0; sending <= 0;               // 비활성: 비트카운터 초기화
        end else begin
            if (sclk_rise) begin
                rx     <= {rx[21:0], mosi_s[1]};
                bitcnt <= bitcnt + 1'b1;
                if (bitcnt == 5'd7) begin            // 명령 8비트 완성
                    rw   <= cmd_now[7];
                    addr <= cmd_now[6:0];
                    if (cmd_now[7]) begin            // 읽기: 보낼 값 준비
                        sending <= 1'b1;
                        case (cmd_now[6:0])
                            7'h00:   tx <= ID_MAGIC;
                            7'h01:   tx <= VERSION;
                            7'h02:   tx <= scratch;
                            default: tx <= 16'h0000;
                        endcase
                    end
                end
                if (bitcnt == 5'd23) begin           // 데이터 16비트 완성(쓰기)
                    if (!rw && addr == 7'h02) scratch <= data_now;
                end
            end
            if (sclk_fall && sending) begin          // 하강엣지에 MISO 갱신(다음 상승에 마스터가 샘플)
                miso <= tx[15];
                tx   <= {tx[14:0], 1'b0};
            end
        end
    end
endmodule
