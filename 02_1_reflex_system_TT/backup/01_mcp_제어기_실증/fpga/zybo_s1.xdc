# zybo_s1.xdc — 스텝1 핀 제약 (Zybo Z7-20)
#   칩(PL)이 MCP2515 를 SPI 로 직접 구동. Pmod JE 에 MCP2515 모듈(3.3V 트랜시버) 연결.
#   ★MCP2515 모듈 5핀: INT SCK SI SO CS (하드웨어 RST 없음 = 소프트웨어 리셋).
#   포트명은 BD 외부 포트명과 일치(reflex_top_s1: mcp_sck/mcp_si/mcp_so/mcp_cs/mcp_int, dip).
#   ★스텝1 은 XADC 불필요 (트리거가 DIP). FSR/XADC 는 스텝3 에서 추가.

## ── Pmod JE: MCP2515 SPI ──
# JE1 = SCK  (칩 → 모듈)
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports mcp_sck]
# JE2 = SI   (칩 MOSI → 모듈 SI)
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports mcp_si]
# JE3 = SO   (모듈 SO → 칩 MISO)
set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports mcp_so]
# JE4 = CS   (칩 → 모듈)
set_property -dict { PACKAGE_PIN H15  IOSTANDARD LVCMOS33 } [get_ports mcp_cs]
# JE7 = INT  (모듈 → 칩)
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports mcp_int]

## ── DIP 비상정지: 슬라이드 스위치 SW0 = G15 ──
set_property -dict { PACKAGE_PIN G15  IOSTANDARD LVCMOS33 } [get_ports dip]
