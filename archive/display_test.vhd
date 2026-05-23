-- test off Atari Display
-- part of  AtariFA
-- bontango 02.2025
--
-- v 1.0
--


LIBRARY ieee;
USE ieee.std_logic_1164.all;

package instruction_buffer_type2 is
	--type DISPLAY_T is array (0 to 6) of std_logic_vector(3 downto 0); -- digit #6 is Player up LEDS
	--type DISPLAY_TS is array (0 to 3) of std_logic_vector(3 downto 0);
	type DISPLAY_ARRAY is array (0 to 31) of std_logic_vector(3 downto 0);
end package instruction_buffer_type2;

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.instruction_buffer_type.all;
use work.instruction_buffer_type2.all;

    entity disp_test is        
        port(
            clk  : in std_logic;      -- 1MHz clock  one clock each uS  
				show   : in  std_logic;		
				--output (display control)
			   display1			: out  DISPLAY_T;
				display2			: out  DISPLAY_T;
				display3			: out  DISPLAY_T;
				display4			: out  DISPLAY_T;
				status_d			: out  DISPLAY_TS
            );
    end disp_test;
    ---------------------------------------------------
    architecture Behavioral of disp_test is
	 	type STATE_T is ( St_Step, St_Load, St_Assign);
		signal state : STATE_T; 	 
		signal count : integer range 0 to 550000 := 0;
		signal digit : integer range 0 to 32 := 0;
		signal disp_array : DISPLAY_ARRAY;
	 begin
	
  disp_test: process (clk, show)
    begin
			if ( show = '0') then  -- Asynchronous reset
				--   output and variable initialisation
				count <= 0;
				digit <= 0;
				disp_array <= (others => x"F" );
				state <= St_Step;
			elsif rising_edge(clk) then
				case state is 		
					when St_Step => 								
						count <= count +1;
							if (count > 550000 ) then
							 count <= 0;
							 state <= St_Load;
						end if;

					when St_Load => 	
					   digit <= digit +1;
						disp_array(digit) <= x"8";
						if ( digit > 0 ) then
							disp_array(digit-1) <= x"F";
						end if;
						if ( digit = 32 ) then
							digit <= 0;
						end if;
						state <= St_Assign;
						
					when St_Assign => 	
						display1(5) <= disp_array(0);
						display1(4) <= disp_array(1);
						display1(3) <= disp_array(2);
						display1(2) <= disp_array(3);
						display1(1) <= disp_array(4);
						display1(0) <= disp_array(5);
						display1(6) <= disp_array(6);
						display2(5) <= disp_array(7);
						display2(4) <= disp_array(8);
						display2(3) <= disp_array(9);
						display2(2) <= disp_array(10);
						display2(1) <= disp_array(11);
						display2(0) <= disp_array(12);
						display2(6) <= disp_array(13);
						display3(5) <= disp_array(14);
						display3(4) <= disp_array(15);
						display3(3) <= disp_array(16);
						display3(2) <= disp_array(17);
						display3(1) <= disp_array(18);
						display3(0) <= disp_array(19);
						display3(6) <= disp_array(20);
						display4(5) <= disp_array(21);
						display4(4) <= disp_array(22);
						display4(3) <= disp_array(23);
						display4(2) <= disp_array(24);
						display4(1) <= disp_array(25);
						display4(0) <= disp_array(26);
						display4(6) <= disp_array(27);
						status_d(3) <= disp_array(28);
						status_d(2) <= disp_array(29);
						status_d(1) <= disp_array(30);
						status_d(0) <= disp_array(31);
						state <= St_Step;
				end case;
			end if; --rising edge		
		end process;
    end Behavioral;