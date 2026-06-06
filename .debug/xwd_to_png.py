#!/usr/bin/env python3
"""Convert XWD (xwd -out) to PNG. Minimal parser for Godot/X11 captures."""
import struct
import sys
from PIL import Image


def read_xwd(path: str) -> Image.Image:
    with open(path, "rb") as f:
        header_size = struct.unpack(">I", f.read(4))[0]
        header = f.read(header_size - 4)
        # Fixed part: width, height, xhot, yhot, depth, bpp, ...
        fields = struct.unpack(">" + "I" * (len(header) // 4), header)
        width, height, _xhot, _yhot, depth = fields[0], fields[1], fields[2], fields[3], fields[4]
        if depth not in (24, 32):
            raise ValueError(f"unsupported xwd depth={depth}")
        # Skip colormap + pixel data header — scan for ZPixmap flag area
        # Simpler: read rest as BGRA 32-bit rows (common for xwd -truecolor)
        row_pad = ((width * (depth // 8) + 3) // 4) * 4
        pixels = bytearray()
        for _y in range(height):
            row = f.read(row_pad)
            for x in range(width):
                off = x * 4
                b, g, r, a = row[off : off + 4]
                pixels.extend((r, g, b))
        return Image.frombytes("RGB", (width, height), bytes(pixels))


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: xwd_to_png.py in.xwd out.png", file=sys.stderr)
        sys.exit(2)
    img = read_xwd(sys.argv[1])
    img.save(sys.argv[2])


if __name__ == "__main__":
    main()
