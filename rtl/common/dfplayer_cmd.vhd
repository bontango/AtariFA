-- ============================================================
-- dfplayer_cmd.vhd
-- Kommando-Sender fuer den DFPlayer Mini (Bestueckung "Audio1" auf dem AtariFA-Board).
-- Teil von AtariFA -- bontango 08.2026
--
-- Zweck: Hintergrundmusik waehrend eines laufenden Spiels. Der Player haengt mit
-- seinem RX an der einzigen Steuerleitung SB_Audio; sein DAC geht direkt in den
-- Onboard-TDA7267. Es gibt KEINE Rueckleitung (kein BUSY, kein RX vom Player) --
-- der Zustand wird hier mitgefuehrt (Signal 'running').
--
-- Herkunft: portiert aus GottFA1_PLuS
--   N:\Projekte\FPGA System1\FPGA_source\rtl\common\DFPlayer_Mini_CMD.vhd (v0.5)
-- Unterschied: dort ein handgebautes 80-Bit-Schieberegister an einem 9600-Hz-Takt,
-- hier das im Baum vorhandene work.UART_TX (rtl/fa_control/uart_tx.vhd) in der
-- clk_50-Domaene -- kein zweiter Takt, nichts fuer die SDC zu tun.
--
-- Rahmenformat (10 Byte laut Datenblatt, davon 2 Pruefsummenbytes):
--   7E FF 06 <cmd> 00 <par1> <par2> [csumH csumL] EF
-- Wir senden wie GottFA nur die 8 Byte OHNE Pruefsumme -- der Player akzeptiert das,
-- im Feld seit GottFA1_PLuS erprobt.
--
-- Verwendete Kommandos:
--   0x42  Status abfragen  -- einmal nach dem Boot, weckt den Player
--   0x06  Lautstaerke      -- par2 = 0..30, nur wenn SET_VOLUME
--   0x17  repeat folder    -- par2 = FOLDER, spielt den Ordner in Endlosschleife
--   0x0D  play/resume      -- weiter an der alten Stelle
--   0x0E  pause
--
-- Trigger in AtariFA.vhd: Q12 = Flipper Control Relay (Latch 0x1088 Bit 6) = "Spiel
-- laeuft". Beleg: Space-Riders-Handbuch Tab. 5-6 "FLIPPER CONTROL RELAY (A)1088 D6",
-- Selbsttest Nr. 12 "Flipper Relay", docs/solenoid_mapping.txt solenoids(12), und im
-- Middle-Earth-ROM 7F36 (Spielstart: ORAA #$40) / 77BC (Game Over: CLR $1088).
-- Details: docs/Background_Music.md.
--
-- GLITCH_CYCLES ist die Entprellung des Triggers: der Wechsel wird erst nach der
-- Wartezeit erneut geprueft und nur dann uebernommen. Faengt kurze Relais-Aussetzer
-- ab und sorgt dafuer, dass ein einzelner Spulenpuls (FA-Control COILS, Kachel 12)
-- die Musik NICHT startet.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dfplayer_cmd is
	generic(
		CLKS_PER_BIT  : integer := 5208;      -- clk_50 / 9600 Baud
		START_DELAY   : integer := 100000000; -- 2 s @clk_50: Player-Boot abwarten
		GLITCH_CYCLES : integer := 25000000;  -- 500 ms Trigger-Entprellung
		FOLDER        : integer := 2;         -- SD-Ordner "02" (wie GottFA1_PLuS)
		SET_VOLUME    : boolean := true;      -- Lautstaerke einmalig setzen?
		VOLUME        : integer := 20         -- 0..30
	);
	port(
		clk_50    : in  std_logic;
		reset     : in  std_logic;            -- synchron, active-high
		trigger   : in  std_logic;            -- '1' = Spiel laeuft
		start_new : in  std_logic;            -- '1' = jedes Spiel von vorn beginnen
		txd       : out std_logic             -- an DFPlayer RX
	);
end dfplayer_cmd;

architecture rtl of dfplayer_cmd is

	type frame_t is array (0 to 7) of std_logic_vector(7 downto 0);
	type state_t is (st_Boot, st_InitCmd, st_Idle, st_Delay, st_Decide,
	                 st_Send, st_Wait);

	-- laengste Wartezeit bestimmt die Zaehlerbreite
	function max_i(a, b : integer) return integer is
	begin
		if a > b then return a; else return b; end if;
	end function;
	constant WAIT_MAX : integer := max_i(START_DELAY, GLITCH_CYCLES);

	signal state      : state_t := st_Boot;
	signal after_send : state_t := st_Idle;   -- Ziel nach dem letzten Rahmenbyte

	signal frame      : frame_t := (others => (others => '0'));
	signal byte_idx   : integer range 0 to 7 := 0;

	signal wait_cnt   : integer range 0 to WAIT_MAX := 0;
	signal init_step  : integer range 0 to 2 := 0;

	signal old_trigger : std_logic := '0';
	signal running     : std_logic := '0';    -- laeuft schon einmal Musik?

	signal tx_dv      : std_logic := '0';
	signal tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
	signal tx_done    : std_logic;
	signal tx_active  : std_logic;

begin

------------------------------------------------------------------------------
-- Serieller Sender: dasselbe Modul wie die ESP32-Strecke, nur mit 9600 Baud
-- (CLKS_PER_BIT = 5208 statt 434). o_TX_Active bleibt hier ungenutzt.
------------------------------------------------------------------------------
TX: entity work.UART_TX
generic map( g_CLKS_PER_BIT => CLKS_PER_BIT )
port map(
	i_Clk       => clk_50,
	i_TX_DV     => tx_dv,
	i_TX_Byte   => tx_byte,
	o_TX_Active => tx_active,
	o_TX_Serial => txd,
	o_TX_Done   => tx_done
);

------------------------------------------------------------------------------
-- Kommando-FSM
------------------------------------------------------------------------------
process(clk_50)
	-- baut den 8-Byte-Rahmen (ohne Pruefsumme, s. Kopf)
	procedure build(signal f : out frame_t;
	                cmd, par1, par2 : in std_logic_vector(7 downto 0)) is
	begin
		f(0) <= x"7E";   -- Startbyte
		f(1) <= x"FF";   -- Version
		f(2) <= x"06";   -- Laenge
		f(3) <= cmd;
		f(4) <= x"00";   -- kein Feedback
		f(5) <= par1;
		f(6) <= par2;
		f(7) <= x"EF";   -- Endbyte
	end procedure;
begin
	if rising_edge(clk_50) then
		tx_dv <= '0';                       -- Default: nur ein Takt lang aktiv

		if reset = '1' then
			state       <= st_Boot;
			after_send  <= st_Idle;
			byte_idx    <= 0;
			wait_cnt    <= 0;
			init_step   <= 0;
			old_trigger <= '0';
			running     <= '0';
		else
			case state is

			-- Player nach dem Einschalten hochlaufen lassen
			when st_Boot =>
				if wait_cnt >= START_DELAY then
					wait_cnt  <= 0;
					init_step <= 0;
					state     <= st_InitCmd;
				else
					wait_cnt <= wait_cnt + 1;
				end if;

			-- Init: Status abfragen, danach optional die Lautstaerke setzen
			when st_InitCmd =>
				byte_idx   <= 0;
				after_send <= st_InitCmd;
				if init_step = 0 then
					build(frame, x"42", x"00", x"00");
					init_step <= 1;
					state     <= st_Send;
				elsif init_step = 1 and SET_VOLUME then
					build(frame, x"06", x"00",
					      std_logic_vector(to_unsigned(VOLUME, 8)));
					init_step <= 2;
					state     <= st_Send;
				else
					state <= st_Idle;
				end if;

			-- Warten auf einen Wechsel von 'trigger'
			when st_Idle =>
				wait_cnt <= 0;
				if trigger /= old_trigger then
					state <= st_Delay;
				end if;

			-- Wechsel nach GLITCH_CYCLES erneut pruefen
			when st_Delay =>
				if wait_cnt >= GLITCH_CYCLES then
					wait_cnt <= 0;
					if trigger /= old_trigger then
						old_trigger <= trigger;
						state       <= st_Decide;
					else
						state <= st_Idle;    -- war ein Glitch
					end if;
				else
					wait_cnt <= wait_cnt + 1;
				end if;

			-- Kommando bestimmen
			when st_Decide =>
				byte_idx   <= 0;
				after_send <= st_Idle;
				if old_trigger = '1' then
					if running = '0' or start_new = '1' then
						-- Ordner in Endlosschleife starten
						build(frame, x"17", x"00",
						      std_logic_vector(to_unsigned(FOLDER, 8)));
						running <= '1';
					else
						build(frame, x"0D", x"00", x"00");  -- resume
					end if;
				else
					build(frame, x"0E", x"00", x"00");      -- pause
				end if;
				state <= st_Send;

			-- ein Byte anstossen. Erst losschicken, wenn UART_TX wirklich in s_Idle
			-- steht: waehrend s_Cleanup ist o_TX_Active noch '1', und im ersten
			-- s_Idle-Takt steht o_TX_Done noch an (2 Takte breit) -- in beiden
			-- Faellen wuerde ein 1-Takt-Puls auf i_TX_DV verpuffen.
			when st_Send =>
				if tx_active = '0' and tx_done = '0' then
					tx_byte <= frame(byte_idx);
					tx_dv   <= '1';
					state   <= st_Wait;
				end if;

			-- auf das Ende des Bytes warten, dann naechstes
			when st_Wait =>
				if tx_done = '1' then
					if byte_idx = 7 then
						byte_idx <= 0;
						state    <= after_send;
					else
						byte_idx <= byte_idx + 1;
						state    <= st_Send;
					end if;
				end if;

			end case;
		end if;
	end if;
end process;

end architecture rtl;
