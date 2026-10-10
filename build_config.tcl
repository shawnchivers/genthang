# Pure build selection: no generated-file writes or Gowin commands here.
set pad db9
if {[info exists ::env(GT_PAD)] && $::env(GT_PAD) ne ""} { set pad $::env(GT_PAD) }
if {[lsearch -exact {ds db9 raw} $pad] < 0} { error "GT_PAD must be ds, db9 or raw" }
if {$pad eq "ds"} {
    puts stderr "warning: GT_PAD=ds is deprecated and is not included in releases"
}

set pinout stock
if {[info exists ::env(GT_PINOUT)] && $::env(GT_PINOUT) ne ""} { set pinout $::env(GT_PINOUT) }
if {[lsearch -exact {stock breadboard breadboard-rev1} $pinout] < 0} {
    error "GT_PINOUT must be stock, breadboard or breadboard-rev1"
}
if {$pinout ne "stock"} {
    if {$pad ne "db9"} { error "GT_PINOUT=$pinout requires GT_PAD=db9" }
    puts stderr "warning: GT_PINOUT=$pinout is deprecated; using the canonical db9 pinout"
    set pinout stock
}
set pad_cst "src/boards/nano20k_$pad.cst"
set output_base genthang_nano20k
if {$pad ne "ds"} { set output_base "genthang_nano20k_$pad" }