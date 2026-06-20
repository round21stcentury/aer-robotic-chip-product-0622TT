# 앱만 재빌드 (플랫폼은 이미 빌드됨). main.c 최신본 반영 후 app.build().
import vitis, os, shutil, glob, traceback
BASE = "/home/haeun/workspace/01_demo_260622/01_piper_fpga_testbed/02_zybo_skeleton/05_zybo_can_eth"
WS   = os.path.join(BASE, "vitis_ws")
SRC  = os.path.join(BASE, "src", "udp_can_main.c")
APP  = "udp_can_app"

def main():
    shutil.copy(SRC, os.path.join(WS, APP, "src", "main.c"))
    print(">> main.c 최신본 복사")
    client = vitis.create_client()
    client.set_workspace(path=WS)
    app = client.get_component(name=APP)
    print(">> app.build()")
    app.build()
    elf = glob.glob(os.path.join(WS, APP, "**", "*.elf"), recursive=True)
    print(">> ELF:", elf)
    print(">> ===== DONE =====" if elf else ">> ===== ELF 없음 =====")

try:
    main()
except Exception:
    print(">> !!! 실패 !!!"); traceback.print_exc()
finally:
    try: vitis.dispose()
    except Exception: pass
