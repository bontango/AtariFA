-- switch_matrix.vhd  --  AtariFA Phase B: reale Atari-Gen1-Switch-Matrix
-- bontango 07.2026
--
-- Freilaufender Scan der 10x8 = 80 Matrix-Positionen (CPU-Adressen 0x2000-0x204F,
-- offset = addr - 0x2000, 0..79). Treibt die On-Board-Dekode-/Rueckkanal-Kette und
-- sampelt den EINEN gemeinsamen Return; Ergebnis = entprellte Zustands-Bits, die
-- AtariFA.vhd auf den CPU-Bus legt (sw_value @0x2010-0x204F, dip_value @0x2000-0x200F).
--
-- Signalkette (verifiziert aus Prototyp-Schaltplan AtariFA_07_Final_Switches_SCH.PDF):
--   FPGA sw_strobe/sw_com --> IC1a 74HCT540 (INVERTIEREND) --> E11a 74LS42 (Spalte, active-low
--   D-Enable je 74145) + 10x SN74LS145N (Zeile A/B/C) --> Schalter --> gemeinsam SW_Common
--   --> IC5a 74HC4049 (INVERTIEREND, 3,3V-Level-Shifter) --> sw_com_in.
--
-- 74LS42-Spalten-Map (reproduziert Original-Ā3-Swap, gleiche F-Bezeichner):
--   SW_Strobe 0->F3, 1->F5, 2->F7, 3->F6, 4->F8, 5->F9, 6->F10, 7->F11, 8->F12, 9->F13.
--   F5=0x2000-07, F3=0x2008-0F(Test@0x200B), F6=0x2010-17(Coin1/Coin2/Start/Slam), F7=0x2018-1F,
--   F9=0x2020-27, F8=0x2028-2F, F11=0x2030-37, F10=0x2038-3F, F13=0x2040-47, F12=0x2048-4F(Replay).
--
-- Abgeleitete Ansteuerung (offset = aktuelle Scan-Adresse - 0x2000):
--   sw_strobe(0)=offset(3)  sw_strobe(1)=not offset(4)  sw_strobe(2)=not offset(5)  sw_strobe(3)=not offset(6)
--   sw_com(0)  =offset(0)   sw_com(1)  =    offset(1)   sw_com(2)  =not offset(2)
--   sw_com_in='1'  =>  Schalter GESCHLOSSEN  (RET_ACTIVE, deckt PinMAME swg1_r "geschlossen=0xFF").
--   Aequivalent: SW_Strobe = {A6,A5,A4,not A3}, SW_COM = {A2,not A1,not A0}.
--
-- Rest-Annahme (First-Boot-Check, sonst schaltplan-sicher): Netz F_SW_Strobe_A..D / F_SW_COM_A..C
--   <-> Port-Index sw_strobe(0..3)/sw_com(0..2) (A=Bit0). Bei falscher Verdrahtung 1-zeilig tauschbar.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity switch_matrix is
	generic (
		-- clk_50-Takte, die eine Position stabil anliegt, bevor gesampelt wird. Deckt den
		-- TTL-Durchlauf (540/42/145/4049 ~60 ns) + 2-FF-Sync und streckt zugleich die Scan-
		-- Pass-Periode fuer die Entprellung. 640 -> ~1 ms/Pass (80*640*20ns), 2-Pass ~2 ms.
		DWELL_CYCLES : integer := 640
	);
	port (
		clk_50    : in  std_logic;
		reset     : in  std_logic;                       -- active-high: Zustand auf "offen"
		-- an On-Board-Dekode (durch invertierenden 74HCT540)
		sw_strobe : out std_logic_vector(3 downto 0);
		sw_com    : out std_logic_vector(2 downto 0);
		-- gemeinsamer Return (durch invertierenden 74HC4049): '1' = adressierter Schalter geschlossen
		sw_com_in : in  std_logic;
		-- entprellter Zustand, indiziert per CPU-offset (addr-0x2000); '1' = geschlossen
		sw_state  : out std_logic_vector(0 to 79)
	);
end switch_matrix;

architecture rtl of switch_matrix is
	signal idx     : std_logic_vector(6 downto 0) := (others => '0'); -- 0..79 = offset
	signal dwell   : integer range 0 to DWELL_CYCLES := 0;
	signal sync0   : std_logic := '0';                               -- 2-FF-Synchronizer (B4)
	signal sync1   : std_logic := '0';
	signal hist    : std_logic_vector(0 to 79) := (others => '0');   -- letzter Sample je Position
	signal state_i : std_logic_vector(0 to 79) := (others => '0');   -- committeter Zustand
begin

	-- Kombinatorische Ansteuerung aus dem aktuellen Scan-Index (idx aendert sich nur 1x pro DWELL)
	sw_strobe(0) <= idx(3);
	sw_strobe(1) <= not idx(4);
	sw_strobe(2) <= not idx(5);
	sw_strobe(3) <= not idx(6);
	sw_com(0)    <= idx(0);
	sw_com(1)    <= idx(1);
	sw_com(2)    <= not idx(2);

	sw_state <= state_i;

	scan : process(clk_50)
		variable i : integer range 0 to 79;
	begin
		if rising_edge(clk_50) then
			-- 2-FF-Einsynchronisierung des asynchronen Returns (behebt B4)
			sync0 <= sw_com_in;
			sync1 <= sync0;

			if reset = '1' then
				idx     <= (others => '0');
				dwell   <= 0;
				hist    <= (others => '0');
				state_i <= (others => '0');
			elsif dwell < DWELL_CYCLES - 1 then
				dwell <= dwell + 1;                       -- Position setzen lassen
			else
				-- am Ende der Verweilzeit sampeln + entprellen (2 aufeinanderfolgende gleiche Pässe)
				i := conv_integer(idx);
				if sync1 = hist(i) then
					state_i(i) <= sync1;                   -- 2 Pässe einig -> uebernehmen
				end if;
				hist(i) <= sync1;
				-- naechste Position
				dwell <= 0;
				if conv_integer(idx) = 79 then
					idx <= (others => '0');
				else
					idx <= idx + 1;
				end if;
			end if;
		end if;
	end process;

end rtl;
