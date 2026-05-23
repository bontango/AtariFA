library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SN7493 is 

  port( 
    Clock : in std_logic;	      -- system clock
	 Clk_in : in std_logic;	      -- rising edge    
	 rst_l: in std_logic;
    Q_out: out std_logic_vector(3 downto 0)
    );

end entity SN7493; 

architecture behaviour of SN7493 is 
	 signal reg1 :std_logic;
    signal reg2 :std_logic;
	signal counter: unsigned(3 downto 0):="0000"; 
begin 

  process(Clock,rst_l)

  begin

    if rst_l = '0' then
      counter <= "0000";
    elsif rising_edge(Clock) then 
	 		reg1  <= Clk_in;
         reg2  <= reg1;
			if (reg1 and (not reg2)) = '1' then
				counter <= counter + 1;
			end if;	
    end if;
  end process; 
  
    Q_out <= std_logic_vector(counter);

end architecture behaviour;

