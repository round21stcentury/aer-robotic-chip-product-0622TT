`timescale 1ns / 1ps
//============================================================================
// estop_tx_src — 스텝1 최소 트리거: DIP 핀 → 0x150 비상정지 프레임 주기 송신
//----------------------------------------------------------------------------
//  스텝1 은 ★반사코어·FSR·움츠림·RX·중재없음★ — 가장 단순한 경로만:
//   DIP(디지털 핀) 를 2단동기화+디바운스 → 안정되면, init 끝난 뒤(can_ready)
//   SEND_DIV 주기로 0x150(B0=0x01 비상정지) 한 프레임씩 송신 펄스.
//  목적: "칩이 MCP 를 몰아 실제 버스에 프레임을 쏘는가" 만 격리 검증.
//  (스텝2 부터 이 자리를 reflex_core 가 대체한다.)
//============================================================================
module estop_tx_src #(
    parameter integer SEND_DIV   = 100000,    // 프레임 주기(클럭). 시뮬은 작게 override
    parameter integer DEBOUNCE   = 16,
    parameter [10:0]  ESTOP_ID   = 11'h150,
    parameter [63:0]  ESTOP_DATA = 64'h0000_0000_0000_0001   // D0=0x01 (비상정지)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dip,             // DIP 비상정지 핀(비동기)
    input  wire        can_ready,       // init_done — MCP 정상모드 진입 후에만 송신
    output wire        gate_active,      // 반사중(=DIP 안정 ON) — 게이트/상태
    output reg  [10:0] tx_id,
    output reg  [3:0]  tx_dlc,
    output reg  [63:0] tx_data,
    output reg         tx_send          // 1클럭 펄스
);
    // 2단 동기화 + 디바운스
    reg [1:0]  sync;
    reg [15:0] cnt;
    reg        stable;
    always @(posedge clk) begin
        if (!rst_n) begin sync<=0; cnt<=0; stable<=0; end
        else begin
            sync <= {sync[0], dip};
            if (sync[1]==stable)         cnt<=0;
            else if (cnt>=DEBOUNCE) begin stable<=sync[1]; cnt<=0; end
            else                          cnt<=cnt+1'b1;
        end
    end
    assign gate_active = stable;

    // 주기 송신 펄스
    reg [31:0] divc;
    always @(posedge clk) begin
        if (!rst_n) begin
            divc<=0; tx_send<=0; tx_id<=ESTOP_ID; tx_dlc<=4'd8; tx_data<=ESTOP_DATA;
        end else begin
            tx_send <= 1'b0;
            tx_id   <= ESTOP_ID; tx_dlc <= 4'd8; tx_data <= ESTOP_DATA;
            if (stable && can_ready) begin
                if (divc >= SEND_DIV-1) begin divc<=0; tx_send<=1'b1; end
                else divc <= divc + 1'b1;
            end else divc <= 0;
        end
    end
endmodule
