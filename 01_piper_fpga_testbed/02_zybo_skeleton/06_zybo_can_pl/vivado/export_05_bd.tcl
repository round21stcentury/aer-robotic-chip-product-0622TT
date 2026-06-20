# export_05_bd.tcl — 05의 block design을 tcl로 뽑아 06의 출발점으로 쓴다.
#   (built Vivado 프로젝트를 복사하면 절대경로 댕글링 → 대신 bd를 tcl로 export해 재생성)
#
# 실행:  cd 06_zybo_can_pl/vivado
#        vivado -mode batch -source export_05_bd.tcl
#   결과: 06_zybo_can_pl/vivado/05_design_ref.tcl  (이걸 06 새 프로젝트에서 source 해 design 재생성)

set here [file normalize [file dirname [info script]]]
set xpr  [file normalize "$here/../../05_zybo_can_eth/zybo_can_v2_vivado/zybo_can_v2_vivado.xpr"]
set out  [file normalize "$here/05_design_ref.tcl"]

if {![file exists $xpr]} { puts "❌ 05 프로젝트 없음: $xpr"; exit 1 }

open_project $xpr
# 블록디자인 이름이 design_1 이 아니면 [get_bd_designs] 로 확인 후 수정
open_bd_design [get_files design_1.bd]
write_bd_tcl -force $out
close_project
puts "✅ 05 block design → $out"
puts "   다음: 06용 새 Vivado 프로젝트 만들고 'source 05_design_ref.tcl' 로 design 재생성 → CTU CAN-FD 추가"
