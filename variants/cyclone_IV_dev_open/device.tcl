# device.tcl - what is specific to THIS board, apart from the pin locations.
# Merged into AtariFA.qsf by scripts\gen_qsf.ps1. Hand maintained.
#
# The first variant that really changes the chip family, and therefore the first one
# whose RtlFamily in variant.psd1 points somewhere else than cyclone_10: the same
# 'dev_open' piggy back board, but populated with a Cyclone IV E instead of a
# Cyclone 10 LP. Both are E144 with 6272 LE and 30 M9K, so the design fits unchanged;
# what does NOT carry over is PIN_22, see pins.tcl.
#
# EP4CE6E22C8 is the chip of N:\Projekte\FPGA Stern\FPGA_source\SternFA_HW2.0_Cyclone_dev_open,
# which builds and flashes on the same Quartus 22.1std.2 - that is where the device
# string, the pin availability and the .cof flash loader come from.
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE6E22C8
set_global_assignment -name LAST_QUARTUS_VERSION "22.1std.2 Lite Edition"
