# Megafunctions generated for the Cyclone IV E family. Selected through the
# RtlFamily key in variants\<name>\variant.psd1.
#
# Same three entity names with the same port lists as rtl\cyclone_10\ - the top
# level does not know which family it is compiled for, the .qsf decides. The two
# folders differ in nothing but the intended_device_family string; the altpll
# parameters (clk0_divide_by 50 out of a 50 MHz input -> 1 MHz cpu_clk) are
# family independent, pll_type and bandwidth_type are "AUTO".
#
# The .qip themselves need no rewriting when the tree moves: they reference their
# own files through [file join $::quartus(qip_path) ...] and are location independent.
set_global_assignment -name QIP_FILE ../../rtl/cyclone_IV/RAM.qip
set_global_assignment -name QIP_FILE ../../rtl/cyclone_IV/cpu_clock.qip
set_global_assignment -name QIP_FILE ../../rtl/cyclone_IV/sound_rom.qip
