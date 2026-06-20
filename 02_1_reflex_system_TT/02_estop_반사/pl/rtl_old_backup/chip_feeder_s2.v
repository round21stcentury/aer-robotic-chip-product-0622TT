`timescale 1ns / 1ps
//============================================================================
// chip_feeder_s2 — 스텝1 PL 설정·되읽기 공급기 (PS 개입 최소, PL 자동)
//----------------------------------------------------------------------------
//  PS→PL→SPI→TT 경로의 PL 쪽 자동화. PS 는 GPIO 에 설정 한 줄(cfg_in)만 쓰고,
//  실제 SPI 는 PL 이 다 한다(사람·PS 가 SPI 를 직접 안 침).
//   부팅: ① SPI_DIV(0x03) ← cfg_in[7:0]  (칩→MCP SPI 속도, PS 가 재합성 없이 변경)
//         ② CONTROL(0x02) ← {15'b0, cfg_in[8]}  (글로벌 enable)
//   운전: 매 SAMPLE_DIV 마다 칩의 ★MCP 되읽기 레지스터★ 7개를 읽어 obs0/obs1 로 묶어
//         PS GPIO(입력)에 노출 → 시리얼에서 CANSTAT/CNF/EFLG/TEC/REC/CANINTF 관측.
//         cfg_in 바뀌면 SPI_DIV 재전송.
//
//   obs0 = {CANSTAT, CNF1, CNF2, CNF3}   (설정이 됐나)
//   obs1 = {EFLG, TEC, REC, CANINTF}     (에러/송신 상태)
//============================================================================
module chip_feeder_s2 #(
    parameter integer SAMPLE_DIV = 50000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_in,        // PS GPIO: [7:0]=SPI_DIV, [8]=enable
    // PL SPI 마스터 핸드셰이크
    output reg         m_start,
    output reg         m_rw,
    output reg  [6:0]  m_addr,
    output reg  [15:0] m_wdata,
    input  wire        m_busy,
    input  wire        m_done,
    input  wire [15:0] m_rdata,
    // PS 로 노출(GPIO 입력)
    output reg  [31:0] obs0,
    output reg  [31:0] obs1,
    output reg         configured
);
    localparam SPIDIV_ADDR=7'h03, CTRL_ADDR=7'h02;
    // 되읽기 주소 7개
    localparam R_CANSTAT=7'h21, R_CNF1=7'h23, R_CNF2=7'h24, R_CNF3=7'h25,
               R_EFLG=7'h26, R_TECREC=7'h27, R_CANINTF=7'h28;

    localparam [3:0] S_W_DIV=4'd0, S_W_DIV_W=4'd1, S_W_CTRL=4'd2, S_W_CTRL_W=4'd3,
                     S_CNT=4'd4, S_RD=4'd5, S_RD_W=4'd6, S_DIV_RE=4'd7, S_DIV_RE_W=4'd8;
    reg [3:0]  st;
    reg [2:0]  ridx;          // 0..6 되읽기 인덱스
    reg [15:0] cnt;
    reg [7:0]  div_applied;
    // 임시 캡처
    reg [7:0]  c_canstat, c_cnf1, c_cnf2, c_cnf3, c_eflg, c_canintf;
    reg [15:0] c_tecrec;

    reg [6:0] rd_addr;
    always @* begin
        case (ridx)
            3'd0: rd_addr=R_CANSTAT;
            3'd1: rd_addr=R_CNF1;
            3'd2: rd_addr=R_CNF2;
            3'd3: rd_addr=R_CNF3;
            3'd4: rd_addr=R_EFLG;
            3'd5: rd_addr=R_TECREC;
            default: rd_addr=R_CANINTF;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_W_DIV; ridx<=0; cnt<=0; m_start<=0; m_rw<=0; m_addr<=0; m_wdata<=0;
            configured<=0; div_applied<=0; obs0<=0; obs1<=0;
            c_canstat<=0; c_cnf1<=0; c_cnf2<=0; c_cnf3<=0; c_eflg<=0; c_canintf<=0; c_tecrec<=0;
        end else begin
            m_start <= 1'b0;
            case (st)
              S_W_DIV: if (!m_busy) begin
                  m_rw<=0; m_addr<=SPIDIV_ADDR; m_wdata<={8'd0, cfg_in[7:0]}; m_start<=1'b1; st<=S_W_DIV_W;
              end
              S_W_DIV_W: if (m_done) begin div_applied<=cfg_in[7:0]; st<=S_W_CTRL; end
              S_W_CTRL: if (!m_busy) begin
                  m_rw<=0; m_addr<=CTRL_ADDR; m_wdata<={15'd0, cfg_in[8]}; m_start<=1'b1; st<=S_W_CTRL_W;
              end
              S_W_CTRL_W: if (m_done) begin configured<=1'b1; cnt<=0; ridx<=0; st<=S_CNT; end

              S_CNT: begin
                  if (cfg_in[7:0] != div_applied)        st <= S_DIV_RE;     // SPI 속도 변경 반영
                  else if (cnt >= SAMPLE_DIV-1) begin cnt<=0; ridx<=0; st<=S_RD; end
                  else cnt <= cnt + 1'b1;
              end
              S_RD: if (!m_busy) begin
                  m_rw<=1; m_addr<=rd_addr; m_wdata<=16'd0; m_start<=1'b1; st<=S_RD_W;
              end
              S_RD_W: if (m_done) begin
                  case (ridx)
                      3'd0: c_canstat<=m_rdata[7:0];
                      3'd1: c_cnf1   <=m_rdata[7:0];
                      3'd2: c_cnf2   <=m_rdata[7:0];
                      3'd3: c_cnf3   <=m_rdata[7:0];
                      3'd4: c_eflg   <=m_rdata[7:0];
                      3'd5: c_tecrec <=m_rdata;          // {TEC,REC}
                      default: c_canintf<=m_rdata[7:0];
                  endcase
                  if (ridx==3'd6) begin
                      obs0 <= {c_canstat, c_cnf1, c_cnf2, c_cnf3};   // 마지막 캡처 직전 값 + 이번 것
                      obs1 <= {c_eflg, c_tecrec, m_rdata[7:0]};      // {EFLG, TEC, REC, CANINTF}
                      st<=S_CNT;
                  end else begin ridx<=ridx+1'b1; st<=S_RD; end
              end
              S_DIV_RE: if (!m_busy) begin
                  m_rw<=0; m_addr<=SPIDIV_ADDR; m_wdata<={8'd0, cfg_in[7:0]}; m_start<=1'b1; st<=S_DIV_RE_W;
              end
              S_DIV_RE_W: if (m_done) begin div_applied<=cfg_in[7:0]; st<=S_CNT; end
              default: st<=S_CNT;
            endcase
        end
    end
endmodule
