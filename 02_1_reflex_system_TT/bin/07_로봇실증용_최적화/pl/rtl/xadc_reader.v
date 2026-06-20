`timescale 1ns / 1ps
//============================================================================
// xadc_reader — XADC Wizard 의 DRP 포트에서 한 채널 변환값을 계속 읽어 xadc_val 로 낸다
//----------------------------------------------------------------------------
//  XADC Wizard 를 연속 변환 모드로 두고, 이 FSM 이 DRP(Dynamic Reconfiguration Port)로
//  해당 채널의 결과 레지스터를 반복해서 읽는다.
//   - 채널 AD14 = VAUX14 → DRP 주소 0x1E (VAUX0~15 결과 = 0x10~0x1F).
//   - DRP 결과는 16비트 레지스터의 상위 12비트(do[15:4])가 변환값(좌측 정렬).
//     → xadc_val = {4'b0, do[15:4]} (12비트 우측 정렬, 칩 임계 0x000~0xFFF 와 같은 자릿수).
//  이 출력 xadc_val 을 reflex_top_xadc.xadc_val 에 연결한다(xadc_stub 자리 대체).
//============================================================================
module xadc_reader #(
    parameter [6:0] CH_DADDR = 7'h1E    // VAUX14 결과 레지스터
)(
    input  wire        clk,
    input  wire        rst_n,
    // XADC Wizard DRP 포트 쪽
    output reg         den,             // den_in
    output reg  [6:0]  daddr,           // daddr_in
    output reg         dwe,             // dwe_in (읽기=0)
    output reg  [15:0] di,              // di_in (읽기 땐 미사용)
    input  wire [15:0] do_in,           // do_out
    input  wire        drdy,            // drdy_out
    // 결과
    output reg  [15:0] xadc_val
);
    localparam S_REQ=2'd0, S_WAIT=2'd1, S_GAP=2'd2;
    reg [1:0]  st;
    reg [3:0]  gap;

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_REQ; den<=1'b0; daddr<=CH_DADDR; dwe<=1'b0; di<=16'd0;
            xadc_val<=16'd0; gap<=4'd0;
        end else begin
            den <= 1'b0;                       // den 은 1클럭 펄스
            case (st)
              S_REQ: begin
                  daddr <= CH_DADDR; dwe <= 1'b0; den <= 1'b1;   // 읽기 요청
                  st <= S_WAIT;
              end
              S_WAIT: begin
                  if (drdy) begin
                      xadc_val <= {4'b0000, do_in[15:4]};        // 12비트 변환값
                      gap <= 4'd0; st <= S_GAP;
                  end
              end
              S_GAP: begin                       // 다음 읽기 전 살짝 쉼
                  if (gap >= 4'd7) st <= S_REQ;
                  else gap <= gap + 1'b1;
              end
              default: st <= S_REQ;
            endcase
        end
    end
endmodule
