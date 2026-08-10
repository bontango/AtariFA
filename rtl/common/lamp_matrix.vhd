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
-- ============================== SCAN-FSM (clk_50) ==============================
-- Je Strobe-Phase laufen ZWEI Schiebedurchlaeufe durch die 595-Kaskade (Register 'pass'):
--   pass=0 "Clear":  24 Nullen schieben -> rck  => alle Zeilen AKTIV auf '0' (Blank beginnt)
--   pass=1 "Daten":  Muster der Phase schieben -> rck  => Zeilen der Phase gehen an
-- Dazwischen wird die Spalte umgeschaltet, und GENAU DAS ist der Unterschied der beiden Modi:
--   orig_timing='0' (Serienstand): strobe_sel wechselt beim CLEAR-Latch, also waehrend die
--     Zeilen aus sind. Bis die Zeilen wieder angehen liegen St_Settle + Datendurchlauf = ~20 us
--     -- Zeit, in der die alte Spalte auf dem Aux-Board abklingen kann.
--   orig_timing='1' (Options-DIP 5 ON): strobe_sel wechselt beim DATEN-Latch, also im selben
--     Moment, in dem die Zeilen scharf werden -- das Zeitverhalten der Original-MPU.
-- Warum das eine Rolle spielt (gemessen 2026-08-10 am Airborne-Spielfeld mit LED-Retrofits,
-- s. docs/Lamp_Preglow_Experiment.md): die Spalten-PNP auf dem Aux-Board (2N5883, hart in
-- Saettigung, Abschalten nur ueber 8,2 K Basis-Emitter) haengen zweistellige us nach. Wechseln
-- Spalte und Zeilen gleichzeitig, sieht die noch leitende ALTE Spalte bereits das NEUE
-- Zeilenmuster -> die Lampe "gleiche Zeile, vorhergehende Spalte" bekommt einen Stromstoss.
-- Fuer einen Gluehfaden nichts, fuer eine LED deutlich sichtbar. Das ist das im Atari
-- Troubleshooting Guide als "keep-alive routine" beschriebene Vorgluehen.
--
-- Blanken durch NULLEN-LATCHEN statt oe_n=Hi-Z: im Original haengen die ULN-Eingaenge an
-- 9334-Latches, die permanent treiben -- eine Aus-Zeile ist dort 100 % der Zeit eine harte '0'.
-- Unser frueheres oe_n-Blankfenster liess die 595-Ausgaenge und damit die ULN-Eingaenge floaten;
-- die uA Leckstrom genuegen einer LED-Retrofit zum Glimmen (am Spielfeld beobachtet: 4 von 8
-- LEDs glimmten OHNE jede Ansteuerung). oe_n ist deshalb nur noch der Reset-/Boot-Blank -- da
-- ist der Inhalt der 595 unbekannt, Hi-Z also der einzige sichere Zustand -- und geht mit dem
-- ersten Nullen-Latch dauerhaft auf '0'. Kostet keine Helligkeit: die Nullen werden geschoben,
-- WAEHREND die Lampe noch leuchtet; die Ausgaenge aendern sich erst mit rck.
--
-- St_ShiftLast haelt den LETZTEN Schiebetakt eine volle Tick-Haelfte high -- s. Kommentar dort.
--
-- Sicherheit: reset='1' ODER enable='0' -> oe_n='1' (alle Lampen AUS), strobe_sel="00".
--   (In AtariFA.vhd: enable=io_live -> Lampen erst mit laufender CPU oder FA-Control-Uebernahme;
--    Boot/Reset sicher AUS. Nach dem Loslassen ist der erste Durchlauf der Clear-Durchlauf, oe_n
--    geht also erst frei, wenn nachweislich Nullen in den Ausgangslatches stehen.)
--
-- HW-TUNBAR (bei falscher Lampe/Strobe am Prototyp NUR die markierten Stellen aendern):
--   * GRP_OF     : (Latch L, Bit b) -> 595-Ausgang N; direkte Abschrift der Excel-Mappe 'aktuell'.
--                  Steht seit 08.2026 in rtl/common/lamp_map_pkg.vhd, weil auch das Top-Level
--                  die Zuordnung braucht (FA-Control schaltet Lampen einzeln, s. rtl/fa_control).
--                  Die dortige Umkehrtabelle FA_LAMP_BIT wird daraus berechnet und faellt
--                  automatisch mit -- GRP_OF bleibt die EINE Stelle zum Tunen.
--   * STROBE_ENC : Strobe-Index s (0..3) -> 2-Bit-Code (Aux-Decoder-Permutation; die
--                  74HCT540-Invertierung von aux_lamp_strobe passiert im Top). Steht seit
--                  08.2026 ebenfalls in rtl/common/lamp_map_pkg.vhd, weil der Lampen-Trace
--                  im Top (DBG_MODE 4/5) dieselbe Kodierung braucht.
--   * Latch=offset[3:2]/Strobe=offset[1:0] : Annahme aus 9334-Adressierung (unten im idx).
--   * Shift-Reihenfolge (vec(23) zuerst = MSB) bzw. welcher 74HC595 zuerst in der Kaskade.
--   * SETTLE_CYCLES : Totzeit zwischen Spaltenwechsel und Zeilen-Scharfwerden. Reicht das
--                  Vorgluehen-Fenster nicht (LED glimmt trotz DIP 5 = OFF weiter), ist DAS der
--                  Hebel -- s. Generic-Block unten.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.lamp_map_pkg.all;        -- GRP_OF, STROBE_ENC (HW-TUNBAR)

entity lamp_matrix is
	generic (
		-- Ruhezeit je Strobe-Phase. Zusammen mit den ZWEI Schiebedurchlaeufen und der
		-- Spalten-Totzeit ergibt das die Phasendauer und damit den Lampen-Frame:
		--   Ein Schiebedurchlauf (FSM, bei SHIFT_DIV=10):
		--     St_Load 1 + 24 x (ShiftLo+ShiftHi) 480 + ShiftLast 10 + Latch 10
		--     = 501 clk = 10 us  (am LA gemessen: 10,000 us seit St_ShiftLast,
		--      docs/Lamp_Refresh_Analysis.md 6.7.1)
		--   Phase = Dwell + Clear-Durchlauf 501 + Settle + Daten-Durchlauf 501 + Enable 1
		--   Serienstand   : 24100 + 501 + 497 + 501 + 1 = 25600 clk x 20 ns = 512,0 us
		--   DIP 5 = ON    : 24597 + 501 +   0 + 501 + 1 = 25600 clk        = 512,0 us
		--     (im Original-Modus ist St_Settle uebersprungen, die Zeit schlaegt statt dessen
		--      auf den Dwell auf -- die Phasendauer ist in beiden Modi GLEICH, sonst
		--      vergleicht man am Spielfeld zwei Variablen statt einer)
		--   Phase = EIN Digit-Slot wie im Original, Frame = 4 Phasen = 2,048 ms = 488,3 Hz
		--   Duty: Serienstand 24602/(4x25600) = 24,0 %, DIP 5 = ON 25099/... = 24,5 %
		--     (0,5 Prozentpunkte = unsichtbar; das Settle-Fenster ist dunkel. Wer den
		--      Unterschied ganz weghaben will, setzt SETTLE_CYCLES = 0 -- dann traegt schon
		--      der Daten-Durchlauf 10 us Totzeit.)
		-- Damit laeuft die Matrix im selben Raster wie die Original-DMA-Kette (Troubleshooting
		-- Guide: 512 us je Spalte, "duty cycle of only 25 %"). Bis SW 0.1.4 stand hier 12500
		-- (250 us, ~961 Hz) -- doppelt so schnell wie das Original bei gleicher Helligkeit.
		-- DWELL_CYCLES ist der einzige Software-seitige HELLIGKEITSHEBEL (Duty, nicht Spannung).
		DWELL_CYCLES  : integer := 24100; -- clk_50-Zyklen Ruhezeit je Strobe-Phase -> 488Hz Frame
		-- Totzeit zwischen Spaltenwechsel und Scharfwerden der Zeilen (nur Serienstand).
		-- Zusammen mit dem Daten-Durchlauf ergibt 497 rund 20 us, in denen die alte Spalte
		-- abklingen kann. HW-TUNBAR: glimmt die "gleiche Zeile, vorhergehende Spalte"-Lampe
		-- trotz DIP 5 = OFF weiter, ist die PNP-Speicherzeit laenger -> 1250 (25 us), dann 2500
		-- (50 us) versuchen und DWELL_CYCLES um denselben Betrag senken (Phase bleibt 25600).
		SETTLE_CYCLES : integer := 497;
		SHIFT_DIV     : integer := 10     -- clk_50 je SRCK-Halbperiode (SHIFT_DIV=10 -> ~2.5MHz Bit-Takt)
	);
	port (
		clk_50      : in  std_logic;
		reset       : in  std_logic;                       -- active-high: alle Lampen AUS
		enable      : in  std_logic;                       -- '1' = Scan aktiv (CPU laeuft)
		-- '1' = Zeitverhalten der Original-MPU (Spaltenwechsel gleichzeitig mit dem Zeilen-Latch,
		-- inkl. Vorgluehen bei LED-Retrofits). Im Top an Options-DIP 5. Wird EINMAL JE FRAME
		-- uebernommen, damit ein Umschalten mitten in der Phase keinen Glitch erzeugt; ein
		-- mechanischer Schalter ist kein zeitkritischer Eingang.
		orig_timing : in  std_logic;
		lamp_state  : in  std_logic_vector(127 downto 0);  -- RAM 0x30-0x3F Shadow (16 Byte)
		ser         : out std_logic;                       -- 74HC595 SER   (-> g_serin_595)
		srck        : out std_logic;                       -- 74HC595 SRCLK (-> g_clk_595)
		rck         : out std_logic;                       -- 74HC595 RCLK  (-> g_rclk_595)
		oe_n        : out std_logic;                       -- 74HC595 /OE   (-> oe_595), active-low
		strobe_sel  : out std_logic_vector(1 downto 0);    -- Strobe-Select (-> aux_lamp_strobe, Top invertiert)
		-- Diagnose fuer den Lampen-Trace im Top (DBG_MODE 4/5): '1' = Zeilen sind aus.
		-- Das ist direkt das 'pass'-Register, kostet also nichts. Seit das Blanken ueber die
		-- Datenlatches laeuft, ist oe_n NICHT mehr das Austastfenster -- ohne diesen Ausgang
		-- wuerde die Messung aus Lamp_Refresh_Analysis.md 6.7 ins Leere zeigen.
		-- Genauigkeit: 'pass' kippt am ENDE des jeweiligen St_Latch, die Zeilen schalten aber
		-- mit der rck-FLANKE an dessen Anfang -- beide Kanten liegen also ~200 ns (ein Tick) zu
		-- spaet. Die BREITE des Fensters stimmt; wer auf ns genau messen will, nimmt rck (zwei
		-- Pulse je Phase: der erste blankt, der zweite schaltet ein).
		blank       : out std_logic
	);
end lamp_matrix;

architecture rtl of lamp_matrix is
	type state_t is (St_Load, St_ShiftLo, St_ShiftHi, St_ShiftLast, St_Latch, St_Settle,
	                St_Enable, St_Dwell);
	signal state     : state_t := St_Load;
	signal shiftreg  : std_logic_vector(23 downto 0) := (others => '0');
	signal bit_cnt   : integer range 0 to 23 := 0;
	signal phase     : integer range 0 to 3 := 0;
	-- zaehlt beide Wartezustaende (Dwell und Settle) -- ein Zaehler genuegt, sie sind nie
	-- gleichzeitig aktiv. Obergrenze ist der Dwell im Original-Modus.
	signal dwell_cnt : integer range 0 to DWELL_CYCLES + SETTLE_CYCLES := 0;
	signal div_cnt   : integer range 0 to SHIFT_DIV := 0;
	signal tick      : std_logic := '0';
	-- '0' = Clear-Durchlauf (24 Nullen), '1' = Datendurchlauf (Muster der Phase).
	-- pass='1' ist gleichzeitig das Austastfenster und geht als 'blank' nach draussen.
	signal pass      : std_logic := '0';
	-- orig_timing, einmal je Frame uebernommen (s. Portkommentar)
	signal orig_mode : std_logic := '0';
	-- Dwell-Ziel: im Original-Modus schlaegt die uebersprungene Settle-Zeit hier auf, damit die
	-- Phase in beiden Modi 25600 clk lang ist.
	signal dwell_lim : integer range 0 to DWELL_CYCLES + SETTLE_CYCLES := DWELL_CYCLES;

	-- GRP_OF (595-Ausgang je Latch/Bit) kommt aus work.lamp_map_pkg -- dort steht auch
	-- die daraus berechnete Umkehrung, die das Top-Level fuer FA-Control braucht.

	-- STROBE_ENC (Strobe-Index s -> 2-Bit-Code an strobe_sel) kommt ebenfalls aus
	-- work.lamp_map_pkg -- der Lampen-Trace im Top (DBG_MODE 4/5) muss dieselbe Kodierung
	-- kennen, um aus strobe_sel auf die sichtbare Phase zurueckzurechnen.
begin

	blank     <= pass;
	dwell_lim <= DWELL_CYCLES + SETTLE_CYCLES when orig_mode = '1' else DWELL_CYCLES;

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
				pass       <= '0';            -- erster Durchlauf nach Reset/Freigabe = Clear
			else
				case state is

					when St_Load =>
						-- Clear-Durchlauf: 24 Nullen -> alle Zeilen aktiv aus.
						-- Datendurchlauf: Muster der aktuellen Phase (vec(N-1) = 595-Ausgang N).
						vec := (others => '0');
						if pass = '1' then
							for L in 0 to 3 loop                     -- Latch-Index 0=1000..3=100C
								for b in 0 to 5 loop                 -- Latch-Bit
									N := GRP_OF(L * 6 + b);          -- 595-Ausgang (0 = unbenutzt)
									if N /= 0 then
										idx := (L * 4 + phase) * 8 + b;  -- RAM-Bit: offset = L*4 + s (HW-TUNBAR)
										vec(N - 1) := lamp_state(idx);
									end if;
								end loop;
							end loop;
						elsif phase = 0 then
							orig_mode <= orig_timing;       -- Modus einmal je Frame uebernehmen
						end if;
						shiftreg <= vec;
						bit_cnt  <= 0;
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
								state <= St_ShiftLast;
							else
								bit_cnt <= bit_cnt + 1;
								state   <= St_ShiftLo;
							end if;
						end if;

					when St_ShiftLast =>
						-- Haelt den 24. SRCK-Puls eine volle Tick-Haelfte (200 ns) high. Ohne diesen
						-- Zustand raeumt St_Latch srck schon in der naechsten clk_50-Flanke ab: der
						-- letzte Puls waere dann nur EINE Taktperiode = 20 ns breit und laege damit
						-- auf der Mindest-Taktpulsbreite des 74HC595 (~20 ns @4,5 V, ueber Temperatur
						-- mehr) -- ohne jeden Spielraum. Am Logikanalysator nachgemessen 2026-08-09
						-- (48 % Trefferquote gegen das 41,7-ns-Raster = exakt 20 ns), Details in
						-- docs/Lamp_Refresh_Analysis.md 6.7.1. srck haelt hier seinen Wert '1'.
						if tick = '1' then
							state <= St_Latch;
						end if;

					when St_Latch =>
						srck <= '0';
						rck  <= '1';                        -- Shift- -> Storage-Register uebernehmen
						if pass = '0' then
							-- Dieser rck schaltet ALLE Zeilen aus -> sicheres Fenster fuer die Spalte
							if orig_mode = '0' then
								strobe_sel <= STROBE_ENC(phase);
							end if;
						else
							-- Dieser rck schaltet die Zeilen der Phase EIN
							if orig_mode = '1' then
								strobe_sel <= STROBE_ENC(phase);   -- gleichzeitig = Original
							end if;
							-- ... und gibt die Ausgaenge dauerhaft frei. Erst HIER, nicht schon beim
							-- Nullen-Latch: nach Reset/Freigabe ist der Inhalt der 595 unbekannt, also
							-- bleibt der erste Clear-Durchlauf noch komplett hochohmig.
							oe_n <= '0';
						end if;
						if tick = '1' then                  -- rck ~1 Tick breit halten (sichere Pulsbreite)
							if pass = '0' then
								pass      <= '1';
								dwell_cnt <= 0;
								if orig_mode = '0' then
									state <= St_Settle;
								else
									state <= St_Load;       -- Original: keine Totzeit
								end if;
							else
								pass  <= '0';
								state <= St_Enable;
							end if;
						end if;

					when St_Settle =>
						-- Spalte ist umgeschaltet, Zeilen sind aus: der alten Spalte Zeit zum
						-- Abklingen geben (2N5883-Speicherzeit, s. Kopf). Vergleich mit >=, damit
						-- SETTLE_CYCLES = 0 nicht haengt, sondern nach einem Takt weitergeht.
						rck <= '0';
						if dwell_cnt >= SETTLE_CYCLES - 1 then
							dwell_cnt <= 0;
							state     <= St_Load;
						else
							dwell_cnt <= dwell_cnt + 1;
						end if;

					when St_Enable =>
						rck       <= '0';
						dwell_cnt <= 0;
						state     <= St_Dwell;

					when St_Dwell =>
						-- Kein oe_n mehr am Phasenende: geblankt wird durch den Nullen-Latch des
						-- naechsten Clear-Durchlaufs. Die Phase bleibt darum noch dessen ~10 us
						-- sichtbar -- richtige Zeile, richtige Spalte, kein Ghosting.
						if dwell_cnt >= dwell_lim - 1 then
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
