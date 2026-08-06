-- fram_i2c.vhd  --  AtariFA Phase C: I2C-Master fuer FRAM FM24CL64B-GTR
-- bontango 07.2026
--
-- Einfacher Single-Master-I2C-Treiber (Bit-Banging-FSM @clk_50) zum Sichern/Wiederherstellen
-- der Spielstaende (Scores + Credits) im externen FRAM. Atari Gen1 hat kein natives NVRAM;
-- das FRAM haelt die persistenten Bytes ueber den Power-Cycle.
--
-- Bausteine (FM24CL64B, 8K x 8):
--   * Slave-Adresse: Control-Code "1010" + A2 A1 A0. Auf AtariFA: A0=1 (3V), A1=A2=0 (GND)
--     -> 7-Bit-Slave 1010_001 = 0x51  (Write-Byte 0xA2, Read-Byte 0xA3).
--   * 2-Byte-Speicheradresse (MSB zuerst), 13 Bit genutzt, obere 3 Bit = 0.
--   * SDA ist open-drain (extern Pull-up): intern nur nach '0' ziehen oder freigeben ('Z').
--     SCL wird als Push-Pull-Ausgang getrieben (Single-Master, keine Clock-Stretch-Ausw.).
--
-- Ablauf WRITE (N_BYTES ab mem_addr):
--   START -> 0xA2 -> AdrHi -> AdrLo -> N x Datenbyte -> STOP
-- Ablauf READ (N_BYTES ab mem_addr):
--   START -> 0xA2 -> AdrHi -> AdrLo -> RepSTART -> 0xA3 -> N x Byte-In (letztes NACK) -> STOP
--
-- Bit-Timing: je I2C-Bit 4 Phasen (Viertelperioden) zu je CLK_DIV clk_50-Takten.
--   Default CLK_DIV=125 -> Viertel=2,5 us -> SCL-Periode 10 us = 100 kHz (FM24CL64B: bis 1 MHz).
--
-- Kein BRAM (reine Register/Records). Slave-ACK wird gesampelt aber (bewusst) nicht als
-- Fehler ausgewertet -- der Ablauf laeuft in jedem Fall bis STOP durch (robust gegen fehlenden
-- Pull-up in der Simulation). Bei Bedarf ack_from_slave nach aussen fuehren.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

package fram_types is
	-- unbeschraenktes Byte-Array fuer die FRAM-Nutzdaten (Save-Puffer / Shadow)
	type fram_data_t is array (natural range <>) of std_logic_vector(7 downto 0);
end package fram_types;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.fram_types.all;

entity fram_i2c is
	generic (
		DEV_ADDR : std_logic_vector(6 downto 0) := "1010001"; -- 0x51 (A0=1,A1=A2=0)
		CLK_DIV  : integer := 125;                            -- clk_50-Takte je I2C-Viertelperiode (~100 kHz)
		N_BYTES  : integer := 16                              -- Bytes je Block-Transfer
	);
	port (
		clk_50   : in  std_logic;
		reset    : in  std_logic;                             -- active-high
		-- Kommando-Schnittstelle: cmd_read/cmd_write mit 1-clk 'go' latchen
		go       : in  std_logic;                             -- 1-clk Start-Strobe
		cmd_read : in  std_logic;                             -- '1'=Read-Block, '0'=Write-Block
		mem_addr : in  std_logic_vector(15 downto 0);         -- FRAM-Startadresse
		wr_data  : in  fram_data_t(0 to N_BYTES-1);           -- zu schreibende Bytes
		rd_data  : out fram_data_t(0 to N_BYTES-1);           -- gelesene Bytes
		busy     : out std_logic;                             -- '1' waehrend Transfer
		done     : out std_logic;                             -- 1-clk Puls bei Abschluss
		ack_dbg  : out std_logic;                             -- letztes Slave-ACK ('0'=ACK), Diagnose
		ack_ok   : out std_logic;                             -- '1' wenn im letzten Transfer mind. 1 Slave-ACK kam (FRAM antwortet)
		scl_dbg  : out std_logic;                             -- Spiegel von scl (out-Port ist nicht lesbar), Diagnose
		dbg_state: out std_logic_vector(2 downto 0);          -- FSM-Zustand (Diagnose)
		-- I2C-Bus
		sda      : inout std_logic;                           -- open-drain ('0' oder 'Z')
		scl      : out std_logic
	);
end fram_i2c;

architecture rtl of fram_i2c is
	-- Makro-Zustandsautomat mit "Unterprogramm"-Ruecksprung (ret_to_seq): der SEQ-Controller
	-- waehlt je Schritt die naechste Primitive (START/TX/RX/STOP), fuehrt sie aus und kehrt zurueck.
	type state_t is (IDLE, SEQ, P_START, P_TX, P_RX, P_STOP, FINISH);
	signal state    : state_t := IDLE;

	signal is_read  : std_logic := '0';
	signal step     : integer range 0 to N_BYTES+8 := 0;   -- Ablaufschritt im SEQ-Controller

	-- Bit-Timing
	signal q_cnt    : integer range 0 to CLK_DIV-1 := 0;   -- Viertelperioden-Zaehler
	signal phase    : integer range 0 to 3 := 0;           -- Phase innerhalb eines Bits
	signal bit_cnt  : integer range 0 to 8 := 0;           -- 0..7 = Datenbits, 8 = ACK-Bit
	signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
	signal rx_send_ack : std_logic := '0';                 -- bei RX: '1' = Master sendet ACK (sonst NACK)
	signal ack_from_slave : std_logic := '1';
	signal ack_ok_i    : std_logic := '0';                 -- sticky: im laufenden Transfer kam >=1 Slave-ACK

	signal scl_i    : std_logic := '1';
	signal sda_low  : std_logic := '0';                    -- '1' = SDA nach '0' ziehen, sonst 'Z'
	signal rd_buf   : fram_data_t(0 to N_BYTES-1) := (others => (others => '0'));

	-- Byte-Index innerhalb der Daten (fuer WR_LOOP / RD_LOOP)
	signal data_idx : integer range 0 to N_BYTES := 0;
begin

	-- Open-Drain SDA + SCL-Ausgang
	sda <= '0' when sda_low = '1' else 'Z';
	scl <= scl_i;
	scl_dbg <= scl_i;
	rd_data <= rd_buf;
	ack_dbg <= ack_from_slave;   -- letztes gesampeltes Slave-ACK ('0'=ACK) nach aussen (Diagnose)
	ack_ok  <= ack_ok_i;         -- '1' = FRAM hat im letzten Transfer geantwortet (mind. 1 ACK)
	with state select dbg_state <=
		"000" when IDLE,   "001" when SEQ,    "010" when P_START, "011" when P_TX,
		"100" when P_RX,   "101" when P_STOP, "110" when FINISH;

	process(clk_50)
		variable phase_last : boolean;
	begin
		if rising_edge(clk_50) then
			done <= '0';   -- Default: nur 1-clk-Puls in FINISH

			-- Ende einer Phase, wenn der Viertelperioden-Zaehler voll ist
			phase_last := (q_cnt = CLK_DIV-1);

			if reset = '1' then
				state    <= IDLE;
				scl_i    <= '1';
				sda_low  <= '0';
				busy     <= '0';
				q_cnt    <= 0;
				phase    <= 0;
				bit_cnt  <= 0;
				step     <= 0;
				data_idx <= 0;
				ack_ok_i <= '0';
			else
				case state is

				----------------------------------------------------------------
				when IDLE =>
					scl_i   <= '1';
					sda_low <= '0';
					busy    <= '0';
					q_cnt   <= 0;
					phase   <= 0;
					bit_cnt <= 0;
					if go = '1' then
						is_read  <= cmd_read;
						step     <= 0;
						data_idx <= 0;
						busy     <= '1';
						ack_ok_i <= '0';        -- neuer Transfer: ACK-Beobachtung zuruecksetzen
						state    <= SEQ;
					end if;

				----------------------------------------------------------------
				-- SEQ: waehlt die naechste Primitive anhand von is_read + step.
				-- WRITE: 0=START 1=TX(0xA2) 2=TX(AdrHi) 3=TX(AdrLo) 4..3+N=TX(Daten) -> STOP
				-- READ : 0=START 1=TX(0xA2) 2=TX(AdrHi) 3=TX(AdrLo) 4=RepSTART 5=TX(0xA3)
				--        6..5+N=RX(Daten)  -> STOP
				when SEQ =>
					q_cnt   <= 0;
					phase   <= 0;
					bit_cnt <= 0;
					if is_read = '0' then
						-- WRITE-Ablauf
						if step = 0 then
							state <= P_START;
						elsif step = 1 then
							shreg <= DEV_ADDR & '0';       -- 0xA2
							state <= P_TX;
						elsif step = 2 then
							shreg <= mem_addr(15 downto 8);
							state <= P_TX;
						elsif step = 3 then
							shreg <= mem_addr(7 downto 0);
							state <= P_TX;
						elsif step <= 3 + N_BYTES then
							data_idx <= step - 4;
							shreg    <= wr_data(step - 4);
							state    <= P_TX;
						else
							state <= P_STOP;
						end if;
						if step > 3 + N_BYTES then
							null;
						else
							step <= step + 1;
						end if;
					else
						-- READ-Ablauf
						if step = 0 then
							state <= P_START;
						elsif step = 1 then
							shreg <= DEV_ADDR & '0';       -- 0xA2 (Write, Adresse setzen)
							state <= P_TX;
						elsif step = 2 then
							shreg <= mem_addr(15 downto 8);
							state <= P_TX;
						elsif step = 3 then
							shreg <= mem_addr(7 downto 0);
							state <= P_TX;
						elsif step = 4 then
							state <= P_START;              -- Repeated START
						elsif step = 5 then
							shreg <= DEV_ADDR & '1';       -- 0xA3 (Read)
							state <= P_TX;
						elsif step <= 5 + N_BYTES then
							data_idx <= step - 6;
							-- alle Bytes ACKen, letztes NACKen
							if step = 5 + N_BYTES then
								rx_send_ack <= '0';        -- NACK vor STOP
							else
								rx_send_ack <= '1';        -- ACK
							end if;
							state <= P_RX;
						else
							state <= P_STOP;
						end if;
						if step > 5 + N_BYTES then
							null;
						else
							step <= step + 1;
						end if;
					end if;

				----------------------------------------------------------------
				-- START / Repeated START: SDA faellt waehrend SCL high
				when P_START =>
					case phase is
						when 0 => scl_i <= '0'; sda_low <= '0';   -- SDA freigeben (high), SCL low
						when 1 => scl_i <= '1'; sda_low <= '0';   -- SCL high, SDA high
						when 2 => scl_i <= '1'; sda_low <= '1';   -- SDA -> low bei SCL high = START
						when 3 => scl_i <= '0'; sda_low <= '1';   -- SCL low, SDA low
					end case;
					if phase_last then
						q_cnt <= 0;
						if phase = 3 then
							phase <= 0;
							state <= SEQ;
						else
							phase <= phase + 1;
						end if;
					else
						q_cnt <= q_cnt + 1;
					end if;

				----------------------------------------------------------------
				-- STOP: SDA steigt waehrend SCL high -> danach Bus idle (beide high)
				when P_STOP =>
					case phase is
						when 0 => scl_i <= '0'; sda_low <= '1';   -- SDA low, SCL low
						when 1 => scl_i <= '1'; sda_low <= '1';   -- SCL high, SDA low
						when 2 => scl_i <= '1'; sda_low <= '0';   -- SDA -> high bei SCL high = STOP
						when 3 => scl_i <= '1'; sda_low <= '0';   -- idle
					end case;
					if phase_last then
						q_cnt <= 0;
						if phase = 3 then
							phase <= 0;
							state <= FINISH;
						else
							phase <= phase + 1;
						end if;
					else
						q_cnt <= q_cnt + 1;
					end if;

				----------------------------------------------------------------
				-- TX: 8 Datenbits (MSB zuerst) + ACK-Bit lesen
				when P_TX =>
					if bit_cnt < 8 then
						-- Datenbit: SDA = shreg(7 - bit_cnt); '1' -> freigeben, '0' -> low ziehen
						case phase is
							when 0 => scl_i <= '0'; sda_low <= not shreg(7 - bit_cnt);
							when 1 => scl_i <= '1';
							when 2 => scl_i <= '1';
							when 3 => scl_i <= '0';
						end case;
					else
						-- ACK-Bit: SDA freigeben, Slave-ACK bei SCL high sampeln
						case phase is
							when 0 => scl_i <= '0'; sda_low <= '0';
							when 1 => scl_i <= '1';
							when 2 => scl_i <= '1'; ack_from_slave <= sda;
							          if sda = '0' then ack_ok_i <= '1'; end if;  -- FRAM hat quittiert
							when 3 => scl_i <= '0';
						end case;
					end if;
					if phase_last then
						q_cnt <= 0;
						if phase = 3 then
							phase <= 0;
							if bit_cnt = 8 then
								bit_cnt <= 0;
								state   <= SEQ;
							else
								bit_cnt <= bit_cnt + 1;
							end if;
						else
							phase <= phase + 1;
						end if;
					else
						q_cnt <= q_cnt + 1;
					end if;

				----------------------------------------------------------------
				-- RX: 8 Datenbits (MSB zuerst) einlesen + Master-ACK/NACK senden
				when P_RX =>
					if bit_cnt < 8 then
						case phase is
							when 0 => scl_i <= '0'; sda_low <= '0';                 -- SDA freigeben
							when 1 => scl_i <= '1';
							when 2 => scl_i <= '1';                                 -- SCL high
							          if phase_last then shreg <= shreg(6 downto 0) & sda; end if;  -- Bit GENAU 1x sampeln (letzter Takt der Phase)
							when 3 => scl_i <= '0';
						end case;
					else
						-- Master-ACK: rx_send_ack='1' -> SDA low ziehen (ACK); sonst freigeben (NACK)
						case phase is
							when 0 => scl_i <= '0'; sda_low <= rx_send_ack;
							when 1 => scl_i <= '1';
							when 2 => scl_i <= '1';
							when 3 => scl_i <= '0'; sda_low <= '0';                 -- danach freigeben
						end case;
					end if;
					if phase_last then
						q_cnt <= 0;
						if phase = 3 then
							phase <= 0;
							if bit_cnt = 8 then
								bit_cnt <= 0;
								rd_buf(data_idx) <= shreg;   -- fertiges Byte ablegen
								state   <= SEQ;
							else
								bit_cnt <= bit_cnt + 1;
							end if;
						else
							phase <= phase + 1;
						end if;
					else
						q_cnt <= q_cnt + 1;
					end if;

				----------------------------------------------------------------
				when FINISH =>
					scl_i   <= '1';
					sda_low <= '0';
					busy    <= '0';
					done    <= '1';
					state   <= IDLE;

				end case;
			end if;
		end if;
	end process;

end rtl;
