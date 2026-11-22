#!/usr/bin/env python3
"""
Convert an Intel HEX Uzebox game into a .uze file (512 byte header + binary),
equivalent to the Uzebox 'packrom' tool. Optional gameinfo.properties
(name=, author=, year=, description=) fills the header text fields.

usage: hex2uze.py game.hex game.uze [gameinfo.properties]
"""
import struct, sys, zlib

def read_hex(fn):
    mem = bytearray(b"\xff" * 65536)
    top, base = 0, 0
    for line in open(fn):
        line = line.strip()
        if not line.startswith(":"):
            continue
        n = int(line[1:3], 16); a = int(line[3:7], 16); t = int(line[7:9], 16)
        d = bytes.fromhex(line[9:9 + 2 * n])
        if t == 0:
            for i, b in enumerate(d):
                addr = base + a + i
                if addr < 61440:          # game area only (below the bootloader)
                    mem[addr] = b
                    top = max(top, addr + 1)
        elif t == 2:
            base = int.from_bytes(d, "big") << 4
        elif t == 4:
            base = int.from_bytes(d, "big") << 16
        elif t == 1:
            break
    return bytes(mem[:top])

def main():
    prog = read_hex(sys.argv[1])
    info = {}
    if len(sys.argv) > 3:
        for ln in open(sys.argv[3], errors="replace"):
            if "=" in ln:
                k, v = ln.split("=", 1)
                info[k.strip()] = v.strip()
    def txt(s, n):
        b = s.encode("ascii", "replace")[:n - 1]
        return b + b"\0" * (n - len(b))
    hdr = bytearray(512)
    hdr[0:6] = b"UZEBOX"
    hdr[6] = 1                                   # header version
    hdr[7] = 0                                   # ATmega644
    struct.pack_into("<I", hdr, 0x08, len(prog))
    struct.pack_into("<H", hdr, 0x0C, int(info.get("year", "0") or 0))
    hdr[0x0E:0x2E] = txt(info.get("name", sys.argv[1].split("/")[-1].rsplit(".", 1)[0]), 32)
    hdr[0x2E:0x4E] = txt(info.get("author", ""), 32)
    struct.pack_into("<I", hdr, 0x14E, zlib.crc32(prog) & 0xFFFFFFFF)
    hdr[0x153:0x193] = txt(info.get("description", ""), 64)
    open(sys.argv[2], "wb").write(bytes(hdr) + prog)
    print("%s: %d bytes, crc32 %08X" % (sys.argv[2], len(prog), zlib.crc32(prog) & 0xFFFFFFFF))

if __name__ == "__main__":
    main()
