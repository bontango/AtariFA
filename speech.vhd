-- ============================================================
-- speech.vhd
-- Boot-Sprachausgabe ("Lisy") als 8-Bit-PCM-Wiedergabe.
-- Teil von AtariFA -- bontango 06.2026
--
-- Konzept/Begruendung: doc/Speech_Boot_Feasibility.md
--   Ursprung war 1-Bit-Delta-Modulation (Logik-/ROM-Minimum). Wegen hoerbarem
--   Quantisierungsrauschen (zu geringe Ueberabtastung) auf 8-Bit-PCM gewechselt:
--   sauberster Klang, Decoder sogar einfacher, dafuer 4 M9K statt 1.
--   - ROM = 8 Bit/Sample (PCM), 4096 x 8            -> 4 M9K
--   - Decoder = Adresszaehler + Ratenteiler         -> ~30 LE (kein Akku)
--   - Ausgabe = First-Order-Sigma-Delta @ clk_50    (identisch zu sound.vhd)
--     -> SB_Sound -> Onboard-RC (3k3/4n7) -> TDA7267
--
-- Eigenstaendig/portabel: keine Bus-Anbindung, nur Start-Trigger.
-- ROM-Inhalt offline erzeugen mit:
--   tools/make_speech_mif.py --in <wav> --out rom/lisy.mif --rate 8000 --pcm \
--                            --fade-out-ms 35 --depth 4096
-- (CLK_DIV-Generic muss zur --rate passen: CLK_DIV = 50e6 / rate.)
--
-- Integriert in AtariFA.vhd (Instanz SPEECH_INST): reset = not boot_phase(0),
-- start = boot_phase(1), Ausgabe ueber SB_Sound-Mux (Vorrang vor Sound-Emulation).
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity speech is
    generic(
        INIT_FILE : string  := "./rom/lisy.mif"; -- 8-Bit-PCM (make_speech_mif.py --pcm)
        N_SAMPLES : integer := 3687;             -- aktive Wortlaenge in Samples (<= 4096); "Lisy"@8kHz
        CLK_DIV   : integer := 6250              -- clk_50 / SAMPLE_HZ  (50e6/8e3 = 6250)
    );
    port(
        clk_50  : in  std_logic;
        reset   : in  std_logic;                 -- synchron, active-high
        start   : in  std_logic;                 -- 1 Puls -> Wort einmal abspielen
        busy    : out std_logic;                 -- '1' waehrend Wiedergabe
        pwm_out : out std_logic                  -- 1-Bit Audio (auf SB_Sound muxbar)
    );
end speech;

architecture rtl of speech is
    constant ADDR_W : integer := 12;             -- 2^12 = 4096 Worte

    signal div_cnt  : integer range 0 to CLK_DIV-1 := 0;
    signal tick     : std_logic := '0';          -- 1-clk Puls @ SAMPLE_HZ

    signal addr     : unsigned(ADDR_W-1 downto 0) := (others => '0');
    signal rom_q    : std_logic_vector(7 downto 0);
    signal pcm_val  : unsigned(7 downto 0);      -- aktueller PCM-Wert in den DAC

    signal playing  : std_logic := '0';
    signal start_d  : std_logic := '0';

    signal sd_acc   : unsigned(8 downto 0) := (others => '0');  -- Sigma-Delta-Akku
begin

    --------------------------------------------------------------------------
    -- 8-Bit-PCM-ROM (altsyncram, 4096 x 8, init aus Generic)
    --------------------------------------------------------------------------
    ROM: entity work.speech_rom
        generic map( init_file => INIT_FILE )
        port map(
            address => std_logic_vector(addr),
            clock   => clk_50,
            q       => rom_q
        );

    --------------------------------------------------------------------------
    -- Sample-Ratenteiler: erzeugt 'tick' mit SAMPLE_HZ, nur waehrend Wiedergabe
    --------------------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            tick <= '0';
            if playing = '0' then
                div_cnt <= 0;
            elsif div_cnt = CLK_DIV-1 then
                div_cnt <= 0;
                tick    <= '1';
            else
                div_cnt <= div_cnt + 1;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- PCM-Ablaufsteuerung: Start an Vorderflanke von 'start'. Pro Sample-Tick
    -- eine Adresse weiter; rom_q liefert den 8-Bit-Wert (1-clk Leselatenz, bei
    -- 6250 clk/Tick vernachlaessigbar). Ende bei N_SAMPLES-1.
    --------------------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                playing <= '0';
                addr    <= (others => '0');
                start_d <= '0';
            else
                start_d <= start;
                if start = '1' and start_d = '0' and playing = '0' then
                    playing <= '1';
                    addr    <= (others => '0');
                elsif playing = '1' and tick = '1' then
                    if addr = to_unsigned(N_SAMPLES-1, ADDR_W) then
                        playing <= '0';
                        addr    <= (others => '0');
                    else
                        addr <= addr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Waehrend Wiedergabe der ROM-Wert, sonst 128 (Mittelpegel = Stille).
    -- Das Wortende ist im ROM bereits auf ~128 ausgeblendet (Fade-Out) -> kein Knacks.
    pcm_val <= unsigned(rom_q) when playing = '1' else x"80";
    busy    <= playing;

    --------------------------------------------------------------------------
    -- First-Order-Sigma-Delta-DAC (identisch zu sound.vhd), 50-MHz-Oversampling
    --------------------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if reset = '1' then
                sd_acc <= (others => '0');
            else
                sd_acc <= ('0' & sd_acc(7 downto 0)) + ('0' & pcm_val);
            end if;
        end if;
    end process;
    pwm_out <= sd_acc(8);

end rtl;
