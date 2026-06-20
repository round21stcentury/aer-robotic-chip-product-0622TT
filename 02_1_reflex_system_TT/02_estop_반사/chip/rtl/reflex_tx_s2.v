`timescale 1ns / 1ps
//============================================================================
// reflex_tx_s2 — 스텝2 반사 송신원: estop_active → 0x150 비상정지 주기 송신
//----------------------------------------------------------------------------
//  reflex_core_s2 의 estop_active 가 서면 SEND_DIV 주기로 0x150(B0=01) 송신 펄스.
//  gate_active = estop_active (게이트/상태). 스텝3·4 에서 포즈 경로가 더해진다.
//============================================================================
module reflex_tx_s2 #(
    parameter integer SEND_DIV   = 100000,
    parameter [10:0]  ESTOP_ID   = 11'h150,
    parameter [63:0]  ESTOP_DATA = 64'h0000_0000_0000_0001   // D0=0x01
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        estop_active,
    input  wire        can_ready,        // init_done
    output wire        gate_active,
    output reg  [10:0] tx_id,
    output reg  [3:0]  tx_dlc,
    output reg  [63:0] tx_data,
    output reg         tx_send
);
    assign gate_active = estop_active;
    reg [31:0] divc;
    always @(posedge clk) begin
        if (!rst_n) begin divc<=0; tx_send<=0; tx_id<=ESTOP_ID; tx_dlc<=4'd8; tx_data<=ESTOP_DATA; end
        else begin
            tx_send <= 1'b0;
            tx_id   <= ESTOP_ID; tx_dlc <= 4'd8; tx_data <= ESTOP_DATA;
            if (estop_active && can_ready) begin
                if (divc >= SEND_DIV-1) begin divc<=0; tx_send<=1'b1; end
                else divc <= divc + 1'b1;
            end else divc <= 0;
        end
    end
endmodule
