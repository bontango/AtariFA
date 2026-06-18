-- 'AtariFA' a Atari Gen1 MPU on a low cost FPGA
-- Atarians, Time 2000, Airborne Avenger, Middle Earth, Space Riders.
-- Ralf Thelen 'bontango' June 2026
-- www.lisy.dev
--
-- The central part of the replacement CPU is a self designed 'piggy back'
-- FPGA board with a Cyclone 10 (10CL006YE144C8G) https://lisy.dev/cyclone10-dev-board.html
-- It emulates the 6800 CPU, provides ram & rom and replaces parts
-- of the TTL chips ( mainly for address latches )
-- parallel to the Atari edge connectors AtariFA do provide alternative 'Box Connectors'
--
-- hardware design by categorie
--
-- 1) general on board components
-- reset switch ( parallel to FPGA board switch)
-- 3 LEDs for status ( parallel to FPGA board LEDs)
-- 10 DIP switches: 4er bank (3 game select + 1 freeplay) + 6er bank (options)
--   first 6 DIPs read at boot via 3x2 strobe matrix (read_the_dips), last 4 (options 3..6) read directly
--
-- 2) display interface ( 4 x 6digit 7segment & 1 x 4digit 7segment )
-- interface to original Atari displays ( score & status)
-- driven by 74HCT540 (inverter)
--
-- 3) switches
-- 1:1 implementation of Atari design with 10x 74LS145 selected by a 74HCT42
-- 1:1 implementation of special handling (glitch filter) of Start,Coin1,Coin2 and Slam Switches
-- 1:1 implementation of onboard programming DIP banks ( 2x8Dips) and hex switch for 'Replay'
-- additional parallel onboard switches for 'Atari Test', 'coin2' and 'start' for easy testing
-- inputs of 74HCT42 ( 4 IOs) and common A,B,C inputs (3 IOs) of 74LS145 driven by 74HCT540 (inverter)
-- switch common input signal connected to FPGA via 74HC4049 level shifter (inverter)
--
-- 4) lamps
-- 1:1 implementation of Atari design with 12 x ULN2003A drivers ( 21x4 lamp matrix for 84 lamps)
-- inputs of ULN2003A or grouped by 4 inputs, selection is done by a cascade of three 74HC595
-- SERIN, CLK, RCLK and OE/ signals are driven by a 74HCT541 ( only non inverted driver on the board!)
-- the 4 lamp strobes are provided by the Atari 'Auxilary Board' ( interface see below)
-- parallel to the Atari edge connectors there 2x25 pins 'Box connectors' for testing purposes
-- the box connectors do also provide the 4 lamp strobes ( driven by four P-Channel Mosfets, Testleds only! )
--
-- 5) solenoids
-- 20 N-Channel MOSFETs (IRL540) driven by 74HCT540 (inverter)
-- The 74HCT540 enable signal for the solenoids is driven by a 74HCT541 ( non inverting)
-- onboard fuseholders for 2A slow blow fuses
--
-- 6) auxilary board interface
-- interface to original Atari auxilary board ( Lamp strobes, Audio, Audio latches, coin door switches input)
-- output signals driven by 74HCT540 (inverter), enable via 'solenoids_enable' (routed through the 74HCT541)
--
-- 7) FRAM
-- I2C FRAM chip (FM24CL64B-GTR) for saving highscores ( Atari do not have a CMOS battery backup)
--
-- 8) integrated sound
-- additional to the sound on Atari auxilary board AtariFA do provide an internal soundcard
-- with an audio amplifier (TDA7267) and an MP3-Mini-Player for Background audio
--
-- 9) ESP32-C3 interface 
-- AtariFA do provide an optional serial interface for an ESP32-C3 ( ESP32-C3 Supper Mini )
-- The ESP32 will provide a Web Interface for easy testing
--
-- 10) debug ports
-- 8 debug ports via 10pin connector for direct connecting Logic Analyzer
--

-- version for AtariFA PCB



LIBRARY ieee;
USE ieee.std_logic_1164.all;

package instruction_buffer_type is
	type DISPLAY_T is array (0 to 6) of std_logic_vector(3 downto 0); -- digit #6 is Player up LEDS
	type DISPLAY_TS is array (0 to 3) of std_logic_vector(3 downto 0);
end package instruction_buffer_type;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.instruction_buffer_type.all;

entity AtariFA is
	port(		

		
	   -- 1) general
		clk_50	: in std_logic;
		reset_sw  : in std_logic;
		LED_D1 	: out STD_LOGIC; -- active low
		LED_D2 	: out STD_LOGIC; -- active low
		LED_D3 	: out STD_LOGIC; -- active low
		
		-- 4 DIPs bank game select; 6 DIPs bank options
		-- first 6 DIPs matrix, last 4 DIPs direct
		dip_ret: in	std_logic_vector(1 downto 0);
		dip_opt: in	std_logic_vector(1 to 4);

		-- 2) display interface
		disp_Data: out 	std_logic_vector(3 downto 0);
		disp_Adr: out 	std_logic_vector(6 downto 0);
		disp_Load			: 	out 	std_logic;
		disp_Cathode_blank			: 	out 	std_logic;
		disp_Anode_blank			: 	out 	std_logic;

		-- 3) switches
		sw_strobe: out 	std_logic_vector(3 downto 0);
		sw_com: out 	std_logic_vector(2 downto 0);
		sw_com_in: in std_logic;
		
		-- 4) lamps
		serin_595			: 	out 	std_logic; -- DIP strobe1 while boot_phase(1)='0' (DIP read window), else lamp serin
		clk_595			: 	out 	std_logic; -- DIP strobe2 while boot_phase(1)='0' (DIP read window), else lamp clk
		rclk_595			: 	out 	std_logic; -- DIP strobe3 while boot_phase(1)='0' (DIP read window), else lamp rclk
		oe_595			: 	out 	std_logic; -- active low
		
		-- 5) solenoids
		solenoids		: out 	std_logic_vector(1 to 20);
		solenoids_enable		: out std_logic;
		
		-- 6) auxilary board interface
		aux_lamp_strobe: out 	std_logic_vector(1 downto 0);
		aux_audio: out 	std_logic_vector(3 downto 0);
		aux_audio_latch: out 	std_logic_vector(5 downto 0);
		
		-- 7) FRAM
		fram_i2c_sda		: inout std_logic;  -- I2C SDA: bidirektional/open-drain (ACK + Read-Back)
		fram_i2c_scl		: out std_logic;
		
		-- 8) integrated sound
		SB_Audio	: out std_logic;
		SB_Sound	: out std_logic;

		-- 9) ESP32-C3 interface 
		ESP32_ser_tx	: in std_logic;				
		ESP32_ser_rx	: out std_logic;				
		ESP32_sig   	: out std_logic;				

		-- 10) debug ports
		debug_signal	: out std_logic_vector(7 downto 0)
		
		);
end;

architecture rtl of AtariFA is 

-- SW version (reserved): not yet read anywhere. Intended to be made readable later
-- (e.g. via a DIP/debug read address or the ESP32 link) so software can query the version.
constant SW_MAIN : std_logic_vector(3 downto 0) := x"0";
constant SW_SUB1 : std_logic_vector(3 downto 0) := x"0";
constant SW_SUB2 : std_logic_vector(3 downto 0) := x"2";

--internal signals via logic
signal reset_h		: 	std_logic;
signal reset_l_stable	:	std_logic; 
signal cpu_clk		:  std_logic; 

signal cpu_addr	: 	std_logic_vector(15 downto 0);
signal cpu_din		: 	std_logic_vector(7 downto 0) := x"FF";
signal cpu_dout	: 	std_logic_vector(7 downto 0);
signal cpu_rw		: 	std_logic;
signal cpu_vma		: 	std_logic;  --valid memory address
signal cpu_irq		: 	std_logic;

signal ram_dout		: std_logic_vector(7 downto 0);
signal ram_cs			: std_logic;
signal ram_cs_mirror			: std_logic;
signal ram_cs_normal			: std_logic;

signal rom1_dout		: std_logic_vector(7 downto 0);
signal rom1_cs			: std_logic;
signal rom2_dout		: std_logic_vector(7 downto 0);
signal rom2_cs			: std_logic;

-- helpers DIP read & boot phase
signal dip_strobe  : std_logic_vector(2 downto 0);
signal g_serin_595 : std_logic := '0';
signal g_clk_595 : std_logic := '0';
signal g_rclk_595 : std_logic := '0';
signal boot_phase	: 	std_logic_vector(3 downto 0) := "0000";
signal game_select : std_logic_vector(2 downto 0);
signal freeplay 	 : std_logic;
-- options(1..2) from matrix (read_the_dips), options(3..6) direct from dip_opt.
-- Reserved for future use (Phase B/C) -- currently assigned but not yet read anywhere.
signal options		 : std_logic_vector(1 to 6);

-- Game-Select: 5 Spiele gleichzeitig im BRAM, ROM1/ROM2-Ausgang per Mux gewaehlt.
-- game_select ist active-low (10K-Pullup an 3,3V, Schalter gegen GND; ON=geschlossen='0').
-- Annahme: Schalter1 = game_select(0) = LSB  ->  game_idx = not game_select.
type rom_byte_array is array(0 to 4) of std_logic_vector(7 downto 0);
signal rom1_douts	: rom_byte_array;   -- 0=Atarians 1=Time 2=Airborne 3=MiddleEarth 4=SpaceRiders
signal rom2_douts	: rom_byte_array;
signal rom1_sel		: std_logic_vector(7 downto 0);   -- roher Game-Mux-Ausgang (vor Freispiel-Overlay)
signal rom2_sel		: std_logic_vector(7 downto 0);
signal game_idx		: integer range 0 to 7;
signal game_sel		: integer range 0 to 4;   -- geklemmt: unbenutzte Codes 5..7 -> 3 (Middle Earth)

-- Freispiel-Overlay: statt 6 zweite ROMs (=+12 M9K, passt nicht) werden die wenigen
-- gepatchten Bytes kombinatorisch ueberlagert, wenn freeplay=Freispiel aktiv (active-low).
-- 42 Bytes, Quelle: Diff rom/<orig> vs rom/freeplay/<orig+f> (validiert: Basis+Patch == Freeplay-ROM).
type fp_patch_t is record
	game : integer range 0 to 4;     -- 0=Atarians 1=Time 2=Airborne 3=MiddleEarth 4=SpaceRiders
	slot : integer range 1 to 2;     -- 1=ROM1 (E0), 2=ROM2 (E00)
	addr : integer range 0 to 2047;  -- ROM-Offset = cpu_addr(10 downto 0)
	data : std_logic_vector(7 downto 0);
end record;
type fp_patch_array_t is array(natural range <>) of fp_patch_t;
constant FP_PATCHES : fp_patch_array_t := (
	-- Atarians ROM2 (atarianf.e00) 0x1DA..0x1E1
	(0,2,16#1DA#,x"B6"),(0,2,16#1DB#,x"00"),(0,2,16#1DC#,x"E0"),(0,2,16#1DD#,x"4C"),
	(0,2,16#1DE#,x"97"),(0,2,16#1DF#,x"CE"),(0,2,16#1E0#,x"4F"),(0,2,16#1E1#,x"01"),
	-- Time 2000 ROM2 (timef.e00) 0x721..0x728
	(1,2,16#721#,x"B6"),(1,2,16#722#,x"00"),(1,2,16#723#,x"CA"),(1,2,16#724#,x"4C"),
	(1,2,16#725#,x"97"),(1,2,16#726#,x"D6"),(1,2,16#727#,x"4F"),(1,2,16#728#,x"01"),
	-- Airborne ROM1 (airbornef.e0) 0x77C..0x781
	(2,1,16#77C#,x"B6"),(2,1,16#77D#,x"00"),(2,1,16#77E#,x"BC"),(2,1,16#77F#,x"97"),
	(2,1,16#780#,x"D5"),(2,1,16#781#,x"39"),
	-- Middle Earth ROM2 (609f) 0x171..0x178
	(3,2,16#171#,x"B6"),(3,2,16#172#,x"00"),(3,2,16#173#,x"1A"),(3,2,16#174#,x"97"),
	(3,2,16#175#,x"1D"),(3,2,16#176#,x"01"),(3,2,16#177#,x"01"),(3,2,16#178#,x"01"),
	-- Space Riders ROM1 (spacelf) 0x1EB..0x1F0 + 0x7F7
	(4,1,16#1EB#,x"00"),(4,1,16#1EC#,x"A8"),(4,1,16#1ED#,x"97"),(4,1,16#1EE#,x"B7"),
	(4,1,16#1EF#,x"01"),(4,1,16#1F0#,x"01"),(4,1,16#7F7#,x"90"),
	-- Space Riders ROM2 (spacerf) 0x000 + 0x752..0x755
	(4,2,16#000#,x"42"),(4,2,16#752#,x"97"),(4,2,16#753#,x"04"),(4,2,16#754#,x"96"),
	(4,2,16#755#,x"B7")
);

signal dma_clk		: std_logic;
signal audio_clk		: std_logic;
signal dma_int		: std_logic;

signal cpu_clk_d1	: std_logic := '0';
signal cpu_clk_d2	: std_logic := '0';
signal ram_wren		: std_logic := '0';

signal wd_cs		: std_logic;
signal wd_kick		: std_logic := '0';
signal wd_reset		: std_logic;

signal dma_counter		: std_logic_vector(8 downto 0) := (others => '0');
signal nmi_level		: std_logic := '0';
signal nmi_level_d		: std_logic := '0';
signal dma_count2		: std_logic := '0';
signal dma_toggle		: std_logic := '0';

signal sw_cs			: std_logic;
signal dip_cs			: std_logic;
signal dip_value		: std_logic_vector(7 downto 0);

-- NVRAM: fake NVRAM byte 0x0200 (PinMAME: generic_nvram, 1 byte)
signal nvram_cs		: std_logic;
signal nvram_wren		: std_logic := '0';
signal nvram_dout		: std_logic_vector(7 downto 0) := x"00";

--display testboard
signal i_disp_Data: std_logic_vector(3 downto 0);
signal i_disp_Adr: 	std_logic_vector(6 downto 0);
signal i_disp_Load			: 		std_logic;
signal i_disp_Cathode_blank			: 		std_logic;
signal i_disp_Anode_blank			: 	std_logic;

				-- input (display data)
signal   display1			: DISPLAY_T;
signal	display2			: DISPLAY_T;
signal	display3			: DISPLAY_T;
signal	display4			: DISPLAY_T;
signal	status_d			: DISPLAY_TS;


-- Diagnose / Verifikation ---------------------------------------------------
-- DISPLAY_TEST: true = disp_test 0→9-Zählmuster (unabhängig vom Game-Code)
--               false = normaler Game-Betrieb (Write-Sniffer aus CPU-RAM)
constant DISPLAY_TEST : boolean := false;
-- (DIAG_SEL/hex7seg entfernt: gehörten zum GottFA3-Testboard mit BCD-SEG7-Anzeige;
--  die Zielplatine hat keinen SEG7-Port. Diagnose läuft hier über debug_signal/LEDs.)
-- DBG_MODE: wählt Belegung debug_signal[7:0] am LA-Header
--   0 = Standard-Mix (cpu_clk/vma/rw/ram_wren/NMI/wd_reset/dma_toggle/rom_cs)
--   1 = cpu_addr(7:0)  — PC-Low-Byte; steht → hängt an diesem Offset in der Page
--   2 = cpu_addr(15:8) — PC-High-Byte; steht → hängt in dieser ROM/RAM-Page
constant DBG_MODE : integer range 0 to 2 := 0;
signal heartbeat_div  : std_logic_vector(24 downto 0) := (others => '0');
   -- Bit 24 toggelt alle 2^24/50e6 ≈ 0.67s → ~0.75 Hz Heartbeat; nur als FPGA-Takt-Fallback genutzt
signal cpu_fetch_cnt  : std_logic_vector(20 downto 0) := (others => '0');
   -- Zählt ROM-CS-Steigeflanken in clk_50; Bit 20 → ~0.6 Hz auf LED_D2 wenn CPU fetcht
   -- (1 MHz cpu_clk, ~1 Fetch/Zyklus → 2^20/50e6 ≈ 0.021s per Bit; Bit20=~21ms*2≈42ms Wait)
   -- Steht LED_D2 dauerhaft: CPU macht keine ROM-Fetches (halted/hängt in RAM/Busy-Loop ohne ROM)
signal rom_cs_d       : std_logic := '0';
   -- Edge-Detect für cpu_fetch_cnt
signal nmi_blink_cnt  : std_logic_vector(11 downto 0) := (others => '0');
   -- Zählt NMI-Generator-Flanken; Bit 11 ≈ 0.48 Hz auf LED_D3 (HW-NMI-Takt, unabhängig von CPU)
signal wd_seen        : std_logic := '0';
   -- Sticky-Latch: '1' wenn Watchdog mind. einmal resettet hat (LED_D1)
signal por_count      : integer range 0 to 50001 := 0;
signal por_active     : std_logic := '1';
   -- Power-on-Reset: hält CPU für 50 000 clk_50-Takte (1 ms) nach Konfiguration im Reset

-- Taster-Synchronizer (2-FF, clk_50-Domäne) — adressiert B4 für die genutzten Eingänge
-- switch[1]=Test, switch[2]=Coin1, switch[3]=Coin2, switch[4]=Start (aktiv-LOW, Pull-up idle='1')
-- HINWEIS: Der 2-FF-Sync-Prozess (sw_meta->sw_sync aus den HW-Switch-Eingängen) ist in dieser
-- Version NICHT vorhanden -> sw_sync bleibt konstant auf Default (alle '1' = idle), die Switch-
-- Eingänge (Test/Coin1/Coin2/Start) sind damit aktuell wirkungslos (Quartus-Warning 10540).
-- Bewusst offen: das Switch-Design muss ohnehin an die neue AtariFA-HW angepasst werden (Phase B).
signal sw_meta        : std_logic_vector(16 downto 1) := (others => '1');
signal sw_sync        : std_logic_vector(16 downto 1) := (others => '1');
-- Dekodierter Switch-Matrix-Wert für cpu_din (gedrückt=0xFF, idle=0x00, non-inverted laut PinMAME swg1_r)
signal sw_value       : std_logic_vector(7 downto 0);

-- ---------------------------------------------------------------------------

begin

-- 8-Kanal-LA auf debug_signal[7:0] — Belegung per DBG_MODE-Konstante wählbar:
-- DBG_MODE=0 (Standard-Mix):
--  [0] cpu_clk    1 MHz Dauertakt     — steht: PLL/Takt tot
--  [1] cpu_vma    CPU-Buszugriffe     — dauerhaft 0: CPU halted/hängt
--  [2] cpu_rw     Read(1)/Write(0)    — zeigt Lese-/Schreibphasen
--  [3] ram_wren   RAM-Schreibstrobe   — nie: CPU schreibt nichts
--  [4] NMI-Puls   alle 512 µs        — fehlt: Attract-Timer zählt nie (Ursache 1)
--  [5] wd_reset   Watchdog-Reset      — pulst periodisch: Watchdog-Loop (Ursache 3)
--  [6] dma_toggle DMA-Toggle-Bit      — steht: Game hängt am DMA-Toggle (Ursache 2)
--  [7] ROM-CS     CPU in ROM          — wechselt mit RAM/IO: CPU läuft
-- DBG_MODE=1: cpu_addr(7:0)   → PC-Low-Byte stehend am LA ablesen
-- DBG_MODE=2: cpu_addr(15:8)  → PC-High-Byte stehend am LA ablesen
gen_dbg0: if DBG_MODE = 0 generate
	debug_signal(0) <= cpu_clk;
	debug_signal(1) <= cpu_vma;
	debug_signal(2) <= cpu_rw;
	debug_signal(3) <= ram_wren;
	debug_signal(4) <= not dma_int;   -- NMI-Puls (aktiv-high für LA sichtbar)
	debug_signal(5) <= wd_reset;
	debug_signal(6) <= dma_toggle;
	debug_signal(7) <= rom1_cs or rom2_cs;
end generate gen_dbg0;
gen_dbg1: if DBG_MODE = 1 generate
	debug_signal <= cpu_addr(7 downto 0);
end generate gen_dbg1;
gen_dbg2: if DBG_MODE = 2 generate
	debug_signal <= cpu_addr(15 downto 8);
end generate gen_dbg2;

-------------------------------
reset_l_stable <= boot_phase(1); --may be set higher if new boot phases added
reset_h <= (not reset_l_stable) or por_active;
   -- WD deliberately disconnected: Game kickt 0x4000 nicht im Attract Mode → permanenter Reset-Loop.
   -- Reaktivieren (or wd_reset) sobald Kick-Bedingung aus Schaltplan/ROM-Disassembly bekannt.

-- LEDs (Schnell-Diagnose ohne LA) — Board-LEDs aktiv-LOW (gegen VCC, Pin nach GND => leuchten bei '0')
LED_D1   <= not wd_seen;           -- Watchdog-Sticky: leuchtet wenn WD mind. 1x resettet hat
LED_D2   <= not cpu_fetch_cnt(20); -- CPU-Fetch-Blinker ~0.6 Hz: blinkt = cpu68 fetcht ROM-Befehle
                                    -- (steht dauerhaft: CPU halted oder hängt ohne ROM-Zugriff)
LED_D3   <= not nmi_blink_cnt(11); -- NMI-Generator-Blinker ~0.48 Hz: blinkt = HW-NMI-Takt läuft
                                    -- (unabhängig von CPU; Freilauf aus dma_counter)

-- use some IOs to read dips at start
-- Route the matrix strobes to the lamp IOs only DURING the DIP read window.
-- Gate on boot_phase(1) (= read_the_dips 'done'): '0' while reading, '1' once finished.
-- (Gating on boot_phase(0) was wrong: boot_phase(0) is the synchronized reset_sw AND the
--  FSM reset, so the FSM only runs when boot_phase(0)='1' -- exactly when the old mux routed
--  g_*_595 instead of dip_strobe, so the strobes never reached the pins.)
serin_595 <= dip_strobe(0) when boot_phase(1) = '0' else g_serin_595;
clk_595 <= dip_strobe(1) when boot_phase(1) = '0' else g_clk_595;
rclk_595 <= dip_strobe(2) when boot_phase(1) = '0' else g_rclk_595;
options(3 to 6) <= dip_opt(1 to 4);
RDIPS: entity work.read_the_dips
port map(
	clk_in		=> cpu_clk,
	-- Hold the DIP-read FSM in reset during boot_phase(0)=0 AND during power-on-reset,
	-- so the (terminal) DIP latch happens only after the PLL has locked and inputs settled.
	i_Rst_L  => boot_phase(0) and not por_active,
	--output 
	game_select	=> game_select,
	freeplay => freeplay,
	game_option	=> options(1 to 2),
	-- strobes
	dip_strobe => dip_strobe,
	-- input
	return1 => dip_ret(0),
	return2 => dip_ret(1),
	-- signal when finished
	done	=> boot_phase(1) -- set to '1' when reading dips is done
);		



----output reversed because of 74HCT540 drivers
disp_Data <= not i_disp_Data;
disp_Adr <= not i_disp_Adr;
disp_Load <= not i_disp_Load;
disp_Cathode_blank <= not i_disp_Cathode_blank;
disp_Anode_blank <= not i_disp_Anode_blank;

------------------------------------------------------------------------------
-- Sichere Inaktiv-Pegel fuer noch nicht implementierte Ausgaenge (Phase B/C).
-- Ohne diese Zuweisungen zieht Quartus undriven Outputs auf '0'. Ueber den
-- INVERTIERENDEN 74HCT540 wuerde '0' die Solenoid-MOSFETs EINschalten. Daher
-- jeden ungenutzten Ausgang explizit inaktiv treiben, damit die Platine schon
-- vor der Phase-B/C-Verdrahtung sicher ist.
------------------------------------------------------------------------------
-- Solenoide: invertierender 74HCT540 -> FPGA '1' => 540-Ausgang '0' => Gate low => MOSFET AUS.
-- Das ist der harte Sicherheitsnetz-Pegel, unabhaengig vom Enable.
solenoids        <= (others => '1');
-- solenoids_enable: laeuft ueber den NICHT invertierenden 74HCT541 an die active-low
-- /OE der 74HCT540 (Solenoid-MOSFETs UND Aux-Board). '1' => /OE high => 540 disabled
-- (hochohmig) => Gate-Pulldowns halten MOSFETs AUS, Aux-Ausgaenge inaktiv.
solenoids_enable <= '1';
-- Lampentreiber (TPIC6B595): oe_595 ist aktiv-low -> '1' = Ausgaenge disabled.
oe_595    <= '1';
g_serin_595 <= '0';
g_clk_595   <= '0';
g_rclk_595  <= '0';
-- Switch-Matrix-Strobes (Phase B): Idle
sw_strobe <= (others => '0');
sw_com    <= (others => '0');
-- Aux-Board (ueber invertierenden 74HCT540, gated von solenoids_enable): solange der
-- 540 disabled ist, definieren die aux-seitigen Pulls den Pegel; Werte hier nur Idle.
aux_lamp_strobe <= (others => '0');
aux_audio       <= (others => '0');
aux_audio_latch <= (others => '0');
-- Integrierter Sound (Phase C): Idle
SB_Audio <= '0';
SB_Sound <= '0';
-- FRAM I2C: Open-Drain im Leerlauf freigeben (externer Pull-up zieht high); SCL idle high.
fram_i2c_sda <= 'Z';
fram_i2c_scl <= '1';
-- ESP32-Link: UART-Leitung ruht HIGH; Signalpin Idle low.
ESP32_ser_rx <= '1';
ESP32_sig    <= '0';
------------------------------------------------------------------------------


DC: entity work.display_control
port map(
	clk		=> cpu_clk, 	
	show => reset_l_stable,
	-- Control/Data Signals,
	disp_Data => i_disp_Data,
	disp_Adr => i_disp_Adr,
	disp_Load => i_disp_Load,
	disp_Cathode_blank => i_disp_Cathode_blank, --C11 -> DSTB Pin1 on K4
	disp_Anode_blank => i_disp_Anode_blank,
	-- input (display data)
	-- digit #6 is Player up LEDS 8==ON 0==OFF
	display1	=> display1,
	display2	=> display2,
	display3	=> display3,
	display4	=> display4,
	status_d	=> status_d
	);
	

gen_disptest : if DISPLAY_TEST generate
DT: entity work.disp_test
port map(
	clk		=> cpu_clk,
	show => reset_l_stable,
	display1	=> display1,
	display2	=> display2,
	display3	=> display3,
	display4	=> display4,
	status_d	=> status_d
	);
end generate gen_disptest;


------------------------------
-- DMA interrupt counter (9-bit synchronous, replaces 3x SN7493 ripple chain)
-- counts cpu_clk rising edges in clk_50 domain; NMI period = 512 cpu_clk = 512 us
------------------------------
dma_clk   <= dma_counter(0);  -- reserved
audio_clk <= dma_counter(2);  -- reserved for Phase C audio
dma_int   <= not (dma_counter(7) and dma_counter(8));
nmi_level <= dma_counter(7) and dma_counter(8);

-- DIP read: 0x2000 bit6 = dma_toggle (display-sync, polled at 0x78BE/0x78C9 in ROM1);
--   bit7=0 (BPL check at 0x721C passes), bits5-0=1 (active-low pull-ups).
-- 0x200B = Atari Test switch: idle sw_sync(1)='1'→0xFF (normal boot), gedrückt '0'→0x00 (888888-Test, 7F9C in ROM1).
-- 0x2001-0x200F (excl. 0x200B): all 1 = DIP switches open / switches not pressed (active-low).
dip_value <= "0" & dma_toggle & "111111" when cpu_addr = x"2000" else
             (others => sw_sync(1))      when cpu_addr = x"200B" else  -- Test-Taster: idle→FF, gedrückt→00
             x"FF";

------------------------------
-- Watchdog (0x4000 write)
------------------------------
WD: entity work.watchdog
generic map (
	RESET_WIDTH => 800    -- 16 µs @ 50 MHz
)
port map(
	clk      => clk_50,
	rst_l    => reset_l_stable,
	kick     => wd_kick,
	wd_reset => wd_reset
);

----------------------
-- address decoding
----------------------

wd_cs     <= '1' when cpu_addr = x"4000" else '0';
sw_cs     <= '1' when cpu_addr >= x"2010" and cpu_addr <= x"204F" and cpu_vma='1' else '0';
dip_cs    <= '1' when cpu_addr(15 downto 4) = x"200" and cpu_vma='1' else '0';  -- 0x2000-0x200F
-- NVRAM 0x0200: 1 Byte fake NVRAM (PinMAME generic_nvram); read-back als Register
nvram_cs  <= '1' when cpu_addr = x"0200" and cpu_vma='1' else '0';

-- RAM -- 0x0000, 0x01FF and mirror at 0x1000-0x11FF
ram_cs_normal <= '1' when cpu_addr(15 downto 9) = "0000000" and cpu_vma='1' else '0';
ram_cs_mirror <= '1' when cpu_addr(15 downto 9) = "0001000" and cpu_vma='1' else '0';
ram_cs <= ram_cs_normal or ram_cs_mirror;

--E0_ROM: entity work.ROM1 --2K 0x7800, 0x0800 & 0xf800, 0x0800
rom1_cs <= '1' when ( cpu_addr(15 downto 11) = "01111" or cpu_addr(15 downto 11) = "11111") and cpu_vma='1' else '0';
--E00_ROM: entity work.ROM2 --2K 0x7000, 0x0800
rom2_cs <= '1' when cpu_addr(15 downto 11) = "01110" and cpu_vma='1' else '0';

-- sw_value: Switch-Matrix-Dekodierung (aktiv-low Taster invertiert auf PinMAME-Pegel gedrückt=0xFF/idle=0x00)
-- switch[2]=Coin1→$2010, switch[3]=Coin2→$2011, switch[4]=Start→$2013; übrige Rows idle=0x00.
sw_value <= (others => not sw_sync(2)) when cpu_addr = x"2010" else  -- Coin1
            (others => not sw_sync(3)) when cpu_addr = x"2011" else  -- Coin2
            (others => not sw_sync(4)) when cpu_addr = x"2013" else  -- Start
            x"00";                                                    -- alle übrigen SW-Rows idle

-- Bus control
cpu_din <=
	ram_dout  when ram_cs   = '1' else
	rom1_dout when rom1_cs  = '1' else
	rom2_dout when rom2_cs  = '1' else
	sw_value  when sw_cs    = '1' else  -- Gen1 swg1_r: idle=0x00, pressed=0xFF; Taster aktiv-low invertiert
	dip_value when dip_cs   = '1' else  -- DIPs + DMA toggle bit at 0x2000; Test-Taster bei 0x200B
	nvram_dout when nvram_cs = '1' else  -- fake NVRAM byte 0x0200
	x"FF";
	
-- B2: synchroner RAM-Write-Strobe (clk_50-Domain)
-- cpu_clk (PLL) wird in clk_50 einsynchronisiert; fallende Flanke = ein Puls
-- wenn cpu_addr/cpu_dout nach der cpu68-Taktflanke stabil sind.
process(clk_50)
begin
	if rising_edge(clk_50) then
		cpu_clk_d1 <= cpu_clk;
		cpu_clk_d2 <= cpu_clk_d1;
		ram_wren  <= ram_cs  and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
		wd_kick   <= wd_cs   and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
		nvram_wren <= nvram_cs and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
		-- NVRAM latch: 1-Byte-Register, schreibbar analog RAM-Write-Strobe
		if nvram_cs = '1' and cpu_rw = '0' and (cpu_clk_d2 = '1' and cpu_clk_d1 = '0') then
			nvram_dout <= cpu_dout;
		end if;
		if reset_l_stable = '0' then
			dma_counter <= (others => '0');
			dma_count2  <= '0';
			dma_toggle  <= '0';
			nmi_level_d <= '0';
		else
			if cpu_clk_d1 = '1' and cpu_clk_d2 = '0' then
				dma_counter <= dma_counter + 1;
			end if;
			nmi_level_d <= nmi_level;
			if nmi_level = '1' and nmi_level_d = '0' then
				if dma_count2 = '1' then
					dma_count2 <= '0';
					dma_toggle <= not dma_toggle;
				else
					dma_count2 <= '1';
				end if;
			end if;
		end if;
	end if;
end process;

-- display shadow buffer: sniff CPU writes to display RAM (0x00-0x1F)
-- captures BCD nibbles written by the game ROM into display1..4 and status_d
-- Mapping verifiziert gegen PinMAME atari.c ram_w (Gen1):
--   0x00-0x0F: Score; offset%4==3 (0x03/07/0B/0F): player-up light → display(6)
--   0x1C-0x1D: Match/Credit → status_d. Range, player-up, match/credit ✓
--   Segment-Reihenfolge: absteigend (30-offset*2) → HW-Feintuning Ziffernfolge noch offen
-- disabled when DISPLAY_TEST=true to avoid multiple-driver conflict with disp_test
gen_gamedisp : if not DISPLAY_TEST generate
process(clk_50)
begin
	if rising_edge(clk_50) then
		if ram_wren = '1' and cpu_addr(8 downto 5) = "0000" then
			case cpu_addr(4 downto 0) is
				-- Player 1 score: RAM 0x00, 0x01, 0x02
				when "00000" => display1(0) <= cpu_dout(7 downto 4); display1(1) <= cpu_dout(3 downto 0);
				when "00001" => display1(2) <= cpu_dout(7 downto 4); display1(3) <= cpu_dout(3 downto 0);
				when "00010" => display1(4) <= cpu_dout(7 downto 4); display1(5) <= cpu_dout(3 downto 0);
				when "00011" => display1(6) <= cpu_dout(3 downto 0);  -- Player 1 up LED (8=on,0=off)
				-- Player 2 score: RAM 0x04, 0x05, 0x06
				when "00100" => display2(0) <= cpu_dout(7 downto 4); display2(1) <= cpu_dout(3 downto 0);
				when "00101" => display2(2) <= cpu_dout(7 downto 4); display2(3) <= cpu_dout(3 downto 0);
				when "00110" => display2(4) <= cpu_dout(7 downto 4); display2(5) <= cpu_dout(3 downto 0);
				when "00111" => display2(6) <= cpu_dout(3 downto 0);  -- Player 2 up LED
				-- Player 3 score: RAM 0x08, 0x09, 0x0A
				when "01000" => display3(0) <= cpu_dout(7 downto 4); display3(1) <= cpu_dout(3 downto 0);
				when "01001" => display3(2) <= cpu_dout(7 downto 4); display3(3) <= cpu_dout(3 downto 0);
				when "01010" => display3(4) <= cpu_dout(7 downto 4); display3(5) <= cpu_dout(3 downto 0);
				when "01011" => display3(6) <= cpu_dout(3 downto 0);  -- Player 3 up LED
				-- Player 4 score: RAM 0x0C, 0x0D, 0x0E
				when "01100" => display4(0) <= cpu_dout(7 downto 4); display4(1) <= cpu_dout(3 downto 0);
				when "01101" => display4(2) <= cpu_dout(7 downto 4); display4(3) <= cpu_dout(3 downto 0);
				when "01110" => display4(4) <= cpu_dout(7 downto 4); display4(5) <= cpu_dout(3 downto 0);
				when "01111" => display4(6) <= cpu_dout(3 downto 0);  -- Player 4 up LED
				-- Match/Credit: RAM 0x1C, 0x1D
				when "11100" => status_d(0) <= cpu_dout(7 downto 4); status_d(1) <= cpu_dout(3 downto 0);
				when "11101" => status_d(2) <= cpu_dout(7 downto 4); status_d(3) <= cpu_dout(3 downto 0);
				when others => null;
			end case;
		end if;
	end if;
end process;
end generate gen_gamedisp;


-- RAM -- 0x0000-0x01FF (512 Byte); 0x0200 ist 1-Byte-NVRAM-Register (s.o., nvram_dout)
RAM: entity work.RAM --512byte
port map(
	address	=> cpu_addr(8 downto 0),
	clock		=> clk_50,
	data		=>  cpu_dout (7 DOWNTO 0),
	wren 		=> ram_wren,
	q			=> ram_dout
);


-- ============================================================
-- Game-Select ROMs: 5 Spiele x ROM1 (E0, 0x7800/0xF800) + ROM2 (E00, 0x7000),
-- je 2K x 8. Alle gleichzeitig im BRAM; der aktive Ausgang wird unten gemuxt.
-- ============================================================
-- ROM1-Slot (E0)
E0_ATARIAN : entity work.game_rom generic map(init_file => "./rom/atarian.e0.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom1_douts(0));
E0_TIME    : entity work.game_rom generic map(init_file => "./rom/time.e0.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom1_douts(1));
E0_AIRBORNE: entity work.game_rom generic map(init_file => "./rom/airborne.e0.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom1_douts(2));
E0_MIDEARTH: entity work.game_rom generic map(init_file => "./rom/608.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom1_douts(3));
E0_SPACE   : entity work.game_rom generic map(init_file => "./rom/spacel.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom1_douts(4));

-- ROM2-Slot (E00)
E00_ATARIAN : entity work.game_rom generic map(init_file => "./rom/atarian.e00.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom2_douts(0));
E00_TIME    : entity work.game_rom generic map(init_file => "./rom/time.e00.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom2_douts(1));
E00_AIRBORNE: entity work.game_rom generic map(init_file => "./rom/airborne.e00.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom2_douts(2));
E00_MIDEARTH: entity work.game_rom generic map(init_file => "./rom/609.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom2_douts(3));
E00_SPACE   : entity work.game_rom generic map(init_file => "./rom/spacer.hex")
	port map(address => cpu_addr(10 downto 0), clock => clk_50, q => rom2_douts(4));

-- Decode game_select (active-low) -> Index, unbenutzte Codes 5..7 -> Middle Earth (3)
game_idx <= conv_integer(not game_select);
game_sel <= game_idx when game_idx <= 4 else 3;
rom1_sel <= rom1_douts(game_sel);
rom2_sel <= rom2_douts(game_sel);

-- Freispiel-Overlay: bei freeplay=0 (active-low) die gepatchten Bytes ueberlagern.
-- Default ist der rohe Game-Mux-Ausgang; Bus-Mux (rom1_cs/rom2_cs) bleibt unveraendert.
fp_overlay : process(rom1_sel, rom2_sel, cpu_addr, game_sel, freeplay)
	variable a  : integer range 0 to 2047;
	variable d1 : std_logic_vector(7 downto 0);
	variable d2 : std_logic_vector(7 downto 0);
begin
	d1 := rom1_sel;
	d2 := rom2_sel;
	if freeplay = '0' then                       -- Freispiel aktiv (active-low)
		a := conv_integer(cpu_addr(10 downto 0));
		for i in FP_PATCHES'range loop
			if FP_PATCHES(i).game = game_sel and FP_PATCHES(i).addr = a then
				if FP_PATCHES(i).slot = 1 then
					d1 := FP_PATCHES(i).data;
				else
					d2 := FP_PATCHES(i).data;
				end if;
			end if;
		end loop;
	end if;
	rom1_dout <= d1;
	rom2_dout <= d2;
end process;


U9: entity work.cpu68
port map(
	clk => cpu_clk,
	rst => reset_h,
	rw => cpu_rw,
	vma => cpu_vma,
	address => cpu_addr,
	data_in => cpu_din,
	data_out => cpu_dout,
	hold => '0',
	halt => '0',
	irq => '0',
	nmi => not dma_int
);

	 
-- cpu clock
clock_gen: entity work.cpu_clock
port map(   
	inclk0 => clk_50,
	c0	=> cpu_clk
);

-----------------------------------------------
-- phase 0: activated by switch on FPGA board	
-- read first time dip settings which sets boot phase 1
-----------------------------------------------
META1: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => reset_sw,
	o_Q => boot_phase(0),
   i_Fast_Clk => clk_50
	);

------------------------------
-- Diagnose-Prozesse
------------------------------

-- Heartbeat-Teiler: 25-Bit-Freilaufzähler auf clk_50 (nur noch als Reserve / FPGA-Takt-Nachweis)
process(clk_50)
begin
	if rising_edge(clk_50) then
		heartbeat_div <= heartbeat_div + 1;
	end if;
end process;

-- CPU-Fetch-Zähler: zählt rising edges von (rom1_cs or rom2_cs) in clk_50
-- Bit 20 → ~0.6 Hz auf LED_D2 solange die CPU ROM-Bytes fetcht.
-- Steht LED_D2 dauerhaft (leuchtet oder dunkel): CPU macht keine ROM-Zugriffe →
--   entweder halted, oder in RAM-Warteschleife ohne ROM-Fetch (dann DBG_MODE=1/2 für PC-Trace).
process(clk_50)
begin
	if rising_edge(clk_50) then
		rom_cs_d <= rom1_cs or rom2_cs;
		if (rom1_cs or rom2_cs) = '1' and rom_cs_d = '0' then
			cpu_fetch_cnt <= cpu_fetch_cnt + 1;
		end if;
	end if;
end process;

-- NMI-Blinker, Watchdog-Sticky, Power-on-Reset
process(clk_50)
begin
	if rising_edge(clk_50) then
		if reset_l_stable = '0' then
			nmi_blink_cnt <= (others => '0');
			wd_seen       <= '0';
			por_count     <= 0;
			por_active    <= '1';
		else
			-- NMI-Flanken-Detect (nmi_level_d wird im clk_50-Hauptprozess gesetzt)
			-- Zähler inkrementiert ~1953 NMI/s; Bit 11 → ~0.48 Hz Blinken auf LED_D3
			if nmi_level = '1' and nmi_level_d = '0' then
				nmi_blink_cnt <= nmi_blink_cnt + 1;
			end if;
			-- Watchdog-Sticky: einmal gesetzt, bleibt bis zum nächsten ext. Reset
			if wd_reset = '1' then
				wd_seen <= '1';
			end if;
			-- Power-on-Reset: hält CPU für 50 000 Takte (1 ms) sicher im Reset
			if por_count < 50000 then
				por_count  <= por_count + 1;
				por_active <= '1';
			else
				por_active <= '0';
			end if;
		end if;
	end if;
end process;


end rtl;


		