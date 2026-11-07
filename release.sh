#!/usr/bin/env bash
# Build every controller variant (see build.tcl) and package a release in release/:
#   genthang_nano20k_<variant>.fs          bitstream only (SRAM load with Gowin Programmer)
#   genthang_nano20k_<variant>_flash.bin   bitstream + menu firmware for SPI flash address 0
#   SHA256SUMS, genthang-v<VERSION>.tar.gz
# Variants: db9 (default) and raw, each also as <pad>_800x480 (GT_VIDEO=800x480, native
# 800x480 DVI for bare TFT panels on a TFP401 board). Raw has its own handheld pinout.
# usage: ./release.sh [outdir]      VARIANTS="db9" ./release.sh   for a subset
#        PACKAGE_ONLY=1 ./release.sh   re-pack the tarball from the images already in outdir
# A variant that misses its clock targets or leaves negative slack fails the release.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-release}
mkdir -p "$OUT"

if [ -z "${PACKAGE_ONLY:-}" ]; then
rm -f "$OUT"/genthang_nano20k_*.fs "$OUT"/genthang_nano20k_*_flash.bin "$OUT"/SHA256SUMS

for variant in ${VARIANTS:-db9 raw raw_3btn db9_800x480 raw_800x480}; do
    case $variant in
        raw|db9)        pad=$variant; video=720p; pinout=stock; name=$variant; base=genthang_nano20k_$variant ;;
        raw_3btn)       pad=raw; video=720p; pinout=stock; name=$variant; base=genthang_nano20k_$variant ;;
        raw_800x480|db9_800x480)
                        pad=${variant%_800x480}; video=800x480; pinout=stock; name=$variant
                        base=genthang_nano20k_$variant ;;
        *) echo "unknown variant: $variant" >&2; exit 2 ;;
    esac
    echo "== $variant (GT_PAD=$pad GT_VIDEO=$video GT_PINOUT=$pinout)"
    three=0; [ "$variant" = raw_3btn ] && three=1
    picture=0; [ "$pad" = raw ] && picture=1
    GT_PAD=$pad GT_VIDEO=$video GT_PINOUT=$pinout GT_3BTN=$three GT_PICTURE=$picture \
        GT_LADDER=1 GT_NO_ADAPTIVE=1 GT_NO_CORE_SWITCH=1 GT_SERIAL_UPLOAD=0 GT_NO_SOUND=0 \
        ./build.sh > "$OUT/build_$name.log" 2>&1
    install -m 644 "impl/pnr/$base.rpt.txt" "$OUT/$base.rpt.txt"
    install -m 644 "impl/pnr/${base}_tr_content.html" "$OUT/${base}_tr_content.html"
    install -m 644 "impl/pnr/$base.fs" "$OUT/genthang_nano20k_$name.fs"   # Gowin writes it read-only
    python3 merge_flash.py "impl/pnr/$base.bin" firmware/firmware.bin \
        "$OUT/genthang_nano20k_${name}_flash.bin"
    python3 - "impl/pnr/${base}_tr_content.html" <<'EOF'
import html, re, sys
t = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', open(sys.argv[1]).read())))
clocks = re.findall(r'\d+ (clk_sys|clk_z80|hclk) ([\d.]+)\(MHz\) ([\d.]+)\(MHz\)', t)
failed = {c for c, _, _ in clocks} != {"clk_sys", "clk_z80", "hclk"}
if failed:
    print("   timing report is missing a clock")
for clk, want, got in clocks:
    miss = float(got) < float(want)
    failed |= miss
    print(f"   {clk}: {got} MHz (needs {want})" + ("  FAILS TIMING" if miss else ""))
tns = t.split('Total Negative Slack Summary:', 1)[1].split('Timing Details', 1)[0]
slack = re.findall(r'(\S+) (Setup|Hold) (-?[\d.]+) (\d+)', tns)
if {kind for _, kind, _, _ in slack} != {"Setup", "Hold"}:
    print("   timing report is missing setup/hold slack")
    failed = True
for _, kind, value, count in slack:
    if float(value) != 0 or int(count) != 0:
        print(f"   negative {kind} slack {value} ({count} endpoints)")
        failed = True
sys.exit(failed)
EOF
done
printf '`define GT_PAD_DB9\n`define GT_LADDER\n`define GT_NO_ADAPTIVE\n`define GT_NO_CORE_SWITCH\n' > src/pad_config.vh
fi

(cd "$OUT" && sha256sum genthang_nano20k_*.fs genthang_nano20k_*_flash.bin > SHA256SUMS)

version=$(tr -d '[:space:]' < VERSION)
package="$OUT/genthang-v$version"
rm -rf "$package"
mkdir -p "$package"
install -m 644 "$OUT"/genthang_nano20k_*.fs "$OUT"/genthang_nano20k_*_flash.bin \
    "$OUT/SHA256SUMS" README.md CHANGELOG.md VERSION LICENSE THIRD_PARTY.md "$package/"
cp -r docs "$package/docs"
# USB serial upload is not in release bitstreams (GT_SERIAL_UPLOAD), so its host tools are not shipped
tar -C "$OUT" -czf "$OUT/genthang-v$version.tar.gz" "genthang-v$version"
rm -rf "$package"
echo "Release package: $OUT/genthang-v$version.tar.gz"
