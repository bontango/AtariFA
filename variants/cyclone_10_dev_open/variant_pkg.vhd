-- variant_pkg.vhd - what this board is, as VHDL constants.
-- Variant: cyclone_10_dev_open (AtariFA PCB v1.0 carrying the 'dev_open' Cyclone 10 board)
--
-- This file lives in the variant folder, not in rtl/common/, and is the FIRST entry
-- in the generated .qsf. Everything else in the design is shared.
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- Leading digit of the version shown on the boot info display (Display1).
	-- Together with SW_SUB1/SW_SUB2 from rtl/common/version_pkg.vhd it reads
	-- BOARD_ID.SW_SUB1.SW_SUB2 - so a release changes exactly one digit, in
	-- version_pkg, and every board follows automatically.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"1";
end package variant_pkg;
