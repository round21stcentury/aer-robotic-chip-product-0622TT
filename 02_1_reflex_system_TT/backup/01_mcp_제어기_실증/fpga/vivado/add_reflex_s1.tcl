# add_reflex_s1.tcl — reflex_top_s1 을 PS7 베이스 BD 에 추가 + 결선 (스텝1)
#   전제: create_project_s1.tcl. 실행: vivado -mode batch -source add_reflex_s1.tcl
#   PS↔PL 인터페이스(★PS 개입 최소, GPIO 한 줄씩):
#     - cfg_gpio (출력 16b) : PS→PL. [7:0]=SPI_DIV(칩→MCP 속도), [8]=enable. 기본 0x0104.
#     - obs_gpio (입력 듀얼 32+32) : PL→PS. ch1=obs0{CANSTAT,CNF1,CNF2,CNF3} ch2=obs1{EFLG,TEC,REC,CANINTF}
#   MCP2515 SPI 핀(JE) 외부. DIP(SW0) 외부.
if {[catch {current_project}]} {
    set _d   [file dirname [file normalize [info script]]]
    set _xpr [glob -nocomplain "$_d/reflex_vivado/*.xpr"]
    if {![llength $_xpr]} { puts "❌ 프로젝트 없음 — create_project_s1.tcl 먼저"; exit 1 }
    open_project [lindex $_xpr 0]
}
open_bd_design [lindex [get_files *.bd] 0]

# 1) reflex_top_s1 + 클럭/리셋
create_bd_cell -type module -reference reflex_top_s1 reflex_top_0
connect_bd_net [get_bd_pins reflex_top_0/aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins reflex_top_0/aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]

# 2) DIP 외부 (XDC SW0=G15)
create_bd_port -dir I dip
connect_bd_net [get_bd_pins reflex_top_0/dip] [get_bd_ports dip]

# 3) MCP2515 SPI 외부핀 (XDC JE1~4,7)
create_bd_port -dir O mcp_sck
create_bd_port -dir O mcp_si
create_bd_port -dir I mcp_so
create_bd_port -dir O mcp_cs
create_bd_port -dir I mcp_int
connect_bd_net [get_bd_pins reflex_top_0/mcp_sck] [get_bd_ports mcp_sck]
connect_bd_net [get_bd_pins reflex_top_0/mcp_si]  [get_bd_ports mcp_si]
connect_bd_net [get_bd_pins reflex_top_0/mcp_so]  [get_bd_ports mcp_so]
connect_bd_net [get_bd_pins reflex_top_0/mcp_cs]  [get_bd_ports mcp_cs]
connect_bd_net [get_bd_pins reflex_top_0/mcp_int] [get_bd_ports mcp_int]

# 4) cfg_gpio (출력 axi_gpio) — PS→PL 설정. (04/05 검증: 출력 gpio 는 lopper 안전)
set_property CONFIG.NUM_MI {1} [get_bd_cells smartconnect_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio cfg_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {16} CONFIG.C_ALL_OUTPUTS {1} \
                        CONFIG.C_DOUT_DEFAULT {0x00000104} CONFIG.C_IS_DUAL {0}] [get_bd_cells cfg_gpio]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins cfg_gpio/S_AXI]
connect_bd_net [get_bd_pins cfg_gpio/s_axi_aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins cfg_gpio/s_axi_aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
connect_bd_net [get_bd_pins cfg_gpio/gpio_io_o]     [get_bd_pins reflex_top_0/cfg_in]

# 5) ★관측성 = PS7 EMIO GPIO (입력)★
#    PS 가 ★읽는★ 경로: axi_gpio(입력)·커스텀 슬레이브는 Vitis2025.2 lopper 가 깨짐
#    ('int' lstrip / unknown IP). EMIO GPIO 는 ps7 gpio0(0xE000A000, 모든 Zynq에 있음)을
#    쓰므로 새 amba_pl 노드가 안 생겨 lopper 안전. obs0/obs1(64비트)을 EMIO 입력으로.
set_property -dict [list CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_EMIO_GPIO_IO {64}] [get_bd_cells processing_system7_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat obs_concat
set_property CONFIG.NUM_PORTS {2} [get_bd_cells obs_concat]
connect_bd_net [get_bd_pins reflex_top_0/obs0] [get_bd_pins obs_concat/In0]   ;# EMIO[31:0]  = bank2
connect_bd_net [get_bd_pins reflex_top_0/obs1] [get_bd_pins obs_concat/In1]   ;# EMIO[63:32] = bank3
connect_bd_net [get_bd_pins obs_concat/dout]   [get_bd_pins processing_system7_0/GPIO_I]

# 6) 주소 고정(PS 코드와 일치): cfg=0x41200000
assign_bd_address
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    if {[string match *cfg_gpio* $seg]} { catch { set_property offset 0x41200000 $seg } }
}

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "✅ reflex_top_s1 결선 완료 (clk/rst, dip, MCP JE, cfg/obs GPIO)."
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    puts "  주소: $seg offset=[get_property offset $seg]"
}
close_project
