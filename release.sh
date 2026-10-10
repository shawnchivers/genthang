#!/usr/bin/env bash
# Build every controller variant (see build.tcl) and package a release in release/:
#   genthang_nano20k_<variant>.fs          bitstream only (SRAM load with Gowin Programmer)
#   genthang_nano20k_<variant>_flash.bin   bitstream + menu firmware for SPI flash address 0
#   SHA256SUMS, genthang-v<VERSION>.tar.gz
# Variants: db9 (default) and raw. Both share the same 12 data GPIOs.
# usage: ./release.sh [outdir]      VARIANTS="db9" ./release.sh   for a subset
#        PACKAGE_ONLY=1 ./release.sh   re-pack the tarball from the images already in outdir
# A variant that misses its clock targets or leaves negative slack fails the release.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-release}
mkdir -p "$OUT"

if [ -z "${PACKAGE_ONLY:-}" ]; then
rm -f "$OUT"/genthang_nano20k_*.fs "$OUT"/genthang_nano20k_*_flash.bin "$OUT"/SHA256SUMS

for variant in ${VARIANTS:-db9 raw}; do
    case $variant in
        ds)             pad=ds;  pinout=stock; name=ds;  base=genthang_nano20k ;;
        raw|db9)        pad=$variant; pinout=stock; name=$variant; base=genthang_nano20k_$variant ;;
        *) echo "unknown variant: $variant" >&2; exit 2 ;;
    esac
    echo "== $variant (GT_PAD=$pad GT_PINOUT=$pinout)"
    GT_PAD=$pad GT_PINOUT=$pinout ./build.sh > "$OUT/build_$name.log" 2>&1
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
for _, kind, value, count in re.findall(r'(\S+) (Setup|Hold) (-?[\d.]+) (\d+)', tns):
    if float(value) != 0 or int(count) != 0:
        print(f"   negative {kind} slack {value} ({count} endpoints)")
        failed = True
sys.exit(failed)
EOF
done
printf '`define GT_PAD_DB9\n' > src/pad_config.vh     # back to the checked-in default
fi

(cd "$OUT" && sha256sum genthang_nano20k_*.fs genthang_nano20k_*_flash.bin > SHA256SUMS)

version=$(tr -d '[:space:]' < VERSION)
package="$OUT/genthang-v$version"
rm -rf "$package"
mkdir -p "$package"
install -m 644 "$OUT"/genthang_nano20k_*.fs "$OUT"/genthang_nano20k_*_flash.bin \
    "$OUT/SHA256SUMS" README.md CHANGELOG.md VERSION LICENSE THIRD_PARTY.md "$package/"
cp -r docs "$package/docs"
mkdir -p "$package/upload"
install -m 755 upload/genthang-upload upload/genthang-upload-gui.py "$package/upload/"
tar -C "$OUT" -czf "$OUT/genthang-v$version.tar.gz" "genthang-v$version"
rm -rf "$package"
echo "Release package: $OUT/genthang-v$version.tar.gz"
