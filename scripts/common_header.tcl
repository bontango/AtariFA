# common_header.tcl - global assignments that are identical in every AtariFA
# variant. Merged into every generated AtariFA.qsf by scripts\gen_qsf.ps1.
#
# NOT here: FAMILY / DEVICE / LAST_QUARTUS_VERSION - those live in
# variants\<name>\device.tcl. TOP_LEVEL_ENTITY is written by gen_qsf.ps1 itself.
#
# NUM_PARALLEL_PROCESSORS is a property of the build machine, not of the board,
# so it belongs here. 14 is deliberate: Quartus only detects 14 processors on this
# machine (Windows reports 20 logical) and anything above that raises warning 20031
# (over subscription).
set_global_assignment -name ORIGINAL_QUARTUS_VERSION 22.1STD.2
set_global_assignment -name PROJECT_CREATION_TIME_DATE "17:57:02  FEBRUARY 09, 2025"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 1
set_global_assignment -name NUM_PARALLEL_PROCESSORS 14
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id Top
set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id Top
set_global_assignment -name PARTITION_COLOR 16764057 -section_id Top
set_global_assignment -name ENABLE_OCT_DONE OFF
set_global_assignment -name USE_CONFIGURATION_DEVICE OFF
set_global_assignment -name CRC_ERROR_OPEN_DRAIN OFF
set_global_assignment -name CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name OUTPUT_IO_TIMING_NEAR_END_VMEAS "HALF VCCIO" -rise
set_global_assignment -name OUTPUT_IO_TIMING_NEAR_END_VMEAS "HALF VCCIO" -fall
set_global_assignment -name OUTPUT_IO_TIMING_FAR_END_VMEAS "HALF SIGNAL SWING" -rise
set_global_assignment -name OUTPUT_IO_TIMING_FAR_END_VMEAS "HALF SIGNAL SWING" -fall
set_global_assignment -name RESERVE_FLASH_NCE_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name ENABLE_CONFIGURATION_PINS OFF
set_global_assignment -name ENABLE_BOOT_SEL_PIN OFF
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top
