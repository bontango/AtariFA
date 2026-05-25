-- lamp_driver - drive lamp matrix via cascade of 11x TPIC6B595N
-- part of AtariFA
-- bontango 05.2026
--
-- v 0.1 - first implementation (Phase B lamps)
--
-- Replaces the original Atari Gen1 9334 addressable latch + ULN2003A chain.
-- 84 lamps -> 11x TPIC6B595N (8-bit power shift register, open drain) = 88 bits.
-- TPIC outputs are latched & static (no multiplex), like the original 9334 latch.
--
-- Source data: lamp_state(87..0), fed from the RAM 0x30-0x3F write-sniffer
-- shadow buffer in AtariFA.vhd (analogous to the display shadow buffer).
--
-- Timing / coherence:
--   Runs in clk_50 domain, fully decoupled from CPU write timing.
--   Double-buffered: lamp_state is snapshotted into shiftreg at frame start,
--   then 88 bits are shifted out MSB-first, then RCK latches them.
--   With SHIFT_DIV=25 -> SRCK ~1 MHz -> full 88-bit frame ~88 us
--   -> ~11 kHz refresh, far faster than any game lamp change (<= 512 us NMI rate).
--
-- Cascade wiring: FPGA ser -> chip0 SER_IN, chip0 SER_OUT -> chip1 SER_IN, ...
--   srck (SRCK) and rck (RCK) are common to all chips.
--   First bit shifted (bit 87) ends up in the LAST chip of the chain.
--   Physical lamp# <-> bit mapping is done in the AtariFA.vhd sniffer (HW fine-tuning).

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity lamp_driver is
	generic (
		-- clk_50 ticks per SRCK half-period; 25 -> ~1 MHz SRCK (~88 us / frame)
		SHIFT_DIV : integer := 25
	);
	port (
		clk_50     : in  std_logic;
		reset      : in  std_logic;                      -- active high
		lamp_state : in  std_logic_vector(87 downto 0);  -- 84 lamps used, 4 spare
		ser        : out std_logic;   -- serial data to chain
		srck       : out std_logic;   -- shift register clock (common)
		rck        : out std_logic;   -- storage/latch clock (common)
		g_n        : out std_logic    -- output enable, active low ('0' = lamps on)
	);
end lamp_driver;

architecture rtl of lamp_driver is
	type state_t is (St_Snapshot, St_ShiftLow, St_ShiftHigh, St_Latch, St_Done);
	signal state    : state_t := St_Snapshot;
	signal shiftreg : std_logic_vector(87 downto 0) := (others => '0');
	signal bit_idx  : integer range 0 to 87 := 0;
	signal div_cnt  : integer range 0 to SHIFT_DIV := 0;
	signal tick     : std_logic := '0';
begin

	g_n <= '0';  -- lamps permanently enabled; on/off is carried in the data

	-- shift-clock tick generator (one tick every SHIFT_DIV clk_50 cycles)
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

	-- shift-out FSM (advances one step per tick)
	process(clk_50)
	begin
		if rising_edge(clk_50) then
			if reset = '1' then
				state   <= St_Snapshot;
				srck    <= '0';
				rck     <= '0';
				ser     <= '0';
				bit_idx <= 0;
			elsif tick = '1' then
				case state is
					when St_Snapshot =>
						shiftreg <= lamp_state;   -- coherent snapshot (double-buffer)
						bit_idx  <= 0;
						srck     <= '0';
						rck      <= '0';
						state    <= St_ShiftLow;

					when St_ShiftLow =>
						ser   <= shiftreg(87);    -- MSB first; data set while SRCK low
						srck  <= '0';
						state <= St_ShiftHigh;

					when St_ShiftHigh =>
						srck     <= '1';          -- rising edge clocks the bit in
						shiftreg <= shiftreg(86 downto 0) & '0';
						if bit_idx = 87 then
							state <= St_Latch;
						else
							bit_idx <= bit_idx + 1;
							state   <= St_ShiftLow;
						end if;

					when St_Latch =>
						srck  <= '0';
						rck   <= '1';             -- transfer shift -> storage register
						state <= St_Done;

					when St_Done =>
						rck   <= '0';
						state <= St_Snapshot;     -- continuous refresh
				end case;
			end if;
		end if;
	end process;

end rtl;
