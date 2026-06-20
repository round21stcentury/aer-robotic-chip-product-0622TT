`timescale 1ns / 1ps
//============================================================================
// tt_um_reflex — TinyTapeout 제출용 껍데기(MPW 래퍼) = "칩 모양 래퍼"
//----------------------------------------------------------------------------
//  TinyTapeout이 정한 표준 핀(ui_in/uo_out/uio_*/ena/clk/rst_n)을 가진다.
//  이 핀 규격은 진짜 칩과 한 치도 다르지 않다. 그래서 이 모듈을
//   - PL 안에 그대로 올려서(1단계) 개발·검증하고,
//   - 별도 FPGA에 올려서(검증 단계) 핀헤더로 잇고,
//   - 제출해서 진짜 칩으로 만든다.
//  바뀌는 것은 이 모듈이 어디서 도느냐뿐, 내용은 같다.
//
//  핀 배치(2026-06-15 확정/동결):
//    ui_in[0]   danger_estop  가장 빠른 비상정지 위험            [사용]
//    ui_in[1]   danger_fast   추가 빠른 위험 신호                [예약]
//    ui_in[2]   can_rx        CAN 수신(CAN 회로용)               [예약]
//    ui_in[6:3] (여유)                                            [여유]
//    ui_in[7]   arm_enable    안전 인터록(1이어야 발사)          [사용]
//    uo_out[0]  valid         결정이 안정됨                      [사용]
//    uo_out[1]  fire          지금 발사                          [사용]
//    uo_out[4:2]action_id     어떤 반사인지(0=없음,1=e-stop,…)   [사용]
//    uo_out[5]  ps_gate       정상 명령 억제(같은 ID, 2-송신기)  [예약]
//    uo_out[6]  can_tx        CAN 송신(CAN 회로용)               [예약]
//    uo_out[7]  heartbeat     살아있음                           [사용]
//    uio[0]     SCLK (입력)   설정/포즈/센서 SPI                 [사용]
//    uio[1]     MOSI (입력)   설정+포즈·센서값+(나중에 정상명령) [사용]
//    uio[2]     CS_n (입력)                                       [사용]
//    uio[3]     MISO (출력)   텔레메트리+반사 계산결과           [사용]
//    uio[5:4]   (여유/텔레메트리)                                 [여유]
//    uio[7:6]   외부 ADC 직결 자리                                [예약]
//============================================================================
module tt_um_reflex (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire        spi_miso, spi_miso_oe;
    wire        valid, fire, heartbeat;
    wire [2:0]  action_id;

    reflex_core_tt u_core (
        .clk(clk), .rst_n(rst_n),
        .danger(ui_in[0]), .arm_enable(ui_in[7]),
        .spi_sclk(uio_in[0]), .spi_mosi(uio_in[1]), .spi_csn(uio_in[2]),
        .spi_miso(spi_miso), .spi_miso_oe(spi_miso_oe),
        .valid(valid), .fire(fire), .action_id(action_id),
        .heartbeat(heartbeat)
    );

    // 결정 출력(병렬). uo_out[6]=can_tx, [5]=ps_gate 는 예약 — 지금은 0.
    assign uo_out = {heartbeat, 1'b0 /*can_tx 예약*/, 1'b0 /*ps_gate 예약*/, action_id, fire, valid};

    // SPI MISO는 uio[3], 나머지 출력 비트는 0. (예약 텔레메트리/ADC uio[7:4]=0)
    assign uio_out = {4'b0000, spi_miso, 3'b000};
    // 방향: uio[7:4] 출력, uio[3] MISO(전송 중만), uio[2:0] 입력
    assign uio_oe  = {4'b1111, spi_miso_oe, 3'b000};

    // 미사용/예약 신호 정리(TinyTapeout lint 경고 방지)
    //  ui_in[1]=danger_fast, [2]=can_rx 는 예약(아직 미사용), [6:3]=여유
    wire _unused = &{1'b0, ena, ui_in[6:1], uio_in[7:3]};
endmodule
