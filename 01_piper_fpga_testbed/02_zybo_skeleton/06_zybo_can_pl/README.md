# 06_zybo_can_pl — CTU CAN-FD를 버스에 올리기 (반사의 토대, AND 검증 방식)

> **목표(06):** CTU CAN-FD를 PL에 올려 **PS CAN과 같은 버스의 2번째 노드**로 동작시킨다.
> 트랜시버 1개를 **wired-AND**로 공유 → 평상시 PS가 명령, 트리거 시 CTU가 끼어들기.
> **06 합격 기준:** ① 평상시 PS 명령이 05와 똑같이 동작 ② CTU가 버스에 프레임(0x150)을 띄우면 candump/로봇에 보임.
>
> **왜 AND 먼저?** CTU 통합(AXI/주소/빌드)·트리거·반사 FSM이 진짜 일이고, 버스 결합은 AND 1줄.
> AND로 **타이밍 로직 없이** "CTU가 버스에서 산다"를 먼저 검증 → 나중에 mux는 idle감지 FSM만 추가(08 후퇴용).

## 구조 (AND 검증 방식)
```
평상시:  PS XCanPs(EMIO) ─┐
                          AND ── 트랜시버 ── 물리 CAN ── 로봇/USB-CAN   (CTU 침묵 → PS 독점)
         CTU CAN-FD(PL) ──┘
                          ▲ RXD → PS_rx 와 CTU_rx 둘 다 (되읽기 필수)

반사:    PS(0x155) ─┐
                    AND ── ...   CTU가 0x150 송신 → CAN 중재가 0x150 채택(낮은ID 승)
         CTU(0x150)─┘
```
- **PS CAN0 EMIO 유지**(안 건드림 = 05 그대로 = 폴백). CTU만 추가.
- override는 **CAN 중재가 자동**(select 신호 없음). AND는 트랜시버 공유용.
- 한계: 같은 ID(후퇴 0x155~7)는 AND로 안 됨 → 08에서 mux+idle감지 추가.

## 폴더 구성 (05에서 소스만 복사)
```
06_zybo_can_pl/
├── src/udp_can_main.c   PS 코드 — XCanPs 정상경로 유지 + CTU AXI 송신 "추가"(상단 마킹)
├── src/can_main.c        PS CAN init 참조
├── build_hil_app.py / rebuild_app.py   ★경로 이식 완료★ (XSA 자동탐색)
├── Makefile, tools/      program/serial/검증 (05 재사용)
├── zybo_can.xdc          ★트랜시버 TXD/RXD 핀 제약 (PS+CTU 공유)★
├── vivado/{export_05_bd.tcl, create_06_project.tcl, 05_design_ref.tcl}
├── sim/                  CTU/AND/반사 시뮬 (시뮬-퍼스트)
└── log.md
```

## 작업 체크리스트

### 1단계 — 출발점 (완료)
- [V] `export_05_bd.tcl` → `05_design_ref.tcl`
- [V] 06 프로젝트 생성 + `source 05_design_ref.tcl` 로 design 재생성

### 2단계 — Vivado: CTU 추가 + AND 결합 (당신 작업)  ※상세는 `../bin/02_ctu_canfd_integration.md`
- [V] **CTU CAN-FD IP** 등록(IP Repository)·추가 → AXI→APB 브리지로 PS M_AXI_GP0에 연결
- [V] **PS CAN0 EMIO 유지** (제거 X). CTU의 `CAN_tx`/`CAN_rx`를 Make External
- [V] ★**wired-AND 게이트**: `trans_TXD = PS_can_tx AND CTU_can_tx`
      → Vivado **`Utility Vector Logic`(AND, 1-bit)** IP 추가해 두 tx를 AND, 출력=트랜시버 TXD
- [V] **RXD → PS_can_rx 와 CTU_rx 둘 다** 연결 (되읽기. 안 하면 진 쪽이 진 줄 모름)
- [V] `trans_TXD`/`RXD`를 트랜시버 핀에 (zybo_can.xdc) — 05 트랜시버 핀 재사용
- [V] **Address Editor → Assign All** → CTU 베이스주소 확인(PS 코드용)
- [V] CTU `scan_enable`=Constant 0, `timestamp[63:0]`=Constant 0 (안 묶으면 Validate 에러)
- [V] **CTU 다 넣은 뒤** .bd 우클릭 → Create HDL Wrapper → Generate Bitstream → Export HW(Include bitstream) → `vivado/zybo_can_pl.xsa`
- [V] 이 06 design도 `write_bd_tcl`로 export(다음 skeleton 베이스)

### 3단계 — PS 코드 (정상경로 유지 + CTU 송신 추가)
- [ ] `init_can()`(XCanPs) **그대로** — 정상 명령은 PS가 계속
- [ ] **CTU 초기화 함수 추가**: AXI로 CTU 비트타이밍(1Mbps)+enable (베이스주소=Address Editor 값)
- [ ] **CTU 송신 함수 추가**: 0x150(또는 임의 ID) 한 장을 CTU TX버퍼에 write + trigger
- [ ] 검증용 트리거: 일단 PS가 (UDP 명령/버튼으로) CTU 송신 호출 — 07에서 이걸 PL FSM(DIP)로 옮김
- (※05 PS 코드를 "교체"하지 않고 "추가"만. 마킹은 추가 위치 안내용)

### 4단계 — 빌드 & 프로그램
- [ ] `source /opt/Xilinx/2025.2/Vitis/settings64.sh && vitis -s build_hil_app.py`
- [ ] `make program`

### 5단계 — ★검증★ (두 가지)
- [ ] (a) 평상시: `cd ../../03_hils && make slider MODE=hil` → **05와 동일**하게 PS 명령으로 로봇 동작(=AND 통과 OK)
- [ ] (b) CTU: 트리거로 CTU가 0x150 송신 → **candump(can0)에 0x150 뜨고 / 로봇 멈춤** → CTU가 버스에 산다 확인
- [ ] ✅ 둘 다 통과 → CTU 검증 끝 → **07_reflex_estop**: 트리거→송신을 **PL FSM(DIP)**로 이전 = 진짜 하드웨어 반사

## 다음 (07/08)
- **07 e-stop**: DIP → PL FSM → CTU가 0x150. (AND+중재 그대로, PS 무손상)
- **08 retreat**: 같은 ID라 mux 필요 → **idle 감지 FSM**(RX 리세시브 ~11비트 카운트) 추가해 PS TX 차단 후 CTU가 0x155~7 스트리밍. 속도는 MotionCtrl 속도필드=100%로 최대.

## CAN 핵심 참고 (개발 내내)
- **레벨:** 도미넌트=0(우선), 리세시브=1. 버스=모든 TX의 AND.
- **프레임:** `SOF│ID(중재)│Control│Data│CRC│ACK│EOF(7리세시브)│IFS(3리세시브)`. 중재는 ID 보내는 동안 일어나고 승자가 끊김없이 Data까지 이어감.
- **idle:** 프레임 끝 EOF+IFS로 **버스가 리세시브 ≥11비트 → idle**(누구나 송신 시작 가능). IFS는 **의무**라 프레임마다 항상 옴 → 최악 대기 ~1프레임(~130µs).
- **AND 방식엔 idle 로직 불필요**(CTU 컨트롤러가 알아서 idle대기+중재). idle감지 FSM은 08 mux에서만.
- 상세: `../bin/02_ctu_canfd_integration.md` (레지스터맵 0x00=DEVICE_ID 0xCAFD 등)
