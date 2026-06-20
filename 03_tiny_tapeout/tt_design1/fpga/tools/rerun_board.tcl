# 보드 재실행: 비트스트림(FPGA)·ps7_init 유지하고 ELF만 다시 내려받아 실행.
#   → 부팅 메시지를 다시 보거나, 코드만 바꿨을 때 program 보다 빠름 (비트스트림 스킵).
#   인자: <app.elf>
set elf [lindex $argv 0]

puts "== connect =="
connect
targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}

puts "== rst -processor + dow + con: $elf =="
rst -processor
dow $elf
con

puts "==== RERUN 완료 — 시리얼(115200)에서 부팅 메시지 다시 나옵니다 ===="
exit
