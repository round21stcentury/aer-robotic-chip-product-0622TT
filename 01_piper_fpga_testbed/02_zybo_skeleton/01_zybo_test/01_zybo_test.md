# 01_zybo_test — PS 부팅 hello_world (최초 단계)

> Zybo Z7-20 **PS 시스템 첫 부팅**을 확인한 베어메탈 hello_world. CAN 이전의 가장 초기 골격.

## 내용
| 파일 | 역할 |
|---|---|
| `hello_world/src/helloworld.c` | UART로 찍는 최소 테스트 앱 |
| `hello_world/src/platform.h` | 플랫폼 설정 |
| `01_zybo_test.xpr` | Vivado 프로젝트 |
| `system_wrapper_pass_to_vitis.xsa` | Vitis용 XSA export |

## 위치
"보드가 살아있고 PS가 돈다"를 확인한 출발점. 이후 02~05로 발전. 보존만(활성 아님).

## 🗑️ 삭제 가능 (~34M, 재생성)
`01_zybo_test.{runs,gen,cache,hw,ip_user_files}`, `hello_world/build/`,
`zybo_test_vitis/export/`, `_ide/`, `.Xil/`.
