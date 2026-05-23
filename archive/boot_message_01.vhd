-- boot message on Atari Display
-- part of  AtariFA
-- bontango 02.2025
--
-- v 1.0
--
--Atari timing
--during setting :
--	disp_Anode_blank high
--	disp_Cathode_blank low
--	setting phase is 70uS
--	with 16x load (active low -> high ) one load 1,24uS low followed by 2,78uS high
-- 
--
--show phase ( 384uS )
--	disp_Anode_blank low
--	disp_Cathode_blank high
--
-- coding
-- disp_addr
--		bits 0..2 digit 0..5 in display ( digit 6	is 'player up ) digit 7 not used
-- 	bits 3..4 player ( 00 == #4; 01 == #3; 10 == #2; 11 == #1 )
--		bits 5..6 ( 01 == status while bits 3&4 == 11 )
-- 
-- implementation
-- Atari uses 8 'rounds' (one per digit) with 16 loads each
-- however most of the loads are not needed and will be ignored by the display
-- the routine here just uses 7 rounds (display digits 0..5 and player up LEDs) 
-- and only 5 loads ( player1 to 4 and status display )
--
--


LIBRARY ieee;
USE ieee.std_logic_1164.all;

package instruction_buffer_type is
	type DISPLAY_T is array (0 to 6) of std_logic_vector(3 downto 0); -- digit #6 is Player up LEDS
	type DISPLAY_TS is array (0 to 3) of std_logic_vector(3 downto 0);
end package instruction_buffer_type;

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.instruction_buffer_type.all;

    entity boot_message is        
        port(
            clk  : in std_logic;      -- 1MHz clock  one clock each uS  
				show   : in  std_logic;		
				-- input (display data)
			   display1			: in  DISPLAY_T;
				display2			: in  DISPLAY_T;
				display3			: in  DISPLAY_T;
				display4			: in  DISPLAY_T;
				status_d			: in  DISPLAY_TS;
-- leds ?				
				--output (display control)
				disp_Data: out 	std_logic_vector(3 downto 0);
				disp_Adr: out 	std_logic_vector(6 downto 0);
				disp_Load			: 	out 	std_logic;
				disp_Cathode_blank			: 	out 	std_logic;
				disp_Anode_blank			: 	out 	std_logic			
            );
    end boot_message;
    ---------------------------------------------------
    architecture Behavioral of boot_message is
		signal count : integer range 0 to 550 := 0;
		signal digit : integer range 0 to 6 := 0;
	 begin
	
  boot_message: process (clk, show)
    begin
			if ( show = '0') then  -- Asynchronous reset
				--   output and variable initialisation
				disp_Cathode_blank <= '1';
				disp_Anode_blank <= '0';
				disp_Load <= '1';
				disp_Adr <= (others => '0');
				count <= 0;
				digit <= 0;
			elsif rising_edge(clk) then
				-- inc count for next round
				count <= count +1; -- 1MHz input we have a clk each uS
				case count is 				
					when 0 => 				
						disp_Load <= '0';
						-- make sure display is OFF during pushing new data
						disp_Cathode_blank <= '1';
						disp_Anode_blank <= '0';					
						-- Display #4
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "000";												
						disp_Data <= display4(digit);						
					when 2 => 										
						disp_Load <= '1'; --push data
						
					when 4 => 				
						disp_Load <= '0';
						-- Display #3
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "001";												
						disp_Data <= display3(digit);						
					when 6 => 										
						disp_Load <= '1'; --push data
						
					when 8 => 				
						disp_Load <= '0';
						-- Display #2
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "010";												
						disp_Data <= display2(digit);						
					when 10 => 										
						disp_Load <= '1'; --push data
					
					when 12 => 				
						disp_Load <= '0';
						-- Display #1
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "011";												
						disp_Data <= display1(digit);						
					when 14 => 										
						disp_Load <= '1'; --push data
					
					when 16 => 				
						disp_Load <= '0';
						-- Status Display #3
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "111";												
						disp_Data <= status_d(digit);						
					when 18 => 										
						disp_Load <= '1'; --push data
					
					--wait before activating display to ensure original timing
					when 123 => 												
						disp_Cathode_blank <= '0';
						disp_Anode_blank <= '1';					
					--prepare for next digit
					when 505 =>		
						count <= 0;
						digit <= digit +1;
						if ( digit = 6 ) then
							digit <= 0;
						end if	;

					when others =>								
						-- do nothing
						--disp_Adr <= (others => '0');
				end case;
			end if; --rising edge		
		end process;
    end Behavioral;