-- display control on Atari Display
-- part of  AtariFA
-- bontango 02.2025
--
-- v 2.0  (2026-06-20) Timing an Originalschaltung angeglichen
--
-- ============================================================================
--  TIMING-QUELLE: gemessen aus realer LogicPort-Aufzeichnung des Original-Boards
--  Ausfuehrliche Doku + Schaltbild-Bezug:  doc/Display_Timing.md
--  (Schaltbild: doc/Display_Logic.png, Sheet 15B; Mess-LPF: _debug/Atari_Display_org*.LPF)
-- ============================================================================
--
-- Gemessenes Original-Timing (10 ns Aufloesung):
--   LOAD-Puls   : low (aktiv) 1,23 us / high 2,77 us / Periode 4,0 us
--   Blank/Setup : 129 us  (disp_Cathode_blank=0, disp_Anode_blank=1  -> Display AUS)
--   Show        : 383 us  (disp_Cathode_blank=1, disp_Anode_blank=0  -> Display AN)
--   Digit-Periode: 512 us (= 129 + 383)  -> Duty ~25% aus / 75% an (1:3)
--   16 Loads/Digit (4 Player x 4 Select), 8 Digits/Frame -> 4,10 ms -> ~244 Hz
--
-- WICHTIG (siehe doc): der dominante Fidelity-Hebel ist das Blank:Show-Verhaeltnis.
--   Die fruehere Fassung (Blank ~11 us / Show ~232 us, 7 Digits, ~585 Hz) lief mit
--   ~95% Einschaltdauer -> Anzeige real ~25% zu hell. Jetzt 75% wie Original.
--
-- coding (DISPLAY ADRS, 7 Bit)
--   bits 0..2 : digit 0..5 in display ( digit 6 = 'player up', digit 7 = unbenutzt )
--   bits 3..4 : player ( 00 == #4; 01 == #3; 10 == #2; 11 == #1 )
--   bits 5..6 : select ( 111 -> status while ... )
--
-- implementation
--   Das Original nutzt 8 'rounds' (eine je Digit) mit je 16 Loads; die meisten Loads
--   werden vom Display ignoriert. Diese FSM nutzt 8 Runden (digit 0..7) und nur 5 Loads
--   (Player1..4 + Status) -- funktional aequivalent, da nur diese 5 Displays existieren.
--   Digit 7 ist der unbenutzte 8. Scan-Slot des Originals und wird leer (x"F") geladen,
--   damit Frame-Periode/Refresh exakt passen (C_LAST_DIGIT=6 setzen => 7 Runden wie frueher).
--
-- Takt = 1 MHz  =>  1 count = 1 us.


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

		-- ----- Timing-Konstanten (us @ 1 MHz), siehe doc/Display_Timing.md ---------
		-- Zaehl-Semantik wie bisher: "count > N" belegt den Zustand fuer ~N+2 Takte.
		-- Blank gesamt = St_Disp_off (1us) + 5x(Load+Push) (10us) + St_Blank-Pad (~118us) = ~129us.
		constant C_BLANK_PAD  : integer := 116;  -- Pad-AUS nach den Loads  -> Blank gesamt ~129 us
		constant C_SHOW       : integer := 381;  -- Display AN              -> Show        ~383 us
		constant C_LAST_DIGIT : integer := 7;    -- 8 Runden (0..7); 6 setzen => 7 Runden (alt)

		-- ----- index-sichere Nibble-Zugriffe ---------------------------------------
		-- DISPLAY_T  hat nur 0..6, DISPLAY_TS nur 0..3. Der laufende 'digit'-Index geht
		-- bis 7 -> Index klemmen und ausserhalb des gueltigen Bereichs leer (x"F") liefern.
		-- (entschaerft zugleich den frueheren latenten status_d(digit>3)-Ueberlauf)
		function display_nibble(d : DISPLAY_T; idx : integer) return std_logic_vector is
			variable i : integer range 0 to 6;
		begin
			if idx > 6 then
				return "1111";          -- digit 7: unbenutzter 8. Scan-Slot -> blank
			else
				i := idx;
				return d(i);
			end if;
		end function;

		function status_nibble(s : DISPLAY_TS; idx : integer) return std_logic_vector is
			variable i : integer range 0 to 3;
		begin
			if idx > 3 then
				return "1111";          -- Status-Display hat nur 4 Ziffern (0..3) -> blank
			else
				i := idx;
				return s(i);
			end if;
		end function;

	 	type STATE_T is ( St_Disp_off,
								St_Load1, St_Push1,
								St_Load2, St_Push2,
								St_Load3, St_Push3,
								St_Load4, St_Push4,
								St_Load5, St_Push5,
								St_Blank, St_Show );
		signal state : STATE_T;
		signal count : integer range 0 to 550 := 0;
		signal digit : integer range 0 to 7 := 0;
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
						-- Display AUS waehrend neue Daten geladen werden (Beginn Blank-Phase)
						disp_Cathode_blank <= '0';
						disp_Anode_blank <= '1';
						state <= St_Load1;

					when St_Load1 =>
						disp_Load <= '0';
						-- Display #4
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "000";
						disp_Data <= display_nibble(display4, digit);
						state <= St_Push1;
					when St_Push1 =>
						disp_Load <= '1'; --push data
						state <= St_Load2;

					when St_Load2 =>
						disp_Load <= '0';
						-- Display #3
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "001";
						disp_Data <= display_nibble(display3, digit);
						state <= St_Push2;
					when St_Push2 =>
						disp_Load <= '1'; --push data
						state <= St_Load3;

					when St_Load3 =>
						disp_Load <= '0';
						-- Display #2
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "010";
						disp_Data <= display_nibble(display2, digit);
						state <= St_Push3;
					when St_Push3 =>
						disp_Load <= '1'; --push data
						state <= St_Load4;

					when St_Load4 =>
						disp_Load <= '0';
						-- Display #1
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "011";
						disp_Data <= display_nibble(display1, digit);
						state <= St_Push4;
					when St_Push4 =>
						disp_Load <= '1'; --push data
						state <= St_Load5;

					when St_Load5 =>
						disp_Load <= '0';
						-- Status Display
						disp_Adr(2 downto 0) <= std_logic_vector( to_unsigned((digit),3));
						disp_Adr(5 downto 3) <= "111";
						disp_Data <= status_nibble(status_d, digit);
						state <= St_Push5;
					when St_Push5 =>
						disp_Load <= '1'; --push data
						state <= St_Blank;

					-- Blank-Phase auf Original-Dauer padden (Display bleibt AUS).
					-- cath/anod behalten ihren in St_Disp_off gesetzten AUS-Pegel (Register).
					when St_Blank =>
						count <= count + 1;
						if (count > C_BLANK_PAD) then    -- ~118 us + ~11 us Loads = ~129 us Blank
							count <= 0;
							state <= St_Show;
						end if;

					-- Show-Phase: Display AN fuer ~383 us, danach naechstes Digit.
					when St_Show =>
						disp_Cathode_blank <= '1';
						disp_Anode_blank <= '0';
						count <= count + 1;
						if (count > C_SHOW) then          -- ~383 us
							count <= 0;
							if ( digit = C_LAST_DIGIT ) then
								digit <= 0;
							else
								digit <= digit + 1;
							end if;
							state <= St_Disp_off;
						end if;
				end case;
			end if; --rising edge
		end process;
    end Behavioral;
