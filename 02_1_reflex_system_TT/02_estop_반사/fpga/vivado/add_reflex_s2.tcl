# add_reflex_s2.tcl — reflex_top_s2(정상명령 패스스루 + e-stop 반사) BD 결선 (스텝2)
#   전제: create_project_s2.tcl. 실행: vivado -mode batch -source add_reflex_s2.tcl
#   PS↔PL (★스텝1 과 동일 패스스루 메일박스 + ★DIP 트리거):
#     cfg_gpio   (out16) @0x41200000 : [7:0]SPI_DIV [8]enable [9]소프트 반사트리거
#     cmd_lo/hi/id (out32×3) @0x41210000/220000/230000 : 정상명령 메일박스
#     dip (in)   : 물리 반사 트리거(SW0=G15). 칩 ui_in[0] 에 소프트트리거와 OR.
#     EMIO GPIO bank2/3 : MCP 되읽기 관측(obs0/obs1)
#   MCP2515 SPI 핀(JE) 외부.
if {[catch {current_project}]} {
    set _d   [file dirname [file normalize [info script]]]
    set _xpr [glob -nocomplain "$_d/reflex_vivado/*.xpr"]
    if {![llength $_xpr]} { puts "❌ 프로젝트 없음 — create_project_s2.tcl 먼저"; exit 1 }
    open_project [lindex $_xpr 0]
}
open_bd_design [lindex [get_files *.bd] 0]

# 1) reflex_top_s2 + 클럭/리셋
create_bd_cell -type module -reference reflex_top_s2 reflex_top_0
connect_bd_net [get_bd_pins reflex_top_0/aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins reflex_top_0/aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]

# 2) DIP 외부 트리거 (XDC SW0=G15)
create_bd_port -dir I dip
connect_bd_net [get_bd_pins reflex_top_0/dip] [get_bd_ports dip]

# 3) MCP2515 SPI 외부핀
foreach {p d} {mcp_sck O mcp_si O mcp_so I mcp_cs O mcp_int I} { create_bd_port -dir $d $p }
connect_bd_net [get_bd_pins reflex_top_0/mcp_sck] [get_bd_ports mcp_sck]
connect_bd_net [get_bd_pins reflex_top_0/mcp_si]  [get_bd_ports mcp_si]
connect_bd_net [get_bd_pins reflex_top_0/mcp_so]  [get_bd_ports mcp_so]
connect_bd_net [get_bd_pins reflex_top_0/mcp_cs]  [get_bd_ports mcp_cs]
connect_bd_net [get_bd_pins reflex_top_0/mcp_int] [get_bd_ports mcp_int]

# 4) 출력 GPIO 4개 (cfg + 메일박스 lo/hi/id). 전부 단일채널 출력(lopper 안전).
set_property CONFIG.NUM_MI {4} [get_bd_cells smartconnect_0]
proc out_gpio {name mi width dflt dst} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio $name
    set_property -dict [list CONFIG.C_GPIO_WIDTH $width CONFIG.C_ALL_OUTPUTS {1} \
                            CONFIG.C_DOUT_DEFAULT $dflt CONFIG.C_IS_DUAL {0}] [get_bd_cells $name]
    connect_bd_intf_net [get_bd_intf_pins smartconnect_0/${mi}_AXI] [get_bd_intf_pins $name/S_AXI]
    connect_bd_net [get_bd_pins $name/s_axi_aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
    connect_bd_net [get_bd_pins $name/s_axi_aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
    connect_bd_net [get_bd_pins $name/gpio_io_o]     [get_bd_pins reflex_top_0/$dst]
}
out_gpio cfg_gpio    M00 16 0x00000104 cfg_in
out_gpio cmd_lo_gpio M01 32 0x00000000 cmd_lo
out_gpio cmd_hi_gpio M02 32 0x00000000 cmd_hi
out_gpio cmd_id_gpio M03 32 0x00000000 cmd_id

# 5) ★관측 = PS7 EMIO GPIO 입력★ obs0/obs1(64비트) → ps7 gpio0 (lopper 안전)
set_property -dict [list CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_EMIO_GPIO_IO {64}] [get_bd_cells processing_system7_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat obs_concat
set_property CONFIG.NUM_PORTS {2} [get_bd_cells obs_concat]
connect_bd_net [get_bd_pins reflex_top_0/obs0] [get_bd_pins obs_concat/In0]
connect_bd_net [get_bd_pins reflex_top_0/obs1] [get_bd_pins obs_concat/In1]
connect_bd_net [get_bd_pins obs_concat/dout]   [get_bd_pins processing_system7_0/GPIO_I]

# 6) 주소 고정 (2패스: overlap 방지)
assign_bd_address
set _i 0
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    catch { set_property offset [format 0x%08x [expr {0x70000000 + $_i*0x10000}]] $seg }
    incr _i
}
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    if {[string match *cfg_gpio*    $seg]} { catch { set_property offset 0x41200000 $seg } }
    if {[string match *cmd_lo_gpio* $seg]} { catch { set_property offset 0x41210000 $seg } }
    if {[string match *cmd_hi_gpio* $seg]} { catch { set_property offset 0x41220000 $seg } }
    if {[string match *cmd_id_gpio* $seg]} { catch { set_property offset 0x41230000 $seg } }
}

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "✅ reflex_top_s2 결선 완료 (메일박스 cmd GPIO + dip + MCP JE + EMIO 관측)."
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    puts "  주소: $seg offset=[get_property offset $seg]"
}
close_project
