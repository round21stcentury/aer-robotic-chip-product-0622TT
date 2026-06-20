# 02_zybo_can — 첫 CAN 실험 (v2 이전)

> 블록디자인 + Vitis 앱으로 **CAN을 처음 시도**한 단계. 이후 04_zybo_can_v2에서
> 근본원인(EMIO·클럭)을 잡아 제대로 동작. 이 폴더는 그 직전 시행착오 버전.

## 내용
| 파일 | 역할 |
|---|---|
| `app_component/src/main.c` | CAN 앱(초기) |
| `zybo_can_vivado/zybo_can_vivado.xpr` | Vivado 프로젝트 |
| `zybo_can_vivado/zybo_can_wrapper.xsa` | XSA export |

## 위치
검증 전 버전이라 **참조용**. 실제 검증·활성은 04(CAN)·05(이더넷).

## 🗑️ 삭제 가능 (~74M, 재생성)
`zybo_can_vivado/{*.runs,*.gen,*.cache,*.hw}`, `zybo_can_vitis/export/`,
`zybo_can_vitis/zynq_fsbl/build/`, `app_component/build/`, `_ide/`.
