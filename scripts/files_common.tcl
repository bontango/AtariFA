# Shared source files - part of every AtariFA variant.
# Paths are relative to the Quartus project directory, which is variants\<name>\.
# The packages come first so the analyser never has to guess the order.
#
# The same relative base applies to the init_file strings inside the ROM wrappers
# (game_rom.vhd, speech_rom.vhd, RAM.vhd, sound_rom.vhd) and to the generic maps in
# top/AtariFA.vhd - they all read ../../rom/. Moving a file between rtl/ and top/
# does NOT change that, moving the project directory does.
set_global_assignment -name VHDL_FILE variant_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/version_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/display_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/read_the_dips.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/switch_matrix.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/solenoid_driver.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/lamp_matrix.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/display_test.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/slow_to_fast_clock.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/cpu68.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/game_rom.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/display_control.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/sound.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/speech.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/speech_rom.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/watchdog.vhd
set_global_assignment -name VHDL_FILE ../../top/AtariFA.vhd
# Deliberately NOT listed: rtl/common/fram_i2c.vhd. The FRAM/NVRAM feature is on
# hold (see docs/FRAM_Persistence.md); the source is kept, the module is out of the
# build and the top level drives the pins to a safe idle. Adding this line back is
# one half of reactivating it, the other half is the top level feature itself.
set_global_assignment -name SDC_FILE AtariFA.sdc
