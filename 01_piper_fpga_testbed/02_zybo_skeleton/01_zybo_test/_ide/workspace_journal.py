# 2026-06-09T15:55:10.528156623
import vitis

client = vitis.create_client()
client.set_workspace(path="01_zybo_test")

platform = client.create_platform_component(name = "zybo_test_vitis",hw_design = "$COMPONENT_LOCATION/../system_wrapper_pass_to_vitis.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

comp = client.create_app_component(name="app_component",platform = "$COMPONENT_LOCATION/../zybo_test_vitis/export/zybo_test_vitis/zybo_test_vitis.xpfm",domain = "standalone_ps7_cortexa9_0")

comp = client.create_app_component(name="hello_world",platform = "$COMPONENT_LOCATION/../zybo_test_vitis/export/zybo_test_vitis/zybo_test_vitis.xpfm",domain = "standalone_ps7_cortexa9_0",template = "hello_world")

platform = client.get_component(name="zybo_test_vitis")
status = platform.build()

comp = client.get_component(name="hello_world")
comp.build()

status = platform.build()

status = platform.build()

comp.build()

vitis.dispose()

