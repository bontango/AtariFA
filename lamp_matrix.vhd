-- lamp_matrix.vhd  --  AtariFA Phase B: 84 Lampen, 21x4 Multiplex-Matrix
-- bontango 07.2026
--
-- Ersetzt den alten lamp_driver.vhd (statische TPIC6B595-Kette, altes Testplatinen-Konzept).
-- Bildet die reale AtariFA-Prototyp-HW nach (doc/Lamp_Logic.png Sheet 18D +
-- doc/Lamp_Logic2.png Sheet 18A + doc/Auxiliary_PCB.png Sheet 10A + doc/AtariFA_Lamps.xlsx):
--   * 12x ULN2003A (A20,B20,A19,B19,A18,B18,A17,B17,A16,B16,A15,B15) = Zeilen/Sink.
--     Deren Eingaenge treibt eine Kaskade aus DREI 74HC595 (24 Bit, 21 genutzt) = 21 "Gruppen".
--   * 4 Strobes SA/SB/SC/SD (Spalten, +20V Lampen-PWR): auf dem Aux-Board aus 2 Bit
--     (LAMP BIT0/1) via 7402-NOR + MC14xx 1-of-4-dekodiert -> hier strobe_sel(1:0).
--   * 84 Lampen = 21 Gruppen x 4 Strobes, zeitmultiplex gescannt (wie das Original).
--
-- Datenquelle: lamp_state(127:0) = RAM 0x30-0x3F Write-Sniffer-Shadow (in AtariFA.vhd,
--   analog Display-Shadow-Buffer). Bit-Index = offset*8 + b
--   (offset 0..15 = RAM 0x30..0x3F, b = Latch-Bit 0..7).
--
-- ============================ MAPPING (HW-abgeleitet) ============================
-- Aus dem 9334-Decode (Sheet 18A): die 8 Byte-Latches (1000/04/08/0C = Lampen, 1080/84/88/8C
-- = Sound/Sol) werden per Adressbits A2,A3,A7 gewaehlt; Latch-Bit b <- Datenbit Db.
-- Aus AtariFA_Lamps.xlsx, Mappe 'aktuell' (byte-genau geparst, Stand 2026-08-05):
--   595-Ausgang (Gruppe) N (1..21) je (Latch L, Bit b) -> Tabelle GRP_OF (unten).
--   Die frueher gueltige Formel N = 4*b + L + 1 (= Mappe 'alt') trifft NICHT mehr zu; die
--   neue Zuordnung ist eine Permutation ohne geschlossene Form. Belegt sind Bits 0..4 aller
--   4 Latches + Bit 5 nur bei Latch 1000 = 21 Gruppen (unveraendert gegenueber 'alt').
-- RAM-Offset-Zerlegung (9334-Adressierung beim DMA-Read von 0x30-0x3F; A7=0=Lampen,
--   A4/A5 fest -> Latch=offset[3:2], Strobe=offset[1:0]):
--   RAM-Offset einer (Latch L, Strobe s)-Zelle = L*4 + s
--   => ser_bit(Gruppe N, Strobe s) = lamp_state[(L*4 + s)*8 + b]   mit N = GRP_OF(L*6 + b)
--
-- Scan-FSM (clk_50): je Strobe-Phase s: (a) oe_n=1 blanken -> (b) 24 Bit schieben (21 genutzt,
--   3 = '0') -> (c) rck-Latch -> (d) strobe_sel<=enc(s) -> (e) oe_n=0 (Phase sichtbar) -> (f) Dwell.
--   Blanken waehrend Schieben/Umschalten verhindert Ghosting. Native ~25% Duty (4-fach-Multiplex).
--
-- Sicherheit: reset='1' ODER enable='0' -> oe_n='1' (alle Lampen AUS), strobe_sel="00".
--   (In AtariFA.vhd: enable=reset_l_stable -> Lampen erst mit laufender CPU; Boot/Reset sicher AUS.)
--
-- HW-TUNBAR (bei falscher Lampe/Strobe am Prototyp NUR die markierten Stellen aendern):
--   * GRP_OF     : (Latch L, Bit b) -> 595-Ausgang N; direkte Abschrift der Excel-Mappe 'aktuell'.
--   * STROBE_ENC : Strobe-Index s (0..3) -> 2-Bit-Code (Aux-Decoder-Permutation; die
--                  74HCT540-Invertierung von aux_lamp_strobe passiert im Top).
--   * Latch=offset[3:2]/Strobe=offset[1:0] : Annahme aus 9334-Adressierung (unten im idx).
--   * Shift-Reihenfolge (vec(23) zuerst = MSB) bzw. welcher 74HC595 zuerst in der Kaskade.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity lamp_matrix is
	generic (
		DWELL_CYCLES : integer := 12500;  -- clk_50-Zyklen je Strobe-Phase (~250us) -> ~1kHz Frame
		SHIFT_DIV    : integer := 10      -- clk_50 je SRCK-Halbperiode (SHIFT_DIV=10 -> ~2.5MHz Bit-Takt)
	);
	port (
		clk_50     : in  std_logic;
		reset      : in  std_logic;                       -- active-high: alle Lampen AUS
		enable     : in  std_logic;                       -- '1' = Scan aktiv (CPU laeuft)
		lamp_state : in  std_logic_vector(127 downto 0);  -- RAM 0x30-0x3F Shadow (16 Byte)
		ser        : out std_logic;                       -- 74HC595 SER   (-> g_serin_595)
		srck       : out std_logic;                       -- 74HC595 SRCLK (-> g_clk_595)
		rck        : out std_logic;                       -- 74HC595 RCLK  (-> g_rclk_595)
		oe_n       : out std_logic;                       -- 74HC595 /OE   (-> oe_595), active-low
		strobe_sel : out std_logic_vector(1 downto 0)     -- Strobe-Select (-> aux_lamp_strobe, Top invertiert)
	);
end lamp_matrix;

architecture rtl of lamp_matrix is
	type state_t is (St_Load, St_ShiftLo, St_ShiftHi, St_Latch, St_Enable, St_Dwell);
	signal state     : state_t := St_Load;
	signal shiftreg  : std_logic_vector(23 downto 0) := (others => '0');
	signal bit_cnt   : integer range 0 to 23 := 0;
	signal phase     : integer range 0 to 3 := 0;
	signal dwell_cnt : integer range 0 to DWELL_CYCLES := 0;
	signal div_cnt   : integer range 0 to SHIFT_DIV := 0;
	signal tick      : std_logic := '0';

	-- HW-TUNBAR: 595-Ausgang (Gruppe) N je (Latch L, Bit b) -- aus doc/AtariFA_Lamps.xlsx,
	-- Mappe 'aktuell'. Index = L*6 + b (L: 0=0x1000, 1=0x1004, 2=0x1008, 3=0x100C);
	-- Wert 0 = Kombination unbenutzt. Alle Werte 1..21 kommen genau einmal vor.
	type grp_t is array(0 to 23) of integer range 0 to 21;
	constant GRP_OF : grp_t := (
		--  b=0  b=1  b=2  b=3  b=4  b=5
		      6,   3,  14,  17,  20,   9,   -- L=0 : 0x1000
		      7,   4,  15,  18,   1,   0,   -- L=1 : 0x1004
		      8,   5,  16,  10,  12,   0,   -- L=2 : 0x1008
		      2,  13,  19,  21,  11,   0);  -- L=3 : 0x100C

	-- HW-TUNBAR: Strobe-Index s (0..3) -> 2-Bit-Code an strobe_sel (Aux-Board dekodiert 1-of-4).
	type enc_t is array(0 to 3) of std_logic_vector(1 downto 0);
	constant STROBE_ENC : enc_t := ("00", "01", "10", "11");
begin

	-- Shift-Takt-Tick: ein Puls alle SHIFT_DIV clk_50-Zyklen (paced die SRCK-Flanken)
	process(clk_50)
	begin
		if rising_edge(clk_50) then
			if div_cnt = SHIFT_DIV - 1 then
				div_cnt <= 0;
				tick    <= '1';
			else
				div_cnt <= div_cnt + 1;
				tick    <= '0';
			end if;
		end if;
	end process;

	-- Scan-FSM
	process(clk_50)
		variable vec : std_logic_vector(23 downto 0);
		variable N, idx : integer;
	begin
		if rising_edge(clk_50) then
			if reset = '1' or enable = '0' then
				state      <= St_Load;
				oe_n       <= '1';            -- Ausgaenge disabled -> alle Lampen AUS (sicher)
				srck       <= '0';
				rck        <= '0';
				ser        <= '0';
				strobe_sel <= "00";
				phase      <= 0;
				bit_cnt    <= 0;
				dwell_cnt  <= 0;
			else
				case state is

					when St_Load =>
						-- 24-Bit-Vektor fuer aktuelle Phase bauen (vec(N-1) = 595-Ausgang N, 1..24)
						vec := (others => '0');
						for L in 0 to 3 loop                     -- Latch-Index 0=1000..3=100C
							for b in 0 to 5 loop                 -- Latch-Bit
								N := GRP_OF(L * 6 + b);          -- 595-Ausgang (0 = unbenutzt)
								if N /= 0 then
									idx := (L * 4 + phase) * 8 + b;  -- RAM-Bit: offset = L*4 + s (HW-TUNBAR)
									vec(N - 1) := lamp_state(idx);
								end if;
							end loop;
						end loop;
						shiftreg <= vec;
						bit_cnt  <= 0;
						oe_n     <= '1';                    -- blanken waehrend Schieben/Umschalten
						rck      <= '0';
						srck     <= '0';
						state    <= St_ShiftLo;

					when St_ShiftLo =>
						if tick = '1' then
							ser   <= shiftreg(23);          -- MSB zuerst; Daten waehrend SRCK low anlegen
							srck  <= '0';
							state <= St_ShiftHi;
						end if;

					when St_ShiftHi =>
						if tick = '1' then
							srck     <= '1';                            -- steigende Flanke taktet das Bit ein
							shiftreg <= shiftreg(22 downto 0) & '0';
							if bit_cnt = 23 then
								state <= St_Latch;
							else
								bit_cnt <= bit_cnt + 1;
								state   <= St_ShiftLo;
							end if;
						end if;

					when St_Latch =>
						srck       <= '0';
						rck        <= '1';                  -- Shift- -> Storage-Register uebernehmen
						strobe_sel <= STROBE_ENC(phase);    -- Strobe dieser Phase waehlen
						if tick = '1' then                  -- rck ~1 Tick breit halten (sichere Pulsbreite)
							state <= St_Enable;
						end if;

					when St_Enable =>
						rck       <= '0';
						oe_n      <= '0';                   -- Ausgaenge frei -> Phase sichtbar
						dwell_cnt <= 0;
						state     <= St_Dwell;

					when St_Dwell =>
						if dwell_cnt = DWELL_CYCLES - 1 then
							oe_n <= '1';                    -- blanken vor Phasenwechsel (Anti-Ghost)
							if phase = 3 then
								phase <= 0;
							else
								phase <= phase + 1;
							end if;
							state <= St_Load;
						else
							dwell_cnt <= dwell_cnt + 1;
						end if;

				end case;
			end if;
		end if;
	end process;

end rtl;
