# 04_zybo_can_v2 — ★검증된 PS CAN 브링업★ (이더넷 이전 베이스라인)

> Zybo **PS CAN0(EMIO) ↔ USB-CAN** 양방향을 **125k/500k/1Mbps 전부 검증**한 폴더.
> 05(이더넷 브리지)의 직전 단계이자, CAN 자체가 동작함을 증명한 **레퍼런스**.

## 무엇을 해결했나
초기 CAN 불통의 근본원인 3가지를 잡은 버전:
1. **EMIO 비활성** → Vivado에서 PS CAN0 EMIO 활성
2. **APER 클럭 미인가 / ÷105 분주** → 앱 SLCR 안전망(`CAN_CLK_CTRL ← 0x00100A01`)
3. 트랜시버 Rs 단락
→ 자세한 분석: `Vivado_ps7_init_버그_분석.md`

## 소스 (유지)
| 파일 | 역할 |
|---|---|
| `src/can_main.c` | PS CAN 베어메탈 앱 (05의 can_main.c 원본) |
| `zybo_can.xdc` | CAN EMIO 핀 제약 |
| `configure_ps_can.tcl` | PS CAN 설정 Tcl |
| `Makefile`, `README.md` | 빌드/문서 |
| `Vivado_ps7_init_버그_분석.md` | ps7_init 버그 분석 |
| `zybo_can_v2_vivado/zybo_can_v2.xsa` | XSA |

## 위치
05_zybo_can_eth는 이 폴더를 복사·발전시킨 것이라 내용이 일부 겹친다.
**현재 보드에 올리는 건 05.** 04는 "CAN만" 필요할 때의 깨끗한 참조로 보존.

## 🗑️ 삭제 가능 (~40M, 재생성)
`zybo_can_v2_vivado/{*.runs,*.gen,*.cache,*.hw,*.ip_user_files}`,
`zybo_can_v2_vitis/.../{export,build,_ide,.rigel_lopper}`.
