-- display control on Atari Display
-- part of  AtariFA
-- bontango 02.2025
--
-- v 1.1
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.instruction_buffer_type.all;

    entity display_control is
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
    end display_control;
    ---------------------------------------------------
    architecture Behavioral of display_control is
	 	type STATE_T is ( St_Disp_off, St_Load1, St_Push1, St_Wait1,
								St_Load2, St_Push2, St_Wait2,
								St_Load3, St_Push3,
								St_Load4, St_Push4,
								St_Load5, St_Push5 );								
		signal state : STATE_T; 	 
		signal count : integer range 0 to 550 := 0;
		signal digit : integer range 0 to 6 := 0;
	 begin
	
  boot_message: process (clk, show)
    begin
			if ( show = '0') then  -- Asynchronous reset
				--   output and variable initialisation
				disp_Cathode_blank <= '0';
				disp_Anode_blank <= '1';
				disp_Load <= '1';
				disp_Adr <= (others => '0');
				count <= 0;
				digit <= 0;
				state <= St_Disp_off;
			elsif rising_edge(clk) then
				-- disp_Adr(6) ist ungenutzt (nur Bits 0..2 Digit, 3..5 Select);
				-- hier getaktet auf '0' treiben -> Register statt Latch (vermeidet Warning 10631)
				disp_Adr(6) <= '0';
				case state is
					when St_Disp_off => 								
						-- make sure display is OFF during pushing new data
						disp_Cathode_blank <= '0';
						disp_Anode_blank <= '1';		
						state <= St_Load1;						
					when St_Load1 => 	
						disp_Load <= '0';			
						-- Display #4
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "000";												
						disp_Data <= display4(digit);		
						state <= St_Push1;
					when St_Push1 => 										
						disp_Load <= '1'; --push data
						state <= St_Load2;
						
					when St_Load2 => 				
						disp_Load <= '0';
						-- Display #3
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "001";												
						disp_Data <= display3(digit);
						state <= St_Push2;						
					when St_Push2 => 										
						disp_Load <= '1'; --push data
						state <= St_Load3;
						
					when St_Load3 => 				
						disp_Load <= '0';
						-- Display #2
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "010";												
						disp_Data <= display2(digit);		
						state <= St_Push3;
					when St_Push3 => 										
						disp_Load <= '1'; --push data
						state <= St_Load4;					
						
					when St_Load4 => 				
						disp_Load <= '0';
						-- Display #1
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "011";												
						disp_Data <= display1(digit);			
						state <= St_Push4;						
					when St_Push4 => 										
						disp_Load <= '1'; --push data
						state <= St_Load5;
						
					when St_Load5 => 				
						disp_Load <= '0';
						-- Status Display #3
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "111";												
						disp_Data <= status_d(digit);		
						state <= St_Push5;						
					when St_Push5 => 										
						disp_Load <= '1'; --push data
						state <= St_Wait1;
						
					--wait before activating display to ensure original timing
					when St_Wait1 => 												
						disp_Cathode_blank <= '1';
						disp_Anode_blank <= '0';	
						count <= count +1;
						if (count > 115 ) then
							count <= 0;
							state <= St_Wait2;
						end if;	
												
					--prepare for next digit
					when St_Wait2 =>	
						count <= count +1;
						if (count > 115 ) then
							count <= 0;
							digit <= digit +1;
							if ( digit = 6 ) then
								digit <= 0;
							end if	;
							state <= St_Disp_off;
						end if;	
				end case;
			end if; --rising edge		
		end process;
    end Behavioral;