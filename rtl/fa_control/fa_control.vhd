-- fa_control.vhd  --  LISY-Slave fuer die "FA-Control"-Schnittstelle
-- bontango 08.2026
--
-- Gegenstelle zu N:\Projekte\FA_Control (ESP32-C3 mit Web-Oberflaeche). Der ESP ist
-- der Master und schickt binaere LISY-Befehle ueber UART (8N1, per Default 115200);
-- dieses Modul fuehrt sie aus und antwortet. Protokoll = LISY API 0.12, unveraendert
-- uebernommen aus N:\Projekte\lisy_5_28\src\lisy\lisy_api.h -- KEINE Eigenerfindung,
-- damit auch ein echter LISY-Host (Raspberry Pi) sich hier anmelden koennte.
--
-- ---------------------------------------------------------------------------
-- WIEDERVERWENDUNG in anderen FPGA-Projekten (WillFA, GottFA, BallyFA, ...)
-- ---------------------------------------------------------------------------
-- Nichts hier drin ist Atari-spezifisch. Uebernahme in ein anderes Projekt:
--   1. Ordner rtl/fa_control/ kopieren (dieses File + fa_control_pkg + uart_rx/tx).
--   2. Vier Zeilen in die Dateiliste des Projekts (bei AtariFA: scripts/files_common.tcl).
--   3. Instanz im Top-Level, Generics auf die Anlage setzen (N_LAMPS, N_SOL, N_SW,
--      N_DISP, DISP_DIGITS, HW_NAME) und die Override-Ausgaenge in die vorhandenen
--      Treiberpfade muxen.
-- Die Anzahlen sind ABSICHTLICH Generics und werden ueber die Opcodes 3..9 an den
-- Host gemeldet -- der Host muss sie also nicht mehr konfiguriert bekommen. Genau
-- das ist der Zweck des Connect-Handshakes.
--
-- VHDL-93 (kein else generate, keine unconstrained Record-Ports): WillFA/GottFA haben
-- Cyclone-II-Varianten, die noch mit Quartus 13.0sp1 gebaut werden.
-- numeric_std wird hier modulintern benutzt; das kollidiert NICHT mit der
-- std_logic_unsigned-Konvention der Top-Levels (der Konflikt entsteht nur innerhalb
-- einer Design-Unit).
--
-- ---------------------------------------------------------------------------
-- UEBERNAHME DER KONTROLLE
-- ---------------------------------------------------------------------------
-- Zwei Bedingungen muessen zusammenkommen, damit der Host die Anlage steuern darf:
--   * ctrl_req  = '0'  -- Hardware-Leitung vom Host ("ich moechte uebernehmen").
--                         Bei AtariFA ist das GPIO10 des ESP32-C3 an FPGA-PIN_11,
--                         active low, mit Weak-Pull-Up im FPGA: kein Host gesteckt
--                         = high = keine Anforderung.
--   * ctrl_allow= '1'  -- Freigabe durch den Betreiber (bei AtariFA Options-DIP 4).
-- Erst der Opcode 100 (LISY_INIT) schaltet dann ctrl_active auf '1'. Die Antwort auf
-- 100 sagt dem Host, woran es lag:
--      0 = Kontrolle gewaehrt
--      1 = verweigert, Freigabe fehlt (DIP steht auf OFF)
--      2 = verweigert, ctrl_req nicht angefordert
-- ctrl_active faellt SOFORT zurueck, wenn eine der beiden Bedingungen wegfaellt --
-- der Freigabeschalter wirkt also auch im laufenden Betrieb -- und ausserdem, wenn
-- laenger als WD_TIMEOUT ueberhaupt kein Byte mehr ankam (Totmannschaltung, z.B.
-- Host abgesteckt). In beiden Faellen werden alle Overrides geloescht.
--
-- Was das Top-Level mit ctrl_active macht (Lampen/Spulen/Displays umschalten, CPU
-- anhalten), ist Sache des Top-Levels -- dieses Modul liefert nur den Zustand und
-- die Sollwerte.
--
-- ---------------------------------------------------------------------------
-- GRENZEN (bewusst, das hier ist ein Testwerkzeug und kein Spielbetrieb)
-- ---------------------------------------------------------------------------
--   * Nur EIN Spulenpuls (Opcode 23) gleichzeitig; ein neuer Puls loest den
--     laufenden ab. Ein Zaehler je Spule waere ein Vielfaches an Registern und
--     die Weboberflaeche pulst ohnehin immer nur eine Spule.
--   * Opcode 24 (Pulszeit) traegt zwar eine Spulennummer, wird hier aber global
--     gespeichert (letzter Wert gilt). Genau so benutzt es FA_Control, das die
--     gleiche Zeit in einer Schleife an alle Spulen schickt.
--   * Unbekannte Opcodes werden ohne Parameter angenommen und mit 0x00 beantwortet
--     (wie im WillFA7-Monitor). Ein unbekannter Opcode MIT Parametern wuerde den
--     Bytestrom verschieben -- die Gegenstelle schickt aber nur die Liste unten.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fa_control_pkg.all;

entity fa_control is
	generic (
		-- Takt/Baudrate: g_CLKS_PER_BIT = f_clk / Baud. 50 MHz / 115200 = 434.
		CLKS_PER_BIT : integer := 434;
		-- Kennung, die Opcode 0 zurueckliefert (ohne NUL, das haengt das Modul an).
		HW_NAME      : string  := "AtariFA";
		-- Version des LISY-Protokolls, das dieses Modul spricht (Opcode 2).
		API_VER      : string  := "0.12";
		-- Bestueckung der Anlage -- das ist es, was der Host per Connect abfragt.
		N_LAMPS      : integer := 84;
		N_SOL        : integer := 22;
		N_SOUNDS     : integer := 16;
		N_SW         : integer := 80;
		N_DISP       : integer := 5;
		DISP_TYPE    : integer := 1;   -- 1 = BCD7 (7-Segment ohne Komma), s. lisy_api_com.c
		DISP_DIGITS  : fa_width_array_t := (4, 6, 6, 6, 6, 0, 0);  -- [0] = Status-Display
		-- Vektorbreiten. Muessen >= der jeweiligen N_* sein -- und sollten NICHT
		-- groesszuegig gewaehlt werden: jeder ueberzaehlige Eintrag kostet einen
		-- Registerplatz plus seinen Anteil an den Adressdekodern und Auslesemuxen.
		-- Bei AtariFA hat "grosszuegig statt genau" rund 900 Logikelemente gekostet.
		MAX_LAMPS    : integer := 84;
		MAX_SOL      : integer := 22;
		MAX_SW       : integer := 80;
		MAX_DIGITS   : integer := 6;
		-- Millisekunden-Basis. Speist die Spulen-Pulszeit UND die Totmannschaltung;
		-- ein eigener Takt-Zaehler fuer den Watchdog waere 27 Bit breit gewesen.
		MS_CYCLES    : integer := 50000;   -- clk-Takte je Millisekunde (50 MHz)
		-- Totmannschaltung: so viele Millisekunden ohne EIN EINZIGES empfangenes
		-- Byte beenden die Uebernahme. 0 = abgeschaltet.
		-- FA_Control sendet den Watchdog-Opcode alle 500 ms.
		WD_TIMEOUT_MS : integer := 2000;
		PULSE_MS_DEF : integer := 50
	);
	port (
		clk         : in  std_logic;                        -- 50 MHz
		reset       : in  std_logic;                        -- active HIGH
		-- Serielle Leitungen. Achtung Namensrichtung: rxd ist der EMPFANG des FPGA,
		-- haengt also am TX des Hosts.
		rxd         : in  std_logic;
		txd         : out std_logic;
		-- Uebernahme
		ctrl_req    : in  std_logic;                        -- active LOW, asynchron
		ctrl_allow  : in  std_logic;                        -- '1' = Betreiber gibt frei
		ctrl_active : out std_logic;                        -- '1' = Host steuert
		-- Auskunft ueber die Anlage (Opcodes 1 und 8)
		ver_main    : in  std_logic_vector(3 downto 0);     -- als ASCII-Ziffern gesendet,
		ver_sub1    : in  std_logic_vector(3 downto 0);     -- Format "M.S1.S2"
		ver_sub2    : in  std_logic_vector(3 downto 0);
		game_info   : in  std_logic_vector(3 downto 0);     -- eine Ziffer, Opcode 8
		-- Istzustand (wird immer gelesen, auch ohne Uebernahme)
		sw_state    : in  std_logic_vector(MAX_SW - 1 downto 0);   -- '1' = geschlossen
		-- Sollzustand (nur gueltig solange ctrl_active = '1')
		lamp_ovr    : out std_logic_vector(MAX_LAMPS - 1 downto 0);
		sol_ovr     : out std_logic_vector(MAX_SOL - 1 downto 0);
		-- Index = Display-Nr * MAX_DIGITS + Ziffer, Ziffer 0 = zuerst gesendet.
		disp_ovr    : out fa_nibble_array_t(0 to N_DISP * MAX_DIGITS - 1);
		snd_ovr     : out std_logic_vector(3 downto 0);
		snd_en      : out std_logic
	);
end fa_control;

architecture rtl of fa_control is

	-- ---------------------------------------------------------------------
	-- LISY API 0.12 -- Opcodes (lisy_api.h). Nur die, die hier vorkommen.
	-- ---------------------------------------------------------------------
	constant OP_G_HW           : integer := 0;    -- -> String  Hardware-Kennung
	constant OP_G_LISY_VER     : integer := 1;    -- -> String  Firmware-Version
	constant OP_G_API_VER      : integer := 2;    -- -> String  Protokoll-Version
	constant OP_G_NO_LAMPS     : integer := 3;    -- -> Byte
	constant OP_G_NO_SOL       : integer := 4;    -- -> Byte
	constant OP_G_NO_SOUNDS    : integer := 5;    -- -> Byte
	constant OP_G_NO_DISP      : integer := 6;    -- -> Byte
	constant OP_G_DISP_DETAIL  : integer := 7;    -- Nr -> 2 Bytes (Typ, Stellen)
	constant OP_G_GAME_INFO    : integer := 8;    -- -> String
	constant OP_G_NO_SW        : integer := 9;    -- -> Byte
	constant OP_G_STAT_LAMP    : integer := 10;   -- Nr -> Byte
	constant OP_S_LAMP_ON      : integer := 11;   -- Nr
	constant OP_S_LAMP_OFF     : integer := 12;   -- Nr
	constant OP_G_STAT_SOL     : integer := 20;   -- Nr -> Byte
	constant OP_S_SOL_ON       : integer := 21;   -- Nr
	constant OP_S_SOL_OFF      : integer := 22;   -- Nr
	constant OP_S_PULSE_SOL    : integer := 23;   -- Nr
	constant OP_S_PULSE_TIME   : integer := 24;   -- Nr, ms
	constant OP_S_RECYCLE_TIME : integer := 25;   -- Nr, ms  (angenommen, ohne Wirkung)
	constant OP_S_DISP_FIRST   : integer := 30;   -- Nr = op-30, dann Laenge + Ziffern
	constant OP_S_DISP_LAST    : integer := 36;
	constant OP_G_STAT_SW      : integer := 40;   -- Nr -> Byte
	constant OP_G_CHANGED_SW   : integer := 41;   -- -> Byte, 127 = keine Aenderung
	constant OP_S_PLAY_SOUND   : integer := 50;   -- Track, Nr
	constant OP_S_STOP_SOUND   : integer := 51;   -- Track
	constant OP_INIT           : integer := 100;  -- -> Byte, s. Kopfkommentar
	constant OP_WATCHDOG       : integer := 101;  -- -> Byte 0
	constant OP_BACK_READY     : integer := 102;  -- -> Byte 0

	constant SW_NO_CHANGE : std_logic_vector(7 downto 0) := x"7F";  -- 127

	-- ---------------------------------------------------------------------
	-- Antwortweg. Alles laeuft ueber "Quelle + Laenge + Index" statt ueber einen
	-- gefuellten Sendepuffer: die Strings sind Konstanten, und ein 12-Byte-Register,
	-- das aus einem Dutzend Zweigen beschrieben wird, kostet neben den Flipflops
	-- vor allem einen sehr breiten Lademux (bei AtariFA rund 400 Logikelemente).
	-- Gehalten werden muessen nur die beiden variablen Antwortbytes.
	-- ---------------------------------------------------------------------
	constant TXBUF_LEN : integer := 12;
	type byte_buf_t is array (0 to TXBUF_LEN - 1) of std_logic_vector(7 downto 0);
	type tx_src_t is (SRC_NONE, SRC_HW, SRC_API, SRC_VER, SRC_GAME, SRC_BYTES);

	-- String -> Puffer, NUL-terminiert (der Rest bleibt 0x00, das IST der Terminator).
	function str_to_buf(s : string) return byte_buf_t is
		variable r : byte_buf_t := (others => x"00");
	begin
		for i in 0 to TXBUF_LEN - 1 loop
			if i < s'length then
				r(i) := std_logic_vector(to_unsigned(character'pos(s(s'low + i)), 8));
			end if;
		end loop;
		return r;
	end function;

	function to_byte(n : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(n, 8));
	end function;

	-- ASCII-Ziffer aus einem Nibble. Sinnvoll nur fuer 0..9 -- Versionsziffern
	-- sind bei allen FA-Projekten einstellig dezimal.
	function ascii_digit(n : std_logic_vector(3 downto 0)) return std_logic_vector is
	begin
		return "0011" & n;
	end function;

	constant HW_BUF  : byte_buf_t := str_to_buf(HW_NAME);
	constant API_BUF : byte_buf_t := str_to_buf(API_VER);
	constant HW_LEN  : integer := HW_NAME'length + 1;   -- inkl. NUL
	constant API_LEN : integer := API_VER'length + 1;

	-- Zaehlerobergrenze der Totmannschaltung; +1, damit WD_TIMEOUT_MS = 0
	-- (abgeschaltet) keinen leeren Wertebereich ergibt.
	constant WD_MAX : integer := WD_TIMEOUT_MS + 1;

	-- ---------------------------------------------------------------------
	-- UART
	-- ---------------------------------------------------------------------
	signal rx_dv    : std_logic;
	signal rx_byte  : std_logic_vector(7 downto 0);
	signal tx_dv    : std_logic := '0';
	signal tx_byte  : std_logic_vector(7 downto 0) := (others => '0');
	signal tx_busy  : std_logic;

	-- ---------------------------------------------------------------------
	-- Protokoll-FSM
	-- ---------------------------------------------------------------------
	type state_t is (S_OPCODE, S_PAR1, S_PAR2, S_DISPDATA,
	                 S_EXEC, S_SEND_LOAD, S_SEND_DV, S_SEND_WAIT);
	signal state   : state_t := S_OPCODE;

	signal opcode  : integer range 0 to 255 := 0;
	signal par1    : integer range 0 to 255 := 0;
	signal par2    : integer range 0 to 255 := 0;
	signal dd_idx  : integer range 0 to 255 := 0;   -- Ziffernzaehler beim Display-Empfang

	signal tx_src  : tx_src_t := SRC_NONE;
	signal tx_b0   : std_logic_vector(7 downto 0) := (others => '0');
	signal tx_b1   : std_logic_vector(7 downto 0) := (others => '0');
	signal tx_len  : integer range 0 to TXBUF_LEN := 0;
	signal tx_idx  : integer range 0 to TXBUF_LEN := 0;
	signal tx_next : std_logic_vector(7 downto 0);   -- das jeweils faellige Byte

	-- ---------------------------------------------------------------------
	-- Uebernahme
	-- ---------------------------------------------------------------------
	signal req_meta : std_logic := '1';
	signal req_sync : std_logic := '1';   -- 2-FF-Synchronizer auf ctrl_req
	signal ctrl_r   : std_logic := '0';
	signal wd_cnt   : integer range 0 to WD_MAX := 0;

	-- ---------------------------------------------------------------------
	-- Sollzustaende
	-- ---------------------------------------------------------------------
	signal lamp_r   : std_logic_vector(MAX_LAMPS - 1 downto 0) := (others => '0');
	signal sol_r    : std_logic_vector(MAX_SOL - 1 downto 0)   := (others => '0');
	signal disp_r   : fa_nibble_array_t(0 to N_DISP * MAX_DIGITS - 1) := (others => x"F");
	signal snd_r    : std_logic_vector(3 downto 0) := (others => '0');
	signal snd_en_r : std_logic := '0';

	-- Spulenpuls (ein Kanal, s. Kopfkommentar)
	signal pulse_run    : std_logic := '0';
	signal pulse_idx    : integer range 0 to MAX_SOL - 1 := 0;
	signal pulse_ms     : integer range 0 to 255 := PULSE_MS_DEF;  -- gesetzt per Opcode 24
	signal pulse_left   : integer range 0 to 255 := 0;

	-- Freilaufender Millisekunden-Takt fuer Pulszeit und Totmannschaltung
	signal ms_div  : integer range 0 to MS_CYCLES - 1 := 0;
	signal ms_tick : std_logic := '0';

	-- ---------------------------------------------------------------------
	-- Schalter-Aenderungsmelder (Opcode 41)
	-- Freilaufender Scan ueber sw_state gegen den zuletzt gemeldeten Stand.
	-- Eine Aenderung wird in pend_* zwischengelagert und beim naechsten Opcode 41
	-- abgeholt. sw_rep wird schon beim Erkennen nachgefuehrt, damit der Scan
	-- weiterlaufen kann; ist pend_* noch belegt, bleibt die Differenz stehen und
	-- wird im naechsten Durchlauf erneut gefunden -- es geht nichts verloren.
	-- ---------------------------------------------------------------------
	signal sw_rep     : std_logic_vector(MAX_SW - 1 downto 0) := (others => '0');
	signal scan_idx   : integer range 0 to MAX_SW - 1 := 0;
	signal pend_valid : std_logic := '0';
	signal pend_idx   : integer range 0 to 127 := 0;
	signal pend_state : std_logic := '0';

begin

	-- Wenn eine dieser Zusicherungen faellt, ist das Modul falsch parametriert.
	assert HW_LEN <= TXBUF_LEN
		report "fa_control: HW_NAME passt nicht in den Sendepuffer" severity failure;
	assert API_LEN <= TXBUF_LEN
		report "fa_control: API_VER passt nicht in den Sendepuffer" severity failure;
	assert N_LAMPS <= MAX_LAMPS and N_SOL <= MAX_SOL and N_SW <= MAX_SW
		report "fa_control: N_* groesser als die zugehoerige MAX_*-Vektorbreite" severity failure;
	assert N_DISP <= FA_MAX_DISP
		report "fa_control: LISY kennt nur die Displays 0..6" severity failure;

	ctrl_active <= ctrl_r;
	lamp_ovr    <= lamp_r;
	sol_ovr     <= sol_r;
	disp_ovr    <= disp_r;
	snd_ovr     <= snd_r;
	snd_en      <= snd_en_r;

	-- Das faellige Antwortbyte. Die Strings sind Konstanten, die Versionsziffern
	-- kommen unveraendert von den Eingaengen -- daraus wird eine kleine Nachschlag-
	-- tabelle statt eines gefuellten Registers.
	tx_pick : process(tx_src, tx_idx, tx_b0, tx_b1, ver_main, ver_sub1, ver_sub2, game_info)
	begin
		case tx_src is
			when SRC_HW  => tx_next <= HW_BUF(tx_idx);
			when SRC_API => tx_next <= API_BUF(tx_idx);
			when SRC_VER =>                        -- "M.S1.S2" + NUL
				case tx_idx is
					when 0      => tx_next <= ascii_digit(ver_main);
					when 1      => tx_next <= x"2E";              -- '.'
					when 2      => tx_next <= ascii_digit(ver_sub1);
					when 3      => tx_next <= x"2E";
					when 4      => tx_next <= ascii_digit(ver_sub2);
					when others => tx_next <= x"00";
				end case;
			when SRC_GAME =>                       -- eine Ziffer + NUL
				if tx_idx = 0 then
					tx_next <= ascii_digit(game_info);
				else
					tx_next <= x"00";
				end if;
			when SRC_BYTES =>
				if tx_idx = 0 then
					tx_next <= tx_b0;
				else
					tx_next <= tx_b1;
				end if;
			when others => tx_next <= x"00";
		end case;
	end process;

	RX: entity work.uart_rx
		generic map (g_CLKS_PER_BIT => CLKS_PER_BIT)
		port map (
			i_Clk       => clk,
			i_RX_Serial => rxd,
			o_RX_DV     => rx_dv,
			o_RX_Byte   => rx_byte
		);

	TX: entity work.uart_tx
		generic map (g_CLKS_PER_BIT => CLKS_PER_BIT)
		port map (
			i_Clk       => clk,
			i_TX_DV     => tx_dv,
			i_TX_Byte   => tx_byte,
			o_TX_Active => tx_busy,
			o_TX_Serial => txd,
			o_TX_Done   => open
		);

	main : process(clk)
		variable op   : integer range 0 to 255;
		variable d    : integer range 0 to FA_MAX_DISP - 1;
		variable resp : std_logic_vector(7 downto 0);
		variable pv   : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clk) then
			if reset = '1' then
				state      <= S_OPCODE;
				tx_dv      <= '0';
				tx_len     <= 0;
				tx_idx     <= 0;
				tx_src     <= SRC_NONE;
				ctrl_r     <= '0';
				wd_cnt     <= 0;
				req_meta   <= '1';
				req_sync   <= '1';
				lamp_r     <= (others => '0');
				sol_r      <= (others => '0');
				disp_r     <= (others => x"F");
				snd_r      <= (others => '0');
				snd_en_r   <= '0';
				pulse_run  <= '0';
				pulse_left <= 0;
				pulse_ms   <= PULSE_MS_DEF;
				ms_div     <= 0;
				ms_tick    <= '0';
				sw_rep     <= (others => '0');
				scan_idx   <= 0;
				pend_valid <= '0';
			else
				tx_dv <= '0';   -- Default: nur ein Takt breit

				-- ---- ctrl_req einsynchronisieren (asynchrone Leitung) ----
				req_meta <= ctrl_req;
				req_sync <= req_meta;

				-- ---- Millisekunden-Takt (freilaufend) ----
				if ms_div = MS_CYCLES - 1 then
					ms_div  <= 0;
					ms_tick <= '1';
				else
					ms_div  <= ms_div + 1;
					ms_tick <= '0';
				end if;

				-- ---- Totmannschaltung: jedes empfangene Byte haelt sie wach ----
				if rx_dv = '1' then
					wd_cnt <= 0;
				elsif ms_tick = '1' and wd_cnt < WD_MAX then
					wd_cnt <= wd_cnt + 1;
				end if;

				-- ---- Uebernahme beenden, sobald eine Bedingung wegfaellt ----
				-- Der Freigabeschalter wirkt damit auch im laufenden Betrieb.
				if ctrl_r = '1' then
					if req_sync = '1' or ctrl_allow = '0'
					   or ((WD_TIMEOUT_MS > 0) and (wd_cnt >= WD_TIMEOUT_MS)) then
						ctrl_r     <= '0';
						lamp_r     <= (others => '0');
						sol_r      <= (others => '0');
						disp_r     <= (others => x"F");
						snd_en_r   <= '0';
						pulse_run  <= '0';
					end if;
				end if;

				-- ---- Spulenpuls auslaufen lassen (vor der FSM, damit ein neuer
				--      Befehl im selben Takt gewinnt) ----
				if pulse_run = '1' and ms_tick = '1' then
					if pulse_left <= 1 then
						pulse_run        <= '0';
						sol_r(pulse_idx) <= '0';
					else
						pulse_left <= pulse_left - 1;
					end if;
				end if;

				-- ---- Schalter-Scan ----
				if scan_idx = N_SW - 1 then
					scan_idx <= 0;
				else
					scan_idx <= scan_idx + 1;
				end if;
				if pend_valid = '0' and sw_state(scan_idx) /= sw_rep(scan_idx) then
					pend_idx        <= scan_idx;
					pend_state      <= sw_state(scan_idx);
					sw_rep(scan_idx) <= sw_state(scan_idx);
					pend_valid      <= '1';
				end if;

				-- ---- Protokoll-FSM ----
				case state is

					-- Opcode annehmen und entscheiden, wie viele Parameterbytes folgen.
					when S_OPCODE =>
						if rx_dv = '1' then
							op := to_integer(unsigned(rx_byte));
							opcode <= op;
							case op is
								when OP_G_DISP_DETAIL | OP_G_STAT_LAMP | OP_S_LAMP_ON |
								     OP_S_LAMP_OFF | OP_G_STAT_SOL | OP_S_SOL_ON |
								     OP_S_SOL_OFF | OP_S_PULSE_SOL | OP_S_PULSE_TIME |
								     OP_S_RECYCLE_TIME | OP_G_STAT_SW | OP_S_PLAY_SOUND |
								     OP_S_STOP_SOUND =>
									state <= S_PAR1;
								when OP_S_DISP_FIRST to OP_S_DISP_LAST =>
									state <= S_PAR1;   -- par1 = Anzahl Ziffern
								when others =>
									state <= S_EXEC;
							end case;
						end if;

					-- Erstes Parameterbyte. Manche Opcodes wollen noch ein zweites,
					-- die Display-Befehle danach par1 Ziffernbytes.
					when S_PAR1 =>
						if rx_dv = '1' then
							par1 <= to_integer(unsigned(rx_byte));
							if opcode = OP_S_PULSE_TIME or opcode = OP_S_RECYCLE_TIME
							   or opcode = OP_S_PLAY_SOUND then
								state <= S_PAR2;
							elsif opcode >= OP_S_DISP_FIRST and opcode <= OP_S_DISP_LAST then
								dd_idx <= 0;
								if to_integer(unsigned(rx_byte)) = 0 then
									state <= S_OPCODE;   -- Laenge 0: nichts zu tun
								else
									state <= S_DISPDATA;
								end if;
							else
								state <= S_EXEC;
							end if;
						end if;

					when S_PAR2 =>
						if rx_dv = '1' then
							par2  <= to_integer(unsigned(rx_byte));
							state <= S_EXEC;
						end if;

					-- Ziffern eines Display-Befehls. Index 0 = zuerst gesendete Ziffer.
					when S_DISPDATA =>
						if rx_dv = '1' then
							d := opcode - OP_S_DISP_FIRST;
							-- Gegen DISP_DIGITS(d) pruefen und nicht gegen MAX_DIGITS:
							-- so werden Ziffernplaetze jenseits der tatsaechlichen Breite
							-- nie beschrieben und fallen bei der Synthese weg.
							if ctrl_r = '1' and d < N_DISP then
								if dd_idx < DISP_DIGITS(d) then
									disp_r(d * MAX_DIGITS + dd_idx) <= rx_byte(3 downto 0);
								end if;
							end if;
							if dd_idx >= par1 - 1 then
								state <= S_OPCODE;
							else
								dd_idx <= dd_idx + 1;
							end if;
						end if;

					-- Befehl ausfuehren und Antwort bereitlegen. tx_len = 0 heisst
					-- "keine Antwort" -- der Host wartet bei diesen Opcodes auch nicht.
					when S_EXEC =>
						tx_src <= SRC_BYTES;
						tx_len <= 0;
						tx_idx <= 0;
						resp   := x"00";

						case opcode is

							-- ---- Info-Gruppe: der Connect-Handshake ----
							when OP_G_HW =>
								tx_src <= SRC_HW;    tx_len <= HW_LEN;
							when OP_G_API_VER =>
								tx_src <= SRC_API;   tx_len <= API_LEN;
							when OP_G_LISY_VER =>
								tx_src <= SRC_VER;   tx_len <= 6;   -- "M.S1.S2" + NUL
							when OP_G_GAME_INFO =>
								tx_src <= SRC_GAME;  tx_len <= 2;   -- Ziffer + NUL
							when OP_G_NO_LAMPS =>
								tx_b0 <= to_byte(N_LAMPS);   tx_len <= 1;
							when OP_G_NO_SOL =>
								tx_b0 <= to_byte(N_SOL);     tx_len <= 1;
							when OP_G_NO_SOUNDS =>
								tx_b0 <= to_byte(N_SOUNDS);  tx_len <= 1;
							when OP_G_NO_DISP =>
								tx_b0 <= to_byte(N_DISP);    tx_len <= 1;
							when OP_G_NO_SW =>
								tx_b0 <= to_byte(N_SW);      tx_len <= 1;
							when OP_G_DISP_DETAIL =>
								-- Zwei Bytes: Typ, Stellen. Typ 0 = Display existiert nicht.
								if par1 < N_DISP then
									tx_b0 <= to_byte(DISP_TYPE);
									tx_b1 <= to_byte(DISP_DIGITS(par1));
								else
									tx_b0 <= x"00";
									tx_b1 <= x"00";
								end if;
								tx_len <= 2;

							-- ---- Zustand lesen: geht immer, auch ohne Uebernahme ----
							-- Die Bereichspruefungen stehen bewusst als geschachtelte ifs
							-- da und nicht als "par1 < N and vektor(par1)" -- sonst haengt
							-- die Gueltigkeit des Index an der Kurzschlussauswertung.
							when OP_G_STAT_LAMP =>
								if par1 < N_LAMPS then
									if lamp_r(par1) = '1' then
										resp := x"01";
									end if;
								end if;
								tx_b0 <= resp;  tx_len <= 1;
							when OP_G_STAT_SOL =>
								if par1 < N_SOL then
									if sol_r(par1) = '1' then
										resp := x"01";
									end if;
								end if;
								tx_b0 <= resp;  tx_len <= 1;
							when OP_G_STAT_SW =>
								if par1 < N_SW then
									if sw_state(par1) = '1' then
										resp := x"01";
									end if;
								end if;
								tx_b0 <= resp;  tx_len <= 1;
							when OP_G_CHANGED_SW =>
								if pend_valid = '1' then
									pv := pend_state & std_logic_vector(to_unsigned(pend_idx, 7));
									tx_b0      <= pv;
									pend_valid <= '0';
								else
									tx_b0 <= SW_NO_CHANGE;
								end if;
								tx_len <= 1;

							-- ---- Stellbefehle: nur mit Uebernahme, sonst folgenlos ----
							when OP_S_LAMP_ON =>
								if ctrl_r = '1' and par1 < N_LAMPS then
									lamp_r(par1) <= '1';
								end if;
							when OP_S_LAMP_OFF =>
								if ctrl_r = '1' and par1 < N_LAMPS then
									lamp_r(par1) <= '0';
								end if;
							when OP_S_SOL_ON =>
								if ctrl_r = '1' and par1 < N_SOL then
									sol_r(par1) <= '1';
								end if;
							when OP_S_SOL_OFF =>
								if ctrl_r = '1' and par1 < N_SOL then
									sol_r(par1)  <= '0';
									if pulse_idx = par1 then
										pulse_run <= '0';
									end if;
								end if;
							when OP_S_PULSE_SOL =>
								if ctrl_r = '1' and par1 < N_SOL then
									sol_r(par1) <= '1';
									pulse_idx   <= par1;
									pulse_left  <= pulse_ms;
									pulse_run   <= '1';
									-- Der Millisekunden-Takt laeuft frei weiter; die Pulszeit
									-- kann dadurch bis zu 1 ms zu kurz ausfallen. Bei 50 ms
									-- Vorgabe ist das ohne Belang.
								end if;
							when OP_S_PULSE_TIME =>
								-- Nummer (par1) wird bewusst ignoriert, s. Kopfkommentar.
								if par2 > 0 then
									pulse_ms <= par2;
								end if;
							when OP_S_RECYCLE_TIME =>
								null;   -- angenommen, ohne Wirkung
							when OP_S_PLAY_SOUND =>
								-- par1 = Track (LISY-Begriff, hier ohne Bedeutung), par2 = Nummer.
								if ctrl_r = '1' and par2 < N_SOUNDS then
									pv       := std_logic_vector(to_unsigned(par2, 8));
									snd_r    <= pv(3 downto 0);
									snd_en_r <= '1';
								end if;
							when OP_S_STOP_SOUND =>
								if ctrl_r = '1' then
									snd_en_r <= '0';
								end if;

							-- ---- Uebernahme anfordern ----
							when OP_INIT =>
								lamp_r     <= (others => '0');
								sol_r      <= (others => '0');
								disp_r     <= (others => x"F");
								snd_en_r   <= '0';
								pulse_run  <= '0';
								pulse_ms   <= PULSE_MS_DEF;
								-- Schalter-Meldung neu aufsetzen: der Host liest gleich
								-- ohnehin alle Zustaende einzeln ab (Opcode 40).
								sw_rep     <= sw_state;
								pend_valid <= '0';
								if ctrl_allow = '0' then
									ctrl_r <= '0';
									resp   := x"01";   -- Freigabe fehlt (DIP steht auf OFF)
								elsif req_sync = '1' then
									ctrl_r <= '0';
									resp   := x"02";   -- ctrl_req nicht angefordert
								else
									ctrl_r <= '1';
									resp   := x"00";   -- gewaehrt
								end if;
								tx_b0 <= resp;  tx_len <= 1;

							when OP_WATCHDOG | OP_BACK_READY =>
								tx_b0 <= x"00";  tx_len <= 1;

							when others =>
								-- Unbekannt: mit 0 quittieren (wie der WillFA7-Monitor)
								tx_b0 <= x"00";  tx_len <= 1;

						end case;

						state <= S_SEND_LOAD;

					-- ---- Sendeschleife ueber tx_buf(0 .. tx_len-1) ----
					when S_SEND_LOAD =>
						if tx_idx >= tx_len then
							state <= S_OPCODE;
						elsif tx_busy = '0' then
							tx_byte <= tx_next;
							tx_dv   <= '1';
							tx_idx  <= tx_idx + 1;
							state   <= S_SEND_DV;
						end if;

					when S_SEND_DV =>
						if tx_busy = '1' then
							state <= S_SEND_WAIT;
						end if;

					when S_SEND_WAIT =>
						if tx_busy = '0' then
							state <= S_SEND_LOAD;
						end if;

				end case;
			end if;
		end if;
	end process;

end rtl;
