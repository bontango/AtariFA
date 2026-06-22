-- ============================================================
-- speech_rom.vhd
-- 8-Bit-PCM-ROM (4096 x 8) fuer speech.vhd (Boot-Sprache "Lisy").
-- altsyncram im ROM-Mode, Init-File per Generic (analog game_rom.vhd).
-- Inhalt erzeugen mit tools/make_speech_mif.py --pcm.
-- Parameter: 4096 x 8, UNREGISTERED q, Cyclone 10 LP -> 4 M9K.
-- (Ungenutzte Worte sind im .mif mit 128 = Mittelpegel/Stille gefuellt.)
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY speech_rom IS
	GENERIC
	(
		init_file	: string := "./rom/lisy.mif"
	);
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END speech_rom;


ARCHITECTURE SYN OF speech_rom IS

	SIGNAL sub_wire0	: STD_LOGIC_VECTOR (7 DOWNTO 0);

BEGIN
	q    <= sub_wire0(7 DOWNTO 0);

	altsyncram_component : altsyncram
	GENERIC MAP (
		address_aclr_a => "NONE",
		clock_enable_input_a => "BYPASS",
		clock_enable_output_a => "BYPASS",
		init_file => init_file,
		intended_device_family => "Cyclone 10 LP",
		lpm_hint => "ENABLE_RUNTIME_MOD=NO",
		lpm_type => "altsyncram",
		numwords_a => 4096,
		operation_mode => "ROM",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		widthad_a => 12,
		width_a => 8,
		width_byteena_a => 1
	)
	PORT MAP (
		address_a => address,
		clock0 => clock,
		q_a => sub_wire0
	);

END SYN;
