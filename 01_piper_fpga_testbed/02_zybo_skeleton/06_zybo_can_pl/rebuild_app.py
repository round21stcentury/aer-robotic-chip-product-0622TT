# 앱만 재빌드 (플랫폼은 이미 빌드됨). main.c 최신본 반영 후 app.build().
import vitis, os, shutil, glob, traceback
BASE = os.path.dirname(os.path.abspath(__file__))   # ★이식 가능★ (=06 폴더)
WS   = os.path.join(BASE, "vitis_ws")
SRC  = os.path.join(BASE, "src", "udp_can_main.c")
APP  = "udp_can_pl_app"

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
