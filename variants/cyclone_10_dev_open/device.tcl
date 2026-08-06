# device.tcl - what is specific to THIS board, apart from the pin locations.
# Merged into AtariFA.qsf by scripts\gen_qsf.ps1. Hand maintained.
#
# Same FPGA as cyclone_10_pcb - only the piggy back board around it differs, which
# is why the whole difference between the two variants is pins.tcl plus BOARD_ID.
set_global_assignment -name FAMILY "Cyclone 10 LP"
set_global_assignment -name DEVICE 10CL006YE144C8G
set_global_assignment -name LAST_QUARTUS_VERSION "22.1std.2 Lite Edition"
