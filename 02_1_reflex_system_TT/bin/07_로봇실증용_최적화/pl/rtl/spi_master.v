`timescale 1ns / 1ps
//============================================================================
// spi_master — 칩 SPI 슬레이브 대상 Mode-0 SPI 마스터 (PL측)
//----------------------------------------------------------------------------
//  05_rs_xadc_trigger 에서 검증된 모듈을 C단계로 가져옴(동일). PL이 칩에 규칙/임계/
//  움츠림 델타를 적재하고, 매 샘플 XADC 값을 써넣는 데 쓴다.
//  한 트랜잭션 = 24비트 {rw, addr[6:0], data[15:0]} (MSB first).
//   - start 1클럭 펄스 → busy=1 → done 1클럭 펄스 + (읽기면 rdata 유효).
//   - 칩이 클럭을 오버샘플하므로 sclk 를 충분히 느리게(HALF 분주).
//============================================================================
module spi_master #(
    parameter integer HALF = 8     // sclk 반주기 = HALF clk 사이클
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // 1클럭 펄스
    input  wire        rw,         // 0=쓰기, 1=읽기
    input  wire [6:0]  addr,
    input  wire [15:0] wdata,
    output reg  [15:0] rdata,
    output reg         busy,
    output reg         done,       // 트랜잭션 끝 1클럭 펄스
    // 칩 SPI 핀
    output reg         sclk,
    output reg         mosi,
    output reg         csn,
    input  wire        miso
);
    localparam S_IDLE=2'd0, S_SETUP=2'd1, S_RUN=2'd2, S_TAIL=2'd3;
    reg [1:0]  st;
    reg [23:0] sh;
    reg [15:0] rsh;
    reg [4:0]  bidx;
    reg [15:0] dcnt;
    reg        phase;

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_IDLE; sclk<=0; mosi<=0; csn<=1; busy<=0; done<=0;
            rdata<=0; sh<=0; rsh<=0; bidx<=0; dcnt<=0; phase<=0;
        end else begin
            done <= 1'b0;
            case (st)
              S_IDLE: begin
                  sclk<=0; csn<=1;
                  if (start) begin
                      sh   <= {rw, addr, wdata};
                      rsh  <= 16'h0;
                      bidx <= 5'd0;
                      dcnt <= 16'd0;
                      phase<= 1'b0;
                      csn  <= 1'b0;
                      busy <= 1'b1;
                      st   <= S_SETUP;
                  end
              end
              S_SETUP: begin
                  mosi <= sh[23];
                  sclk <= 1'b0;
                  if (dcnt >= HALF-1) begin dcnt<=0; phase<=1'b0; st<=S_RUN; end
                  else dcnt <= dcnt + 1'b1;
              end
              S_RUN: begin
                  if (dcnt >= HALF-1) begin
                      dcnt <= 16'd0;
                      if (phase == 1'b0) begin
                          sclk  <= 1'b1;
                          phase <= 1'b1;
                          if (bidx >= 5'd8) rsh <= {rsh[14:0], miso};
                      end else begin
                          sclk  <= 1'b0;
                          phase <= 1'b0;
                          if (bidx == 5'd23) st <= S_TAIL;
                          else begin
                              mosi <= sh[22 - bidx];
                              bidx <= bidx + 1'b1;
                          end
                      end
                  end else dcnt <= dcnt + 1'b1;
              end
              S_TAIL: begin
                  csn <= 1'b1; sclk <= 1'b0; mosi <= 1'b0;
                  if (dcnt >= HALF-1) begin
                      dcnt<=0; busy<=1'b0; done<=1'b1; rdata<=rsh; st<=S_IDLE;
                  end else dcnt <= dcnt + 1'b1;
              end
            endcase
        end
    end
endmodule
