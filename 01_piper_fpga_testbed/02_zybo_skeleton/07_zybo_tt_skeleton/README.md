# 07_zybo_tt_skeleton

TinyTapeout으로 만들 반사 칩의 스켈레톤입니다. 칩과 똑같은 입출력을 가진 래퍼를 PL에 올려, 칩이 될 로직을 미리 개발하고 검증하는 환경입니다. 베이스는 `06_zybo_can_pl`입니다.

## 무엇을 위한 폴더인가

같은 반사 로직을 세 곳에서 똑같이 돌리는 것이 목표입니다. 먼저 이 PL 안에서, 다음에 별도 FPGA에서 핀헤더로 이어서, 마지막에 진짜 칩으로 만듭니다. 바뀌는 것은 로직이 어디서 도느냐뿐이고 내용은 같습니다. 그래서 여기서 검증한 동작은 칩이 되어도 그대로입니다.

## 칩의 핀 구성

- 위험 입력은 `ui_in[0]`, 안전 인터록은 `ui_in[7]`. 나머지 입력 핀은 다른 위험 플래그와 모드를 위해 예약.
- 반사 결정은 `uo_out`로 나갑니다. valid, fire, action_id(3비트), estop_level, heartbeat.
- 설정과 데이터는 SPI로 주고받습니다. `uio[0]`=SCLK, `uio[1]`=MOSI, `uio[2]`=CS_n, `uio[3]`=MISO.
- `uio[7:4]`는 텔레메트리와 외부 ADC 직결을 위해 핀만 미리 잡아 둔 자리입니다.

빠른 반사 결정은 병렬 신호로 즉시 나가고, 설정과 센서 데이터는 SPI로 주고받습니다. 그래서 SPI가 바빠도 반사 발사는 느려지지 않습니다.

## 구성 파일

- `rtl/tt_um_reflex.v` — 칩 모양 래퍼(TinyTapeout 제출 형식).
- `rtl/reflex_core_tt.v` — 칩 내부 반사 로직.
- `rtl/spi_slave.v` — 설정·데이터용 SPI 슬레이브.
- `sim/tb_tt_um_reflex.v`, `sim/run_sim.sh` — 검증.

## 검증 실행

```bash
cd sim
bash run_sim.sh
```

SPI로 ID와 SCRATCH를 확인하고, 위험 입력에 반사가 나오는지 확인합니다. 자세한 진행과 결정 사항은 `log.md`를 보세요.
