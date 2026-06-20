# zybo_s1.xdc — 스텝1 핀 제약 (Zybo Z7-20): MCP2515 SPI (Pmod JE)
#   포트명은 BD 외부 포트명과 일치(reflex_top_s1: mcp_sck/mcp_si/mcp_so/mcp_cs/mcp_int).
#   ★스텝1(패스스루) 은 DIP 불필요 — 반사 트리거(DIP/FSR)는 스텝2~4.
#   이더넷(정상명령)은 PS MIO 라 XDC 불필요.

## ── Pmod JE: MCP2515 SPI ──
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports mcp_sck]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports mcp_si]
set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports mcp_so]
set_property -dict { PACKAGE_PIN H15  IOSTANDARD LVCMOS33 } [get_ports mcp_cs]
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports mcp_int]
