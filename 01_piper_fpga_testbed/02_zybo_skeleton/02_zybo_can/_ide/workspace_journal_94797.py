# 2026-06-10T20:53:06.448877032
import vitis

client = vitis.create_client()
client.set_workspace(path="02_zybo_can")

platform = client.get_component(name="zybo_can_vitis")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../zybo_can_vivado/zybo_can_wrapper.xsa")

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../zybo_can_vivado/zybo_can_wrapper.xsa")

status = platform.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../zybo_can_vivado/zybo_can_wrapper.xsa")

status = platform.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../zybo_can_vivado/zybo_can_wrapper.xsa")

status = platform.build()

comp.build()

vitis.dispose()

