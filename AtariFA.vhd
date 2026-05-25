-- 'AtariFA' a Atari Gen1 MPU on a low cost FPGA
-- Ralf Thelen 'bontango' 08.2021
-- www.lisy.dev
--
-- version 0.1 Test outputs only

-- from pinmame Atari.c
-----------------------------------------
--  Memory map for CPU board (GENERATION 1)
-----------------------------------------
--static MEMORY_READ_START(ATARI1_readmem)
--{0x0000,0x01ff, ram_r},			/* RAM */
--{0x0200,0x0200,	MRA_ROM},		/* fake NVRAM */
--{0x1080,0x1080,	latch1080_r},	/* read latches */
--{0x1084,0x1084,	latch1084_r},	/* read latches */
--{0x1088,0x1088,	latch1088_r},	/* read latches */
--{0x108c,0x108c,	latch108c_r},	/* read latches */
--{0x2000,0x200f,	dipg1_r},		/* dips */
--{0x2010,0x204f,	swg1_r},		/* inputs */
--{0x7000,0x7fff,	MRA_ROM},		/* ROM */
--{0xf000,0xffff,	MRA_ROM},		/* reset vector */
--MEMORY_END

--static MEMORY_WRITE_START(ATARI1_writemem)
--{0x0000,0x01ff, ram_w, &ram},	/* RAM */
--{0x0200,0x0200,	MWA_RAM, &generic_nvram, &generic_nvram_size},	/* fake NVRAM */
--{0x1000,0x107f, ram_w},			/* RAM mirror, on Middle Earth only */
--{0x1080,0x1080,	latch1080_w},	/* solenoids */
--{0x1081,0x1083, ram_w1},		/* RAM mirror, on Middle Earth only */
--{0x1084,0x1084,	latch1084_w},	/* solenoids */
--{0x1085,0x1087, ram_w2},		/* RAM mirror, on Middle Earth only */
--{0x1088,0x1088,	latch1088_w},	/* solenoids */
--{0x1089,0x108b, ram_w3},		/* RAM mirror, on Middle Earth only */
--{0x108c,0x108c,	latch108c_w},	/* solenoids */
--{0x108d,0x11ff, ram_w4},		/* RAM mirror, on Middle Earth only */
--{0x2000,0x200f,	dipg1_w},		/* dip switch memory area is written to by code */
--{0x3000,0x3000,	soundg1_w},		/* audio enable */
--{0x4000,0x4000,	watchdog_w},	/* watchdog reset? */
--{0x508c,0x508c,	latch508c_w},	/* additional solenoids, on Time 2000 only */
--{0x6000,0x6000,	audiog1_w},		/* audio reset */
--{0xffff,0xffff,	MWA_NOP},		/* Middle Earth writes here */
--MEMORY_END
	
-- atarigames.c
-------------------------------------------------------------------
-- Middle Earth (02/1978)
-------------------------------------------------------------------
--INITGAME1(midearth, atari_disp1, FLIPSW1920, 1, 2)
--ATARI_2_ROMSTART(midearth,      "608.bin",      CRC(28b92faf) SHA1(8585770f4059049f1dcbc0c6ef5718b6ff1a5431),
--                                                        "609.bin",      CRC(589df745) SHA1(4bd3e4f177e8d86bab41f3a14c169b936eeb480a))
--ATARI_SNDSTART("82s130.bin", CRC(da1f77b4) SHA1(b21fdc1c6f196c320ec5404013d672c35f95890b))
--ATARI_ROMEND
--CORE_GAMEDEFNV(midearth,"Middle Earth",1978,"Atari",gl_mATARI1A,0)

-- atari.h	
--NOTE: E00 should be loaded lower in memory,
--           so we load it first - easier than changing each entry in atarigames.c*/
--#define ATARI_2_ROMSTART(name, n1, chk1, n2, chk2) \
--   ROM_START(name) \
--     NORMALREGION(0x10000, ATARI_MEMREG_CPU) \
--       ROM_LOAD(n2, 0x7000, 0x0800, chk2) \
--       ROM_LOAD(n1, 0x7800, 0x0800, chk1) \
--         ROM_RELOAD(0xf800, 0x0800)

--#define ATARI_SNDSTART(n1, chk1) \
--     NORMALREGION(0x1000, REGION_SOUND1) \
--       ROM_LOAD_NIB_LOW(n1, 0x0000, 0x0200, chk1)

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
		-- GottFA3 Testboard		
		SEG7		: out 	std_logic_vector(3 downto 0);
		LED_SD_Error 	: out STD_LOGIC;	-- D1  - E9
		LED_active 	: out STD_LOGIC;  -- D2 - F7
		LED_status 	: out STD_LOGIC;	-- D3 - C6
		
	   -- the FPGA board
		clk_50	: in std_logic; 	-- E1
		reset_l  : in std_logic; 	-- K6
		LED1		: out std_logic; 	-- J6
		-- sram
		BUFFER_E_N		: out std_logic; -- 74HC541 buffer control
		--BUFFER_DATA		: out std_logic_vector(7 downto 0); -- data out (for buffer)
		BUFFER_DATA		: buffer std_logic_vector(7 downto 0); -- data out (for buffer)
		
		--SRAM_ADDR	: out std_logic_vector(17 downto 0); -- address 
		SRAM_ADDR	: buffer std_logic_vector(17 downto 0); -- address 
		SRAM_CE_N   : out std_logic; -- chip select					
		SRAM_OE_N   : out std_logic; -- output enable
		--SRAM_WE_N   : out std_logic; -- write enable		
		SRAM_WE_N   : buffer std_logic; -- write enable		
		SRAM_IO     : in std_logic_vector(7 downto 0); -- data in
		
		-- integrated sound
		Audio_O	: out std_logic; 	-- A14
		DFP_tx	: out std_logic; 	-- D15

		-- WillFA DIAG Interface
		Diag_Seg_1		: out 	std_logic_vector(6 downto 0);
		Diag_Seg_2		: out 	std_logic_vector(5 downto 0);
		Diag_option		: in std_logic;
		
		-- SPI SD card & EEprom
		CS_SDcard	: 	buffer 	std_logic; 
		CS_EEprom	: 	buffer 	std_logic;
		MOSI			: 	out 	std_logic;
		MISO			: 	in 	std_logic;
		SPI_CLK			: 	out 	std_logic;
						
		--display
		disp_Data: out 	std_logic_vector(3 downto 0);
		disp_Adr: out 	std_logic_vector(6 downto 0);
		disp_Load			: 	out 	std_logic;
		disp_Cathode_blank			: 	out 	std_logic;
		disp_Anode_blank			: 	out 	std_logic;
		
		
		--switches		
		switch: in 	std_logic_vector(16 downto 1);			
		
		--dips 		
		options		: in 	std_logic_vector(7 downto 0);

		-- DEBug
		debug_addr	: out std_logic_vector(15 downto 0);
		debug_data	: out std_logic_vector(7 downto 0);
		debug_signal	: out std_logic_vector(7 downto 0)


		);
end;

architecture rtl of AtariFA is 

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

begin

--debug
--debug_addr <= cpu_addr;
--debug_data <= cpu_din when cpu_rw='1' else cpu_dout;
--debug_signal(0) <= reset_l_stable;
--debug_signal(1) <= cpu_rw;
--debug_signal(2) <= ram_cs;
--debug_signal(3) <= cpu_rw;
--debug_signal(4) <= dma_int;
--debug_signal(5) <= dma_clk;
--debug_signal(6) <= cpu_clk;

debug_addr(3 downto 0) <= i_disp_Data;
debug_data(6 downto 0) <= i_disp_Adr;
debug_signal(0) <= i_disp_Load;
debug_signal(1) <= i_disp_Cathode_blank;
debug_signal(2) <= i_disp_Anode_blank;

-------------------------------

reset_h <= (not reset_l_stable) or wd_reset;

-- LEDs
LED1 <= '0';
LED_SD_Error <= '0';
SEG7 <= "0001";

----output reversed because of 74HCT240 drivers
disp_Data <= not i_disp_Data;
disp_Adr <= not i_disp_Adr;
disp_Load <= not i_disp_Load;
disp_Cathode_blank <= not i_disp_Cathode_blank;
disp_Anode_blank <= not i_disp_Anode_blank;

BM: entity work.boot_message
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
	
--DT: entity work.disp_test
--port map(
--	clk		=> cpu_clk,
--	show => reset_l_stable,
--	display1	=> display1,
--	display2	=> display2,
--	display3	=> display3,
--	display4	=> display4,
--	status_d	=> status_d
--	);

	
------------------------------
-- DMA interrupt counter (9-bit synchronous, replaces 3x SN7493 ripple chain)
-- counts cpu_clk rising edges in clk_50 domain; NMI period = 512 cpu_clk = 512 us
------------------------------
dma_clk   <= dma_counter(0);  -- reserved
audio_clk <= dma_counter(2);  -- reserved for Phase C audio
dma_int   <= not (dma_counter(7) and dma_counter(8));
nmi_level <= dma_counter(7) and dma_counter(8);

-- DIP read: 0x2000 bit6 = dma_toggle (game code checks this to proceed); all other DIPs = 0x00
dip_value <= "0" & dma_toggle & "000000" when cpu_addr = x"2000" else x"00";

------------------------------
-- Watchdog (0x4000 write)
------------------------------
WD: entity work.watchdog
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

-- RAM -- 0x0000, 0x01FF and mirror at 0x1000-0x11FF
ram_cs_normal <= '1' when cpu_addr(15 downto 9) = "0000000" and cpu_vma='1' else '0';
ram_cs_mirror <= '1' when cpu_addr(15 downto 9) = "0001000" and cpu_vma='1' else '0';
ram_cs <= ram_cs_normal or ram_cs_mirror;

--E0_ROM: entity work.ROM1 --2K 0x7800, 0x0800 & 0xf800, 0x0800
rom1_cs <= '1' when ( cpu_addr(15 downto 11) = "01111" or cpu_addr(15 downto 11) = "11111") and cpu_vma='1' else '0';
--E00_ROM: entity work.ROM2 --2K 0x7000, 0x0800
rom2_cs <= '1' when cpu_addr(15 downto 11) = "01110" and cpu_vma='1' else '0';

-- Bus control
cpu_din <=
	ram_dout  when ram_cs  = '1' else
	rom1_dout when rom1_cs = '1' else
	rom2_dout when rom2_cs = '1' else
	x"00"     when sw_cs   = '1' else  -- all switches open
	dip_value when dip_cs  = '1' else  -- DIPs + DMA toggle bit at 0x2000
	x"FF";
	
-- B2: synchroner RAM-Write-Strobe (clk_50-Domain)
-- cpu_clk (PLL) wird in clk_50 einsynchronisiert; fallende Flanke = ein Puls
-- wenn cpu_addr/cpu_dout nach der cpu68-Taktflanke stabil sind.
process(clk_50)
begin
	if rising_edge(clk_50) then
		cpu_clk_d1 <= cpu_clk;
		cpu_clk_d2 <= cpu_clk_d1;
		ram_wren <= ram_cs and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
		wd_kick  <= wd_cs  and (not cpu_rw) and (cpu_clk_d2 and not cpu_clk_d1);
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

-- RAM -- 0x0000, 0x0200
RAM: entity work.RAM --512byte
port map(
	address	=> cpu_addr(8 downto 0),
	clock		=> clk_50,
	data		=>  cpu_dout (7 DOWNTO 0),
	wren 		=> ram_wren,
	q			=> ram_dout
);


--Middle Earth 608
E0_ROM: entity work.ROM1 --2K 0x7800, 0x0800 & 0xf800, 0x0800
port map(
	address	=> cpu_addr(10 downto 0),
	clock		=> clk_50,
	q			=> rom1_dout
	);

E00_ROM: entity work.ROM2 --2K 0x7000, 0x0800
port map(
	address	=> cpu_addr(10 downto 0),
	clock		=> clk_50,
	q			=> rom2_dout
);


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

--clock_gen: entity work.cpu_clk_gen
--port map(   
--	clk_in => clk_50,
--	clk_out	=> cpu_clk
--);

META1: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => reset_l,
	o_Q => reset_l_stable,
   i_Fast_Clk => clk_50
	);

	
end rtl;


		