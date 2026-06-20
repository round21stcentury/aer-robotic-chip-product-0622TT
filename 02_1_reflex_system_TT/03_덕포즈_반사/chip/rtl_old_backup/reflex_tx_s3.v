`timescale 1ns / 1ps
//============================================================================
// reflex_tx_s3 — 스텝3 반사 송신원: 비상정지(0x150) vs 홈포즈(0x155~7) 선택
//----------------------------------------------------------------------------
//  estop_active 면 0x150 주기 송신. 아니고 pose_active 면 pose_gen 의 포즈 프레임 통과.
//  gate_active = estop|pose. (04 reflex_tx_src 와 동일 골격, 스텝4 에서 그대로 확장.)
//============================================================================
module reflex_tx_s3 #(
    parameter integer SEND_DIV   = 100000,
    parameter [10:0]  ESTOP_ID   = 11'h150,
    parameter [63:0]  ESTOP_DATA = 64'h0000_0000_0000_0001
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        estop_active,
    input  wire        pose_active,
    input  wire        can_ready,
    // pose_gen 출력
    input  wire [10:0] pose_id,
    input  wire [3:0]  pose_dlc,
    input  wire [63:0] pose_data,
    input  wire        pose_send,
    // mcp_tx_send 로
    output wire [10:0] tx_id,
    output wire [3:0]  tx_dlc,
    output wire [63:0] tx_data,
    output wire        tx_send,
    output wire        gate_active
);
    reg [31:0] divc;
    reg        estop_send;
    always @(posedge clk) begin
        if (!rst_n) begin divc<=0; estop_send<=0; end
        else begin
            estop_send <= 1'b0;
            if (estop_active && can_ready) begin
                if (divc==SEND_DIV-1) begin divc<=0; estop_send<=1'b1; end
                else divc<=divc+1'b1;
            end else divc<=0;
        end
    end
    assign tx_id   = estop_active ? ESTOP_ID   : pose_id;
    assign tx_dlc  = estop_active ? 4'd8       : pose_dlc;
    assign tx_data = estop_active ? ESTOP_DATA : pose_data;
    assign tx_send = estop_active ? estop_send : (pose_active & can_ready & pose_send);
    assign gate_active = estop_active | pose_active;
endmodule
