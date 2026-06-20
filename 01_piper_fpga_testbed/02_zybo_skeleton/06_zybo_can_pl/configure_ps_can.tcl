# PS7 CAN0 설정 Tcl — Vivado Tcl Console 에서 붙여넣기 (GUI 대신, 선택)
# 블록디자인에 ZYNQ7 PS가 processing_system7_0 이름으로 있다고 가정.
#
# 사용법: 블록디자인 연 상태에서 Tcl Console 에 한 줄씩(또는 통째로) 붙여넣기.
#   ※ 속성 이름은 Vivado 버전에 따라 약간 다를 수 있음. 에러나면 GUI로 (README 1-2).
#   ※ 끝나고 반드시 GUI에서 CAN_0 인터페이스 Make External + Generate Bitstream.

set ps [get_bd_cells processing_system7_0]

set_property -dict [list \
  CONFIG.PCW_CAN0_PERIPHERAL_ENABLE   {1} \
  CONFIG.PCW_CAN0_CAN0_IO             {EMIO} \
  CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC   {IO PLL} \
  CONFIG.PCW_CAN0_PERIPHERAL_FREQMHZ  {100} \
] $ps

# 확인 출력
puts "CAN0 enable : [get_property CONFIG.PCW_CAN0_PERIPHERAL_ENABLE  $ps]"
puts "CAN0 IO     : [get_property CONFIG.PCW_CAN0_CAN0_IO            $ps]  (EMIO 여야 함)"
puts "CAN0 clksrc : [get_property CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC  $ps]  (IO PLL 여야 함)"
puts "CAN0 freq   : [get_property CONFIG.PCW_CAN0_PERIPHERAL_FREQMHZ $ps]  (100 목표)"

# 그 다음 (GUI 또는 Tcl):
#   make_bd_intf_pins_external [get_bd_intf_pins $ps/CAN_0]
#   → 외부 인터페이스 포트 CAN_0_0 (phy_tx 출력 + phy_rx 입력) 생성
# 그리고 wrapper 생성 → zybo_can.xdc 추가 → Generate Bitstream → Export XSA(+bitstream)
