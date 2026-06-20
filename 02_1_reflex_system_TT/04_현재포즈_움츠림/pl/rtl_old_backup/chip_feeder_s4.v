`timescale 1ns / 1ps
//============================================================================
// chip_feeder_s4 — 스텝4 PL 공급기 (설정 + 움츠림 델타 + XADC 스트림 + 되읽기)
//----------------------------------------------------------------------------
//  스텝3 에 ★움츠림 델타(J2·J3) 적재★ 추가. 부팅(★규칙 마지막):
//    0)SPI_DIV  1)CONTROL  2)THRESH1  3)DELTA_J2(0x41)  4)DELTA_J3(0x42)  5)RULE1(0x11)★last
//  운전: 매 SAMPLE_DIV ① XADC_VAL(0x30) ② MCP 되읽기 7개 → obs0/obs1.
//        thr/rule/div/d2/d3 바뀌면 즉시 재전송(PS 가 부팅 후에도 변경 가능).
//============================================================================
module chip_feeder_s4 #(
    parameter integer SAMPLE_DIV = 50000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_in,        // [7:0]SPI_DIV [8]enable
    input  wire [15:0] thr_in,
    input  wire [15:0] rule_in,
    input  wire [15:0] d2_in,         // 움츠림 델타 J2 (0.001도, 부호)
    input  wire [15:0] d3_in,         // 움츠림 델타 J3
    input  wire [15:0] xadc_val,
    output reg         m_start,
    output reg         m_rw,
    output reg  [6:0]  m_addr,
    output reg  [15:0] m_wdata,
    input  wire        m_busy,
    input  wire        m_done,
    input  wire [15:0] m_rdata,
    output reg  [31:0] obs0,
    output reg  [31:0] obs1,
    output reg         configured
);
    localparam SPIDIV=7'h03, CTRL=7'h02, THR1=7'h19, DJ2=7'h41, DJ3=7'h42, RULE1=7'h11, XADC=7'h30;
    localparam R0=7'h21, R1=7'h23, R2=7'h24, R3=7'h25, R4=7'h26, R5=7'h27, R6=7'h28;

    localparam [4:0] S_CFG=0, S_CFG_W=1, S_CHK=2, S_XADC=3, S_XADC_W=4, S_RD=5, S_RD_W=6,
                     S_THR=7, S_THR_W=8, S_RULE=9, S_RULE_W=10, S_DIV=11, S_DIV_W=12,
                     S_D2=13, S_D2_W=14, S_D3=15, S_D3_W=16;
    reg [4:0]  st;
    reg [2:0]  cfgstep;       // 0..5
    reg [2:0]  ridx;
    reg [15:0] cnt;
    reg [7:0]  div_a; reg [15:0] thr_a, rule_a, d2_a, d3_a;
    reg [7:0]  c_canstat, c_cnf1, c_cnf2, c_cnf3, c_eflg, c_canintf; reg [15:0] c_tecrec;

    reg [6:0] cfg_addr; reg [15:0] cfg_data;
    always @* begin
        case (cfgstep)
            3'd0: begin cfg_addr=SPIDIV; cfg_data={8'd0,cfg_in[7:0]}; end
            3'd1: begin cfg_addr=CTRL;   cfg_data={15'd0,cfg_in[8]};  end
            3'd2: begin cfg_addr=THR1;   cfg_data=thr_in;             end
            3'd3: begin cfg_addr=DJ2;    cfg_data=d2_in;              end
            3'd4: begin cfg_addr=DJ3;    cfg_data=d3_in;              end
            default: begin cfg_addr=RULE1; cfg_data=rule_in;          end   // ★마지막
        endcase
    end
    reg [6:0] rd_addr;
    always @* begin
        case (ridx)
            3'd0: rd_addr=R0; 3'd1: rd_addr=R1; 3'd2: rd_addr=R2; 3'd3: rd_addr=R3;
            3'd4: rd_addr=R4; 3'd5: rd_addr=R5; default: rd_addr=R6;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_CFG; cfgstep<=0; ridx<=0; cnt<=0; m_start<=0; m_rw<=0; m_addr<=0; m_wdata<=0;
            configured<=0; div_a<=0; thr_a<=0; rule_a<=0; d2_a<=0; d3_a<=0; obs0<=0; obs1<=0;
            c_canstat<=0; c_cnf1<=0; c_cnf2<=0; c_cnf3<=0; c_eflg<=0; c_canintf<=0; c_tecrec<=0;
        end else begin
            m_start <= 1'b0;
            case (st)
              S_CFG: if (!m_busy) begin m_rw<=0; m_addr<=cfg_addr; m_wdata<=cfg_data; m_start<=1'b1; st<=S_CFG_W; end
              S_CFG_W: if (m_done) begin
                  if (cfgstep==3'd5) begin
                      div_a<=cfg_in[7:0]; thr_a<=thr_in; rule_a<=rule_in; d2_a<=d2_in; d3_a<=d3_in;
                      configured<=1'b1; cnt<=0; ridx<=0; st<=S_CHK;
                  end else begin cfgstep<=cfgstep+3'd1; st<=S_CFG; end
              end
              S_CHK: begin
                  if      (cfg_in[7:0]!=div_a)  st<=S_DIV;
                  else if (thr_in     !=thr_a)  st<=S_THR;
                  else if (d2_in      !=d2_a)   st<=S_D2;
                  else if (d3_in      !=d3_a)   st<=S_D3;
                  else if (rule_in    !=rule_a) st<=S_RULE;
                  else if (cnt>=SAMPLE_DIV-1) begin cnt<=0; ridx<=0; st<=S_XADC; end
                  else cnt<=cnt+1'b1;
              end
              S_XADC: if (!m_busy) begin m_rw<=0; m_addr<=XADC; m_wdata<=xadc_val; m_start<=1'b1; st<=S_XADC_W; end
              S_XADC_W: if (m_done) begin ridx<=0; st<=S_RD; end
              S_RD: if (!m_busy) begin m_rw<=1; m_addr<=rd_addr; m_wdata<=16'd0; m_start<=1'b1; st<=S_RD_W; end
              S_RD_W: if (m_done) begin
                  case (ridx)
                      3'd0: c_canstat<=m_rdata[7:0]; 3'd1: c_cnf1<=m_rdata[7:0]; 3'd2: c_cnf2<=m_rdata[7:0];
                      3'd3: c_cnf3<=m_rdata[7:0];    3'd4: c_eflg<=m_rdata[7:0]; 3'd5: c_tecrec<=m_rdata;
                      default: c_canintf<=m_rdata[7:0];
                  endcase
                  if (ridx==3'd6) begin obs0<={c_canstat,c_cnf1,c_cnf2,c_cnf3}; obs1<={c_eflg,c_tecrec,m_rdata[7:0]}; st<=S_CHK; end
                  else begin ridx<=ridx+1'b1; st<=S_RD; end
              end
              S_THR:  if (!m_busy) begin m_rw<=0; m_addr<=THR1;  m_wdata<=thr_in;  m_start<=1'b1; st<=S_THR_W; end
              S_THR_W:  if (m_done) begin thr_a<=thr_in;   st<=S_CHK; end
              S_RULE: if (!m_busy) begin m_rw<=0; m_addr<=RULE1; m_wdata<=rule_in; m_start<=1'b1; st<=S_RULE_W; end
              S_RULE_W: if (m_done) begin rule_a<=rule_in; st<=S_CHK; end
              S_DIV:  if (!m_busy) begin m_rw<=0; m_addr<=SPIDIV; m_wdata<={8'd0,cfg_in[7:0]}; m_start<=1'b1; st<=S_DIV_W; end
              S_DIV_W:  if (m_done) begin div_a<=cfg_in[7:0]; st<=S_CHK; end
              S_D2:   if (!m_busy) begin m_rw<=0; m_addr<=DJ2; m_wdata<=d2_in; m_start<=1'b1; st<=S_D2_W; end
              S_D2_W:   if (m_done) begin d2_a<=d2_in; st<=S_CHK; end
              S_D3:   if (!m_busy) begin m_rw<=0; m_addr<=DJ3; m_wdata<=d3_in; m_start<=1'b1; st<=S_D3_W; end
              S_D3_W:   if (m_done) begin d3_a<=d3_in; st<=S_CHK; end
              default: st<=S_CHK;
            endcase
        end
    end
endmodule
