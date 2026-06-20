# zybo_s4.xdc — 스텝4 핀 제약 (Zybo Z7-20)
#   칩(PL)이 MCP2515 를 SPI 로 직접 구동. Pmod JE 에 MCP2515 모듈(3.3V 트랜시버) 연결.
#   ★MCP2515 모듈 5핀: INT SCK SI SO CS (하드웨어 RST 없음 = 소프트웨어 리셋).
#   포트명은 BD 외부 포트명과 일치(reflex_top_s4: mcp_sck/mcp_si/mcp_so/mcp_cs/mcp_int, dip).
#   ★스텝4: estop=DIP(SW0), 현재포즈 J5 움츠림=소프트(0x7F0) 또는 ★FSR(XADC VAUX14, JXADC).

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

## ── DIP 비상정지(estop·freeze): 슬라이드 스위치 SW0 = G15 ──
set_property -dict { PACKAGE_PIN G15  IOSTANDARD LVCMOS33 } [get_ports dip]
## ── ★DIP 덕포즈복귀: 슬라이드 스위치 SW1 = P15 (Zybo Z7. 보드 다르면 SW1 핀 확인) ──
set_property -dict { PACKAGE_PIN P15  IOSTANDARD LVCMOS33 } [get_ports dip2]

## ── ★XADC 아날로그 입력: JXADC AD14 = VAUX14 (단극, N16=GND) ──
#   make_bd_intf_pins_external Vaux14 → 외부 포트 Vaux14_0_v_p / Vaux14_0_v_n
#   ★FSR/Due DAC → (필요시 1/3 분압) → JXADC JA1핀(N15). JA7핀(N16) → GND. 입력 0~1V, 절대 1V 초과 금지.
set_property -dict { PACKAGE_PIN N15  IOSTANDARD LVCMOS33 } [get_ports Vaux14_0_v_p] ;# JXADC AD14P
set_property -dict { PACKAGE_PIN N16  IOSTANDARD LVCMOS33 } [get_ports Vaux14_0_v_n] ;# JXADC AD14N(GND)
