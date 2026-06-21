-- Atari Gen1 integrated sound emulation
-- part of AtariFA
-- bontango 06.2026
--
-- Bildet die Original-Tonerzeugung der Prozessor-PCB digital nach:
--   D12      Sound-ROM (sound_rom): 16 Wellenformen x 32 Samples, 4 Bit  (rom/82s130.hex)
--   D13      Pitch-Teiler (74LS9316), Preset = Latch 1088  -> Teiler (16 - pitch)
--   E12/E13  Sample-Zaehler (74LS93)                       -> 5-Bit Adresse A0..A4
--   Latch 1080 = Wellenform-Auswahl  (ROM-Adresse A5..A8)
--   Latch 1084 = Lautstaerke         (Original: Aux-Board 4016-Attenuator)
--
-- Adresse D12 = "0" & snd_select(4) & sample_cnt(5)   (16 x 32 = 512 Worte)
-- Tonfrequenz ~ AUDIO_CLK / ((16 - snd_pitch) * 32)
--
-- Vereinfachung (siehe Plan): synchrone Zaehler statt 74163/7493-Ripple; AUDIO ENABLE/RESET
--   modelliert als "Dauerton, Wellenform-Neustart bei Auswahl-Wechsel". "Aus" via snd_volume=0.
--
-- Zwei Ausgaben (Auswahl per options(3) im Top, nicht hier):
--   sample : roher 4-Bit ROM-Nibble                 -> Aux-Board DAC          (Original-Pfad)
--   sb_pwm : 1-Bit Sigma-Delta von (sample*volume)  -> Onboard RC + TDA7267   (Emulations-Pfad)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sound is
    generic(
        -- AUDIO CLK = clk_50 / C_AUDIO_DIV. Original ~= cpu_clk/2 = 500 kHz -> 50e6/100.
        -- Einziger Tonhoehen-Tuning-Hebel, falls Toene zu hoch/tief klingen.
        C_AUDIO_DIV : integer := 100
    );
    port(
        clk_50     : in  std_logic;
        reset_l    : in  std_logic;
        snd_select : in  std_logic_vector(3 downto 0);  -- Latch 1080: Wellenform
        snd_pitch  : in  std_logic_vector(3 downto 0);  -- Latch 1088: Tonhoehe
        snd_volume : in  std_logic_vector(3 downto 0);  -- Latch 1084: Lautstaerke
        sample     : out std_logic_vector(3 downto 0);  -- roher ROM-Nibble (Aux-Pfad)
        sb_pwm     : out std_logic                      -- Sigma-Delta (Onboard-Pfad)
    );
end sound;

architecture rtl of sound is
    signal div_cnt    : integer range 0 to C_AUDIO_DIV-1 := 0;
    signal audio_en   : std_logic := '0';               -- 1-clk Puls @ AUDIO CLK

    signal pitch_cnt  : unsigned(3 downto 0) := (others => '0');
    signal step       : std_logic := '0';               -- 1-clk Puls je Sample-Schritt

    signal sample_cnt : unsigned(4 downto 0) := (others => '0');
    signal sel_d      : std_logic_vector(3 downto 0) := (others => '0');

    signal rom_addr   : std_logic_vector(9 downto 0);
    signal rom_q      : std_logic_vector(7 downto 0);
    signal nibble     : std_logic_vector(3 downto 0);

    signal sd_acc     : unsigned(8 downto 0) := (others => '0');  -- Sigma-Delta-Akku
begin

    --------------------------------------------------------------------------
    -- D12 Sound-ROM
    --------------------------------------------------------------------------
    rom_addr <= "0" & snd_select & std_logic_vector(sample_cnt);
    D12: entity work.sound_rom
        port map(
            address => rom_addr,
            clock   => clk_50,
            q       => rom_q
        );
    nibble <= rom_q(3 downto 0);
    sample <= nibble;

    --------------------------------------------------------------------------
    -- AUDIO CLK enable: clk_50 / C_AUDIO_DIV
    --------------------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if div_cnt = C_AUDIO_DIV-1 then
                div_cnt  <= 0;
                audio_en <= '1';
            else
                div_cnt  <= div_cnt + 1;
                audio_en <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Pitch-Teiler (D13): "step" alle (16 - snd_pitch) AUDIO-CLK-Pulse
    --   cmp = 15 - snd_pitch (0..15) -> Periode cmp+1 = 16 - snd_pitch
    --------------------------------------------------------------------------
    process(clk_50)
        variable cmp : unsigned(3 downto 0);
    begin
        if rising_edge(clk_50) then
            step <= '0';
            if reset_l = '0' then
                pitch_cnt <= (others => '0');
            elsif audio_en = '1' then
                cmp := to_unsigned(15, 4) - unsigned(snd_pitch);
                if pitch_cnt >= cmp then
                    pitch_cnt <= (others => '0');
                    step <= '1';
                else
                    pitch_cnt <= pitch_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Sample-Zaehler (E12/E13): +1 je "step", mod 32;
    --   Neustart bei Wellenform-Wechsel (entspricht AUDIO RESET)
    --------------------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            sel_d <= snd_select;
            if reset_l = '0' or snd_select /= sel_d then
                sample_cnt <= (others => '0');
            elsif step = '1' then
                sample_cnt <= sample_cnt + 1;  -- 5 Bit -> wrap mod 32
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Volume + 1.-Ordnung Sigma-Delta-DAC (Onboard-Pfad)
    --   pcm = 128 + (sample-8) * volume   (AC um Mitte 128; volume=0 -> stumm)
    --   Oversampling 50 MHz vs. RC ~10 kHz -> saubere Wandlung
    --------------------------------------------------------------------------
    process(clk_50)
        variable centered : signed(5 downto 0);   -- sample-8 : -8..7
        variable scaled   : signed(10 downto 0);  -- centered*volume : -120..105
        variable pcm      : integer range 0 to 255;
    begin
        if rising_edge(clk_50) then
            if reset_l = '0' then
                sd_acc <= (others => '0');
            else
                centered := signed(resize(unsigned(nibble), 6)) - to_signed(8, 6);
                scaled   := resize(centered * signed('0' & unsigned(snd_volume)), 11);
                pcm      := 128 + to_integer(scaled);
                sd_acc   <= ('0' & sd_acc(7 downto 0)) + ('0' & to_unsigned(pcm, 8));
            end if;
        end if;
    end process;
    sb_pwm <= sd_acc(8);

end rtl;
