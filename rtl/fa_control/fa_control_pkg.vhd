-- fa_control_pkg.vhd  --  Typen fuer das FA-Control-Interface (rtl/fa_control/)
-- bontango 08.2026
--
-- Kleines Paket, damit fa_control.vhd Ports mit Nibble-Feldern und einen
-- Generic mit den Display-Breiten haben kann. Bewusst schlank gehalten: wer das
-- Interface in ein anderes FPGA-Projekt (WillFA, GottFA, ...) uebernimmt, kopiert
-- den ganzen Ordner rtl/fa_control/ und traegt vier Zeilen in die Dateiliste ein.
--
-- VHDL-93, kein numeric_std hier -- das Paket wird auch von Top-Levels benutzt,
-- die mit std_logic_unsigned arbeiten (AtariFA-Konvention), und die beiden
-- Bibliotheken vertragen sich in einer Design-Unit nicht.

library ieee;
use ieee.std_logic_1164.all;

package fa_control_pkg is

	-- LISY kennt die Displays 0..6 (Opcodes 30..36 = LISY_S_DISP_0..6).
	-- Display 0 ist per Konvention das Status-/Credit-Display.
	constant FA_MAX_DISP : integer := 7;

	-- Ziffernfeld. Der Index in fa_control.disp_ovr ist  d * MAX_DIGITS + i,
	-- wobei i = 0 die ZUERST gesendete Ziffer ist. LISY sendet rechtsbuendig und
	-- hoechstwertig zuerst -- i = 0 ist also die LINKE Ziffer der Anzeige.
	-- Ob das Top-Level die Reihenfolge drehen muss, haengt an der Verdrahtung
	-- der Digit-Adresse (bei AtariFA: ja, siehe dortiger Kommentar am Mux).
	type fa_nibble_array_t is array (natural range <>) of std_logic_vector(3 downto 0);

	-- Display-Breiten (Stellen je Display). 0 = Display existiert nicht.
	type    fa_int_array_t   is array (natural range <>) of integer range 0 to 16;
	subtype fa_width_array_t is fa_int_array_t(0 to FA_MAX_DISP - 1);

end package fa_control_pkg;
