#!/usr/bin/env python3
"""gowin_pack wrapper for UzeTang's open-source build.

On the Tang Nano 20K the SNES pad pins (25-30) share I/O bank 5 with the
HDMI pins. apicula's gowin_pack forces any bank with LVDS outputs to a
1.2 V configuration, which also changes the pad pins' input settings.

This wrapper:
  - keeps banks with LVDS outputs at 3.3 V (the board's real VCCIO),
  - sets the pad data inputs' remaining configuration fuses as the Gowin IDE
    does (see PAD_INPUT_FUSES), and
  - optionally (--iob-from REF.fs) copies the I/O-block configuration fuses
    of the tiles holding pins 25-30 from a reference bitstream (for example
    one built by the Gowin IDE), so those pins are set up exactly as Gowin
    sets them. Only the IOB attribute fuses are copied, not routing.

Usage: gowin_pack_bank33.py [--iob-from REF.fs] <normal gowin_pack args>
"""
import sys
import apycula.gowin_pack as gp
from apycula import chipdb
from apycula.bslib import read_bitstream

PAD_TILES = [(54, 5), (54, 7), (54, 13)]     # pins 25/26, 27/28, 29/30

# Fuses that differ between apicula and the Gowin IDE for the two pad data
# inputs (pin 25 = tile (54,5) IOBA, pin 30 = tile (54,13) IOBB) once the
# bank is at 3.3 V. Set as the Gowin IDE sets them for an LVCMOS33 input:
#   CLAMP=PCI on, and the input-standard bit that apicula sets for
#   differential / reference-voltage standards cleared.
PAD_INPUT_FUSES = {
    (54, 5):  {(25, 27): 1, (26, 28): 0},     # IOBA, pin 25 (joy1_data)
    (54, 13): {(25, 31): 1, (26, 30): 0},     # IOBB, pin 30 (joy2_data)
}

args = sys.argv[1:]
ref = None
if args[:1] == ["--iob-from"]:
    ref = args[1]
    args = args[2:]

gp.Device.get_lvds_bank_vccio = lambda self: "3.3"

_orig = {}
for cls in [gp.Device] + gp.Device.__subclasses__():
    if "fuse_bitmap" in cls.__dict__:
        _orig[cls] = cls.__dict__["fuse_bitmap"]

def make_fixed_wrapper(orig):
    def fuse_bitmap(self, tilemap, *a, **k):
        for tile, fuses in PAD_INPUT_FUSES.items():
            for (fr, fc), v in fuses.items():
                tilemap[tile][fr][fc] = v
        return orig(self, tilemap, *a, **k)
    return fuse_bitmap

if not ref:
    for cls, orig in _orig.items():
        setattr(cls, "fuse_bitmap", make_fixed_wrapper(orig))

if ref:
    def make_wrapper(orig):
        def fuse_bitmap(self, tilemap, *a, **k):
            db = self.chipdb.db if hasattr(self.chipdb, "db") else self.chipdb
            bm, _, _, _ = read_bitstream(ref)
            ref_tiles = chipdb.tile_bitmap(db, bm)
            for (r, c) in PAD_TILES:
                ttyp = db[r, c].ttyp
                coords = set()
                for name in ("IOBA", "IOBB"):
                    for fuses in db.longval[ttyp].get(name, {}).values():
                        coords |= set(fuses)
                for (fr, fc) in coords:
                    tilemap[(r, c)][fr][fc] = ref_tiles[(r, c)][fr][fc]
            print(f"copied IOB fuses of {PAD_TILES} from {ref}", file=sys.stderr)
            return orig(self, tilemap, *a, **k)
        return fuse_bitmap

    for cls, orig in _orig.items():
        setattr(cls, "fuse_bitmap", make_wrapper(orig))

sys.argv = ["gowin_pack"] + args
gp.main()
