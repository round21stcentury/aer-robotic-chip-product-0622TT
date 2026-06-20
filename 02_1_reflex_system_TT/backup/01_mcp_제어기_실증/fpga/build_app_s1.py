# build_app_s1.py — 스텝1 PS 앱 Vitis 빌드 (lwIP/CAN 없음, 관측 출력만)
#   실행: source /opt/Xilinx/2025.2/Vitis/settings64.sh && vitis -s build_app_s1.py
#   = XSA(reflex_s1.xsa) → standalone 플랫폼 + hello_world + main.c 교체 + (옵션)SPI_DIV 주입 + 빌드.
import vitis, os, shutil, glob, traceback

BASE = os.path.dirname(os.path.abspath(__file__))
_xsa = sorted(glob.glob(os.path.join(BASE, "**", "*.xsa"), recursive=True))
XSA  = next((x for x in _xsa if "reflex_s1" in os.path.basename(x)), (_xsa[0] if _xsa else ""))
# ★Vitis/lopper 는 경로에 한글(비ASCII)이 있으면 SDT 생성에서 깨짐('Invalid project location').
#   스텝 폴더명이 한글이라, Vitis 워크스페이스는 ★ASCII 경로★(02_1_reflex_system_TT/_vitis_ws/s1)에 둔다.
#   (Vivado 합성은 한글 경로 OK. XSA 입력은 그대로 읽힘 — 출력 워크스페이스만 ASCII 면 됨.)
ASCII_ROOT = os.path.dirname(os.path.dirname(BASE))   # .../02_1_reflex_system_TT (ASCII)
WS   = os.path.join(ASCII_ROOT, "_vitis_ws", "s1")
SRC  = os.path.join(BASE, "src", "reflex_s1_main.c")
PLAT = "zybo_s1"
APP  = "reflex_s1_app"
DOM  = "standalone_ps7_cortexa9_0"

def main():
    assert XSA and os.path.exists(XSA), "XSA 없음 (make xsa 먼저): " + str(XSA)
    assert os.path.exists(SRC), "소스 없음: " + SRC
    print(">> XSA:", XSA)

    if os.path.isdir(WS):
        print(">> 기존 vitis_ws 삭제(클린 재시작)")
        shutil.rmtree(WS)

    client = vitis.create_client()
    client.set_workspace(path=WS)

    print(">> [1/3] create_platform_component (standalone)")
    platform = client.create_platform_component(
        name=PLAT, hw_design=XSA, os="standalone", cpu="ps7_cortexa9_0")
    print(">> [2/3] platform.build()")
    platform.build()

    xpfm = glob.glob(os.path.join(WS, PLAT, "**", "*.xpfm"), recursive=True)[0]
    print(">> xpfm:", xpfm)

    print(">> create_app_component (template=hello_world)")
    app = client.create_app_component(
        name=APP, platform=xpfm, domain=DOM, template="hello_world")

    app_src = os.path.join(WS, APP, "src")
    dst = os.path.join(app_src, "helloworld.c")
    if not os.path.exists(dst):
        for c in glob.glob(os.path.join(app_src, "*.c")):
            if "int main" in open(c).read():
                dst = c; break
    shutil.copy(SRC, dst)
    # ★빌드시 SPI 속도 주입★ — Makefile 이 SPI_DIV(정수) env 로 넘기면 맨 위에 #define 주입
    _spd = os.environ.get("SPI_DIV")
    if _spd:
        with open(dst) as f: body = f.read()
        with open(dst, "w") as f: f.write("#define SPI_DIV_CODE %s\n" % _spd + body)
        print(">> SPI 속도 주입: #define SPI_DIV_CODE %s" % _spd)
    print(">> main 교체 완료:", dst)

    print(">> [3/3] app.build()")
    app.build()
    elf = glob.glob(os.path.join(WS, APP, "**", "*.elf"), recursive=True)
    print(">> ✅ ELF:", elf)

try:
    main()
except Exception:
    traceback.print_exc()
    raise
