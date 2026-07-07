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
		serin_595			: 	out 	std_logic; -- DIP strobe1 (dip_strobe(0)) while boot_phase(1)='0' (DIP read window), else lamp serin
		clk_595			: 	out 	std_logic; -- DIP strobe3 (dip_strobe(2)) while boot_phase(1)='0' (DIP read window), else lamp clk
		rclk_595			: 	out 	std_logic; -- DIP strobe2 (dip_strobe(1)) while boot_phase(1)='0' (DIP read window), else lamp rclk
		oe_595			: 	out 	std_logic; -- active low
		
		-- 5) solenoids
		solenoids		: out 	std_logic_vector(1 to 20);
		solenoids_enable		: out std_logic;
		
		-- 6) auxilary board interface
		aux_lamp_strobe: out 	std_logic_vector(1 downto 0);
		aux_audio: out 	std_logic_vector(3 downto 0);
		aux_audio_latch: out 	std_logic_vector(3 downto 0);
		aux_sol_latch: out 	std_logic_vector(1 downto 0);
		
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

-- SW version SW_MAIN.SW_SUB1.SW_SUB2: shown on the boot info display (Display1 during the
-- ~5 s version/config screen, boot_phase(2)). Not yet machine-readable by the game software;
-- could later be exposed via a DIP/debug read address or the ESP32 link for a software query.
constant SW_MAIN : std_logic_vector(3 downto 0) := x"0";
constant SW_SUB1 : std_logic_vector(3 downto 0) := x"0";
constant SW_SUB2 : std_logic_vector(3 downto 0) := x"7";

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
-- integrated sound (siehe sound.vhd): drei Sound-Latches + Modul-Ausgaenge
signal snd_select	: std_logic_vector(3 downto 0) := (others => '0');  -- Latch 1080: Wellenform
signal snd_pitch	: std_logic_vector(3 downto 0) := (others => '0');  -- Latch 1088: Tonhoehe
signal snd_volume	: std_logic_vector(3 downto 0) := (others => '0');  -- Latch 1084: Lautstaerke
signal snd_sample	: std_logic_vector(3 downto 0);  -- roher 4-Bit ROM-Nibble (Aux-Pfad)
signal snd_pwm		: std_logic;                     -- 1-Bit Sigma-Delta (Onboard-Pfad)
signal sound_cs		: std_logic;
-- AUDIO ENABLE/RESET (PinMAME atari.c: 0x3000 soundg1_w, 0x6000-0x6FFF audiog1_w) -> Gate fuer sound.vhd.
-- Ohne Enable-Gatterung bleibt ein gestarteter Ton als Dauerton stehen (HW-Symptom 2026-07-06).
signal audio_enable	: std_logic := '0';              -- '1' = Ton freigegeben, '0' = stumm
signal audio_en_cs	: std_logic;                     -- Write 0x3000 (AUDIO ENABLE)
signal audio_rst_cs	: std_logic;                     -- Write 0x6000-0x6FFF (AUDIO RESET)
-- Solenoid-Steuerung (Phase B, solenoid_driver.vhd): Write-Strobe + Modul-Ausgaenge (aktiv-high).
-- sol_ah/coin_cntr_ah/lockout_ah werden im Top invertiert (74HCT540) auf die Ports gelegt.
signal sol_wr		: std_logic := '0';
signal sol_ah		: std_logic_vector(1 to 20);
signal coin_cntr_ah	: std_logic;
signal lockout_ah	: std_logic;
-- Boot-Sprachausgabe ("Lisy", speech.vhd): eigener 1-Bit-Sigma-Delta-Strom + busy.
-- Start an Vorderflanke boot_phase(1); Ausgabe ueber SB_Sound-Mux (Vorrang vor Sound).
signal speech_pwm	: std_logic;                     -- 1-Bit Sigma-Delta der Sprachausgabe
signal speech_busy	: std_logic;                     -- '1' waehrend "Lisy" abgespielt wird

-- helpers DIP read & boot phase
signal dip_strobe  : std_logic_vector(2 downto 0);
signal g_serin_595 : std_logic := '0';
signal g_clk_595 : std_logic := '0';
signal g_rclk_595 : std_logic := '0';
-- Lamp-Matrix (Phase B, lamp_matrix.vhd): RAM-0x30-0x3F-Shadow + Modul-Ausgaenge.
signal lamp_state      : std_logic_vector(127 downto 0) := (others => '0');
signal lamp_ser        : std_logic;
signal lamp_srck       : std_logic;
signal lamp_rck        : std_logic;
signal lamp_oe_n       : std_logic;
signal lamp_strobe_sel : std_logic_vector(1 downto 0);
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

signal dma_counter		: std_logic_vector(11 downto 0) := (others => '0');
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

				-- input (display data) -- "Spiel/Normal"-Quelle (Sniffer bzw. disp_test)
signal   display1			: DISPLAY_T;
signal	display2			: DISPLAY_T;
signal	display3			: DISPLAY_T;
signal	display4			: DISPLAY_T;
signal	status_d			: DISPLAY_TS;

-- Boot-Phase 2: Version/Config-Infoanzeige (~5s nach DIP-Read, vor CPU-Start)
constant INFO_SHOW_CYCLES : integer := 5000000;          -- cpu_clk=1MHz -> 5s
signal	info_count		: integer range 0 to INFO_SHOW_CYCLES := 0;
signal	disp_show		: std_logic;                     -- Display aktiv ab DIP-Read fertig
-- Boot-Info-Inhalt (kombinatorisch aus SW_*, game_idx, options, freeplay)
signal	bi_display1		: DISPLAY_T;
signal	bi_display2		: DISPLAY_T;
signal	bi_display3		: DISPLAY_T;
signal	bi_display4		: DISPLAY_T;
signal	bi_status		: DISPLAY_TS;
-- gemuxte display_control-Eingaenge: Boot-Info (Phase 2) vs. Spiel/Normal
signal	dc_display1		: DISPLAY_T;
signal	dc_display2		: DISPLAY_T;
signal	dc_display3		: DISPLAY_T;
signal	dc_display4		: DISPLAY_T;
signal	dc_status		: DISPLAY_TS;


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
--   3 = Boot-Trace (cpu_clk/boot_phase0/por_active/boot_phase1/boot_phase2/reset_h/
--       dip_strobe0/i_disp_Load) — zeigt Fortschritt der Power-on-/Boot-Sequenz
constant DBG_MODE : integer range 0 to 3 := 0;
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

-- Switch-Matrix (Phase B): reale 10x8-Matrix per switch_matrix.vhd gescannt.
-- sw_state(offset) = entprellter Zustand je CPU-offset (addr-0x2000); '1' = geschlossen.
-- Der 2-FF-Synchronizer (B4) liegt jetzt im Modul; die alten sw_meta/sw_sync (GottFA3-Erbe,
-- dedizierte Switch-Pins) entfallen -- alle Schalter kommen ueber den einen sw_com_in-Rueckkanal.
signal sw_state       : std_logic_vector(0 to 79);
-- Dekodierter Switch-Matrix-Wert für cpu_din (geschlossen=0xFF, offen=0x00, laut PinMAME swg1_r)
signal sw_value       : std_logic_vector(7 downto 0);

-- ---------------------------------------------------------------------------

begin

-- 8-Kanal-LA auf debug_signal[7:0] — Belegung per DBG_MODE-Konstante wählbar:
-- DBG_MODE=0 (Standard-Mix):
--  [0] cpu_clk    1 MHz Dauertakt     — steht: PLL/Takt tot
--  [1] cpu_vma    CPU-Buszugriffe     — dauerhaft 0: CPU halted/hängt
--  [2] cpu_rw     Read(1)/Write(0)    — zeigt Lese-/Schreibphasen
--  [3] ram_wren   RAM-Schreibstrobe   — nie: CPU schreibt nichts
--  [4] NMI-Puls   alle 4096 µs (244 Hz) — fehlt: Attract-Timer zählt nie (Ursache 1)
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
-- DBG_MODE=3 (Boot-Trace): Fortschritt der Power-on-/Boot-Sequenz sichtbar machen.
--  [0] cpu_clk        Referenz/Heartbeat (läuft immer aus der PLL)
--  [1] boot_phase(0)  synchronisiertes reset_sw ('1' = Reset NICHT gedrückt)
--  [2] por_active     Power-on-Reset — steht dauerhaft '1': Boot-Deadlock (POR zählt nie herunter)
--  [3] boot_phase(1)  DIP-Read fertig (read_the_dips 'done')
--  [4] boot_phase(2)  Info-Fenster vorbei (= reset_l_stable, CPU freigegeben)
--  [5] reset_h        CPU-Reset ('1' = CPU im Reset)
--  [6] dip_strobe(0)  DIP-Read-Matrix-Aktivität (nur im Read-Fenster)
--  [7] i_disp_Load    Display-Multiplex-Aktivität (Load-Strobe)
gen_dbg3: if DBG_MODE = 3 generate
	debug_signal(0) <= cpu_clk;
	debug_signal(1) <= boot_phase(0);
	debug_signal(2) <= por_active;
	debug_signal(3) <= boot_phase(1);
	debug_signal(4) <= boot_phase(2);
	debug_signal(5) <= reset_h;
	debug_signal(6) <= dip_strobe(0);
	debug_signal(7) <= i_disp_Load;
end generate gen_dbg3;

-------------------------------
reset_l_stable <= boot_phase(2); -- CPU-Release erst nach DIP-Read (Phase 1) + Info-Anzeige (Phase 2)
disp_show <= boot_phase(1);       -- Display aktiv ab DIP-Read fertig (durch Info-Phase bis ins Spiel)
reset_h <= (not reset_l_stable) or por_active;
   -- WD deliberately disconnected: Game kickt 0x4000 nicht im Attract Mode → permanenter Reset-Loop.
   -- Reaktivieren (or wd_reset) sobald Kick-Bedingung aus Schaltplan/ROM-Disassembly bekannt.

-- LEDs (Schnell-Diagnose ohne LA) — Board-LEDs aktiv-LOW (gegen VCC, Pin nach GND => leuchten bei '0')
LED_D1   <= not wd_seen;           -- Watchdog-Sticky: leuchtet, wenn der WD mind. einmal resettet hat
LED_D2   <= not cpu_fetch_cnt(20); -- CPU-Fetch-Blinker ~0.6 Hz: blinkt = cpu68 fetcht ROM-Befehle
                                    -- (steht dauerhaft: CPU halted oder hängt ohne ROM-Zugriff)
LED_D3   <= not nmi_blink_cnt(8);  -- NMI-Generator-Blinker ~0.48 Hz: blinkt = HW-NMI-Takt läuft
                                    -- (unabhängig von CPU; Freilauf aus dma_counter; 244 NMI/s -> Bit8 ~0.48 Hz)

-- use some IOs to read dips at start
-- Route the matrix strobes to the lamp IOs only DURING the DIP read window.
-- Gate on boot_phase(1) (= read_the_dips 'done'): '0' while reading, '1' once finished.
-- (Gating on boot_phase(0) was wrong: boot_phase(0) is the synchronized reset_sw AND the
--  FSM reset, so the FSM only runs when boot_phase(0)='1' -- exactly when the old mux routed
--  g_*_595 instead of dip_strobe, so the strobes never reached the pins.)
-- HW-Zuordnung (2026-07-02, Prototyp): clk_595 = Strobe3 (dip_strobe(2)),
-- rclk_595 = Strobe2 (dip_strobe(1)) -- gegenueber der urspruenglichen Annahme getauscht.
serin_595 <= dip_strobe(0) when boot_phase(1) = '0' else g_serin_595;
clk_595 <= dip_strobe(2) when boot_phase(1) = '0' else g_clk_595;
rclk_595 <= dip_strobe(1) when boot_phase(1) = '0' else g_rclk_595;
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
-- Solenoide (Phase B): getrieben vom solenoid_driver (Instanz SOL, s.u.). sol_ah ist aktiv-high
-- ('1'=bestromt); invertierender 74HCT540 -> FPGA '1' => 540-Ausgang '0' => Gate low => MOSFET AUS.
-- Das Modul haelt bei Reset/enable=0 alles auf 0 (AUS) -> hier '1' am Port (sicher).
solenoids        <= not sol_ah;
-- Muenztuer-Spulen ueber Aux-Board (invertierender 74HCT540): aktiv-high coin_cntr/lockout -> invertiert.
aux_sol_latch(0) <= not coin_cntr_ah;   -- COIN_CNTREN (0x1080 bit4)
aux_sol_latch(1) <= not lockout_ah;     -- LOCKOUT_EN  (0x1080 bit5)
-- solenoids_enable: laeuft ueber den NICHT invertierenden 74HCT541 an die active-low /OE der
-- 74HCT540 (Solenoid-MOSFETs UND Aux-Board). '0' => 540 freigegeben, '1' => disabled (sicher).
-- Freigabe erst mit CPU (reset_l_stable = boot_phase(2)); Boot/Reset = '1' = disabled.
-- Achtung: gibt auch den Original-Audio-Aux-Pfad frei (aux-Signale am selben 540, beabsichtigt).
solenoids_enable <= not reset_l_stable;
-- Lamp-Matrix (Phase B, lamp_matrix.vhd, Instanz LAMP): treibt die 74HC595-Kaskade ueber den
-- NICHT-invertierenden 74HCT541. oe_595 aktiv-low ('0'=Ausgaenge frei). Bei Boot/Reset haelt
-- das Modul (enable='0') oe_595='1' => Lampen sicher AUS.
oe_595      <= lamp_oe_n;
g_serin_595 <= lamp_ser;
g_clk_595   <= lamp_srck;
g_rclk_595  <= lamp_rck;
-- Aux-Board Lamp-Strobe (ueber INVERTIERENDEN 74HCT540, gated von solenoids_enable): 2-Bit-Select
-- -> dortiger 1-of-4-Decoder (SA/SB/SC/SD). Invertiert wg. 74HCT540 (Konvention wie disp_*).
-- Waehrend Boot (540 disabled) definieren die aux-seitigen Pulls den Pegel; Wert hier nur wirksam
-- sobald solenoids_enable freigibt (= CPU laeuft).
aux_lamp_strobe <= not lamp_strobe_sel;
-- Sound-Ausgabe-Mux (options(3), active-low; dynamisch im Spiel umschaltbar):
--   '1' (DIP OFF) = Original : AUDIO 0..3 + Volume-Latch ans Aux-Board (dortiger DAC/4016/Amp)
--   '0' (DIP ON)  = Emulation: 1-Bit Sigma-Delta ueber SB_Sound (Onboard RC + TDA7267)
-- Aux-Datenleitungen invertiert wegen 74HCT540 (Konvention wie disp_*); HW-Vorbehalt: der
-- Original-Pfad erreicht das Aux-Board erst, wenn der 74HCT540 enabled ist (solenoids_enable,
-- Phase B/C). aux_audio_latch ist 4 Bit: Volume auf Bit 3..0
aux_audio       <= not snd_sample                      when options(3) = '1' else (others => '0');
aux_audio_latch <= (not snd_volume)             when options(3) = '1' else (others => '0');
-- Boot-Sprache hat Vorrang: waehrend speech_busy spricht das Sprachmodul ueber SB_Sound,
-- danach (im Spiel) normaler Emulations-Sound bei options(3)=ON. Faellt ins Info-Fenster.
SB_Sound        <= speech_pwm                           when speech_busy = '1'
              else snd_pwm                              when options(3) = '0'
              else '0';
-- SB_Audio: separater MP3/Background-Pfad (ESP32/Mini-Player) -- nicht Teil der Emulation.
SB_Audio <= '0';
-- FRAM I2C: Open-Drain im Leerlauf freigeben (externer Pull-up zieht high); SCL idle high.
fram_i2c_sda <= 'Z';
fram_i2c_scl <= '1';
-- ESP32-Link: UART-Leitung ruht HIGH; Signalpin Idle low.
ESP32_ser_rx <= '1';
ESP32_sig    <= '0';
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- Boot-Phase 2: ~5s Version/Config-Anzeige nach DIP-Read, vor CPU-Freigabe.
-- Timer laeuft auf cpu_clk (1 MHz); haelt boot_phase(2)=0 solange Phase 1 nicht
-- fertig, zaehlt dann INFO_SHOW_CYCLES hoch und gibt mit boot_phase(2)='1' die
-- CPU frei (reset_l_stable). Eigener Treiber nur fuer Bit 2 (Bits 0/1 separat).
------------------------------------------------------------------------------
boot_info_timer : process(cpu_clk)
begin
	if rising_edge(cpu_clk) then
		if boot_phase(1) = '0' then          -- DIP-Read noch nicht fertig
			info_count <= 0;
			boot_phase(2) <= '0';
		elsif info_count < INFO_SHOW_CYCLES then
			info_count <= info_count + 1;     -- Info-Fenster laeuft (~5s)
		else
			boot_phase(2) <= '1';             -- Info-Fenster vorbei -> CPU freigeben
		end if;
	end if;
end process;

------------------------------------------------------------------------------
-- Boot-Info-Inhalt (kombinatorisch). HW-Verdrahtung: Index 0 = physisch RECHTS,
-- Index 5 = physisch LINKS (Digit-Adresse gegenlaeufig). display_control liest
-- LINEAR (d(idx)) -> die Ziffern hier gespiegelt ablegen, damit die Info-Anzeige
-- rechtsbuendig/richtig herum erscheint. (Die Umkehr sass frueher zentral in
-- display_control.vhd, spiegelte aber die Spielanzeige doppelt -> jetzt nur hier.)
-- x"F"=blank, Digit 6 = Player-up-LED (hier aus = x"0", nicht Teil der Ziffernfolge).
------------------------------------------------------------------------------
boot_info : process(game_select, options, freeplay)
begin
	-- Display 1: Version SW_MAIN SW_SUB1 SW_SUB2 (rechtsbuendig: SUB2 ganz rechts = Index 0)
	bi_display1 <= (others => x"F");
	bi_display1(2) <= SW_MAIN;
	bi_display1(1) <= SW_SUB1;
	bi_display1(0) <= SW_SUB2;
	bi_display1(6) <= x"0";

	-- Display 2: Game Select game_idx (0..7 = not game_select), 2-stellig dezimal
	-- mit fuehrender 0. Wertebereich 0..7 -> Zehnerstelle stets 0, Einer = 0..7.
	bi_display2 <= (others => x"F");
	bi_display2(1) <= x"0";                       -- Zehnerstelle (immer 0)
	bi_display2(0) <= '0' & (not game_select);    -- Einerstelle 0..7 (ganz rechts)
	bi_display2(6) <= x"0";

	-- Display 3: options(1..6), ON wird als '0' gelesen -> '1' anzeigen.
	-- Option 1 = physisch links (Index 5) .. Option 6 = physisch rechts (Index 0).
	bi_display3 <= (others => x"F");
	for i in 1 to 6 loop
		if options(i) = '0' then
			bi_display3(6-i) <= x"1";
		else
			bi_display3(6-i) <= x"0";
		end if;
	end loop;
	bi_display3(6) <= x"0";

	-- Display 4: Freeplay (active-low) -> '1' wenn aktiv, sonst '0' (ganz rechts = Index 0)
	bi_display4 <= (others => x"F");
	if freeplay = '0' then
		bi_display4(0) <= x"1";
	else
		bi_display4(0) <= x"0";
	end if;
	bi_display4(6) <= x"0";

	-- Status-Display: blank
	bi_status <= (others => x"F");
end process;

-- Mux: in Phase 2 (boot_phase(2)='0') Boot-Info, danach Spiel/Normal-Daten.
dc_display1 <= bi_display1 when boot_phase(2) = '0' else display1;
dc_display2 <= bi_display2 when boot_phase(2) = '0' else display2;
dc_display3 <= bi_display3 when boot_phase(2) = '0' else display3;
dc_display4 <= bi_display4 when boot_phase(2) = '0' else display4;
dc_status   <= bi_status   when boot_phase(2) = '0' else status_d;


DC: entity work.display_control
port map(
	clk		=> cpu_clk,
	show => disp_show,
	-- Control/Data Signals,
	disp_Data => i_disp_Data,
	disp_Adr => i_disp_Adr,
	disp_Load => i_disp_Load,
	disp_Cathode_blank => i_disp_Cathode_blank, --C11 -> DSTB Pin1 on K4
	disp_Anode_blank => i_disp_Anode_blank,
	-- input (display data) -- gemuxt: Boot-Info (Phase 2) vs. Spiel/Normal
	-- digit #6 is Player up LEDS 8==ON 0==OFF
	display1	=> dc_display1,
	display2	=> dc_display2,
	display3	=> dc_display3,
	display4	=> dc_display4,
	status_d	=> dc_status
	);


gen_disptest : if DISPLAY_TEST generate
DT: entity work.disp_test
port map(
	clk		=> cpu_clk,
	show => disp_show,
	display1	=> display1,
	display2	=> display2,
	display3	=> display3,
	display4	=> display4,
	status_d	=> status_d
	);
end generate gen_disptest;

------------------------------------------------------------------------------
-- integrated sound 
------------------------------------------------------------------------------
-- sound.vhd bildet D12-ROM + D13-Pitch-Teiler + E12/E13-Sample-Zaehler nach.
-- Eingaenge: die drei Sound-Latches (1080/1088/1084), unten am Bus dekodiert.
-- Ausgaenge: snd_sample (4-Bit, Aux-Pfad) und snd_pwm (Sigma-Delta, Onboard-Pfad).
-- Die Auswahl Original/Emulation per options(3) erfolgt im Ausgabe-Mux (oben).
SND: entity work.sound
port map(
	clk_50		=> clk_50,
	reset_l		=> reset_l_stable,
	snd_select	=> snd_select,
	snd_pitch	=> snd_pitch,
	snd_volume	=> snd_volume,
	snd_enable	=> audio_enable,
	sample		=> snd_sample,
	sb_pwm		=> snd_pwm
	);

------------------------------------------------------------------------------
-- Boot-Sprachausgabe "Lisy" (speech.vhd) -- spielt einmal beim Boot.
-- reset: not boot_phase(0) (= synchronisiertes reset_sw, active-low). '0' im Lauf,
--   '1' bei Config/HW-Reset -> sauberer Neustart der Wiedergabe nach Reset.
--   (por_active/reset_h sind WAEHREND des Info-Fensters aktiv -> hier ungeeignet!)
-- start: Pegel boot_phase(1) (DIP-Read fertig). Das interne start_d-Edge-Detect in
--   speech.vhd loest die einmalige Wiedergabe an der 0->1-Flanke aus.
-- Ausgabe ueber SB_Sound-Mux (speech_busy hat Vorrang, siehe oben).
SPEECH_INST: entity work.speech
generic map(
	-- Startverzoegerung: "Lisü" erst ~2 s in den Boot abspielen (100e6 clk_50 @50MHz),
	-- damit das 0,46-s-Wort NICHT ins Einschalt-/Mute-Fenster des TDA7267 faellt (es gibt
	-- keinen FPGA-Mute-Pin; HW-bestaetigt 2026-07-07: bei ~2,5 s hoerbar, dann auf 2 s gekuerzt).
	-- Wort spielt 2,0–2,46 s; Info-Fenster endet erst bei 5 s (boot_phase(2), CPU-Release). Tunbar.
	START_DELAY => 100000000
	)
port map(
	clk_50  => clk_50,
	reset   => not boot_phase(0),
	start   => boot_phase(1),
	busy    => speech_busy,
	pwm_out => speech_pwm
	);

-- Onboard-Pfad SB_Sound (Emulation): 1-Bit-PWM -> RC-Tiefpass -> TDA7267
--   SB_Sound 0---XXXXX---+---0 analog audio
--                 3k3    |
--                       === 4n7
--                        |
--                       GND

------------------------------
-- DMA interrupt counter (12-bit synchronous, entspricht der 3x SN7493 Ripple-Kette = /4096)
-- counts cpu_clk rising edges in clk_50 domain; NMI-Periode = 4096 cpu_clk = 4096 us = 244 Hz
-- (PinMAME ATARI_NMIFREQ=244; gemessene Frame-Periode 4096 us, s. doc/Display_Timing.md).
-- War frueher /512 (9-Bit, 1953 Hz = 8x zu schnell -> Switch-Mehrfach-Registrierung).
------------------------------
dma_clk   <= dma_counter(0);  -- reserved
audio_clk <= dma_counter(2);  -- reserved for Phase C audio
dma_int   <= not (dma_counter(10) and dma_counter(11));
nmi_level <= dma_counter(10) and dma_counter(11);

-- DIP-Region 0x2000-0x200F: volles 1:1 aus der Matrix (SW1/SW2-Programmier-DIPs), zwei Ausnahmen:
--   0x2000: kein DIP-Read, sondern DMA-Sync -> Bit7=0 (BPL-Check @0x721C), Bit6=dma_toggle
--           (Display-Sync, ROM-Poll @0x78BE/0x78C9), Bit5..0=1.
--   0x200B: Testschalter-Leitung, NICHT invertiert (wie jede DIP-Position: gedrueckt/geschlossen
--           -> 0xFF, Bit7=1). ROM-verifiziert (doc/Switch_Reading_Analysis.md): Middle Earth @7F9C
--           und Airborne @7AB4 werten Bit7 aus und erwarten Bit7=1 = Test gedrueckt. Frueher faelschlich
--           invertiert -> andere Spiele booteten in den Selbsttest. Faellt fuer non-ME mit dem
--           allgemeinen DIP-Zweig zusammen.
--           Middle Earth (game_idx=3, PinMAME MACHINE_INIT ATARI1A): testSwBits=0x0F -> unteres Nibble
--           invertiert (dipg1_r: 0x200B ^= 0x0F) auf der NICHT-invertierten Basis -> offen 0x0F, gedrueckt 0xF0.
--   sonst : DIP aus Matrix (ON/geschlossen -> 0xFF, wie PinMAME dipg1_r).
dip_value <= ("0" & dma_toggle & "111111")                              when cpu_addr = x"2000" else
             (7 downto 4 => sw_state(11), 3 downto 0 => not sw_state(11)) when (cpu_addr = x"200B" and game_idx = 3) else
             (others => sw_state(conv_integer(cpu_addr(6 downto 0))));

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

------------------------------------------------------------------------------
-- Switch-Matrix (Phase B): reale 10x8-Matrix scannen (switch_matrix.vhd).
-- Freilaufend in clk_50; treibt sw_strobe/sw_com (durch inv. 74HCT540 -> 74LS42 + 74LS145),
-- sampelt den einen Rueckkanal sw_com_in (durch inv. 74HC4049) und liefert sw_state(0..79)
-- (offset = addr-0x2000; '1' = geschlossen). Reset an reset_l_stable gekoppelt.
------------------------------------------------------------------------------
SWM: entity work.switch_matrix
port map(
	clk_50    => clk_50,
	reset     => not reset_l_stable,
	sw_strobe => sw_strobe,
	sw_com    => sw_com,
	sw_com_in => sw_com_in,
	sw_state  => sw_state
);

------------------------------------------------------------------------------
-- Solenoid-Steuerung (Phase B): solenoid_driver.vhd latcht die vier Sol-Latches
-- 0x1080/1084/1088/108C (Write-Strobe sol_wr, latch_sel = cpu_addr(3:2)) und treibt
-- sol_ah(1..20) + Muenztuer (coin_cntr_ah/lockout_ah), oben invertiert auf die Ports.
-- reset/enable an reset_l_stable gekoppelt (AUS im Boot/Reset, live sobald CPU laeuft).
------------------------------------------------------------------------------
SOL: entity work.solenoid_driver
port map(
	clk_50    => clk_50,
	reset     => not reset_l_stable,
	wr        => sol_wr,
	latch_sel => cpu_addr(3 downto 2),
	data      => cpu_dout,
	enable    => reset_l_stable,
	sol       => sol_ah,
	coin_cntr => coin_cntr_ah,
	lockout   => lockout_ah
);

------------------------------------------------------------------------------
-- Lamp-Matrix (Phase B, lamp_matrix.vhd): scannt die 21x4-Multiplex-Matrix (84 Lampen)
-- aus dem RAM-0x30-0x3F-Shadow (lamp_state, s. lamp_sniffer) und treibt die 74HC595-Kaskade
-- (ser/srck/rck/oe_n) + 2-Bit-Strobe-Select. reset/enable an reset_l_stable gekoppelt
-- (AUS im Boot/Reset, live sobald CPU laeuft -- analog Solenoide).
------------------------------------------------------------------------------
LAMP: entity work.lamp_matrix
port map(
	clk_50     => clk_50,
	reset      => not reset_l_stable,
	enable     => reset_l_stable,
	lamp_state => lamp_state,
	ser        => lamp_ser,
	srck       => lamp_srck,
	rck        => lamp_rck,
	oe_n       => lamp_oe_n,
	strobe_sel => lamp_strobe_sel
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

-- Sound-Latches 0x1080/1084/1088 (nur Bits 3..0; Bits 7..4 reserviert fuer Solenoide, Phase B).
-- Hinweis: 0x1080-0x108F ueberlappt den RAM-Mirror (ram_cs_mirror). Unkritisch -- die I/O-Latches
-- sind write-only; das Spiel liest sie nicht als RAM zurueck, der redundante RAM-Write ist folgenlos.
sound_cs <= '1' when cpu_addr(15 downto 4) = x"108" and cpu_vma='1' else '0';

-- AUDIO ENABLE (0x3000, PinMAME soundg1_w) und AUDIO RESET (0x6000-0x6FFF, audiog1_w).
-- Steuern das Ein-/Ausschalten des Tongenerators (audio_enable -> sound.vhd). Bisher freie Adressen.
audio_en_cs  <= '1' when cpu_addr = x"3000" and cpu_vma='1' else '0';
audio_rst_cs <= '1' when cpu_addr(15 downto 12) = x"6" and cpu_vma='1' else '0';  -- 0x6000-0x6FFF

-- sw_value: Switch-Matrix @0x2010-0x204F -> offset = cpu_addr(6 downto 0) (0x10..0x4F).
-- sw_state(offset)='1' = geschlossen -> ganzes Byte 0xFF (PinMAME swg1_r), sonst 0x00.
-- Mappt Coin1(0x2010)/Coin2(0x2011)/Start(0x2012)/Slam(0x2013), alle Playfield-Schalter und
-- den Replay-Hex-Schalter (0x204C-0x204F) korrekt (frueherer Start@0x2013-Bug damit behoben).
sw_value <= (others => sw_state(conv_integer(cpu_addr(6 downto 0))));

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
		-- Solenoid-Latch-Write (0x108x): 1-clk-Puls, analog ram_wren -> solenoid_driver
		sol_wr    <= sound_cs and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
		-- NVRAM latch: 1-Byte-Register, schreibbar analog RAM-Write-Strobe
		if nvram_cs = '1' and cpu_rw = '0' and (cpu_clk_d2 = '1' and cpu_clk_d1 = '0') then
			nvram_dout <= cpu_dout;
		end if;
		-- Sound-Latches 0x1080/1084/1088: Bits 3..0 in die Steuer-Register fuer sound.vhd.
		if sound_cs = '1' and cpu_rw = '0' and (cpu_clk_d2 = '1' and cpu_clk_d1 = '0') then
			case cpu_addr(3 downto 0) is
				when x"0" => snd_select <= cpu_dout(3 downto 0);  -- 0x1080 Wellenform
				when x"4" => snd_volume <= cpu_dout(3 downto 0);  -- 0x1084 Lautstaerke
				when x"8" => snd_pitch  <= cpu_dout(3 downto 0);  -- 0x1088 Tonhoehe
				when others => null;
			end case;
		end if;
		-- AUDIO ENABLE/RESET (PinMAME atari.c). Ohne diese Gatterung bleibt ein gestarteter
		-- Ton als Dauerton stehen. Per-Spiel-Semantik (doc/atarigames.c sndType = gameSpecific1):
		--   Middle Earth / Space Riders (game_idx 3/4, gameSpecific1 & 2): 0x3000 -> EIN,
		--     jedes 0x6000 -> AUS (Reset).
		--   Atarians / Time 2000 / Airborne (idx 0/1/2): 0x6000 datenabhaengig (Daten/=0 -> EIN,
		--     =0 -> AUS); 0x3000 ohne Wirkung.
		if reset_l_stable = '0' then
			audio_enable <= '0';                          -- Boot/Reset: stumm
		elsif cpu_rw = '0' and (cpu_clk_d2 = '1' and cpu_clk_d1 = '0') then
			if game_idx = 3 or game_idx = 4 then
				if audio_en_cs = '1' then
					audio_enable <= '1';
				elsif audio_rst_cs = '1' then
					audio_enable <= '0';
				end if;
			else
				if audio_rst_cs = '1' then
					if cpu_dout /= x"00" then
						audio_enable <= '1';
					else
						audio_enable <= '0';
					end if;
				end if;
			end if;
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
--
-- HW-VERIFIZIERT (2026-07-03, Prototyp): das Player-Select-Feld (disp_Adr(5..3)) ist
-- gegenlaeufig verdrahtet — analog zur Ziffernreihenfolge. Ohne Umkehr erschien der
-- Player-4-Score physisch auf Player 1 usw. Daher wird die PinMAME-RAM-Player-Nummer
-- hier gespiegelt auf das Display-Signal gemappt: Player1→display4, Player2→display3,
-- Player3→display2, Player4→display1 (display_control bleibt unveraendert; Boot-Info
-- ist davon nicht betroffen und bleibt korrekt). RAM-Offsets folgen weiter PinMAME.
--
-- HW-VERIFIZIERT (2026-07-03, Prototyp): innerhalb jedes Score-Bytes sind die beiden
-- BCD-Ziffern (High-/Low-Nibble) paarweise vertauscht — '200000' erschien als '020000',
-- Selbsttest-Nr. '     1' als '    1 '. Daher: Low-Nibble (3..0) -> gerader/rechter Index,
-- High-Nibble (7..4) -> ungerader/linker Index (LSD rechts). Betrifft NUR die 4 Player-
-- Scores (Sniffer); Player-up-LED (Index 6), Status/Credit-Ball (0x1C/1D) und Boot-Info/
-- Version bleiben unveraendert und korrekt.
-- disabled when DISPLAY_TEST=true to avoid multiple-driver conflict with disp_test
gen_gamedisp : if not DISPLAY_TEST generate
process(clk_50)
begin
	if rising_edge(clk_50) then
		if ram_wren = '1' and cpu_addr(8 downto 5) = "0000" then
			case cpu_addr(4 downto 0) is
				-- Player 1 score (RAM 0x00-0x03) -> display4 (HW: Player-Feld gespiegelt, Nibble-Paar getauscht)
				when "00000" => display4(1) <= cpu_dout(7 downto 4); display4(0) <= cpu_dout(3 downto 0);
				when "00001" => display4(3) <= cpu_dout(7 downto 4); display4(2) <= cpu_dout(3 downto 0);
				when "00010" => display4(5) <= cpu_dout(7 downto 4); display4(4) <= cpu_dout(3 downto 0);
				when "00011" => display4(6) <= cpu_dout(3 downto 0);  -- Player 1 up LED (8=on,0=off)
				-- Player 2 score (RAM 0x04-0x07) -> display3
				when "00100" => display3(1) <= cpu_dout(7 downto 4); display3(0) <= cpu_dout(3 downto 0);
				when "00101" => display3(3) <= cpu_dout(7 downto 4); display3(2) <= cpu_dout(3 downto 0);
				when "00110" => display3(5) <= cpu_dout(7 downto 4); display3(4) <= cpu_dout(3 downto 0);
				when "00111" => display3(6) <= cpu_dout(3 downto 0);  -- Player 2 up LED
				-- Player 3 score (RAM 0x08-0x0B) -> display2
				when "01000" => display2(1) <= cpu_dout(7 downto 4); display2(0) <= cpu_dout(3 downto 0);
				when "01001" => display2(3) <= cpu_dout(7 downto 4); display2(2) <= cpu_dout(3 downto 0);
				when "01010" => display2(5) <= cpu_dout(7 downto 4); display2(4) <= cpu_dout(3 downto 0);
				when "01011" => display2(6) <= cpu_dout(3 downto 0);  -- Player 3 up LED
				-- Player 4 score (RAM 0x0C-0x0F) -> display1
				when "01100" => display1(1) <= cpu_dout(7 downto 4); display1(0) <= cpu_dout(3 downto 0);
				when "01101" => display1(3) <= cpu_dout(7 downto 4); display1(2) <= cpu_dout(3 downto 0);
				when "01110" => display1(5) <= cpu_dout(7 downto 4); display1(4) <= cpu_dout(3 downto 0);
				when "01111" => display1(6) <= cpu_dout(3 downto 0);  -- Player 4 up LED
				-- Match/Credit: RAM 0x1C, 0x1D (korrekt, NICHT getauscht — Status-Konvention weicht ab)
				when "11100" => status_d(0) <= cpu_dout(7 downto 4); status_d(1) <= cpu_dout(3 downto 0);
				when "11101" => status_d(2) <= cpu_dout(7 downto 4); status_d(3) <= cpu_dout(3 downto 0);
				when others => null;
			end case;
		end if;
	end if;
end process;
end generate gen_gamedisp;

-- lamp shadow buffer: sniff CPU writes to lamp RAM (0x30-0x3F) into lamp_state.
-- 16 Byte = 128 Bit; Bit-Index = offset*8 + b (offset = cpu_addr(3:0)). Das Multiplex-/
-- Physik-Mapping (Latch/Bit/Strobe -> 595-Gruppe) macht lamp_matrix.vhd. Laeuft unabhaengig
-- von DISPLAY_TEST. Nur Page-0-Schreibzugriffe (cpu_addr(15:4)=0x003), nicht der RAM-Mirror.
lamp_sniffer : process(clk_50)
begin
	if rising_edge(clk_50) then
		if ram_wren = '1' and cpu_addr(15 downto 4) = x"003" then
			for i in 0 to 7 loop
				lamp_state(conv_integer(cpu_addr(3 downto 0)) * 8 + i) <= cpu_dout(i);
			end loop;
		end if;
	end if;
end process;


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

-- NMI-Blinker, Watchdog-Sticky (Diagnose; an reset_l_stable gekoppelt = zyklusfrei)
process(clk_50)
begin
	if rising_edge(clk_50) then
		if reset_l_stable = '0' then
			nmi_blink_cnt <= (others => '0');
			wd_seen       <= '0';
		else
			-- NMI-Flanken-Detect (nmi_level_d wird im clk_50-Hauptprozess gesetzt)
			-- Zähler inkrementiert ~244 NMI/s; Bit 8 → ~0.48 Hz Blinken auf LED_D3
			if nmi_level = '1' and nmi_level_d = '0' then
				nmi_blink_cnt <= nmi_blink_cnt + 1;
			end if;
			-- Watchdog-Sticky: einmal gesetzt, bleibt bis zum nächsten ext. Reset
			if wd_reset = '1' then
				wd_seen <= '1';
			end if;
		end if;
	end if;
end process;

-- Power-on-Reset: MUSS unabhängig von reset_l_stable laufen, sonst Boot-Deadlock.
-- (reset_l_stable=boot_phase(2) steigt erst am Ende der Boot-Sequenz, die aber
--  por_active='0' voraussetzt: read_the_dips wird über i_Rst_L=boot_phase(0) and
--  not por_active im Reset gehalten. Koppelt man por_active an reset_l_stable,
--  kann der Zähler nie herunterzählen → alles außer cpu_clk bleibt statisch.)
-- Daher an boot_phase(0) (= synchronisiertes reset_sw, aktiv-low) gekoppelt:
--  losgelassener Reset → einmalig ~1 ms hochzählen, dann por_active='0' (DIP-Read frei);
--  Reset-Tastendruck → boot_phase(0)='0' → voller Reboot (DIP-Read + Info-Anzeige).
process(clk_50)
begin
	if rising_edge(clk_50) then
		if boot_phase(0) = '0' then          -- ext. Reset gedrückt / Config-Settle
			por_count  <= 0;
			por_active <= '1';
		elsif por_count < 50000 then          -- ~1 ms @ 50 MHz
			por_count  <= por_count + 1;
			por_active <= '1';
		else
			por_active <= '0';
		end if;
	end if;
end process;


end rtl;


		