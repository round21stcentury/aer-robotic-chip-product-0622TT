# bin — 문서·계약서·CAN 레퍼런스 모음 (지식 베이스)

> 빌드 산출물이 아니라 **문서/스펙/참조 C코드 모음**. 전부 유지.

## 핵심: 팀원 핸드오프 계약서 (`bin/doc/`)
| 파일 | 역할 |
|---|---|
| `doc/00_핸드오프_README.md` | ★진입점★ — ROS/PC 팀에게 넘긴 Phase 1 HIL 핸드오프 가이드 |
| `doc/CAN-이더넷_브리지_계약서.md` | ★13바이트 UDP↔CAN 브리지 계약★ (PC↔FPGA 인터페이스) |
| `doc/CAN_프로토콜_계약서.md` | Piper CAN 프레임 인코딩(0x151/0x155~7/0x471 등) |

> 이 계약서가 02_zybo_skeleton/05(FPGA)와 03_hils/pc_bridge(PC)를 잇는 **인터페이스 정의**다.

## 진행/디버깅 노트
| 파일 | 내용 |
|---|---|
| `01_zynq_ps_bringup.md` | PS 부팅·셋업 |
| `02_ctu_canfd_integration.md` | CTU CAN-FD IP 통합 노트(Phase 2 참고) |
| `debug.md`, `CAN_디버깅_핸드오프.md` | 디버깅 절차/핸드오프 |
| `can_*.c` (여러 개) | CAN 송수신 레퍼런스/검증 C 스니펫 |

## 🗑️ 삭제 가능
없음 — 전부 유지(문서·스펙·참조 코드).
