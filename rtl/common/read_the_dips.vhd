-- read the dips on AtariFA
-- bontango 06.2026
--
-- v 1.0
-- v 1.1 (SW 0.4.1, 11.2026): nach jedem Strobe-Wechsel SETTLE_CYCLES warten, bevor die
--       Rueckleitungen gelesen werden. Vorher lag zwischen Strobe-Wechsel und Abtastung genau
--       ein clk_in-Takt (1 us). Die Rueckleitungen ziehen nur ueber 10 K Pull-up hoch; war der
--       DIP der vorigen Zeile auf derselben Rueckleitung ON, kann die Leitung nach 1 us noch
--       low sein und der DIP der naechsten Zeile wird faelschlich als ON gelesen. Betroffen war
--       vor allem options(2) (return2, Vorgaengerzeile = Freispiel) = FRAM loeschen ab SW 0.4.0.

LIBRARY ieee;
USE ieee.std_logic_1164.all;

    entity read_the_dips is
        generic(
            SETTLE_CYCLES : integer := 50     -- clk_in-Takte je Zeile (cpu_clk 1 MHz -> 50 us)
            );
        port(
            clk_in  : in std_logic;
				i_Rst_L : in std_logic;     -- FPGA Reset
				--output
				done		: out std_logic;        -- set to 1 when read finished
				game_select	:	out std_logic_vector(2 downto 0);
				freeplay		: out std_logic;
				game_option	:	out std_logic_vector(1 to 2);
				-- strobes
			   dip_strobe		: out std_logic_vector(2 downto 0);
				-- input
				return1			: in std_logic;
				return2			: in std_logic
            );
    end read_the_dips;
    ---------------------------------------------------
    architecture Behavioral of read_the_dips is
	 	type STATE_T is ( Start, Read1, Read2, Read3, Idle );
		signal state  : STATE_T := Start;
		signal settle : integer range 0 to SETTLE_CYCLES := 0;
	begin


	 read_dips_proc: process (clk_in)  -- fully synchronous; return1/2 sampled on rising edge
    begin
		if rising_edge(clk_in) then
			if i_Rst_L = '0' then --Reset condidition (reset_l)
			  state <= Start;
			  dip_strobe <= "111";
			  done <= '0';
			  settle <= 0;
			else
				-- In Read1..Read3 erst die Wartezeit abzaehlen, dann abtasten + naechste Zeile
				if state /= Start and state /= Idle and settle < SETTLE_CYCLES then
					settle <= settle + 1;
				else
					settle <= 0;
					case state is
						when Start =>
							dip_strobe <= "110";
							state <= Read1;
						when Read1 =>
							game_select(0) <= return1;
							game_select(1) <= return2;
							dip_strobe <= "101";
							state <= Read2;
						when  Read2 =>
							game_select(2) <= return1;
							freeplay <= return2;
							dip_strobe <= "011";
							state <= Read3;
						when  Read3 =>
							game_option(1) <= return1;
							game_option(2) <= return2;
							dip_strobe <= "111";
							state <= Idle;
						when  Idle =>
							done <= '1'; -- set after first round
					end case;
				end if;
			end if; --reset
		end if;	--rising edge
		end process;
    end Behavioral;
