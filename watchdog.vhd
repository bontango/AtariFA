-- Watchdog timer for Atari Gen1 MPU
-- Write to 0x4000 resets the counter (kick). On timeout, asserts wd_reset
-- for RESET_WIDTH clk cycles, then releases. Provides both power-on reset
-- (counter starts at 0 and times out before game code runs) and hang recovery.
-- Bontango 2026

library ieee;
use ieee.std_logic_1164.all;

entity watchdog is
  generic (
    TIMEOUT_COUNT : natural := 12_500_000;  -- ~250 ms @ 50 MHz
    RESET_WIDTH   : natural := 50           -- reset pulse width in clk cycles (~1 us)
  );
  port (
    clk      : in  std_logic;  -- clk_50
    rst_l    : in  std_logic;  -- reset_l_stable (external reset, active low)
    kick     : in  std_logic;  -- 1-cycle pulse on write to 0x4000
    wd_reset : out std_logic   -- active-high CPU reset pulse on timeout
  );
end watchdog;

architecture rtl of watchdog is
  signal count : natural range 0 to TIMEOUT_COUNT + RESET_WIDTH := 0;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_l = '0' then
        count    <= 0;
        wd_reset <= '0';
      elsif count >= TIMEOUT_COUNT then
        wd_reset <= '1';
        if count = TIMEOUT_COUNT + RESET_WIDTH - 1 then
          count <= 0;
        else
          count <= count + 1;
        end if;
      else
        wd_reset <= '0';
        if kick = '1' then
          count <= 0;
        else
          count <= count + 1;
        end if;
      end if;
    end if;
  end process;
end rtl;
