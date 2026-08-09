-- lamp_map_pkg.vhd  --  Zuordnung der 84 Lampen zur 21x4-Matrix
-- bontango 08.2026
--
-- GRP_OF sass frueher in der Architecture von lamp_matrix.vhd und war damit von
-- aussen unsichtbar. Seit die FA-Control-Schnittstelle (rtl/fa_control) Lampen
-- einzeln nach ihrer PHYSISCHEN Nummer schalten kann, braucht auch das Top-Level
-- die Zuordnung -- allerdings andersherum. Deshalb steht die Tabelle jetzt hier,
-- und die Umkehrung wird zur Elaborationszeit daraus BERECHNET.
--
-- >>> GRP_OF bleibt die eine Stelle, an der die Lampenzuordnung getunt wird. <<<
-- Es gibt bewusst keine zweite, von Hand gepflegte Tabelle, die auseinanderlaufen
-- koennte: FA_LAMP_BIT faellt automatisch mit.
--
-- Hintergrund (unveraendert aus lamp_matrix.vhd, Quellen: doc/Lamp_Logic.png Sheet
-- 18D, doc/Lamp_Logic2.png Sheet 18A, doc/AtariFA_Lamps.xlsx Mappe 'aktuell'):
--   * 84 Lampen = 21 "Gruppen" (74HC595-Ausgaenge, treiben die ULN2003A-Zeilen)
--     x 4 Strobes (Spalten SA/SB/SC/SD, +20 V, kommen vom Aux-Board).
--   * Die CPU schreibt die Lampen ins RAM 0x30-0x3F. Der Write-Sniffer im Top-Level
--     spiegelt das nach lamp_state(127:0), Bit-Index = offset*8 + b.
--   * offset einer (Latch L, Strobe s)-Zelle = L*4 + s   (9334-Adressierung)
--   * Gruppe N einer (Latch L, Bit b)-Zelle = GRP_OF(L*6 + b)
--   => lamp_state-Bit einer Lampe (Gruppe N, Strobe s) = (L*4 + s)*8 + b
--
-- Die frueher gueltige Formel N = 4*b + L + 1 (Excel-Mappe 'alt') trifft NICHT mehr
-- zu; die aktuelle Zuordnung ist eine Permutation ohne geschlossene Form.

library ieee;
use ieee.std_logic_1164.all;

package lamp_map_pkg is

	constant LAMP_GROUPS  : integer := 21;   -- genutzte 74HC595-Ausgaenge
	constant LAMP_STROBES : integer := 4;    -- SA/SB/SC/SD
	constant LAMP_COUNT   : integer := LAMP_GROUPS * LAMP_STROBES;   -- 84

	-- HW-TUNBAR: 595-Ausgang (Gruppe) N je (Latch L, Bit b).
	-- Index = L*6 + b (L: 0=0x1000, 1=0x1004, 2=0x1008, 3=0x100C).
	-- Wert 0 = Kombination unbenutzt. Alle Werte 1..21 kommen genau einmal vor.
	type grp_t is array(0 to 23) of integer range 0 to LAMP_GROUPS;
	constant GRP_OF : grp_t := (
		--  b=0  b=1  b=2  b=3  b=4  b=5
		      6,   3,  14,  17,  20,   9,   -- L=0 : 0x1000
		      7,   4,  15,  18,   1,   0,   -- L=1 : 0x1004
		      8,   5,  16,  10,  12,   0,   -- L=2 : 0x1008
		      2,  13,  19,  21,  11,   0);  -- L=3 : 0x100C

	-- HW-TUNBAR: Strobe-Index s (0..3) -> 2-Bit-Code an strobe_sel (Aux-Board dekodiert 1-of-4).
	-- Stand frueher in der Architecture von lamp_matrix.vhd; liegt aus demselben Grund wie GRP_OF
	-- jetzt hier: das Top-Level muss die Kodierung mitlesen koennen (Lampen-Trace DBG_MODE 4/5
	-- rekonstruiert aus strobe_sel, welche Strobe-Phase gerade sichtbar ist).
	type enc_t is array(0 to LAMP_STROBES - 1) of std_logic_vector(1 downto 0);
	constant STROBE_ENC : enc_t := ("00", "01", "10", "11");

	-- Umkehrung fuer die FA-Control-Schnittstelle.
	-- Lampennummer n (0..83) = (Gruppe-1) * 4 + Strobe, also Gruppe 1 Strobe 0 = 0,
	-- Gruppe 1 Strobe 3 = 3, Gruppe 2 Strobe 0 = 4, ... Gruppe 21 Strobe 3 = 83.
	-- FA_LAMP_BIT(n) liefert den zugehoerigen Bit-Index in lamp_state(127:0).
	type lamp_bit_t is array(0 to LAMP_COUNT - 1) of integer range 0 to 127;

	function build_lamp_bit return lamp_bit_t;
	constant FA_LAMP_BIT : lamp_bit_t := build_lamp_bit;

end package lamp_map_pkg;


package body lamp_map_pkg is

	-- Laeuft einmal beim Elaborieren ueber GRP_OF und dreht die Zuordnung um.
	-- Nicht in Logik uebersetzt -- das Ergebnis ist eine Konstante.
	function build_lamp_bit return lamp_bit_t is
		variable r : lamp_bit_t := (others => 0);
		variable n : integer;
	begin
		for L in 0 to 3 loop
			for b in 0 to 5 loop
				if GRP_OF(L * 6 + b) /= 0 then
					for s in 0 to LAMP_STROBES - 1 loop
						n     := (GRP_OF(L * 6 + b) - 1) * LAMP_STROBES + s;
						r(n)  := (L * 4 + s) * 8 + b;
					end loop;
				end if;
			end loop;
		end loop;
		return r;
	end function;

end package body lamp_map_pkg;
