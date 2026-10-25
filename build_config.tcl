# Pure build selection: no generated-file writes or Gowin commands here.
set pad db9
if {[info exists ::env(GT_PAD)] && $::env(GT_PAD) ne ""} { set pad $::env(GT_PAD) }
if {[lsearch -exact {db9 raw} $pad] < 0} { error "GT_PAD must be db9 or raw" }

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
set video 720p
if {[info exists ::env(GT_VIDEO)] && $::env(GT_VIDEO) ne ""} { set video $::env(GT_VIDEO) }
if {[lsearch -exact {720p 800x480} $video] < 0} { error "GT_VIDEO must be 720p or 800x480" }

# Colour mode and brightness menu: on for the raw handheld build, off for DB9 (no room left)
# Brightness (shares the scanline dimmer): on for raw, off for db9 (no logic to spare)
set picture [expr {$pad eq "raw" ? 1 : 0}]
if {[info exists ::env(GT_PICTURE)] && $::env(GT_PICTURE) ne ""} { set picture $::env(GT_PICTURE) }
if {[lsearch -exact {0 1} $picture] < 0} { error "GT_PICTURE must be 0 or 1" }

set pad_cst "src/boards/nano20k_$pad.cst"
set output_base "genthang_nano20k_$pad"
set three_btn [expr {[info exists ::env(GT_3BTN)] && $::env(GT_3BTN) eq "1"}]
if {$three_btn} { append output_base "_3btn" }
if {$video ne "720p"} { append output_base "_$video" }