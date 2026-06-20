# 03_arduino_due_cantest — Arduino Due CAN 레퍼런스 (FPGA 아님)

> CAN 버스를 **외부 노드(Arduino Due)**로 자극/검증하기 위한 스케치 모음.
> FPGA와 무관한 **참조용 손코드**. 용량 작음(~20K), 전부 유지.

## 내용
| 파일 | 역할 |
|---|---|
| `due_can_test.ino` | 단일 노드 CAN 송수신 테스트 |
| `due_can_2node.ino` | 2노드 CAN 주고받기 |
| `sketch_jun10b/sketch_jun10b.ino` | 스케치 변형 |

## 쓰임
보드 CAN을 디버깅할 때 "정상 노드"가 하나 필요하면 이 Due를 버스에 붙여 candump 대조용으로 사용.

## 🗑️ 삭제 가능
없음 — 전부 손코드 스케치(유지).
