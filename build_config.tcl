# Pure build selection: no generated-file writes or Gowin commands here.
set pad ds
if {[info exists ::env(GT_PAD)] && $::env(GT_PAD) ne ""} { set pad $::env(GT_PAD) }
if {[lsearch -exact {ds db9 raw} $pad] < 0} { error "GT_PAD must be ds, db9 or raw" }

set pinout stock
if {[info exists ::env(GT_PINOUT)] && $::env(GT_PINOUT) ne ""} { set pinout $::env(GT_PINOUT) }
if {[lsearch -exact {stock breadboard} $pinout] < 0} {
    error "GT_PINOUT must be stock or breadboard"
}
if {$pinout eq "breadboard" && $pad ne "db9"} {
    error "GT_PINOUT=breadboard requires GT_PAD=db9"
}
set pad_cst "src/boards/nano20k_$pad.cst"
set output_base genthang_nano20k
if {$pinout eq "breadboard"} {
    set pad_cst "src/boards/nano20k_db9_breadboard.cst"
    set output_base genthang_nano20k_db9_breadboard
}