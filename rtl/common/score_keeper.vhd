-- score_keeper.vhd - letzte Spielstaende + Highscore je Spiel im I2C-FRAM (SW 0.4.0)
--
-- Spielunabhaengig: arbeitet nur auf den Display-Shadow-Buffern (display1..4, Index 0 = rechte
-- Ziffer, 5 = linke, 6 = Player-up-LED) und auf in_game aus der Player-up-Erkennung im Top-Level.
-- Es wird NICHTS ins Spiel-RAM geschrieben - die gespeicherten Werte werden nur in die Anzeige
-- eingeblendet, solange kein Spiel laeuft (s. docs/FRAM_Persistence.md, Abschnitt SW 0.4.0).
--
-- Ablauf:
--   Boot   (boot_done, nach dem DIP-Read): erase='1' (DIP 2 OFF, SW 0.4.2) -> Funktion AUS:
--          Slot des Spiels mit Nullen ueberschreiben, danach nichts speichern und nichts
--          einblenden. Sonst (DIP 2 ON = Funktion an) Slot lesen; gueltig, wenn Byte 0 = Magic 0xA5.
--          (SW 0.4.0/0.4.1: ON = loeschen, OFF = an - im Test fuer "an/aus" gehalten, daher gedreht.)
--   Spiel  snap='1' (die up-Lampe des Spielers am Zug leuchtet) -> Displays mitschreiben.
--          Fallende Flanke von in_game = Spielende -> letzte Staende = Schnappschuss,
--          Highscore = max(alt, bester Spieler), Slot schreiben.
--   Attract (in_game='0'): bis zum ersten Spiel nach dem Boot die gespeicherten letzten Staende
--          statt der Spielanzeige; ausserdem im Wechsel NORMAL_CYCLES Spielanzeige /
--          HS_CYCLES Highscore auf allen vier Spieler-Displays (wie Bally). Die Player-up-LEDs
--          (Index 6) und das Status-Display bleiben immer die des Spiels.
--
-- FRAM-Slot je Spiel (16 Byte ab game_sel*16):
--   [0]      Magic 0xA5
--   [1..12]  letzte Staende, je Display 3 Byte (display1, display2, display3, display4),
--            Byte = Ziffer(2k+1) & Ziffer(2k), k = 2,1,0 (linkes Paar zuerst)
--   [13..15] Highscore, gleiche Kodierung
-- Ziffern werden roh gespeichert (Blank-Nibbles bleiben Blank); beim Vergleich zaehlt ein
-- Nibble > 9 als 0.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.instruction_buffer_type.all;
use work.fram_types.all;

entity score_keeper is
	generic (
		NORMAL_CYCLES : integer := 400000000;   -- 8 s Spielanzeige / letzte Staende
		HS_CYCLES     : integer := 200000000    -- 4 s Highscore
	);
	port (
		clk_50    : in  std_logic;
		reset     : in  std_logic;              -- active-high (Board-Reset)
		boot_done : in  std_logic;              -- DIP-Read fertig, options gueltig
		run       : in  std_logic;              -- CPU laeuft (reset_l_stable)
		erase     : in  std_logic;              -- '1' = Funktion aus + Slot beim Boot loeschen (DIP 2 OFF)
		game_sel  : in  integer range 0 to 4;
		in_game   : in  std_logic;
		snap      : in  std_logic;              -- Schnappschuss-Strobe (up-Lampe leuchtet)
		display1  : in  DISPLAY_T;
		display2  : in  DISPLAY_T;
		display3  : in  DISPLAY_T;
		display4  : in  DISPLAY_T;
		out1      : out DISPLAY_T;
		out2      : out DISPLAY_T;
		out3      : out DISPLAY_T;
		out4      : out DISPLAY_T;
		valid     : out std_logic;              -- Slot gueltig (beim Boot gelesen oder gespeichert)
		saved     : out std_logic;              -- 1-clk-Puls je Speichervorgang (Diagnose)
		fram_ok   : out std_logic;              -- FRAM hat im letzten Transfer quittiert
		sda       : inout std_logic;
		scl       : out std_logic
	);
end score_keeper;

architecture rtl of score_keeper is

	constant N_REC  : integer := 16;
	constant MAGIC  : std_logic_vector(7 downto 0) := x"A5";
	constant ZERO24 : std_logic_vector(23 downto 0) := (others => '0');

	type score_arr is array (0 to 3) of std_logic_vector(23 downto 0);  -- 6 Ziffern je Display

	signal last_sc   : score_arr := (others => (others => '1'));         -- gespeicherte Staende
	signal snap_sc   : score_arr := (others => (others => '1'));         -- Schnappschuss im Spiel
	signal hs        : std_logic_vector(23 downto 0) := (others => '1');
	signal best      : std_logic_vector(23 downto 0) := (others => '0');
	signal any_sc    : std_logic := '0';
	signal idx       : integer range 0 to 3 := 0;
	signal hs_valid  : std_logic := '0';
	signal loaded    : std_logic := '0';     -- 1-clk: gueltiger Slot beim Boot gelesen
	signal show_last : std_logic := '0';     -- bis zum ersten Spiel die gespeicherten Staende
	signal show_hs   : std_logic := '0';
	signal in_game_d : std_logic := '0';
	signal active    : std_logic := '0';     -- Funktion an (beim Boot nicht geloescht)
	signal phase_cnt : integer range 0 to NORMAL_CYCLES + HS_CYCLES := 0;

	signal f_go, f_rd, f_busy, f_done, f_ack : std_logic := '0';
	signal f_erase     : std_logic := '0';
	signal f_wr, f_rdd : fram_data_t(0 to N_REC-1);
	signal f_addr      : std_logic_vector(15 downto 0);

	-- S_CMP vergleicht je Takt EINEN Spieler mit dem bisher besten Wert. Alle vier in einem
	-- Takt (erste Fassung) kostete ~1000 LUTs und riss das clk_50-Timing um 33 ns.
	type st_t is (S_WAIT, S_BOOT, S_RUN, S_CMP, S_COMMIT, S_SAVE);
	signal st : st_t := S_WAIT;

	-- 6 Ziffern eines Displays (Index 5..0) als 24 Bit, linke Ziffer oben
	function pack(d : DISPLAY_T) return std_logic_vector is
	begin
		return d(5) & d(4) & d(3) & d(2) & d(1) & d(0);
	end function;

	-- Zahlenwert: Ziffern > 9 (Blank) werden 0. Danach ist BCD als Binaerzahl vergleichbar.
	function norm(a : std_logic_vector(23 downto 0)) return std_logic_vector is
		variable r : std_logic_vector(23 downto 0);
	begin
		for i in 0 to 5 loop
			if a(i*4+3 downto i*4) > x"9" then
				r(i*4+3 downto i*4) := x"0";
			else
				r(i*4+3 downto i*4) := a(i*4+3 downto i*4);
			end if;
		end loop;
		return r;
	end function;

	-- Anzeige: Score-Ziffern aus v, Player-up-LED aus dem Spiel
	function unpack(v : std_logic_vector(23 downto 0); g : DISPLAY_T) return DISPLAY_T is
		variable r : DISPLAY_T;
	begin
		for i in 0 to 5 loop
			r(i) := v(i*4+3 downto i*4);
		end loop;
		r(6) := g(6);
		return r;
	end function;

begin

	f_addr <= x"00" & '0' & conv_std_logic_vector(game_sel, 3) & "0000";

	-- Schreibdaten direkt aus den Registern (keine zweite Kopie); beim Loeschen Nullen
	f_wr(0) <= x"00" when f_erase = '1' else MAGIC;
	gen_wr : for p in 0 to 3 generate
		f_wr(1 + p*3) <= x"00" when f_erase = '1' else last_sc(p)(23 downto 16);
		f_wr(2 + p*3) <= x"00" when f_erase = '1' else last_sc(p)(15 downto 8);
		f_wr(3 + p*3) <= x"00" when f_erase = '1' else last_sc(p)(7 downto 0);
	end generate;
	f_wr(13) <= x"00" when f_erase = '1' else hs(23 downto 16);
	f_wr(14) <= x"00" when f_erase = '1' else hs(15 downto 8);
	f_wr(15) <= x"00" when f_erase = '1' else hs(7 downto 0);

	FRAM: entity work.fram_i2c
	generic map(
		DEV_ADDR => "1010001",   -- 0x51 (A0=3V, A1=A2=GND)
		CLK_DIV  => 125,         -- ~100 kHz SCL
		N_BYTES  => N_REC
	)
	port map(
		clk_50    => clk_50,
		reset     => reset,
		go        => f_go,
		cmd_read  => f_rd,
		mem_addr  => f_addr,
		wr_data   => f_wr,
		rd_data   => f_rdd,
		busy      => f_busy,
		done      => f_done,
		ack_dbg   => open,
		ack_ok    => f_ack,
		scl_dbg   => open,
		dbg_state => open,
		sda       => sda,
		scl       => scl
	);

	fram_ok <= f_ack;

	-- FRAM-Steuerung, Schnappschuss, Spielende, Highscore
	ctrl : process(clk_50)
		variable cur : std_logic_vector(23 downto 0);
	begin
		if rising_edge(clk_50) then
			f_go   <= '0';
			saved  <= '0';
			loaded <= '0';
			if reset = '1' then
				st        <= S_WAIT;
				f_rd      <= '0';
				f_erase   <= '0';
				valid     <= '0';
				hs_valid  <= '0';
				in_game_d <= '0';
				active    <= '0';
				snap_sc   <= (others => (others => '1'));
			else
				in_game_d <= in_game;
				if snap = '1' then
					snap_sc(0) <= pack(display1);
					snap_sc(1) <= pack(display2);
					snap_sc(2) <= pack(display3);
					snap_sc(3) <= pack(display4);
				end if;

				case st is
				when S_WAIT =>
					if boot_done = '1' and f_busy = '0' then
						f_erase <= erase;
						f_rd    <= not erase;
						active  <= not erase;
						f_go    <= '1';
						st      <= S_BOOT;
					end if;
				when S_BOOT =>
					if f_done = '1' then
						if f_rd = '1' and f_rdd(0) = MAGIC then
							for p in 0 to 3 loop
								last_sc(p) <= f_rdd(1 + p*3) & f_rdd(2 + p*3) & f_rdd(3 + p*3);
							end loop;
							hs     <= f_rdd(13) & f_rdd(14) & f_rdd(15);
							valid  <= '1';
							loaded <= '1';
							if norm(f_rdd(13) & f_rdd(14) & f_rdd(15)) /= ZERO24 then
								hs_valid <= '1';
							end if;
						end if;
						f_erase <= '0';
						st      <= S_RUN;
					end if;
				when S_RUN =>
					-- Spielende. run='1' schliesst den Abbruch durch FA-Control-Uebernahme aus
					-- (dann faellt in_game mit run). active='0' (DIP 2 OFF): nichts speichern.
					if in_game = '0' and in_game_d = '1' and run = '1' and active = '1' then
						if hs_valid = '1' then
							best <= hs;
						else
							best <= (others => '0');
						end if;
						any_sc <= '0';
						idx    <= 0;
						st     <= S_CMP;
					end if;
				when S_CMP =>
					cur := snap_sc(idx);
					if norm(cur) > norm(best) then
						best <= cur;
					end if;
					if norm(cur) /= ZERO24 then
						any_sc <= '1';
					end if;
					if idx = 3 then
						st <= S_COMMIT;
					else
						idx <= idx + 1;
					end if;
				when S_COMMIT =>
					-- ein Spiel ohne einen einzigen Punkt wird nicht gespeichert
					if any_sc = '1' then
						last_sc  <= snap_sc;
						hs       <= best;
						hs_valid <= '1';
						valid    <= '1';
						f_rd     <= '0';
						f_go     <= '1';
						st       <= S_SAVE;
					else
						st <= S_RUN;
					end if;
				when S_SAVE =>
					if f_done = '1' then
						saved <= '1';
						st    <= S_RUN;
					end if;
				end case;
			end if;
		end if;
	end process;

	-- Anzeige-Wechsel im Attract
	attract : process(clk_50)
	begin
		if rising_edge(clk_50) then
			if reset = '1' then
				show_last <= '0';
				show_hs   <= '0';
				phase_cnt <= 0;
			elsif loaded = '1' then
				show_last <= '1';         -- gespeicherte Staende bis zum ersten Spiel zeigen
			elsif run = '0' or in_game = '1' then
				if in_game = '1' then
					show_last <= '0';     -- ab dem ersten Spiel zeigt das Spiel selbst die Staende
				end if;
				show_hs   <= '0';
				phase_cnt <= 0;
			else
				if phase_cnt = NORMAL_CYCLES + HS_CYCLES then
					phase_cnt <= 0;
				else
					phase_cnt <= phase_cnt + 1;
				end if;
				if hs_valid = '1' and phase_cnt >= NORMAL_CYCLES then
					show_hs <= '1';
				else
					show_hs <= '0';
				end if;
			end if;
		end if;
	end process;

	out1 <= unpack(hs, display1) when show_hs = '1' else unpack(last_sc(0), display1) when show_last = '1' else display1;
	out2 <= unpack(hs, display2) when show_hs = '1' else unpack(last_sc(1), display2) when show_last = '1' else display2;
	out3 <= unpack(hs, display3) when show_hs = '1' else unpack(last_sc(2), display3) when show_last = '1' else display3;
	out4 <= unpack(hs, display4) when show_hs = '1' else unpack(last_sc(3), display4) when show_last = '1' else display4;

end rtl;
