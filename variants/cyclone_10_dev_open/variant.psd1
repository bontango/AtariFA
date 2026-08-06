@{
    Name        = 'cyclone_10_dev_open'
    Title       = "AtariFA PCB v1.0 with the 'dev_open' Cyclone 10 board (10CL006YE144C8G)"
    BoardId     = 1
    RtlFamily   = 'cyclone_10'
    Options     = @()
    BinFolder   = 'dev_open'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    # Board wiring worth keeping, it used to be a comment in this variant's own copy
    # of the top level: reset switch and all four status LEDs sit ON the 'dev_open'
    # piggy back board itself, LED_D4 being the spare one. Only three debug lines
    # reach the 10 pin logic analyser header, so debug_signal[3..7] have no location.
    VirtualPins = @('debug_signal[3]', 'debug_signal[4]', 'debug_signal[5]',
                    'debug_signal[6]', 'debug_signal[7]')
    Notes       = 'NOT hardware tested. Derived from cyclone_10_pcb on 06.08.2026, pin out only.'
}
