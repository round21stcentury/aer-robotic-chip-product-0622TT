# 2026-06-11T04:23:01.828499323
import vitis

client = vitis.create_client()
client.set_workspace(path="02_zybo_can")

platform = client.get_component(name="zybo_can_vitis")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

