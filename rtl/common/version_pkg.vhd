-- version_pkg.vhd - the software version, shared by every AtariFA variant.
--
-- The version shown on the boot info display (Display1 during the ~5 s
-- version/config screen, boot_phase(2)) is
--
--     BOARD_ID . SW_SUB1 . SW_SUB2
--
-- with BOARD_ID coming from variants/<name>/variant_pkg.vhd. A release therefore
-- changes exactly ONE digit here and all boards follow - the older arrangement,
-- where SW_MAIN sat in each variant's own copy of the top level, is what let the
-- two variants drift to 0.1.2 and 1.1.2 with no single place to bump.
--
-- Not machine-readable by the game software. It IS readable over the ESP32 link:
-- rtl/fa_control answers LISY opcode 1 (G_LISY_VER) with "BOARD_ID.SW_SUB1.SW_SUB2"
-- built from these constants, so FA_Control shows the running version on connect.
library ieee;
use ieee.std_logic_1164.all;

package version_pkg is
	-- Beide Stellen werden auf dem CD4511 angezeigt und koennen daher nur 0..9 sein --
	-- nach 0.1.9 kommt 0.2.0, nicht 0.1.10.
	constant SW_SUB1 : std_logic_vector(3 downto 0) := x"3";
	constant SW_SUB2 : std_logic_vector(3 downto 0) := x"3";
end package version_pkg;
