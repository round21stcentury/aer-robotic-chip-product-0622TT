`timescale 1ns / 1ps
//============================================================================
// spi_slave_s1 — 스텝1 칩 SPI 슬레이브 (PL 마스터가 칩을 프로그래밍/되읽기)
//----------------------------------------------------------------------------
//  04 spi_slave_v4 의 ★검증된 타이밍(2단동기화+엣지검출, 8비트 명령+16비트 데이터)★
//  을 그대로 쓰되, 스텝1 범위로 레지스터를 정리:
//   - 쓰기(PS→칩): CONTROL(0x02), ★SPI_DIV(0x03)=칩→MCP SPI 반주기★(런타임 속도).
//   - 읽기(칩→PS, ★관측성★): MCP 되읽기 진단(mcp_probe 가 채움)을 그대로 노출.
//
//  레지스터 맵 (16비트):
//    0x00 ID_MAGIC(R)=0xCAFD   0x01 VERSION(R)=0x0501   0x02 CONTROL(R/W) bit0=enable
//    0x03 SPI_DIV(R/W) [7:0]=칩→MCP SCLK 반주기 (기본 4 → sclk=clk/8)
//    0x20 STATUS(R)            0x21 CANSTAT(R)  0x22 CANCTRL(R)
//    0x23 CNF1(R) 0x24 CNF2(R) 0x25 CNF3(R) 0x26 EFLG(R)
//    0x27 {TEC,REC}(R)         0x28 CANINTF(R)
//============================================================================
module spi_slave_s1 #(
    parameter [15:0] ID_MAGIC = 16'hCAFD,
    parameter [15:0] VERSION  = 16'h0501
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,
    input  wire mosi,
    input  wire csn,
    output reg  miso,
    output wire miso_oe,
    // 설정 출력
    output reg  [15:0] control,
    output reg  [15:0] spi_div,        // [7:0] = 칩→MCP SCLK 반주기
    // 텔레메트리 입력 (관측)
    input  wire [15:0] status,
    input  wire [7:0]  canstat, canctrl, cnf1, cnf2, cnf3, eflg, tec, rec, canintf
);
    // 2단 동기화 + 엣지검출 (v4와 동일)
    reg [1:0] sclk_s, mosi_s, csn_s;
    reg       sclk_d;
    always @(posedge clk) begin
        if (!rst_n) begin sclk_s<=0; mosi_s<=0; csn_s<=2'b11; sclk_d<=0; end
        else begin
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

    reg [22:0] rx;
    reg [4:0]  bitcnt;
    reg        rw;
    reg [6:0]  addr;
    reg [15:0] tx;
    reg        sending;
    wire [7:0]  cmd_now  = {rx[6:0],  mosi_s[1]};
    wire [15:0] data_now = {rx[14:0], mosi_s[1]};

    always @(posedge clk) begin
        if (!rst_n) begin
            rx<=0; bitcnt<=0; rw<=0; addr<=0; tx<=0; sending<=0; miso<=0;
            control <= 16'h0001;
            spi_div <= 16'h0004;       // 기본 칩→MCP 반주기 4 (sclk = clk/8)
        end else if (!csn_active) begin
            bitcnt<=0; sending<=0;
        end else begin
            if (sclk_rise) begin
                rx     <= {rx[21:0], mosi_s[1]};
                bitcnt <= bitcnt + 1'b1;
                if (bitcnt == 5'd7) begin            // 명령 8비트 완성
                    rw   <= cmd_now[7];
                    addr <= cmd_now[6:0];
                    if (cmd_now[7]) begin            // 읽기: 값 준비
                        sending <= 1'b1;
                        case (cmd_now[6:0])
                            7'h00:   tx <= ID_MAGIC;
                            7'h01:   tx <= VERSION;
                            7'h02:   tx <= control;
                            7'h03:   tx <= spi_div;
                            7'h20:   tx <= status;
                            7'h21:   tx <= {8'h00, canstat};
                            7'h22:   tx <= {8'h00, canctrl};
                            7'h23:   tx <= {8'h00, cnf1};
                            7'h24:   tx <= {8'h00, cnf2};
                            7'h25:   tx <= {8'h00, cnf3};
                            7'h26:   tx <= {8'h00, eflg};
                            7'h27:   tx <= {tec, rec};
                            7'h28:   tx <= {8'h00, canintf};
                            default: tx <= 16'h0000;
                        endcase
                    end
                end
                if (bitcnt == 5'd23) begin           // 데이터 16비트 완성(쓰기)
                    if (!rw) case (addr)
                        7'h02:   control <= data_now;
                        7'h03:   spi_div <= data_now;
                        default: ;
                    endcase
                end
            end
            if (sclk_fall && sending) begin
                miso <= tx[15];
                tx   <= {tx[14:0], 1'b0};
            end
        end
    end
endmodule
