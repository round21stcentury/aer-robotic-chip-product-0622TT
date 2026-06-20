`timescale 1ns / 1ps
//============================================================================
// spi_slave_s4 — 스텝4 칩 SPI 슬레이브 (s2 + 움츠림 델타 RECOIL_DELTA_J1~6)
//----------------------------------------------------------------------------
//  s2(SPI_DIV + 규칙·임계·XADC + MCP 되읽기) 에 움츠림 델타(0x40~0x45, 16비트 부호) 추가.
//  ★델타는 부팅 프로그래밍에서 PL 이 적재(PS 가 GPIO 로 변경) — reflex_pose_gen 의 현재+델타.
//  VERSION=0x0504.
//============================================================================
module spi_slave_s4 #(
    parameter [15:0] ID_MAGIC = 16'hCAFD,
    parameter [15:0] VERSION  = 16'h0504
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sclk,
    input  wire mosi,
    input  wire csn,
    output reg  miso,
    output wire miso_oe,
    output reg  [15:0] control,
    output reg  [15:0] spi_div,
    output reg  [15:0] rule0, rule1, rule2, rule3,
    output reg  [15:0] thresh0, thresh1, thresh2, thresh3,
    output reg  [15:0] xadc_val,
    output reg  [15:0] recoil_d1, recoil_d2, recoil_d3, recoil_d4, recoil_d5, recoil_d6,
    input  wire [15:0] status,
    input  wire [7:0]  canstat, canctrl, cnf1, cnf2, cnf3, eflg, tec, rec, canintf
);
    reg [1:0] sclk_s, mosi_s, csn_s;
    reg       sclk_d;
    always @(posedge clk) begin
        if (!rst_n) begin sclk_s<=0; mosi_s<=0; csn_s<=2'b11; sclk_d<=0; end
        else begin
            sclk_s <= {sclk_s[0], sclk}; mosi_s <= {mosi_s[0], mosi};
            csn_s  <= {csn_s[0],  csn};  sclk_d <= sclk_s[1];
        end
    end
    wire sclk_rise = sclk_s[1] & ~sclk_d;
    wire sclk_fall = ~sclk_s[1] & sclk_d;
    wire csn_active = ~csn_s[1];
    assign miso_oe = csn_active;

    reg [22:0] rx; reg [4:0] bitcnt; reg rw; reg [6:0] addr; reg [15:0] tx; reg sending;
    wire [7:0]  cmd_now  = {rx[6:0],  mosi_s[1]};
    wire [15:0] data_now = {rx[14:0], mosi_s[1]};

    always @(posedge clk) begin
        if (!rst_n) begin
            rx<=0; bitcnt<=0; rw<=0; addr<=0; tx<=0; sending<=0; miso<=0;
            control <= 16'h0001; spi_div <= 16'h0004;
            rule0 <= 16'h0039; rule1 <= 16'h0000; rule2 <= 16'h0000; rule3 <= 16'h0000;
            thresh0<=16'h0; thresh1<=16'h0; thresh2<=16'h0; thresh3<=16'h0; xadc_val<=16'h0;
            recoil_d1<=16'h0; recoil_d2<=16'h0; recoil_d3<=16'h0; recoil_d4<=16'h0; recoil_d5<=16'h0; recoil_d6<=16'h0;
        end else if (!csn_active) begin
            bitcnt<=0; sending<=0;
        end else begin
            if (sclk_rise) begin
                rx <= {rx[21:0], mosi_s[1]}; bitcnt <= bitcnt + 1'b1;
                if (bitcnt == 5'd7) begin
                    rw <= cmd_now[7]; addr <= cmd_now[6:0];
                    if (cmd_now[7]) begin
                        sending <= 1'b1;
                        case (cmd_now[6:0])
                            7'h00: tx <= ID_MAGIC;   7'h01: tx <= VERSION;  7'h02: tx <= control;  7'h03: tx <= spi_div;
                            7'h10: tx <= rule0;      7'h11: tx <= rule1;    7'h12: tx <= rule2;     7'h13: tx <= rule3;
                            7'h18: tx <= thresh0;    7'h19: tx <= thresh1;  7'h1A: tx <= thresh2;   7'h1B: tx <= thresh3;
                            7'h30: tx <= xadc_val;   7'h20: tx <= status;
                            7'h21: tx <= {8'h00,canstat}; 7'h22: tx <= {8'h00,canctrl};
                            7'h23: tx <= {8'h00,cnf1};    7'h24: tx <= {8'h00,cnf2}; 7'h25: tx <= {8'h00,cnf3};
                            7'h26: tx <= {8'h00,eflg};    7'h27: tx <= {tec,rec};    7'h28: tx <= {8'h00,canintf};
                            7'h40: tx <= recoil_d1;  7'h41: tx <= recoil_d2; 7'h42: tx <= recoil_d3;
                            7'h43: tx <= recoil_d4;  7'h44: tx <= recoil_d5; 7'h45: tx <= recoil_d6;
                            default: tx <= 16'h0000;
                        endcase
                    end
                end
                if (bitcnt == 5'd23) begin
                    if (!rw) case (addr)
                        7'h02: control <= data_now;  7'h03: spi_div <= data_now;
                        7'h10: rule0 <= data_now;    7'h11: rule1 <= data_now;  7'h12: rule2 <= data_now;  7'h13: rule3 <= data_now;
                        7'h18: thresh0<=data_now;    7'h19: thresh1<=data_now;  7'h1A: thresh2<=data_now;  7'h1B: thresh3<=data_now;
                        7'h30: xadc_val<=data_now;
                        7'h40: recoil_d1<=data_now;  7'h41: recoil_d2<=data_now; 7'h42: recoil_d3<=data_now;
                        7'h43: recoil_d4<=data_now;  7'h44: recoil_d5<=data_now; 7'h45: recoil_d6<=data_now;
                        default: ;
                    endcase
                end
            end
            if (sclk_fall && sending) begin miso <= tx[15]; tx <= {tx[14:0], 1'b0}; end
        end
    end
endmodule
