`timescale 1ns / 1ps
//============================================================================
// chip_feeder_s3 — 스텝3 PL 공급기 (설정 + XADC 스트리밍 + 되읽기 관측)
//----------------------------------------------------------------------------
//  PS 는 GPIO 몇 줄만 쓰고, SPI 는 PL 이 다 함.
//   부팅(★규칙 마지막 — 임계 전 규칙 켜면 xadc(0)>=0=참 오발사 방지):
//     0) SPI_DIV(0x03) ← cfg_in[7:0]
//     1) CONTROL(0x02) ← {15'b0, cfg_in[8]}
//     2) THRESH1(0x19) ← thr_in              (FSR 임계, PS 변경)
//     3) RULE1(0x11)   ← rule_in             (FSR 규칙: 홈/estop/움츠림 선택) ★마지막 enable
//   운전: 매 SAMPLE_DIV 마다 ① XADC_VAL(0x30) ← xadc_val(라이브 센서) ② MCP 되읽기 7개 → obs0/obs1.
//         thr_in/rule_in/cfg_in[7:0] 바뀌면 즉시 재전송.
//============================================================================
module chip_feeder_s3 #(
    parameter integer SAMPLE_DIV = 50000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_in,        // [7:0]=SPI_DIV [8]=enable
    input  wire [15:0] thr_in,        // FSR 임계
    input  wire [15:0] rule_in,       // FSR 규칙
    input  wire [15:0] xadc_val,      // 라이브 XADC
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
    localparam SPIDIV_ADDR=7'h03, CTRL_ADDR=7'h02, THR1_ADDR=7'h19, RULE1_ADDR=7'h11, XADC_ADDR=7'h30;
    localparam R_CANSTAT=7'h21, R_CNF1=7'h23, R_CNF2=7'h24, R_CNF3=7'h25, R_EFLG=7'h26, R_TECREC=7'h27, R_CANINTF=7'h28;

    localparam [3:0] S_CFG=4'd0, S_CFG_W=4'd1, S_CHK=4'd2, S_XADC=4'd3, S_XADC_W=4'd4,
                     S_RD=4'd5, S_RD_W=4'd6, S_THR=4'd7, S_THR_W=4'd8, S_RULE=4'd9, S_RULE_W=4'd10,
                     S_DIV=4'd11, S_DIV_W=4'd12;
    reg [3:0]  st;
    reg [1:0]  cfgstep;       // 0..3
    reg [2:0]  ridx;          // 0..6
    reg [15:0] cnt;
    reg [7:0]  div_applied;
    reg [15:0] thr_applied, rule_applied;
    reg [7:0]  c_canstat, c_cnf1, c_cnf2, c_cnf3, c_eflg, c_canintf;
    reg [15:0] c_tecrec;

    // 부팅 적재표 (조합)
    reg [6:0] cfg_addr; reg [15:0] cfg_data;
    always @* begin
        case (cfgstep)
            2'd0: begin cfg_addr=SPIDIV_ADDR; cfg_data={8'd0, cfg_in[7:0]}; end
            2'd1: begin cfg_addr=CTRL_ADDR;   cfg_data={15'd0, cfg_in[8]};  end
            2'd2: begin cfg_addr=THR1_ADDR;   cfg_data=thr_in;              end
            default: begin cfg_addr=RULE1_ADDR; cfg_data=rule_in;           end
        endcase
    end
    // 되읽기 주소 (조합)
    reg [6:0] rd_addr;
    always @* begin
        case (ridx)
            3'd0: rd_addr=R_CANSTAT; 3'd1: rd_addr=R_CNF1; 3'd2: rd_addr=R_CNF2; 3'd3: rd_addr=R_CNF3;
            3'd4: rd_addr=R_EFLG;    3'd5: rd_addr=R_TECREC; default: rd_addr=R_CANINTF;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_CFG; cfgstep<=0; ridx<=0; cnt<=0; m_start<=0; m_rw<=0; m_addr<=0; m_wdata<=0;
            configured<=0; div_applied<=0; thr_applied<=0; rule_applied<=0; obs0<=0; obs1<=0;
            c_canstat<=0; c_cnf1<=0; c_cnf2<=0; c_cnf3<=0; c_eflg<=0; c_canintf<=0; c_tecrec<=0;
        end else begin
            m_start <= 1'b0;
            case (st)
              S_CFG: if (!m_busy) begin m_rw<=0; m_addr<=cfg_addr; m_wdata<=cfg_data; m_start<=1'b1; st<=S_CFG_W; end
              S_CFG_W: if (m_done) begin
                  if (cfgstep==2'd3) begin
                      div_applied<=cfg_in[7:0]; thr_applied<=thr_in; rule_applied<=rule_in;
                      configured<=1'b1; cnt<=0; ridx<=0; st<=S_CHK;
                  end else begin cfgstep<=cfgstep+2'd1; st<=S_CFG; end
              end

              S_CHK: begin
                  if      (cfg_in[7:0] != div_applied)  st<=S_DIV;
                  else if (thr_in      != thr_applied)  st<=S_THR;
                  else if (rule_in     != rule_applied) st<=S_RULE;
                  else if (cnt >= SAMPLE_DIV-1) begin cnt<=0; ridx<=0; st<=S_XADC; end
                  else cnt <= cnt + 1'b1;
              end
              S_XADC: if (!m_busy) begin m_rw<=0; m_addr<=XADC_ADDR; m_wdata<=xadc_val; m_start<=1'b1; st<=S_XADC_W; end
              S_XADC_W: if (m_done) begin ridx<=0; st<=S_RD; end
              S_RD: if (!m_busy) begin m_rw<=1; m_addr<=rd_addr; m_wdata<=16'd0; m_start<=1'b1; st<=S_RD_W; end
              S_RD_W: if (m_done) begin
                  case (ridx)
                      3'd0: c_canstat<=m_rdata[7:0]; 3'd1: c_cnf1<=m_rdata[7:0]; 3'd2: c_cnf2<=m_rdata[7:0];
                      3'd3: c_cnf3<=m_rdata[7:0];    3'd4: c_eflg<=m_rdata[7:0]; 3'd5: c_tecrec<=m_rdata;
                      default: c_canintf<=m_rdata[7:0];
                  endcase
                  if (ridx==3'd6) begin
                      obs0 <= {c_canstat, c_cnf1, c_cnf2, c_cnf3};
                      obs1 <= {c_eflg, c_tecrec, m_rdata[7:0]};
                      st<=S_CHK;
                  end else begin ridx<=ridx+1'b1; st<=S_RD; end
              end
              S_THR:  if (!m_busy) begin m_rw<=0; m_addr<=THR1_ADDR;  m_wdata<=thr_in;  m_start<=1'b1; st<=S_THR_W; end
              S_THR_W:  if (m_done) begin thr_applied<=thr_in;   st<=S_CHK; end
              S_RULE: if (!m_busy) begin m_rw<=0; m_addr<=RULE1_ADDR; m_wdata<=rule_in; m_start<=1'b1; st<=S_RULE_W; end
              S_RULE_W: if (m_done) begin rule_applied<=rule_in; st<=S_CHK; end
              S_DIV:  if (!m_busy) begin m_rw<=0; m_addr<=SPIDIV_ADDR; m_wdata<={8'd0,cfg_in[7:0]}; m_start<=1'b1; st<=S_DIV_W; end
              S_DIV_W:  if (m_done) begin div_applied<=cfg_in[7:0]; st<=S_CHK; end
              default: st<=S_CHK;
            endcase
        end
    end
endmodule
