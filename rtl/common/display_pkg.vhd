-- display_pkg.vhd - the display shadow buffer types.
--
-- Package name is still 'instruction_buffer_type' so every existing
-- 'use work.instruction_buffer_type.all' keeps working. It used to sit in the head
-- of AtariFA.vhd, which put it AFTER its users (display_control, display_test) in
-- the .qsf file list. That worked - Quartus elaborates in more than one pass - but
-- the convention in this tree is packages first, and only a file of its own can be
-- first. See scripts/files_common.tcl.
LIBRARY ieee;
USE ieee.std_logic_1164.all;

package instruction_buffer_type is
	type DISPLAY_T is array (0 to 6) of std_logic_vector(3 downto 0); -- digit #6 is Player up LEDS
	type DISPLAY_TS is array (0 to 3) of std_logic_vector(3 downto 0);
end package instruction_buffer_type;
