`timescale 1ns / 1ps
//============================================================================
// reflex_core_tt — 칩 내부 반사 로직 (1단계 최소판)
//----------------------------------------------------------------------------
//  두 갈래로 동작한다.
//   1) 빠른 경로: 위험 입력(danger)을 동기화·디바운스해서, 위험하면 즉시
//      fire/action_id를 병렬 신호로 내보낸다. SPI를 거치지 않아 빠르다.
//   2) 설정/데이터 경로: SPI 슬레이브로 설정값을 받고 상태를 읽게 한다.
//      (1단계에서는 ID/VERSION/SCRATCH 레지스터까지만. 규칙 표는 다음 단계.)
//
//  앞으로 02(디폴트 포즈 회귀), 09(현재 포즈 기반 프레임 생성)는 이 모듈을
//  키워나간다. 바깥 핀 규격(아래 포트)은 고정해서 단계가 바뀌어도 그대로 쓴다.
//============================================================================
module reflex_core_tt #(
    parameter integer DEBOUNCE = 4,    // 위험 입력 디바운스(칩 clk 기준). 1단계는 작게.
    parameter integer HB_BIT   = 20    // heartbeat 토글 비트
)(
    input  wire        clk,
    input  wire        rst_n,
    // ── 빠른 위험 입력 ──
    input  wire        danger,
    input  wire        arm_enable,     // 안전 인터록: 1이어야 반사 발사
    // ── SPI(설정·데이터) ──
    input  wire        spi_sclk,
    input  wire        spi_mosi,
    input  wire        spi_csn,
    output wire        spi_miso,
    output wire        spi_miso_oe,
    // ── 반사 결정 출력(빠른 병렬) ──
    output reg         valid,
    output reg         fire,
    output reg  [2:0]  action_id,
    output wire        heartbeat
);
    // ── SPI 슬레이브 ──
    spi_slave u_spi (
        .clk(clk), .rst_n(rst_n),
        .sclk(spi_sclk), .mosi(spi_mosi), .csn(spi_csn),
        .miso(spi_miso), .miso_oe(spi_miso_oe)
    );

    // ── 위험 입력 2단 동기화 + 디바운스 ──
    reg [1:0] dsync;
    always @(posedge clk) if (!rst_n) dsync <= 0; else dsync <= {dsync[0], danger};
    reg [7:0] db;  reg dstable;
    always @(posedge clk) begin
        if (!rst_n)                   begin db <= 0; dstable <= 0; end
        else if (dsync[1] == dstable) db <= 0;
        else if (db >= DEBOUNCE) begin dstable <= dsync[1]; db <= 0; end
        else                          db <= db + 1'b1;
    end

    // ── 반사 결정(1단계: 위험하고 무장돼 있으면 e-stop=동작1) ──
    always @(posedge clk) begin
        if (!rst_n) begin valid <= 0; fire <= 0; action_id <= 0; end
        else begin
            valid <= 1'b1;                         // 1단계는 항상 유효
            if (dstable && arm_enable) begin
                fire <= 1'b1; action_id <= 3'd1;
            end else begin
                fire <= 1'b0; action_id <= 3'd0;
            end
        end
    end

    // ── heartbeat(살아있음 표시) ──
    reg [HB_BIT:0] hb;
    always @(posedge clk) if (!rst_n) hb <= 0; else hb <= hb + 1'b1;
    assign heartbeat = hb[HB_BIT];
endmodule
