`timescale 1ns / 1ps
//============================================================================
// reflex_pose_gen_s3 — 스텝3 홈복귀 포즈 프레임 생성기 (절대 홈 = 전부 0)
//----------------------------------------------------------------------------
//  pose_active 동안 0x155(J1·J2)/0x156(J3·J4)/0x157(J5·J6) 세 프레임을 SEND_DIV 주기로
//  돌아가며 송신. 목표는 ★고정 홈(URDF 기본 = 전부 0)★ — 현재포즈·델타·RX 는 스텝4.
//  관절 명령 = 2×부호32비트(0.001도, big-endian). 홈이 0 이라 세 프레임 데이터 모두 0.
//  (구조는 스텝4 reflex_pose_gen 와 호환 — 거기선 현재+델타로 목표가 바뀜.)
//============================================================================
module reflex_pose_gen_s3 #(
    parameter signed [31:0] HOME_J1=32'sd0, HOME_J2=32'sd0, HOME_J3=32'sd0,
    parameter signed [31:0] HOME_J4=32'sd0, HOME_J5=32'sd0, HOME_J6=32'sd0,
    parameter integer SEND_DIV = 1000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pose_active,
    output reg  [10:0] reflex_id,
    output reg  [3:0]  reflex_dlc,
    output reg  [63:0] reflex_data,
    output reg         reflex_send
);
    // 2×부호32비트 → 64비트 (big-endian: 각 관절 최상위바이트 먼저, lo=앞관절 D0~D3)
    function [63:0] enc_frame;
        input signed [31:0] lo, hi;
        begin
            enc_frame = { hi[7:0], hi[15:8], hi[23:16], hi[31:24],
                          lo[7:0], lo[15:8], lo[23:16], lo[31:24] };
        end
    endfunction

    reg [1:0]  frame_idx;
    reg [15:0] divcnt;
    reg        active_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            frame_idx<=0; divcnt<=0; active_d<=0;
            reflex_id<=0; reflex_dlc<=4'd8; reflex_data<=0; reflex_send<=0;
        end else begin
            reflex_send <= 1'b0;
            active_d    <= pose_active;
            if (pose_active && !active_d) begin
                frame_idx <= 2'd0; divcnt <= 16'd0;          // 발동 순간 처음부터
            end else if (pose_active) begin
                if (divcnt == SEND_DIV-1) begin
                    divcnt <= 16'd0;
                    case (frame_idx)
                        2'd0: begin reflex_id<=11'h155; reflex_data<=enc_frame(HOME_J1,HOME_J2); end
                        2'd1: begin reflex_id<=11'h156; reflex_data<=enc_frame(HOME_J3,HOME_J4); end
                        default: begin reflex_id<=11'h157; reflex_data<=enc_frame(HOME_J5,HOME_J6); end
                    endcase
                    reflex_dlc  <= 4'd8;
                    reflex_send <= 1'b1;
                    frame_idx   <= (frame_idx==2'd2) ? 2'd0 : frame_idx+1'b1;
                end else divcnt <= divcnt + 1'b1;
            end else begin
                frame_idx <= 2'd0; divcnt <= 16'd0;
            end
        end
    end
endmodule
