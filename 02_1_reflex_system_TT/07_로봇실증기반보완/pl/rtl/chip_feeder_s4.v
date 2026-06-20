`timescale 1ns / 1ps
//============================================================================
// chip_feeder_s3 — 스텝3 PL 공급기 (★정상명령 릴레이 + 설정 + ★XADC 트리거 적재 + MCP 되읽기 관측)
//----------------------------------------------------------------------------
//  PS(이더넷 lwIP)가 받은 CAN 프레임을 ★GPIO 메일박스★ 로 PL 에 넘기면, 이 모듈이
//  SPI 로 칩 정상-프레임 레지스터(0x50~0x55)에 써넣어 칩이 MCP 로 중계하게 한다.
//   메일박스(PS→PL, GPIO 출력):
//     cmd_lo[31:0] = 데이터 D0~D3 (D0=[7:0])
//     cmd_hi[31:0] = 데이터 D4~D7
//     cmd_id[31:0] = [31]=토글, [10:0]=CAN id.  PS 가 lo/hi 먼저 쓰고 ★토글 마지막★.
//   토글이 바뀌면 새 프레임 → 래치 후 릴레이(6 SPI 쓰기). 릴레이는 ★되읽기보다 우선★.
//  ★XADC 트리거(스텝3 완성): 주기마다 rule_in→rule2(0x12), thr_in→thresh2(0x1A),
//     xadc_val→0x30 적재. 칩 reflex_core_s3 가 (xadc_val>=thresh2) 면 rule2(src=1) 발동→홈포즈.
//     rule_in/thr_in 은 PS GPIO 라 ★재합성 없이 런타임 튜닝/활성화★. rule1(소프트 트리거)은 유지.
//   부팅: SPI_DIV(0x03)·CONTROL(0x02) 적재. 운전: 새 프레임 릴레이 / 주기적 (rule/thr/xadc 적재 + MCP 되읽기).
//============================================================================
module chip_feeder_s4 #(
    parameter integer SAMPLE_DIV = 50000,
    parameter [6:0]   RULE2_ADDR = 7'h12,   // 칩 RULE2 (XADC 규칙: FSR 선택 — estop/덕포즈/움찔)
    parameter [6:0]   THR2_ADDR  = 7'h1A,   // 칩 THRESH2 (FSR 임계, 1개)
    parameter [6:0]   FLO_ADDR   = 7'h46,   // 칩 FLINCH_LO (움찔 지속 틱 하위)
    parameter [6:0]   FHI_ADDR   = 7'h47,   // 칩 FLINCH_HI (상위)
    parameter [6:0]   D5_ADDR    = 7'h44,   // 칩 RECOIL_D5 = J5 움츠림 델타(0.001도)
    parameter [6:0]   RSPD_ADDR  = 7'h48,   // 칩 REFLEX_SPEED (반사 0x151 속도율)
    parameter [6:0]   DBNC_ADDR  = 7'h49,   // ★칩 DEBOUNCE (FSR 디바운스 사이클)
    parameter [6:0]   HYST_ADDR  = 7'h4A,   // ★칩 HYST (슈미트 히스테리시스 시프트)
    parameter [6:0]   XADC_ADDR  = 7'h30    // 칩 XADC_VAL
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] cfg_in,          // [7:0]SPI_DIV [8]enable [9]소프트 pose 트리거
    // ★정상명령 메일박스 (PS GPIO)
    input  wire [31:0] cmd_lo,
    input  wire [31:0] cmd_hi,
    input  wire [31:0] cmd_id,          // [31]=toggle [10:0]=id
    // ★XADC 트리거 (PS GPIO + XADC IP). 임계 1개(thr_in), 규칙 1개(rule_in=FSR 기능 선택)
    input  wire [15:0] xadc_val,        // XADC 현재 측정값 (하위 12비트 유효)
    input  wire [15:0] thr_in,          // FSR 임계 (PS 가 GPIO 로, 재합성 없이 변경)
    input  wire [15:0] rule_in,         // ★FSR 규칙 선택: 0x79=estop / 0x5A=덕포즈 / 0x5B=움찔 / 0=비활성
    input  wire [31:0] flinch_in,       // ★움찔(act3) 1회성 지속 틱 (PS가 클럭상대로 설정 → 칩 0x46/0x47)
    input  wire [15:0] d5_in,       // ★J5 움츠림 델타(PS RECOIL_RAD→0.001도, 칩 0x44)
    input  wire [15:0] rspeed_in,       // ★반사 0x151 속도율 (1~100, PS가 → 칩 0x48)
    input  wire [15:0] debounce_in,     // ★FSR 디바운스 사이클 (PS가 → 칩 0x49). 노이즈 자가발동 방지
    input  wire [15:0] hyst_in,         // ★슈미트 히스테리시스 시프트 (PS가 → 칩 0x4A). 꾹눌러도 1회 락
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

    localparam [4:0] S_DIV=0, S_DIV_W=1, S_CTRL=2, S_CTRL_W=3, S_CHK=4,
                     S_RLY=5, S_RLY_W=6, S_RD=7, S_RD_W=8, S_DIVRE=9, S_DIVRE_W=10,
                     S_RULE2=11, S_RULE2_W=12, S_THR=13, S_THR_W=14, S_XADC=15, S_XADC_W=16,
                     S_FLO=17, S_FLO_W=18, S_FHI=19, S_FHI_W=20, S_D5=21, S_D5_W=22,
                     S_RSPD=23, S_RSPD_W=24, S_DBNC=25, S_DBNC_W=26, S_HYST=27, S_HYST_W=28;
    reg [4:0]  st;
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
                  else if (cnt>=SAMPLE_DIV-1) begin cnt<=0; st<=S_RULE2; end       // 주기: rule/thr/xadc 적재 → 되읽기
                  else cnt<=cnt+1'b1;
              end
              // ── 정상 프레임 릴레이 (6 쓰기) ──
              S_RLY: if (!m_busy) begin m_rw<=0; m_addr<=rly_addr; m_wdata<=rly_data; m_start<=1'b1; st<=S_RLY_W; end
              S_RLY_W: if (m_done) begin
                  if (rly==3'd5) begin pending<=1'b0; st<=S_CHK; end   // 트리거까지 끝
                  else begin rly<=rly+1'b1; st<=S_RLY; end
              end
              // ── ★XADC 트리거 적재: rule2(FSR 선택 기능) → thresh2 → flinch(0x46/0x47) → xadc_val ──
              S_RULE2:   if (!m_busy) begin m_rw<=0; m_addr<=RULE2_ADDR; m_wdata<=rule_in;        m_start<=1'b1; st<=S_RULE2_W; end
              S_RULE2_W: if (m_done) st<=S_THR;
              S_THR:     if (!m_busy) begin m_rw<=0; m_addr<=THR2_ADDR;  m_wdata<=thr_in;         m_start<=1'b1; st<=S_THR_W; end
              S_THR_W:   if (m_done) st<=S_FLO;
              S_FLO:     if (!m_busy) begin m_rw<=0; m_addr<=FLO_ADDR;   m_wdata<=flinch_in[15:0]; m_start<=1'b1; st<=S_FLO_W; end
              S_FLO_W:   if (m_done) st<=S_FHI;
              S_FHI:     if (!m_busy) begin m_rw<=0; m_addr<=FHI_ADDR;   m_wdata<=flinch_in[31:16];m_start<=1'b1; st<=S_FHI_W; end
              S_FHI_W:   if (m_done) st<=S_D5;
              S_D5:    if (!m_busy) begin m_rw<=0; m_addr<=D5_ADDR;  m_wdata<=d5_in;      m_start<=1'b1; st<=S_D5_W; end
              S_D5_W:  if (m_done) st<=S_RSPD;
              S_RSPD:   if (!m_busy) begin m_rw<=0; m_addr<=RSPD_ADDR; m_wdata<=rspeed_in; m_start<=1'b1; st<=S_RSPD_W; end
              S_RSPD_W: if (m_done) st<=S_DBNC;
              S_DBNC:   if (!m_busy) begin m_rw<=0; m_addr<=DBNC_ADDR; m_wdata<=debounce_in; m_start<=1'b1; st<=S_DBNC_W; end
              S_DBNC_W: if (m_done) st<=S_HYST;
              S_HYST:   if (!m_busy) begin m_rw<=0; m_addr<=HYST_ADDR; m_wdata<=hyst_in;     m_start<=1'b1; st<=S_HYST_W; end
              S_HYST_W: if (m_done) st<=S_XADC;
              S_XADC:    if (!m_busy) begin m_rw<=0; m_addr<=XADC_ADDR;  m_wdata<=xadc_val;       m_start<=1'b1; st<=S_XADC_W; end
              S_XADC_W:  if (m_done) begin ridx<=0; st<=S_RD; end
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
