-- ============================================================
-- game_rom.vhd
-- Generischer 2K x 8 ROM-Wrapper (altsyncram, ROM-Mode) fuer AtariFA.
-- Ersetzt die wizard-generierten ROM1.vhd/ROM2.vhd: das Init-File wird
-- per Generic gesetzt, damit dieselbe Entity fuer alle Spiele/Slots
-- (5 Spiele x ROM1/ROM2) instanziiert werden kann.
-- Parameter identisch zu ROM1.vhd: 2048 x 8, UNREGISTERED q, Cyclone 10 LP.
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

ENTITY game_rom IS
	GENERIC
	(
		init_file	: string := "./rom/608.hex"
	);
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (10 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
	);
END game_rom;


ARCHITECTURE SYN OF game_rom IS

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
		numwords_a => 2048,
		operation_mode => "ROM",
		outdata_aclr_a => "NONE",
		outdata_reg_a => "UNREGISTERED",
		widthad_a => 11,
		width_a => 8,
		width_byteena_a => 1
	)
	PORT MAP (
		address_a => address,
		clock0 => clock,
		q_a => sub_wire0
	);

END SYN;
