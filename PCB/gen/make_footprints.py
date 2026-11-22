#!/usr/bin/env python3
"""Footprint library for the UzeTang board (KiCad 7 format).

- SNES_CONNECTOR, TACTILE-PTH, SDCARD_4UCONN, LED3MM, UZEBOX_ESP-12_TH:
  converted from the Uzebox Omega v1.5 KiCad library (itself converted from
  the Uzebox Eagle libraries), so pads sit exactly where the Uzebox case and
  the Uzebox parts expect them.
- TangNano20K: Tang Nano 20K on two 1x20 2.54 mm female headers, 20.32 mm
  apart. Pads are named after the FPGA pin (power pins: 3V3_1, 3V3_2, 5V,
  GND_1..GND_3), from Sipeed's pinout.
- MountingHole_3.3mm_Uzebox, Hole_2.2mm (light pipe), Bumpon (silk marker).
"""
import re, sys, os
OMEGA = sys.argv[1]
OUT = sys.argv[2]

def led_inner_ring_to_fab(s):
    # The LED's inner 3 mm silk ring crosses its own pads; keep it on F.Fab only
    return re.sub(r'(\(fp_arc \(start [^()]*\) \(mid [^()]*\) \(end [^()]*\) \(stroke \(width 0\.1524\) \(type solid\)\) \(layer )"F\.SilkS"',
                  r'\1"F.Fab"', s)


def convert(name):
    s = open(os.path.join(OMEGA, name + ".kicad_mod")).read()
    if name == "LED3MM":
        s = led_inner_ring_to_fab(s)
    s = re.sub(r'\(version \d+\)', '(version 20221018)', s)
    s = re.sub(r'\(generator "[^"]*"\)', '(generator pcbnew)', s)
    # KiCad 8 'property' fields -> KiCad 7 fp_text
    s = s.replace('(property "Reference" "REF**"', '(fp_text reference "REF**"')
    s = re.sub(r'\(property "Value" "([^"]*)"', r'(fp_text value "\1"', s)
    s = re.sub(r'\(property "[^"]*" "[^"]*"[^\n]*\n', '', s)
    open(os.path.join(OUT, name + ".kicad_mod"), "w").write(s)

for n in ("SNES_CONNECTOR", "TACTILE-PTH", "SDCARD_4UCONN", "LED3MM", "UZEBOX_ESP-12_TH"):
    convert(n)

# ---------------- Tang Nano 20K ----------------
# Local coordinates: USB end at -y, HDMI end at +y, viewed from the top.
LEFT = ["73", "74", "75", "85", "77", "15", "16", "27", "28", "25",
        "26", "29", "30", "31", "17", "20", "19", "18", "3V3_1", "GND_1"]
RIGHT = ["5V", "GND_2", "76", "80", "42", "41", "56", "54", "51", "48",
         "55", "49", "86", "79", "GND_3", "3V3_2", "72", "71", "53", "52"]
lines = ['(footprint "TangNano20K" (version 20221018) (generator pcbnew)',
         '  (layer "F.Cu")',
         '  (descr "Sipeed Tang Nano 20K (GW2AR-18) on two 1x20 2.54mm female headers, 20.32mm apart. Pads named after FPGA pins.")',
         '  (tags "Tang Nano 20K FPGA")',
         '  (attr through_hole)',
         '  (fp_text reference "REF**" (at 0 -31.5) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))))',
         '  (fp_text value "TangNano20K" (at 0 0 90) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))))']
def rect(x1, y1, x2, y2, layer, w):
    return [f'  (fp_line (start {x1} {y1}) (end {x2} {y1}) (stroke (width {w}) (type solid)) (layer "{layer}"))',
            f'  (fp_line (start {x2} {y1}) (end {x2} {y2}) (stroke (width {w}) (type solid)) (layer "{layer}"))',
            f'  (fp_line (start {x2} {y2}) (end {x1} {y2}) (stroke (width {w}) (type solid)) (layer "{layer}"))',
            f'  (fp_line (start {x1} {y2}) (end {x1} {y1}) (stroke (width {w}) (type solid)) (layer "{layer}"))']
lines += rect(-11.275, -27.02, 11.275, 27.02, "F.SilkS", 0.15)          # 22.55 x 54.04 board
lines += rect(-7.5, 18.2, 7.5, 32.0, "F.Fab", 0.1)                      # HDMI receptacle
lines += rect(-4.5, -29.8, 4.5, -20.5, "F.Fab", 0.1)                    # USB-C receptacle
lines += rect(-11.6, -30.1, 11.6, 32.3, "F.CrtYd", 0.05)
lines += ['  (fp_text user "HDMI" (at 0 25 ) (layer "F.SilkS") (effects (font (size 1.5 1.5) (thickness 0.2))))',
          '  (fp_text user "USB-C" (at 0 -24) (layer "F.SilkS") (effects (font (size 1.5 1.5) (thickness 0.2))))',
          '  (fp_text user "TANG NANO 20K" (at 0 0 90) (layer "F.SilkS") (effects (font (size 1.5 1.5) (thickness 0.2))))']
for i in range(20):
    y = round(-24.13 + 2.54 * i, 3)
    for x, name in ((-10.16, LEFT[i]), (10.16, RIGHT[i])):
        shape = "rect" if name in ("3V3_1", "5V") else "circle"
        lines.append(f'  (pad "{name}" thru_hole {shape} (at {x} {y}) (size 1.8 1.8) (drill 1.0) (layers "*.Cu" "*.Mask"))')
        lab = name.split("_")[0]
        lx = x - 2.6 if x < 0 else x + 2.6
        lines.append(f'  (fp_text user "{lab}" (at {lx} {y}) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))))')
lines.append(')')
open(os.path.join(OUT, "TangNano20K.kicad_mod"), "w").write("\n".join(lines) + "\n")

# ---------------- holes ----------------
open(os.path.join(OUT, "MountingHole_3.3mm_Uzebox.kicad_mod"), "w").write('''(footprint "MountingHole_3.3mm_Uzebox" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (descr "Uzebox case mounting hole, 3.3mm (M3), with 6.5mm keep-clear ring")
  (attr exclude_from_pos_files exclude_from_bom)
  (fp_text reference "REF**" (at 0 -4.2) (layer "F.SilkS") hide (effects (font (size 1 1) (thickness 0.15))))
  (fp_text value "MountingHole" (at 0 4.2) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))))
  (fp_circle (center 0 0) (end 3.25 0) (stroke (width 0.15) (type solid)) (fill none) (layer "F.SilkS"))
  (fp_circle (center 0 0) (end 3.5 0) (stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd"))
  (pad "" np_thru_hole circle (at 0 0) (size 3.302 3.302) (drill 3.302) (layers "*.Cu" "*.Mask"))
)
''')
open(os.path.join(OUT, "Hole_2.2mm_LightPipe.kicad_mod"), "w").write('''(footprint "Hole_2.2mm_LightPipe" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (descr "Light pipe mounting hole, 2.2mm, as on the Uzebox Omega")
  (attr exclude_from_pos_files exclude_from_bom)
  (fp_text reference "REF**" (at 0 -2.5) (layer "F.SilkS") hide (effects (font (size 1 1) (thickness 0.15))))
  (fp_text value "Hole_2.2mm" (at 0 2.5) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))))
  (fp_circle (center 0 0) (end 1.6 0) (stroke (width 0.05) (type solid)) (fill none) (layer "F.CrtYd"))
  (pad "" np_thru_hole circle (at 0 0) (size 2.2 2.2) (drill 2.2) (layers "*.Cu" "*.Mask"))
)
''')
open(os.path.join(OUT, "Bumpon.kicad_mod"), "w").write('''(footprint "Bumpon" (version 20221018) (generator pcbnew)
  (layer "F.Cu")
  (descr "Rubber bumper position (Digikey SJ5303-7-ND): small silk circle at the centre (two sit next to mounting holes), outline on B.Fab")
  (attr exclude_from_pos_files)
  (fp_text reference "REF**" (at 0 -6.5) (layer "B.SilkS") hide (effects (font (size 1 1) (thickness 0.15)) (justify mirror)))
  (fp_text value "Bumpon" (at 0 6.5) (layer "B.Fab") (effects (font (size 1 1) (thickness 0.15)) (justify mirror)))
  (fp_circle (center 0 0) (end 5.6 0) (stroke (width 0.15) (type solid)) (fill none) (layer "B.Fab"))
  (fp_circle (center 0 0) (end 0.3 0) (stroke (width 0.1) (type solid)) (fill none) (layer "B.SilkS"))
)
''')
print("footprints written")
