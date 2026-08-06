-- read the dips on AtariFA
-- bontango 06.2026
--
-- v 1.0 

LIBRARY ieee;
USE ieee.std_logic_1164.all;

    entity read_the_dips is
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
		signal state : STATE_T := Start;       		
	begin
	
	
	 read_dips_proc: process (clk_in)  -- fully synchronous; return1/2 sampled on rising edge
    begin
		if rising_edge(clk_in) then			
			if i_Rst_L = '0' then --Reset condidition (reset_l)    
			  state <= Start;
			  dip_strobe <= "111";
			  done <= '0';
			else
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
			end if; --reset				
		end if;	--rising edge		
		end process;
    end Behavioral;