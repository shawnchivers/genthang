#!/usr/bin/env python3
import argparse
from pathlib import Path


ROM_OFFSET = 0x500000
FLASH_SIZE = 0x800000


def main():
    parser = argparse.ArgumentParser(
        description="Combine a Nano 20K flash bitstream and the menu firmware (at 0x500000)."
    )
    parser.add_argument("bitstream", type=Path, help="raw Gowin .bin image")
    parser.add_argument("rom", type=Path, help="firmware/firmware.bin (menu firmware)")
    parser.add_argument("output", type=Path, help="combined raw flash image")
    args = parser.parse_args()

    bitstream = args.bitstream.read_bytes()
    rom = args.rom.read_bytes()

    if len(bitstream) > ROM_OFFSET:
        parser.error(
            f"bitstream is {len(bitstream)} bytes and overlaps ROM offset 0x{ROM_OFFSET:X}"
        )
    if len(rom) > FLASH_SIZE - ROM_OFFSET:
        parser.error(f"payload is {len(rom)} bytes, more than fits after 0x{ROM_OFFSET:X}")

    image = bitstream + bytes([0xFF]) * (ROM_OFFSET - len(bitstream)) + rom
    args.output.write_bytes(image)
    print(
        f"Wrote {args.output} ({len(image)} bytes): "
        f"bitstream at 0x0, firmware at 0x{ROM_OFFSET:X}"
    )


if __name__ == "__main__":
    main()