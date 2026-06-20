# Vitis Unified 2025.2 자동 빌드 — 플랫폼 생성 + lwip220 + lwIP Echo Server 앱 + main.c 교체 + 빌드
# 실행: source /opt/Xilinx/2025.2/Vitis/settings64.sh && vitis -s build_hil_app.py
import vitis, os, shutil, glob, traceback

BASE = "/home/haeun/workspace/01_demo_260622/01_piper_fpga_testbed/02_zybo_skeleton/05_zybo_can_eth"
XSA  = os.path.join(BASE, "zybo_can_v2_vivado", "zybo_can_eth.xsa")
WS   = os.path.join(BASE, "vitis_ws")
SRC  = os.path.join(BASE, "src", "udp_can_main.c")
PLAT = "zybo_eth"
APP  = "udp_can_app"
DOM  = "standalone_ps7_cortexa9_0"

def main():
    assert os.path.exists(XSA), "XSA 없음: " + XSA
    assert os.path.exists(SRC), "소스 없음: " + SRC

    # 깨끗한 재실행을 위해 vitis_ws 초기화 (이 폴더만)
    if os.path.isdir(WS):
        print(">> 기존 vitis_ws 삭제(클린 재시작)")
        shutil.rmtree(WS)

    client = vitis.create_client()
    client.set_workspace(path=WS)

    print(">> [1/5] create_platform_component (XSA: %s)" % XSA)
    platform = client.create_platform_component(
        name=PLAT, hw_design=XSA, os="standalone", cpu="ps7_cortexa9_0")

    try:
        print(">> domains:", platform.list_domains())
    except Exception as e:
        print("   (list_domains 무시:", e, ")")

    print(">> [2/5] set_lib lwip220 + 템플릿 요구 BSP 파라미터 설정")
    domain = platform.get_domain(name=DOM)
    domain.set_lib(lib_name="lwip220")

    # lwip_echo_server 템플릿이 요구하는 파라미터 (불리언은 소문자 "true")
    cfgs = [
        ("lwip220", "lwip220_dhcp", "true"),
        ("lwip220", "lwip220_lwip_dhcp_does_acd_check", "true"),
        ("lwip220", "lwip220_pbuf_pool_size", 2048),
        ("xiltimer", "XILTIMER_en_interval_timer", "true"),
        # PHY 링크속도 100M 고정: PC 어댑터가 10/100이라 자동감지가 "link_speed invalid"로 깨짐.
        ("lwip220", "lwip220_temac_phy_link_speed", "CONFIG_LINKSPEED100"),
    ]
    for lib, param, val in cfgs:
        domain.set_config(option="lib", param=param, value=val, lib_name=lib)
        print("   set_config OK: %s.%s=%s" % (lib, param, val))

    print(">> [3/5] platform.build()  (BSP에 lwip220+파라미터 반영 — 수 분 소요)")
    platform.build()

    xpfm = glob.glob(os.path.join(WS, PLAT, "**", "*.xpfm"), recursive=True)
    print(">> xpfm:", xpfm)
    xpfm = xpfm[0]

    print(">> [4/5] create_app_component (template=lwip_echo_server)")
    app = client.create_app_component(
        name=APP, platform=xpfm, domain=DOM, template="lwip_echo_server")

    # main.c 교체
    app_src = os.path.join(WS, APP, "src")
    print(">> 앱 src 내용(교체 전):", sorted(os.listdir(app_src)))
    shutil.copy(SRC, os.path.join(app_src, "main.c"))
    print(">> main.c ← udp_can_main.c 교체 완료")

    print(">> [5/5] app.build()")
    app.build()

    elf = glob.glob(os.path.join(WS, APP, "**", "*.elf"), recursive=True)
    print(">> 빌드 산출물 ELF:", elf)
    print(">> ===== DONE =====" if elf else ">> ===== 빌드됐으나 ELF 못 찾음(경로확인) =====")

try:
    main()
except Exception:
    print(">> !!! 실패 !!!")
    traceback.print_exc()
finally:
    try:
        vitis.dispose()
    except Exception:
        pass
