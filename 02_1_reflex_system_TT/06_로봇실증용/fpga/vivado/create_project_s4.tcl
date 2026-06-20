# create_project_s4.tcl — 스텝4 Vivado 프로젝트 생성 (PS7 베이스 + 스텝4 RTL)
#   실행: cd fpga/vivado && vivado -mode batch -source create_project_s4.tcl
#   ★CTU/CAN IP 불필요 (칩이 MCP2515 로 CAN 직접). ★XADC 는 스텝4에 필요 (현재포즈 움츠림 = FSR 트리거).
set here     [file normalize [file dirname [info script]]]
set proj     "reflex_vivado"
set proj_dir "$here/$proj"
set part     "xc7z020clg400-1"

if {[file exists $proj_dir]} { puts "❌ 이미 존재: $proj_dir (지우고 재실행)"; exit 1 }
create_project $proj $proj_dir -part $part

# 스텝4 RTL: chip/rtl(칩) + pl/rtl(reflex_top_s4/chip_feeder_s4/spi_master)
set rtl [concat [glob -nocomplain "$here/../../chip/rtl/*.v"] [glob -nocomplain "$here/../../pl/rtl/*.v"]]
if {[llength $rtl]} { add_files -norecurse $rtl; puts "RTL 추가: [llength $rtl] 파일" }

# 핀 제약 (JE=MCP, SW0=DIP, JXADC=VAUX14)
add_files -fileset constrs_1 -norecurse "$here/../zybo_s4.xdc"

# PS7 전용 베이스 BD (공용 보일러플레이트)
source "$here/../../../common/base_design.tcl"
regenerate_bd_layout
save_bd_design
puts "✅ 프로젝트 생성: $proj_dir/$proj.xpr (PS7 베이스 + 스텝4 RTL)"
puts "   다음: add_reflex_s4.tcl"
close_project
