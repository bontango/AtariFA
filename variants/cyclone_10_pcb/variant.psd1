@{
    Name        = 'cyclone_10_pcb'
    Title       = "AtariFA PCB v1.0 with the lisy.dev Cyclone 10 piggy back board (10CL006YE144C8G)"
    BoardId     = 0
    RtlFamily   = 'cyclone_10'
    Options     = @()
    BinFolder   = 'FPGA_board_v4.x'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    # LED_D4 does not exist on this board: it carries three status LEDs, wired in
    # parallel to the three LEDs of the piggy back board. The reset switch is also
    # in parallel to the one on the piggy back board.
    VirtualPins = @('LED_D4')
    Notes       = 'Lead variant - development and hardware testing happen here. Tested through SW 0.1.4.'
}
