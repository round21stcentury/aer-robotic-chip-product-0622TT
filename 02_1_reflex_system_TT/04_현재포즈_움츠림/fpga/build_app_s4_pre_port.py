# build_app_s4.py — 스텝2 PS 앱 (★lwIP 정상명령 패스스루 + 반사 소프트트리거) Vitis 빌드
#   스텝1 build_app_s1.py 와 동일 흐름: lwip220 플랫폼 + lwip_echo_server 템플릿 + main.c 교체.
#   ★Vitis 는 한글경로서 깨짐 → 워크스페이스는 ASCII (_vitis_ws/s2).
import vitis, os, shutil, glob, traceback

BASE = os.path.dirname(os.path.abspath(__file__))
_xsa = sorted(glob.glob(os.path.join(BASE, "**", "*.xsa"), recursive=True))
XSA  = next((x for x in _xsa if "reflex_s4" in os.path.basename(x)), (_xsa[0] if _xsa else ""))
ASCII_ROOT = os.path.dirname(os.path.dirname(BASE))      # .../02_1_reflex_system_TT (ASCII)
WS   = os.path.join(ASCII_ROOT, "_vitis_ws", "s4")
SRC  = os.path.join(BASE, "src", "reflex_s4_main.c")
PLAT = "zybo_s4"
APP  = "reflex_s4_app"
DOM  = "standalone_ps7_cortexa9_0"

def main():
    assert XSA and os.path.exists(XSA), "XSA 없음 (make xsa 먼저): " + str(XSA)
    assert os.path.exists(SRC), "소스 없음: " + SRC
    print(">> XSA:", XSA)
    if os.path.isdir(WS):
        print(">> 기존 vitis_ws 삭제"); shutil.rmtree(WS)

    client = vitis.create_client()
    client.set_workspace(path=WS)

    print(">> [1/5] create_platform_component")
    platform = client.create_platform_component(
        name=PLAT, hw_design=XSA, os="standalone", cpu="ps7_cortexa9_0")

    print(">> [2/5] set_lib lwip220 + BSP 파라미터 (05 검증값)")
    domain = platform.get_domain(name=DOM)
    domain.set_lib(lib_name="lwip220")
    cfgs = [
        ("lwip220", "lwip220_dhcp", "true"),
        ("lwip220", "lwip220_lwip_dhcp_does_acd_check", "true"),
        ("lwip220", "lwip220_pbuf_pool_size", 2048),
        ("xiltimer", "XILTIMER_en_interval_timer", "true"),
        ("lwip220", "lwip220_temac_phy_link_speed", "CONFIG_LINKSPEED100"),
    ]
    for lib, param, val in cfgs:
        domain.set_config(option="lib", param=param, value=val, lib_name=lib)

    print(">> [3/5] platform.build() (lwip220 BSP — 수 분)")
    platform.build()
    xpfm = glob.glob(os.path.join(WS, PLAT, "**", "*.xpfm"), recursive=True)[0]

    print(">> [4/5] create_app_component (template=lwip_echo_server)")
    app = client.create_app_component(name=APP, platform=xpfm, domain=DOM, template="lwip_echo_server")
    app_src = os.path.join(WS, APP, "src")
    dst = os.path.join(app_src, "main.c")
    if not os.path.exists(dst):
        for c in glob.glob(os.path.join(app_src, "*.c")):
            if "int main" in open(c).read(): dst = c; break
    shutil.copy(SRC, dst)
    inject = ""
    for env_name, macro in [("SPI_DIV","SPI_DIV_CODE"), ("PACE_US","PACE_US")]:
        v = os.environ.get(env_name)
        if v:
            inject += "#define %s %s\n" % (macro, v)
            print(">> 주입: #define %s %s" % (macro, v))
    if inject:
        with open(dst) as f: body = f.read()
        with open(dst, "w") as f: f.write(inject + body)
    print(">> main.c ← reflex_s4_main.c 교체")

    print(">> [5/5] app.build()")
    app.build()
    elf = glob.glob(os.path.join(WS, APP, "**", "*.elf"), recursive=True)
    print(">> ✅ ELF:", elf)

try:
    main()
except Exception:
    traceback.print_exc(); raise
finally:
    try: vitis.dispose()
    except Exception: pass
