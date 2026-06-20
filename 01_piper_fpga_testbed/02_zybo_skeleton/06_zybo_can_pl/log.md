# 06_zybo_can_pl 변경 로그

> **규칙:** 동작변경/새 변형은 in-place 금지 → `_v숫자` 복사본 + 여기 기록. (코드 버전 규칙)
> 06은 05_zybo_can_eth의 소스 복사본에서 출발 → PL CAN으로 이식.

## v1 (2026-06-14) — 밑작업 스캐폴드
- 05_zybo_can_eth에서 **소스만** 복사(생성물 vitis_ws/*_vivado/_ide/*.log 제외):
  `src/{udp_can_main.c,can_main.c}`, `build_hil_app.py`, `rebuild_app.py`, `Makefile`,
  `tools/`, `zybo_can.xdc`, `configure_ps_can.tcl`.
- **빌드 스크립트 경로 이식**: `BASE = 하드코딩 → os.path.dirname(abspath(__file__))`,
  XSA 자동탐색(glob), PLAT/APP = `zybo_pl`/`udp_can_pl_app`.
- `src/udp_can_main.c` 상단에 **XCanPs→CTU CAN-FD AXI 교체 3곳 마킹**(init/send/recv).
- `vivado/export_05_bd.tcl` 추가 — 05 block design을 tcl로 뽑아 06 출발점.
- README에 작업 체크리스트(1~5단계) + 투명검증 기준.
- 아직 **하드웨어(PL CAN) 미작업** — Vivado 작업은 사용자 몫(README 2단계).

## (다음) v2 — 사용자 Vivado 작업 후
- CTU CAN-FD 추가/핀배선/XSA export → PS 코드 3곳 교체 → 투명검증 결과 기록.
