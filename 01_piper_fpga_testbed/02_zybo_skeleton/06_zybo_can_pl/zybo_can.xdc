# Zybo Z7-20 — PS CAN0 (EMIO) 핀 제약
# Pmod JE: 1번핀=V12, 2번핀=W16  (Digilent Zybo-Z7 마스터 XDC 기준)
#
# ⚠️ 포트 이름은 Make External 후 실제 생성된 이름과 일치해야 함.
#    인터페이스 통째로 external 하면 보통: CAN_0_0_phy_tx / CAN_0_0_phy_rx
#    개별 핀 external 하면: CAN0_PHY_TX_0 / CAN0_PHY_RX_0
#    → I/O Ports 탭에서 실제 이름 확인 후 아래 [get_ports ...] 를 맞춰 수정!

# --- 아래는 "인터페이스 통째 external" 가정 (권장) ---
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports CAN_0_0_phy_tx] ;# JE1 → 트랜시버 실제 TXD
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports CAN_0_0_phy_rx] ;# JE2 ← 트랜시버 실제 RXD

# --- 개별 핀 external 했으면 위 두 줄 대신 이거 ---
#set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports CAN0_PHY_TX_0]
#set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports CAN0_PHY_RX_0]
