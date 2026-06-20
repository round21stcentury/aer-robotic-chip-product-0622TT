# add_reflex_s4.tcl — reflex_top_s4(정상명령 패스스루 + 현재포즈 J5 움츠림 반사) BD 결선 (스텝4)
#   전제: create_project_s4.tcl. 실행: vivado -mode batch -source add_reflex_s4.tcl
#   PS↔PL (★스텝1 과 동일 패스스루 메일박스 + ★DIP 트리거):
#     cfg_gpio   (out16) @0x41200000 : [7:0]SPI_DIV [8]enable [9]소프트 반사트리거
#     cmd_lo/hi/id (out32×3) @0x41210000/220000/230000 : 정상명령 메일박스
#     dip (in)   : 물리 반사 트리거(SW0=G15). 칩 ui_in[0] 에 소프트트리거와 OR.
#     EMIO GPIO bank2/3 : MCP 되읽기 관측(obs0/obs1)
#   MCP2515 SPI 핀(JE) 외부.
if {[catch {current_project}]} {
    set _d   [file dirname [file normalize [info script]]]
    set _xpr [glob -nocomplain "$_d/reflex_vivado/*.xpr"]
    if {![llength $_xpr]} { puts "❌ 프로젝트 없음 — create_project_s4.tcl 먼저"; exit 1 }
    open_project [lindex $_xpr 0]
}
open_bd_design [lindex [get_files *.bd] 0]

# ★06_로봇실증용: PS7 FCLK_CLK0 50→20MHz (TT칩 20MHz 조건 재현). 이 BD 한정.
#   reset 블록명 rst_ps7_0_50M 은 외형만(클럭 무관 동작). 빌드 로그의 PCW_ACT_FPGA0...FREQMHZ 로 실제값 확인.
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {20}] [get_bd_cells processing_system7_0]

# 1) reflex_top_s4 + 클럭/리셋
create_bd_cell -type module -reference reflex_top_s4 reflex_top_0
connect_bd_net [get_bd_pins reflex_top_0/aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins reflex_top_0/aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]

# 2) DIP 외부 트리거 (XDC SW0=G15=estop, ★SW1=P15=덕포즈복귀)
create_bd_port -dir I dip
connect_bd_net [get_bd_pins reflex_top_0/dip] [get_bd_ports dip]
create_bd_port -dir I dip2
connect_bd_net [get_bd_pins reflex_top_0/dip2] [get_bd_ports dip2]

# 3) MCP2515 SPI 외부핀
foreach {p d} {mcp_sck O mcp_si O mcp_so I mcp_cs O mcp_int I} { create_bd_port -dir $d $p }
connect_bd_net [get_bd_pins reflex_top_0/mcp_sck] [get_bd_ports mcp_sck]
connect_bd_net [get_bd_pins reflex_top_0/mcp_si]  [get_bd_ports mcp_si]
connect_bd_net [get_bd_pins reflex_top_0/mcp_so]  [get_bd_ports mcp_so]
connect_bd_net [get_bd_pins reflex_top_0/mcp_cs]  [get_bd_ports mcp_cs]
connect_bd_net [get_bd_pins reflex_top_0/mcp_int] [get_bd_ports mcp_int]

# 4) 출력 GPIO 9개 (cfg + 메일박스 lo/hi/id + ★XADC thr/rule + 움찔 flinch + ★J5 움츠림 델타 d5 + ★반사속도 rspeed). 전부 단일채널 출력(lopper 안전).
set_property CONFIG.NUM_MI {13} [get_bd_cells smartconnect_0]
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
out_gpio thr_gpio    M04 16 0x00000C29 thr_in    ;# ★FSR 임계 기본 0x0C29≈0.76V (입력 0.55~1.0V 직결). PS가 재합성없이 튜닝
out_gpio rule_gpio   M05 16 0x00000000 rule_in   ;# ★FSR 규칙 기본 0=비활성 (부팅 거짓발동 방지 — chip reset도 rule2=0). PS가 FSR_RULE 로 설정. 0x79=estop/0x5A=덕포즈/0x5B=움츠림_덕포즈/0x5C=움츠림_현재
out_gpio flinch_gpio M06 32 0x00989680 flinch_in ;# ★움츠림(act3) 1회성 지속 틱 기본 10,000,000=0.2s@50MHz. PS가 FLINCH_MS 로 튜닝(클럭상대)
out_gpio d5_gpio     M07 16 0x00004325 d5_in     ;# ★J5 움츠림 델타 기본 0x4325=17189(0.30rad→0.001도). 칩 0x44 RECOIL_DELTA_J5. PS가 RECOIL_RAD 로 튜닝
out_gpio rspeed_gpio M08 16 0x00000064 rspeed_in ;# ★반사 0x151 속도율 기본 0x64=100(최대). PS가 REFLEX_SPEED 로 튜닝. 실로봇 move_spd_rate
out_gpio debounce_gpio M10 16 0x00009C40 debounce_in ;# ★FSR 디바운스 기본 0x9C40=40000=2ms@20MHz (노이즈 자가발동 방지). 칩 0x49. PS가 DEBOUNCE_MS 로 튜닝(클럭상대). M09는 lat_gpio
out_gpio hyst_gpio   M12 16 0x00000002 hyst_in   ;# ★슈미트 히스테리시스 시프트 기본 2=25%(해제임계=thr×0.75). 칩 0x4A + PL 레이턴시. PS가 HYST_SHIFT 로 튜닝(1=50%빡빡/3=12.5%). M11은 reflex_gpio

# 4c) ★06_로봇실증용: 반사지연 측정값 입력 GPIO (dual in: ch1=트리거→결정 cyc, ch2=트리거→RTS발사 cyc). PS가 읽어 ÷CLK_MHZ→µs.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio lat_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} \
                        CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] [get_bd_cells lat_gpio]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M09_AXI] [get_bd_intf_pins lat_gpio/S_AXI]
connect_bd_net [get_bd_pins lat_gpio/s_axi_aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins lat_gpio/s_axi_aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
connect_bd_net [get_bd_pins lat_gpio/gpio_io_i]  [get_bd_pins reflex_top_0/lat_decision]
connect_bd_net [get_bd_pins lat_gpio/gpio2_io_i] [get_bd_pins reflex_top_0/lat_issued]

# 4d) ★반사 활성상태 입력 GPIO (1비트 reflex_active) → PS가 읽어 PC로 /reflex_active 통지
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio reflex_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {0}] [get_bd_cells reflex_gpio]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M11_AXI] [get_bd_intf_pins reflex_gpio/S_AXI]
connect_bd_net [get_bd_pins reflex_gpio/s_axi_aclk]    [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins reflex_gpio/s_axi_aresetn] [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
connect_bd_net [get_bd_pins reflex_gpio/gpio_io_i]     [get_bd_pins reflex_top_0/reflex_active]

# 4b) ★실제 XADC: XADC Wizard(VAUX14 단극 연속 DRP) + xadc_reader(DRP 읽기) → reflex_top.xadc_val★
create_bd_cell -type ip -vlnv xilinx.com:ip:xadc_wiz xadc_wiz_0
set_property -dict [list \
  CONFIG.INTERFACE_SELECTION {ENABLE_DRP} \
  CONFIG.XADC_STARUP_SELECTION {single_channel} \
  CONFIG.SINGLE_CHANNEL_SELECTION {VAUXP14_VAUXN14} \
  CONFIG.CHANNEL_ENABLE_VAUXP14_VAUXN14 {true} \
  CONFIG.BIPOLAR_VAUXP14_VAUXN14 {false} \
  CONFIG.TIMING_MODE {Continuous} \
] [get_bd_cells xadc_wiz_0]
create_bd_cell -type module -reference xadc_reader xadc_rd_0
connect_bd_net [get_bd_pins xadc_rd_0/den]       [get_bd_pins xadc_wiz_0/den_in]
connect_bd_net [get_bd_pins xadc_rd_0/daddr]     [get_bd_pins xadc_wiz_0/daddr_in]
connect_bd_net [get_bd_pins xadc_rd_0/dwe]       [get_bd_pins xadc_wiz_0/dwe_in]
connect_bd_net [get_bd_pins xadc_rd_0/di]        [get_bd_pins xadc_wiz_0/di_in]
connect_bd_net [get_bd_pins xadc_wiz_0/do_out]   [get_bd_pins xadc_rd_0/do_in]
connect_bd_net [get_bd_pins xadc_wiz_0/drdy_out] [get_bd_pins xadc_rd_0/drdy]
connect_bd_net [get_bd_pins xadc_wiz_0/dclk_in]  [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins xadc_rd_0/clk]       [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net [get_bd_pins xadc_rd_0/rst_n]     [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
connect_bd_net [get_bd_pins xadc_rd_0/xadc_val]  [get_bd_pins reflex_top_0/xadc_val]
# reset_in = 0 (active-high → 0=동작)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xadc_rst0
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells xadc_rst0]
connect_bd_net [get_bd_pins xadc_rst0/dout] [get_bd_pins xadc_wiz_0/reset_in]
# 아날로그 입력 외부로 (JXADC AD14 = N15/N16, XDC에서 핀 매핑 → Vaux14_0_v_p/n)
make_bd_intf_pins_external [get_bd_intf_pins xadc_wiz_0/Vaux14]

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
    if {[string match *thr_gpio*    $seg]} { catch { set_property offset 0x41240000 $seg } }
    if {[string match *rule_gpio*   $seg]} { catch { set_property offset 0x41250000 $seg } }
    if {[string match *flinch_gpio* $seg]} { catch { set_property offset 0x41260000 $seg } }
    if {[string match *d5_gpio*     $seg]} { catch { set_property offset 0x41270000 $seg } }
    if {[string match *rspeed_gpio* $seg]} { catch { set_property offset 0x41280000 $seg } }
    if {[string match *lat_gpio*    $seg]} { catch { set_property offset 0x41290000 $seg } }
    if {[string match *debounce_gpio* $seg]} { catch { set_property offset 0x412A0000 $seg } }
    if {[string match *reflex_gpio*  $seg]} { catch { set_property offset 0x412B0000 $seg } }
    if {[string match *hyst_gpio*    $seg]} { catch { set_property offset 0x412C0000 $seg } }
}

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "✅ reflex_top_s4 결선 완료 (메일박스 cmd GPIO + dip + MCP JE + EMIO 관측 + ★XADC VAUX14 + thr/rule/flinch GPIO + ★J5 움츠림 델타 d5 GPIO + ★반사속도 rspeed GPIO)."
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    puts "  주소: $seg offset=[get_property offset $seg]"
}
close_project
