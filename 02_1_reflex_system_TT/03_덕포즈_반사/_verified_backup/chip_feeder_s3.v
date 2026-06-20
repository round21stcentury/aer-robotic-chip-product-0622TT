`timescale 1ns / 1ps
//============================================================================
// chip_feeder_s3 — 스텝1 PL 공급기 (★정상명령 릴레이 + 설정 + MCP 되읽기 관측)
//----------------------------------------------------------------------------
//  PS(이더넷 lwIP)가 받은 CAN 프레임을 ★GPIO 메일박스★ 로 PL 에 넘기면, 이 모듈이
//  SPI 로 칩 정상-프레임 레지스터(0x50~0x55)에 써넣어 칩이 MCP 로 중계하게 한다.
//   메일박스(PS→PL, GPIO 출력):
//     cmd_lo[31:0] = 데이터 D0~D3 (D0=[7:0])
//     cmd_hi[31:0] = 데이터 D4~D7
//     cmd_id[31:0] = [31]=토글, [10:0]=CAN id.  PS 가 lo/hi 먼저 쓰고 ★토글 마지막★.
//   토글이 바뀌면 새 프레임 → 래치 후 릴레이(6 SPI 쓰기). 릴레이는 ★되읽기보다 우선★
//   (로봇 명령이 관측 때문에 늦지 않게).
//   부팅: SPI_DIV(0x03)·CONTROL(0x02) 적재. 운전: 새 프레임 릴레이 / 주기적 MCP 되읽기.
//============================================================================
module chip_feeder_s3 #(
    parameter integer SAMPLE_DIV = 50000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_in,          // [7:0]SPI_DIV [8]enable
    // ★정상명령 메일박스 (PS GPIO)
    input  wire [31:0] cmd_lo,
    input  wire [31:0] cmd_hi,
    input  wire [31:0] cmd_id,          // [31]=toggle [10:0]=id
    // PL SPI 마스터 핸드셰이크
    output reg         m_start,
    output reg         m_rw,
    output reg  [6:0]  m_addr,
    output reg  [15:0] m_wdata,
    input  wire        m_busy,
    input  wire        m_done,
    input  wire [15:0] m_rdata,
    // PS 로 노출(관측)
    output reg  [31:0] obs0,
    output reg  [31:0] obs1,
    output reg         configured
);
    localparam SPIDIV=7'h03, CTRL=7'h02;
    localparam N_ID=7'h50, N_D10=7'h51, N_D32=7'h52, N_D54=7'h53, N_D76=7'h54, N_SEND=7'h55;
    localparam R0=7'h21, R1=7'h23, R2=7'h24, R3=7'h25, R4=7'h26, R5=7'h27, R6=7'h28;

    localparam [3:0] S_DIV=0, S_DIV_W=1, S_CTRL=2, S_CTRL_W=3, S_CHK=4,
                     S_RLY=5, S_RLY_W=6, S_RD=7, S_RD_W=8, S_DIVRE=9, S_DIVRE_W=10;
    reg [3:0]  st;
    reg [2:0]  ridx;          // 0..6 되읽기
    reg [2:0]  rly;           // 0..5 릴레이 스텝
    reg [15:0] cnt;
    reg [7:0]  div_a;
    // 메일박스 래치
    reg        last_tog;
    reg        pending;
    reg [10:0] f_id; reg [31:0] f_lo, f_hi;
    reg [7:0]  c_canstat,c_cnf1,c_cnf2,c_cnf3,c_eflg,c_canintf; reg [15:0] c_tecrec;
    // ★settle: 토글 변화 후 N클럭 대기 → cmd_lo/hi 안정 후 래치(GPIO 쓰기 스큐 무관)
    localparam integer SETTLE_N = 64;
    reg        seen;
    reg [6:0]  stl;

    // 새 프레임 감지(토글 변화)
    wire new_frame = (cmd_id[31] != last_tog);

    // 릴레이 스텝 주소/데이터 (조합)
    reg [6:0] rly_addr; reg [15:0] rly_data;
    always @* begin
        case (rly)
            3'd0: begin rly_addr=N_ID;  rly_data={5'b0, f_id};   end
            3'd1: begin rly_addr=N_D10; rly_data=f_lo[15:0];     end
            3'd2: begin rly_addr=N_D32; rly_data=f_lo[31:16];    end
            3'd3: begin rly_addr=N_D54; rly_data=f_hi[15:0];     end
            3'd4: begin rly_addr=N_D76; rly_data=f_hi[31:16];    end
            default: begin rly_addr=N_SEND; rly_data=16'h0001;   end  // 송신 트리거
        endcase
    end
    // 되읽기 주소 (조합)
    reg [6:0] rd_addr;
    always @* begin
        case (ridx)
            3'd0: rd_addr=R0; 3'd1: rd_addr=R1; 3'd2: rd_addr=R2; 3'd3: rd_addr=R3;
            3'd4: rd_addr=R4; 3'd5: rd_addr=R5; default: rd_addr=R6;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st<=S_DIV; ridx<=0; rly<=0; cnt<=0; m_start<=0; m_rw<=0; m_addr<=0; m_wdata<=0;
            configured<=0; div_a<=0; obs0<=0; obs1<=0; last_tog<=0; pending<=0; f_id<=0; f_lo<=0; f_hi<=0;
            seen<=0; stl<=0;
            c_canstat<=0; c_cnf1<=0; c_cnf2<=0; c_cnf3<=0; c_eflg<=0; c_canintf<=0; c_tecrec<=0;
        end else begin
            m_start <= 1'b0;
            // ★토글 변화 감지 → SETTLE_N 클럭 대기 → 안정된 데이터를, 릴레이중이 아닐 때 래치.
            //   PS 가 프레임을 PACE_US(150µs) 동안 안 건드리므로 64클럭(1.3µs) 대기면 cmd_lo/hi
            //   확실히 안정 → GPIO 쓰기 스큐(토글이 데이터보다 먼저 도착)로 인한 섞임 차단.
            //   릴레이중(S_RLY/S_RLY_W) 래치 금지 → f_lo/f_hi 중간 변경에 의한 섞임도 차단.
            if (!seen) begin
                if (new_frame) begin seen <= 1'b1; stl <= 7'd0; end
            end else begin
                if (stl < SETTLE_N) stl <= stl + 1'b1;
                else if (st != S_RLY && st != S_RLY_W) begin
                    last_tog <= cmd_id[31];
                    f_id <= cmd_id[10:0]; f_lo <= cmd_lo; f_hi <= cmd_hi; pending <= 1'b1;
                    seen <= 1'b0;
                end
            end
            case (st)
              S_DIV:  if (!m_busy) begin m_rw<=0; m_addr<=SPIDIV; m_wdata<={8'd0,cfg_in[7:0]}; m_start<=1'b1; st<=S_DIV_W; end
              S_DIV_W:  if (m_done) begin div_a<=cfg_in[7:0]; st<=S_CTRL; end
              S_CTRL: if (!m_busy) begin m_rw<=0; m_addr<=CTRL; m_wdata<={15'd0,cfg_in[8]}; m_start<=1'b1; st<=S_CTRL_W; end
              S_CTRL_W: if (m_done) begin configured<=1'b1; cnt<=0; st<=S_CHK; end

              S_CHK: begin
                  if      (pending)              begin rly<=0; st<=S_RLY; end      // ★릴레이 우선
                  else if (cfg_in[7:0]!=div_a)   st<=S_DIVRE;
                  else if (cnt>=SAMPLE_DIV-1) begin cnt<=0; ridx<=0; st<=S_RD; end
                  else cnt<=cnt+1'b1;
              end
              // ── 정상 프레임 릴레이 (6 쓰기) ──
              S_RLY: if (!m_busy) begin m_rw<=0; m_addr<=rly_addr; m_wdata<=rly_data; m_start<=1'b1; st<=S_RLY_W; end
              S_RLY_W: if (m_done) begin
                  if (rly==3'd5) begin pending<=1'b0; st<=S_CHK; end   // 트리거까지 끝
                  else begin rly<=rly+1'b1; st<=S_RLY; end
              end
              // ── MCP 되읽기 (관측) ──
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
              S_DIVRE: if (!m_busy) begin m_rw<=0; m_addr<=SPIDIV; m_wdata<={8'd0,cfg_in[7:0]}; m_start<=1'b1; st<=S_DIVRE_W; end
              S_DIVRE_W: if (m_done) begin div_a<=cfg_in[7:0]; st<=S_CHK; end
              default: st<=S_CHK;
            endcase
        end
    end
endmodule
