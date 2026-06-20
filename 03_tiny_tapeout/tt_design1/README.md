# tt_design1 — TT 반사 칩 (첫 완성본)

> **이 설계물 = TinyTapeout 반사 코어 `tt_um_reflex_s3` + 이를 검증/구동하는 Zynq PL·PS 하니스.**
> 4스텝(패스스루·estop·덕포즈·움찔) 목표를 한 칩에 담은 **첫 완성본**. HW(HIL) 검증 완료.
> 칩 내부 사양은 **`칩_사양서.md`**, 작업 이력은 **`수행기록.md`**, 이 문서는 **경계·사용법·빌드·튜닝**.

---

## 1. 이게 뭐냐 (한눈에)
로봇 팔(Piper)의 CAN 명령 경로 한가운데 **칩이 앉아** 평상시엔 명령을 **그대로 중계**, 위험 신호가 오면 **명령을 끊고 반사 동작을 주입**한다. 칩이 CAN의 **유일한 송신자**라 "차단 게이트"가 칩 내부 멀티플렉서 한 줄.

**트리거 2개, 각각 한 기능:**
| 트리거 | 기능 | 설명 |
|---|---|---|
| **DIP(SW0)** | **estop** (항상) | 물리 비상정지. 누르면 0x150 주입, 로봇 정지 |
| **FSR(아날로그/XADC)** | **estop · 덕포즈 · 움찔 중 1택** | 전압이 임계 넘으면 발동. 어떤 반사인지는 `FSR_RULE`로 선택 |

- **estop**: 0x150 주기송신 → 로봇 정지
- **덕포즈**: 0x155~7=0 (홈) 주입, 센서 누르는 동안 유지
- **움찔**: 홈포즈를 ★잠깐(FLINCH_MS) 발동했다 자동해제★ = "홱 움찔" (엣지 1회성)

---

## 2. 파일 구조
```
chip/rtl/      ★TT 칩 RTL (이게 타입아웃 대상)
  tt_um_reflex_s3.v   최상위(TT 표준 핀)
  spi_slave_full.v    PL↔칩 SPI 슬레이브 + 레지스터맵(설정/정상프레임/되읽기)
  reflex_core_s3.v    규칙 기반 반사 결정(estop/덕포즈/움찔 + 우선순위 + XADC 비교 + 움찔 1회성)
  reflex_pose_gen_s3.v 홈포즈 프레임 생성   reflex_tx_s3.v 반사 송신원(estop vs 포즈)
  mcp_tx_mux.v        평상시/반사 먹스      mcp_init.v MCP2515 초기화
  mcp_tx_send.v 송신  mcp_probe.v 되읽기   mcp_arb4.v SPI 4클라이언트 중재
  spi_master_mcp_v2.v 칩→MCP SPI 드라이버
chip/sim/      tb_tt_um_reflex_s3.v (칩 통합 시뮬) + run_sim_top.sh
pl/rtl/        reflex_top_s3.v(PL 최상위) chip_feeder_s3.v(칩 자동설정/명령릴레이) spi_master.v xadc_reader.v
pl/sim/        tb_reflex_top_s3.v (PL 통합 시뮬) + run_sim_topc.sh
fpga/          vivado/*.tcl(프로젝트·결선·XSA) build_app_s3.py(PS앱) src/reflex_s3_main.c zybo_s3.xdc tools/
Makefile       빌드·프로그램·시뮬·튜닝 자동화 (§6)
```

---

## 3. ★경계 / 계약 (안정된 인터페이스 — 뒤로 내부 자유 교체)
이 설계의 뼈대는 **좁고 안정된 계약 경계**다. 각 경계만 지키면 양쪽 내부를 따로 바꿔도 된다.

| 경계 | 계약 (고정) |
|---|---|
| **칩 핀** (TT 24 IO) | ui_in[0]=DIP, [1]=소프트트리거, [2]=MCP_INT, [3]=MCP_MISO, [7]=arm. uio[0:2]=슬레이브 SPI(in), [3]=miso, [4:6]=MCP SPI(out). uo_out=관측. **동결.** |
| **칩 SPI 레지스터맵** | 24비트 트랜잭션(8b 명령+16b 데이터). 0x10~13 규칙·0x18~1B 임계·0x30 XADC·0x46/47 움찔틱·0x50~55 정상프레임·0x20~28 되읽기. (상세 `칩_사양서.md`) |
| **CAN 프레임** | estop=0x150(D0=1) · 포즈=0x155/156/157(관절 2×부호32비트 0.001°,BE) · ★속도=0x151(ctrl1·move1·REFLEX_SPEED — 반사가 포즈 앞에 주입) · (수신용 0x2A5~7·0x2A1 — 안 씀) |
| **아날로그 입력** | JXADC AD14 = N15(P)/N16(N→GND). **0.55~1.0V 직결**(분압X). 절대 1V 초과 금지 |
| **PS UDP** | 192.168.1.10:5000. 13바이트(can_id 4B BE + dlc 1B + 8 data). 명령 id 집합 {0x150,151,155,156,157,471}. ★제어 0x7F0(소프트 트리거 on/off) |
| **make 옵션** | 칩 동작 파라미터를 재합성 없이(ELF만) 바꾸는 계약 (§6) |

---

## 4. 데이터 경로
```
[정상] PC슬라이더 →UDP→ PS(lwIP) →GPIO메일박스→ PL(chip_feeder) →SPI→ 칩(0x50~55) →먹스(normal)→ MCP2515 →CAN→ 로봇
[반사] DIP/FSR(아날로그) → 칩 reflex_core(규칙중재) → reflex_tx/pose_gen → 먹스(reflex,gate_active=1로 정상차단) → MCP →CAN→ 로봇
```

---

## 5. 빌드 / 프로그래밍
```bash
make sim       # 칩+PL 시뮬 PASS 확인 (먼저)
make fpga      # 프로젝트→결선→XSA (Vivado, XADC 포함). ★Chrome 닫기(OOM), -jobs 2
make build     # PS 앱(lwIP) — 칩 파라미터 주입(§6). ASCII 워크스페이스
make program   # 보드 JTAG (비트 + ELF)
make rerun     # ELF만 다시(빠름, MCP 리셋). 파라미터만 바꿨을 때
```
- **RTL/BD 바꾸면** `make fpga`부터 (재합성). ★단 `fpga/vivado/reflex_vivado` 먼저 지워 clean recreate (증분캐시 stale 함정).
- **칩 파라미터(§6)만 바꾸면** `make build VAR=.. && make rerun` — **재합성 불필요(~1분)**.

---

## 6. ★make 옵션 (칩 파라미터 — 재합성 없이 ELF로)
PS가 부팅 때 칩 레지스터에 써넣는 값들. `make build OPT=값 && make rerun`.

| 옵션 | 기본 | 뜻 | 칩 레지스터 |
|---|---|---|---|
| `SPI_DIV` | 4 | 칩→MCP SPI SCLK 반주기(클럭). 클수록 느림 | 0x03 |
| `FSR_RULE` | 0x005A | **FSR 반사 선택**: `0x79`=estop · `0x5A`=덕포즈 · `0x5B`=움찔 · `0`=비활성 | rule2(0x12) |
| `THRESH_V` | 0.76 | FSR 발동 임계 전압(V). 코드=V×4096 (입력 0.55~1.0V) | thresh2(0x1A) |
| `FLINCH_MS` | 200 | 움찔 1회성 지속(ms) | 0x46/0x47 |
| `CLK_MHZ` | 50 | 칩 클럭(MHz). 움찔 틱 = FLINCH_MS×CLK_MHZ×1000 | (틱 계산용) |
| `REFLEX_SPEED` | 100 | **반사(덕포즈/움찔) 이동 속도율(1~100)** = 실로봇 move_spd_rate. estop 무관 | 0x48 |
| `PACE_US` | 300 | PS 프레임 페이싱(µs). >파이프라인222 → 손상0 | (PS) |

**예시:**
```bash
make build FSR_RULE=0x79 && make rerun                 # FSR → estop
make build FSR_RULE=0x5B FLINCH_MS=150 && make rerun   # FSR → 움찔(0.15초)
make build THRESH_V=0.85 && make rerun                 # 임계 0.85V로
make build FSR_RULE=0x5B CLK_MHZ=25 && make rerun       # ★칩 클럭 25MHz면 움찔 틱 자동 재계산
```
★**왜 클럭상대 틱?** 움찔 지속을 ms가 아니라 **클럭 틱**으로 칩에 넣음 → 칩이 다른 속도로 돌면 `CLK_MHZ`만 바꿔 같은 ms 유지.

---

## 7. 운전 / 사용법 (HIL)
1. **순서 중요:** HIL(virtual_robot) **먼저** 띄우고 → `make rerun` → 그다음 트리거. (estop이 ACK해줄 로봇 없이 발동하면 MCP bus-off → §8)
2. **SW0(DIP) 내려둘 것** — 올리면 estop이 항상 발동(평상시 동작 안 보임).
3. **평상시:** 슬라이더 → 로봇 추종 (패스스루).
4. **반사:**
   - DIP 올림 → 로봇 정지(estop). 내림 → 복귀.
   - FSR 전압 ≥THRESH_V → 선택된 반사(FSR_RULE) 발동.
     - estop: 정지   · 덕포즈: 홈 유지(누르는 동안)   · 움찔: 홈쪽 0.2초 홱 → 자동복귀(1회성, 다시 하려면 전압 내렸다 올림)
   - 소프트(UDP 0x7F0 d0=1/0): 덕포즈 on/off (물리 FSR 없이 테스트용)

---

## 8. 주의사항
- **★bus-off 함정:** estop을 버스에 ACK해줄 로봇 없이 쏘면 TEC↑→bus-off→트리거 내려도 안 풀림(MCP 리셋=`make rerun` 필요). HIL은 로봇 먼저. (**움찔은 1회성이라 spam 없어 안전.**)
- **재합성 캐시 함정:** RTL 고친 뒤 `make fpga`만 재실행하면 stale 캐시 재사용 → `reflex_vivado` 폴더 삭제 후 재생성해야 반영.
- **아날로그 1V 초과 금지** (XADC 손상). Due는 0.55~1.0V 클램프.
- **OOM:** Vivado `-jobs 2` 고정(14GB램), 빌드 중 Chrome 닫기.
- **한글경로:** Vitis(make build)는 ASCII 워크스페이스(`../_vitis_ws`)에서 — 자동 처리됨.

---

## 9. 검증 상태
- ✅ 칩 시뮬(tb_tt_um_reflex_s3): 패스스루·estop·덕포즈·★움찔(발동→자동해제→재무장).
- ✅ PL 시뮬(tb_reflex_top_s3): FSR 규칙 0x5A/0x79/0x5B 전환 + 움찔 1회성.
- ✅ HW(HIL): DIP estop · FSR estop · FSR 덕포즈 · FSR 움찔 전부 실측 동작. 보드 건강(움찔 빌드 TEC=0).
- 칩 규모(FPGA OOC 참고): FF≈901, LUT≈793. (TT 타일 수는 OpenLane 필요 — 보류.)

---

## 10. 로드맵
- 이 완성본 = **타임드 플린치로 "움츠림" 실현**(RX 없이). 
- parked: **RX 기반 "진짜 현재포즈 상대 움츠림"**(0x40~45 델타 + MCP RX). RX 공존버그(공유 SPI 드라이버 경쟁) 해결 후. (`04_현재포즈_움츠림`에 옛 시도 보존)
