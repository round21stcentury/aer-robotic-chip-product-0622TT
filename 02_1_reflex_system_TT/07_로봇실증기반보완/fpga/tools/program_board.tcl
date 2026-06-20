# Zybo Z7-20 보드 JTAG 프로그래밍 (Vitis GUI 없이). launch.json의 Run 설정과 동일.
#   인자: <bitstream.bit> <ps7_init.tcl> <app.elf>
# 흐름: connect → APU rst -system → fpga → A9#0 ps7_init/post → rst -processor → dow → con
set bit [lindex $argv 0]
set ps7 [lindex $argv 1]
set elf [lindex $argv 2]

puts "== connect =="
connect

puts "== reset system =="
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 2000

puts "== program FPGA: $bit =="
fpga -file $bit

puts "== ps7_init / ps7_post_config =="
targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}
source $ps7
ps7_init
ps7_post_config

puts "== download elf + run: $elf =="
targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}
rst -processor
dow $elf
con

puts "==== DONE: 보드 실행 중 (시리얼 115200 /dev/ttyUSB1 에서 부팅 메시지 확인) ===="
exit
