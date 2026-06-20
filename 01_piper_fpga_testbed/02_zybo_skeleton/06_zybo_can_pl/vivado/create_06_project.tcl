# create_06_project.tcl — 06용 새 Vivado 프로젝트 생성 + 05 block design 재생성
#   전제: 같은 폴더에 05_design_ref.tcl 있어야 함 (export_05_bd.tcl 먼저 실행)
#
# 실행:  cd 06_zybo_can_pl/vivado
#        vivado -mode batch -source create_06_project.tcl
#   그 다음 GUI:  vivado zybo_can_pl_vivado/zybo_can_pl_vivado.xpr

set here      [file normalize [file dirname [info script]]]
set proj_name "zybo_can_pl_vivado"
set proj_dir  "$here/$proj_name"
set part      "xc7z020clg400-1"           ;# 보드파일 불필요 — 부품번호만 (Vivado 내장)

if {![file exists "$here/05_design_ref.tcl"]} {
    puts "❌ 05_design_ref.tcl 없음 → 먼저: vivado -mode batch -source export_05_bd.tcl"; exit 1
}
if {[file exists $proj_dir]} {
    puts "❌ 이미 존재: $proj_dir  (재실행하려면 이 폴더를 지우고)"; exit 1
}

# 1) 프로젝트 생성 (RTL, 부품 지정)
create_project $proj_name $proj_dir -part $part

# 2) 제약(XDC) 추가 — 06의 핀 제약 (CTU CAN 핀은 나중에 여기 추가)
add_files -fileset constrs_1 -norecurse "$here/../zybo_can.xdc"

# 3) 05 block design 재생성 (절대경로 없는 tcl)
source "$here/05_design_ref.tcl"
regenerate_bd_layout
save_bd_design

puts "✅ 06 프로젝트 생성 + 05 design 로드 완료"
puts "   → $proj_dir/$proj_name.xpr"
puts "   다음(GUI): vivado $proj_dir/$proj_name.xpr"
puts "      ① CTU CAN-FD IP 추가 + AXI 연결 + 트랜시버 핀 배선(zybo_can.xdc)"
puts "      ② .bd 우클릭 → Create HDL Wrapper (CTU 추가 끝난 뒤에)"
puts "      ③ Generate Bitstream → Export Hardware (Include bitstream) → vivado/zybo_can_pl.xsa"
close_project
