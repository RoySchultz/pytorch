#!/usr/bin/env python3
"""Generate simple PNG icons for the extension."""
import struct, zlib, os

def png(size, bg=(15, 52, 96), fg=(96, 165, 250)):
    """Create a minimal valid PNG with a solid background colour."""
    w = h = size

    def chunk(tag, data):
        raw = tag + data
        return struct.pack('>I', len(data)) + raw + struct.pack('>I', zlib.crc32(raw) & 0xFFFF_FFFF)

    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)

    # Each row starts with filter byte 0 (None)
    row = bytes([0]) + bytes(list(bg) * w)
    idat = zlib.compress(row * h)

    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

os.makedirs('icons', exist_ok=True)
for size in (16, 48, 128):
    with open(f'icons/icon{size}.png', 'wb') as f:
        f.write(png(size))
    print(f'icons/icon{size}.png aangemaakt')
