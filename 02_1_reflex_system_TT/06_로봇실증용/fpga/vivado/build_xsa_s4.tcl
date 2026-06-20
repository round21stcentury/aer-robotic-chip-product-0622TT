# build_xsa_s4.tcl — 스텝4: bd 래퍼 → 합성/구현/비트 → XSA.
#   전제: create_project_s4 + add_reflex_s4.  실행: vivado -mode batch -source build_xsa_s4.tcl
set here [file normalize [file dirname [info script]]]
set xpr  [lindex [glob -nocomplain "$here/reflex_vivado/*.xpr"] 0]
if {![file exists $xpr]} { puts "❌ 프로젝트 없음"; exit 1 }
open_project $xpr
set bd  [lindex [get_files *.bd] 0]
open_bd_design $bd
set bdn [get_property NAME [current_bd_design]]
generate_target all [get_files $bd]
make_wrapper -files [get_files $bd] -top -import
set_property top ${bdn}_wrapper [current_fileset]
update_compile_order -fileset sources_1
# ★증분합성 끄기(옛 체크포인트 재사용 방지)
catch { set_property AUTO_INCREMENTAL_CHECKPOINT false [get_runs synth_1] }
# ★-jobs 2 (메모리 vivado-oom-build-jobs: 14GiB 램 OOM 방지, 무인 야간빌드 안전). Chrome 닫기.
catch { reset_run impl_1 }
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
set pr [get_property PROGRESS [get_runs impl_1]]
if {$pr != "100%"} { puts "❌ impl 미완료 progress=$pr"; exit 1 }
set xsa "$here/reflex_vivado/reflex_s4.xsa"
write_hw_platform -fixed -include_bit -force $xsa
puts "✅ XSA 완료: $xsa"
close_project
