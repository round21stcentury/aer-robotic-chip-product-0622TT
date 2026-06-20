`timescale 1ns / 1ps
//============================================================================
// mcp2515_model_v2 — ★데이터시트 기준★ MCP2515 시뮬 모델 (재설계 원칙 #5)
//----------------------------------------------------------------------------
//  지난 실패: 옛 모델이 "드라이버 가정에 맞춰" 짜여 실물 버그(모드/순서)를 못 잡음.
//  이 모델은 ★MCP2515 의 진짜 규칙★ 을 강제해 그런 버그를 시뮬에서 드러낸다:
//   1) CNF1/2/3·RXB0CTRL·CANINTE 등 ★설정 레지스터는 "설정 모드(OPMOD=100)"에서만 쓰여진다.★
//      설정 모드가 아닐 때 쓰면 ★무시★ → 되읽기에서 0 으로 보임(= 순서 버그 노출).
//   2) CANCTRL 의 REQOP[7:5] 를 쓰면 CANSTAT 의 OPMOD[7:5] 가 그 모드로 바뀐다.
//   3) RTS(송신요청)는 ★정상 모드(OPMOD=000)에서만★ 실제 송신으로 본다. 정상 모드가
//      아니면 송신 실패로 보고 ★TXERR 카운트(tx_fail_cnt)★ 만 올린다(버스로 안 나감).
//   4) 송신 성공 시 tx_count 증가 + last_tx_* 스냅샷 → TB 가 "무엇이 몇 번 나갔나" 확인.
//  SPI Mode 0: 상승엣지 MOSI 샘플, 하강엣지 SO 제시.
//----------------------------------------------------------------------------
//  ★주의: 비트수준 CAN 타이밍/ACK 는 모델링 안 함(레지스터·모드·송신요청 수준).
//    실제 버스 동작은 HIL 실물 candump 로 검증한다(시뮬은 필요조건일 뿐).
//============================================================================
module mcp2515_model_v2 (
    input  wire sclk,
    input  wire mosi,
    input  wire csn,
    output wire miso,
    output wire int_n            // active-low: RX0IF 서면 0
);
    localparam CANSTAT=8'h0E, CANCTRL=8'h0F, CANINTF=8'h2C;
    localparam CNF3=8'h28, CNF2=8'h29, CNF1=8'h2A, CANINTE=8'h2B, RXB0CTRL=8'h60;

    reg [7:0]  regs [0:127];
    reg [7:0]  shin;
    reg [2:0]  bitc;
    reg [31:0] bytec;
    reg [7:0]  cmd, mask_r;
    reg [6:0]  addr_r;
    reg [7:0]  shout;
    reg        so_bit, drive;
    integer    i;
    // 송신 스냅샷/카운터 (TB 관측용)
    reg [10:0] last_tx_id;
    reg [3:0]  last_tx_dlc;
    reg [63:0] last_tx_data;
    reg        last_tx_seen;
    integer    tx_count;          // ★정상모드에서 성공한 송신 횟수
    integer    tx_fail_cnt;       // ★정상모드 아닐 때 RTS 친 횟수(버그 신호)

    assign miso  = (~csn && drive) ? so_bit : 1'bz;
    assign int_n = ~regs[CANINTF][0];

    // 현재 설정 모드인가 (OPMOD = CANSTAT[7:5] == 100)
    function is_config; input dummy; begin is_config = (regs[CANSTAT][7:5] == 3'b100); end endfunction
    // 현재 정상 모드인가 (OPMOD == 000)
    function is_normal; input dummy; begin is_normal = (regs[CANSTAT][7:5] == 3'b000); end endfunction
    // 설정모드에서만 써지는 레지스터인가
    function cfg_only; input [6:0] a; begin
        cfg_only = (a==CNF1[6:0])||(a==CNF2[6:0])||(a==CNF3[6:0])||(a==CANINTE[6:0])||(a==RXB0CTRL[6:0]);
    end endfunction

    initial begin
        for (i=0;i<128;i=i+1) regs[i]=8'h00;
        regs[CANSTAT]=8'h80;        // 리셋 후 설정 모드
        regs[CANCTRL]=8'h87;
        shin=0; bitc=0; bytec=0; cmd=0; mask_r=0; addr_r=0; shout=0; so_bit=0; drive=0;
        last_tx_id=0; last_tx_dlc=0; last_tx_data=0; last_tx_seen=0; tx_count=0; tx_fail_cnt=0;
    end

    always @(negedge csn) begin bitc<=0; bytec<=0; drive<=0; end

    always @(posedge sclk) begin
        if (!csn) begin
            if (bitc==3'd7) begin
                proc_byte({shin[6:0], mosi});
                bitc  <= 3'd0;
                bytec <= bytec + 1;
            end else begin
                shin <= {shin[6:0], mosi};
                bitc <= bitc + 1'b1;
            end
        end
    end

    always @(negedge sclk) begin
        if (!csn && drive) begin
            so_bit <= shout[7];
            shout  <= {shout[6:0], 1'b0};
        end
    end

    task proc_byte(input [7:0] b);
        begin
            if (bytec==0) begin
                cmd <= b;
                case (b)
                    8'hC0: begin regs[CANSTAT]<=8'h80; regs[CANCTRL]<=8'h87; end       // RESET → 설정 모드
                    8'hA0: begin shout<=regs[CANINTF]; drive<=1'b1; end                // READ STATUS
                    default:
                        if ((b & 8'hF8)==8'h80 && b[0]) begin                           // RTS TXB0
                            if (is_normal(1'b0)) begin                                  // ★정상 모드에서만 송신
                                last_tx_id  <= {regs[8'h31], regs[8'h32][7:5]};
                                last_tx_dlc <= regs[8'h35][3:0];
                                last_tx_data<= {regs[8'h3D],regs[8'h3C],regs[8'h3B],regs[8'h3A],
                                                regs[8'h39],regs[8'h38],regs[8'h37],regs[8'h36]};
                                last_tx_seen<= 1'b1;
                                tx_count    <= tx_count + 1;
                                regs[8'h30] <= 8'h08;    // ★TXREQ busy (0x30 읽으면 클리어 → 칩 폴 1회 돔)
                            end else begin
                                tx_fail_cnt <= tx_fail_cnt + 1;                         // ★모드 틀림 = 송신 실패
                            end
                        end
                endcase
            end else if (bytec==1) begin
                addr_r <= b[6:0];
                if (cmd==8'h03) begin
                    shout<=regs[b[6:0]]; drive<=1'b1;                                   // READ: 데이터 준비
                    if (b[6:0]==7'h30) regs[8'h30] <= regs[8'h30] & ~8'h08;            // ★TXREQ 읽으면 클리어(송신완료 모사)
                end
            end else begin
                case (cmd)
                    8'h02: begin                                                        // WRITE(자동증가)
                        if (!(cfg_only(addr_r) && !is_config(1'b0)))                     // ★설정전용은 설정모드만
                            regs[addr_r] <= b;
                        if (addr_r==CANCTRL) regs[CANSTAT] <= {b[7:5], regs[CANSTAT][4:0]};  // 모드 반영
                        addr_r <= addr_r + 1'b1;
                    end
                    8'h05: begin                                                        // BIT MODIFY
                        if (bytec==2) mask_r<=b;
                        else if (!(cfg_only(addr_r) && !is_config(1'b0)))
                            regs[addr_r] <= (regs[addr_r] & ~mask_r) | (b & mask_r);
                    end
                    8'h03: begin shout<=regs[addr_r+1'b1]; addr_r<=addr_r+1'b1; end      // READ 연속
                    default: ;
                endcase
            end
        end
    endtask

    // ── TB 가 수신 프레임 주입(시뮬 전용, 스텝4) ──
    task mdl_rx_inject(input [10:0] iid, input [3:0] idlc, input [63:0] idata);
        begin
            regs[8'h61] = iid[10:3];
            regs[8'h62] = {iid[2:0], 5'b0};
            regs[8'h65] = {4'b0, idlc};
            regs[8'h66] = idata[7:0];   regs[8'h67] = idata[15:8];  regs[8'h68] = idata[23:16];
            regs[8'h69] = idata[31:24]; regs[8'h6A] = idata[39:32]; regs[8'h6B] = idata[47:40];
            regs[8'h6C] = idata[55:48]; regs[8'h6D] = idata[63:56];
            regs[CANINTF] = regs[CANINTF] | 8'h01;   // RX0IF
        end
    endtask
endmodule
