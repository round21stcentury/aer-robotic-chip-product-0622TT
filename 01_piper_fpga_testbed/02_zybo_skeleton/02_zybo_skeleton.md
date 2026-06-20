# 02_zybo_skeleton — FPGA 하드웨어 "펌웨어"

> **역할:** Zybo Z7-20(Zynq-7000)에 올라가는 **Vivado/Vitis 프로젝트들**.
> 번호 = 개발 단계 진화 순서. **지금 보드에 올라가는 건 `05_zybo_can_eth`**(이더넷→CAN 브리지).

## 단계별 폴더 (L2)
```
02_zybo_skeleton/
├── 01_zybo_test/            ① PS 부팅 hello_world (가장 초기)            [상세: 01_zybo_test.md]
├── 02_zybo_can/            ② 첫 CAN 실험 (블록디자인+Vitis 앱)           [02_zybo_can.md]
├── 03_arduino_due_cantest/③ Arduino Due CAN 레퍼런스 스케치 (FPGA 아님) [03_arduino_due_cantest.md]
├── 04_zybo_can_v2/         ④ ★검증된 PS CAN 브링업★ (EMIO, 1Mbps)        [04_zybo_can_v2.md]
├── 05_zybo_can_eth/        ⑤ ★현재 활성★ 이더넷 UDP→CAN HIL 브리지       [05_zybo_can_eth.md]
└── bin/                    📚 문서·계약서·CAN 레퍼런스 C 모음            [bin.md]
```
최상위 `.md`들(`01_zynq_ps_bringup.md`, `02_ctu_canfd_integration.md`, `CAN_디버깅_핸드오프.md`, `debug.md`)은 진행/디버깅 노트.

## 진화 줄거리
| 단계 | 무엇을 해결했나 |
|---|---|
| 01 → 02 | PS 부팅 → 첫 CAN 송수신 |
| 02 → **04** | CAN이 안 되던 근본원인(EMIO 비활성·클럭 분주) 해결 → **125k/500k/1Mbps 검증** |
| 04 → **05** | CAN 위에 **이더넷(lwIP UDP)** 얹어 PC가 원격으로 CAN을 쏘게 → **HIL 루프 완성** |

## 빌드/이식의 핵심 (꼭 기억)
- **하드웨어 정의 = XSA** (`05.../zybo_can_eth.xsa`). 이걸로 Vitis 플랫폼을 **새로 생성**한다.
- **빌드된 Vivado/Vitis 프로젝트 폴더는 절대경로가 박혀있어 복사하면 깨진다**(댕글링).
  → 복사 대신 **소스 + XSA로 재생성**. (`05_zybo_can_eth.md`의 빌드 절 참고.)

## 🗑️ 삭제 가능 (총 ~279M, 빌드하면 재생성)
각 단계 폴더 공통:
- Vivado: `*.runs/ *.gen/ *.cache/ *.hw/ *.ip_user_files/`
- Vitis: `*_vitis/.../export/`, `vitis_ws/.../{build,_ide}/`, `.Xil/`, `.rigel_lopper/`
- 기타: `hs_err_pid*.log`, `__pycache__/`

**유지:** `.c .h .xdc .tcl .py Makefile .md .xpr .xsa` + `bin/`, `03_arduino_due_cantest/` 전체.
폴더별 정확한 목록은 각 L2 문서 참고.
