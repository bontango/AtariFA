@{
    Name        = 'cyclone_IV_dev_open'
    Title       = "AtariFA PCB v1.0 with the 'dev_open' Cyclone IV board (EP4CE6E22C8)"
    BoardId     = 2
    RtlFamily   = 'cyclone_IV'
    Options     = @()
    BinFolder   = 'dev_open_cyclone_IV'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    # Same 'dev_open' piggy back board as cyclone_10_dev_open, so the board wiring is
    # identical: reset switch and all four status LEDs sit ON the board itself, LED_D4
    # being the spare one. Only three debug lines reach the 10 pin logic analyser
    # header, so debug_signal[3..7] have no location.
    VirtualPins = @('debug_signal[3]', 'debug_signal[4]', 'debug_signal[5]',
                    'debug_signal[6]', 'debug_signal[7]')
    # RtlFamily is what makes this variant different from cyclone_10_dev_open beyond
    # two pins: it selects scripts\files_cyclone_IV.tcl instead of files_cyclone_10.tcl,
    # so the megafunctions come out of rtl\cyclone_IV\. First real use of that key.
    Notes       = 'NOT hardware tested. Derived from cyclone_10_dev_open on 02.09.2026: same board, Cyclone IV E instead of Cyclone 10 LP, dip_opt[1] and dip_opt[3] moved because PIN_22 is no user I/O on this chip.'
}
