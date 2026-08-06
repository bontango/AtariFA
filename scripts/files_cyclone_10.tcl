# Megafunctions generated for the Cyclone 10 LP family. Selected through the
# RtlFamily key in variants\<name>\variant.psd1.
#
# A second family (a Cyclone IV test board, say) becomes rtl\cyclone_iv\ holding
# the same three entity names with the same port lists, plus a files_cyclone_iv.tcl
# next to this file. No VHDL construct is needed for that - the .qsf decides.
#
# The .qip themselves need no rewriting when the tree moves: they reference their
# own files through [file join $::quartus(qip_path) ...] and are location independent.
set_global_assignment -name QIP_FILE ../../rtl/cyclone_10/RAM.qip
set_global_assignment -name QIP_FILE ../../rtl/cyclone_10/cpu_clock.qip
set_global_assignment -name QIP_FILE ../../rtl/cyclone_10/sound_rom.qip
