-- solenoid_driver.vhd  --  AtariFA Phase B: 20 Solenoide + 2 Muenztuer-Spulen
-- bontango 07.2026
--
-- Bildet die vier Original-Solenoid-Latches der Prozessor-PCB nach (statische
-- Latches wie das Original 74LS175, kein Multiplex). Die CPU schreibt nach
-- 0x1080/1084/1088/108C; nur die SOLENOID-Bits werden hier verwendet:
--   0x1080 bit4..7, 0x1084 bit4..7, 0x1088 bit4..7, 0x108C bit0..7  = 20 Bits.
--   (Die unteren Nibbles 0x1080/1084/1088 bit0..3 = SOUND, siehe sound.vhd.)
--
-- Ausgang: sol(1..20) = solenoids(1..20) = F_Q1..F_Q20 (aktiv-high '1'=bestromt);
--   AtariFA.vhd invertiert fuer den 74HCT540 (-> '1' = MOSFET AUS).
-- Muenztuer (Aux-PCB): coin_cntr = 0x1080 bit4, lockout = 0x1080 bit5.
--
-- Sicherheit: bei reset='1' ODER enable='0' sind alle Solenoide AUS (Defense-in-depth,
--   zusaetzlich zur physischen solenoids_enable-Gate am 74HCT540). Kein Auto-Timeout:
--   LOCKOUT ist ein Dauerstrom-Coil, Puls-Timing macht der Game-Code (wie Original).
--
-- Bit->Ausgang-Zuordnung: schaltplan-/HW-verifiziert aus solenoid_mapping.txt
--   (keine Doppelbelegung geprueft; F_Q14/F_Q18 auf diesem Board unbestueckt).
--   Bei falscher Reihenfolge am Prototyp: NUR den Zuordnungsblock unten anpassen.

library ieee;
use ieee.std_logic_1164.all;

entity solenoid_driver is
	port (
		clk_50    : in  std_logic;
		reset     : in  std_logic;                       -- active-high: alle Ausgaenge AUS
		wr        : in  std_logic;                        -- 1-clk-Strobe (clk_50) bei 0x108x-Write
		latch_sel : in  std_logic_vector(1 downto 0);     -- cpu_addr(3 downto 2): 00=1080 01=1084 10=1088 11=108C
		data      : in  std_logic_vector(7 downto 0);     -- cpu_dout
		enable    : in  std_logic;                        -- '1'=Solenoide live; '0'=erzwinge AUS
		sol       : out std_logic_vector(1 to 20);        -- aktiv-high ('1'=bestromt)
		coin_cntr : out std_logic;                        -- aktiv-high (0x1080 bit4)
		lockout   : out std_logic                         -- aktiv-high (0x1080 bit5)
	);
end solenoid_driver;

architecture rtl of solenoid_driver is
	-- gelatchte Latch-Register (nur die genutzten Bits werden ausgewertet)
	signal l1080 : std_logic_vector(7 downto 0) := (others => '0');
	signal l1084 : std_logic_vector(7 downto 0) := (others => '0');
	signal l1088 : std_logic_vector(7 downto 0) := (others => '0');
	signal l108c : std_logic_vector(7 downto 0) := (others => '0');
	signal sol_i : std_logic_vector(1 to 20);
begin

	-- Latch-Uebernahme in clk_50; Reset loescht alle Latches (alle Solenoide AUS).
	process(clk_50)
	begin
		if rising_edge(clk_50) then
			if reset = '1' then
				l1080 <= (others => '0');
				l1084 <= (others => '0');
				l1088 <= (others => '0');
				l108c <= (others => '0');
			elsif wr = '1' then
				case latch_sel is
					when "00"   => l1080 <= data;   -- 0x1080
					when "01"   => l1084 <= data;   -- 0x1084
					when "10"   => l1088 <= data;   -- 0x1088
					when others => l108c <= data;   -- 0x108C
				end case;
			end if;
		end if;
	end process;

	----------------------------------------------------------------------
	-- Bit -> Ausgang  (aus solenoid_mapping.txt; HW-tunbar: nur hier anpassen)
	----------------------------------------------------------------------
	sol_i(1)  <= l1084(7);
	sol_i(2)  <= l1084(5);
	sol_i(3)  <= l1084(6);
	sol_i(4)  <= l1088(5);
	sol_i(5)  <= l108c(6);
	sol_i(6)  <= l1088(7);
	sol_i(7)  <= l1088(4);
	sol_i(8)  <= l1084(4);
	sol_i(9)  <= l108c(3);
	sol_i(10) <= l108c(0);
	sol_i(11) <= l1080(7);
	sol_i(12) <= l1088(6);
	sol_i(13) <= l1080(6);
	sol_i(14) <= '0';            -- F_Q14 unbestueckt
	sol_i(15) <= l108c(5);
	sol_i(16) <= l108c(7);
	sol_i(17) <= l108c(4);
	sol_i(18) <= '0';            -- F_Q18 unbestueckt
	sol_i(19) <= l108c(2);
	sol_i(20) <= l108c(1);

	-- enable-Gate (Defense-in-depth): bei enable='0' alle Solenoide AUS
	sol       <= sol_i when enable = '1' else (others => '0');
	coin_cntr <= l1080(4) when enable = '1' else '0';   -- COIN_CNTREN
	lockout   <= l1080(5) when enable = '1' else '0';   -- LOCKOUT_EN

end rtl;
