"""Convert a raw Genesis ROM into the hex images used by the testbenches.

rom8.hex  - bytes in file order (SPI flash contents)
rom16.hex - big-endian 16-bit words (ideal_mem)
rom32.hex - 32-bit SDRAM words: even 16-bit word in [15:0], odd word in [31:16]
"""
import sys

rom = open(sys.argv[1], "rb").read()
if len(rom) % 4:
    rom += b"\xff" * (4 - len(rom) % 4)

with open("rom8.hex", "w") as f:
    f.write("\n".join(f"{b:02x}" for b in rom) + "\n")
with open("rom16.hex", "w") as f:
    f.write("\n".join(f"{rom[i]:02x}{rom[i+1]:02x}" for i in range(0, len(rom), 2)) + "\n")
with open("rom32.hex", "w") as f:
    f.write("\n".join(f"{rom[i+2]:02x}{rom[i+3]:02x}{rom[i]:02x}{rom[i+1]:02x}"
                      for i in range(0, len(rom), 4)) + "\n")
print(f"{len(rom)} bytes -> rom8/16/32.hex")
