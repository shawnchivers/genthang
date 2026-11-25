"""Check TESTOUT words from tests/roms/vdp_timing.s against documented NTSC H40 values."""
import sys

words = [int(line.split()[1], 16) for line in sys.stdin if line.startswith("TESTOUT ")]
results = {}
i = 0
sizes = {1: 3, 4: 1, 5: 1, 6: 1, 7: 1}
while i < len(words) and words[i] != 0xFFFF:
    tag = words[i]
    results[tag] = words[i + 1:i + 1 + sizes[tag]]
    i += 1 + sizes[tag]
# (name, measured, low, high): DMA rates in bytes/line from the VDP documentation,
# 205 (68K->VRAM blank), 18 (active), 204 (fill blank), 102 (copy blank)
checks = [
    ("lines per frame", results[1][0], 262, 262),
    ("V after $EA", results[1][1], 0xE5, 0xE5),
    ("H samples in $B7-$E3 gap", results[1][2], 0, 0),
    ("68K->VRAM 4096 B display off (lines)", results[4][0], 4096 // 205 - 1, 4096 // 205 + 2),
    ("68K->VRAM 512 B active (lines)", results[5][0], 512 // 18 - 1, 512 // 18 + 2),
    ("VRAM fill 4096 B display off (lines)", results[6][0], 4096 // 204 - 1, 4096 // 204 + 2),
    ("VRAM copy 2048 B display off (lines)", results[7][0], 2048 // 102 - 1, 2048 // 102 + 2),
]
bad = 0
for name, got, lo, hi in checks:
    ok = lo <= got <= hi
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {name}: {got} (expected {lo}..{hi})")
if bad or len(results) != len(sizes):
    sys.exit("VDP timing: FAILED")
print("VDP timing: counters and DMA rates match documented NTSC H40 hardware")
