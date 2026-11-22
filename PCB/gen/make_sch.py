#!/usr/bin/env python3
"""Generate the UzeTang Board schematic (KiCad 7) and its symbol library.

Every part gets a simple box symbol whose pin numbers are the footprint pad
names. Each pin has a short wire and a net label (or a no-connect flag), so
the schematic and the PCB carry exactly the same netlist. Nets are read from
the routed board, which is itself built from gen/design.py.

    python3 gen/make_sch.py        (after gen/make_pcb.py place)

Also writes UzeTang-Board.kicad_sym and sym-lib-table, and links the board's
footprints to the schematic symbols (so Update PCB from Schematic works).
"""
import math, os, sys, uuid
import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import design as D

PROJ = os.path.dirname(HERE)
PCB = os.path.join(PROJ, "UzeTang-Board.kicad_pcb")
SCH = os.path.join(PROJ, "UzeTang-Board.kicad_sch")
SYMLIB = os.path.join(PROJ, "UzeTang-Board.kicad_sym")
LIB = D.LIB
G = 2.54
NS = uuid.UUID("6b1f0e0c-5a3e-4c55-9a51-0b7a3d1e2f10")


def uid(*k):
    return str(uuid.uuid5(NS, "/".join(map(str, k))))


ROOT = uid("root")

# ---------------------------------------------------------------- symbols
# name -> (left pins, right pins, hide pin names); pins are (number, name)
SNES = [("P$8", "VCC"), ("P$9", "CLK"), ("P$10", "LATCH"), ("P$11", "DATA"),
        ("P$12", "NC"), ("P$13", "NC"), ("P$14", "GND")]
SD = [("1", "DAT3/CS"), ("2", "CMD"), ("3", "VSS1"), ("4", "VDD"), ("5", "CLK"),
      ("6", "VSS2"), ("7", "DAT0"), ("8", "DAT1"), ("9", "DAT2"),
      ("CD", "CD"), ("WP", "WP"), ("SH@1", "SHIELD"), ("SH@2", "SHIELD")]
ESP_L = [("1", "RST"), ("2", "ADC"), ("3", "EN"), ("4", "IO16"), ("5", "IO14"),
         ("6", "IO12"), ("7", "IO13"), ("8", "VCC")]
ESP_R = [("16", "TXD"), ("15", "RXD"), ("14", "IO5"), ("13", "IO4"), ("12", "IO0"),
         ("11", "IO2"), ("10", "IO15"), ("9", "GND")]


def tang_pins(fp):
    rows = {"L": [], "R": []}
    for p in fp.Pads():
        q = p.GetPos0()
        rows["L" if q.x < 0 else "R"].append((q.y, p.GetNumber()))
    nm = lambda n: n.split("_")[0] if "_" in n else n
    left = [(n, nm(n)) for _, n in sorted(rows["L"])]
    right = [(n, nm(n)) for _, n in sorted(rows["R"])]
    return left, right


def symbol_defs(board):
    t_l, t_r = tang_pins(board.FindFootprintByReference("U1"))
    return {
        "TangNano20K": (t_l, t_r, False, "U", "Sipeed Tang Nano 20K (GW2AR-18) on 2x20 headers, USB-C/HDMI to the rear"),
        "SNES_Port": (SNES, [], False, "J", "SNES controller socket (Uzebox footprint)"),
        "SD_Socket": (SD, [], False, "J", "microSD socket, Wurth 693063020911"),
        "ESP-12F": (ESP_L, ESP_R, False, "U", "ESP-12F module on 2 mm receptacles"),
        "LD1117V33": ([("3", "VIN")], [("2", "VOUT"), ("1", "GND")], False, "U", "3.3 V 800 mA LDO, TO-220"),
        "SW_Tactile": ([("1", "A"), ("2", "A")], [("3", "B"), ("4", "B")], False, "SW", "6 mm tactile switch, 4 pins"),
        "LED": ([("A", "A")], [("K", "K")], False, "D", "3 mm LED"),
        "R": ([("1", "~")], [("2", "~")], True, "R", "Resistor"),
        "C": ([("1", "~")], [("2", "~")], True, "C", "Capacitor"),
        "CP": ([("1", "+")], [("2", "-")], False, "C", "Polarised capacitor"),
    }


def sym_for(ref, fpname):
    if ref == "U1": return "TangNano20K"
    if ref in ("J1", "J2"): return "SNES_Port"
    if ref == "J3": return "SD_Socket"
    if ref == "U2": return "ESP-12F"
    if ref == "U3": return "LD1117V33"
    if ref.startswith("SW"): return "SW_Tactile"
    if ref.startswith("D"): return "LED"
    if ref.startswith("R"): return "R"
    if ref.startswith("C"): return "CP" if "CP_" in fpname else "C"
    return None


def geom(left, right, hide):
    n = max(len(left), len(right))
    top = (n - 1) // 2
    if hide:
        w = 2 * G
    else:
        ll = max([len(x[1]) for x in left] + [0])
        rl = max([len(x[1]) for x in right] + [0])
        w = max(2 * G, math.ceil(((ll + rl) * 1.3 + 4) / 2 / G) * G)
    L = G if hide else 2 * G
    pins = []
    for i, (num, name) in enumerate(left):
        pins.append((num, name, -(w + L), (top - i) * G, 0, L))
    for i, (num, name) in enumerate(right):
        pins.append((num, name, w + L, (top - i) * G, 180, L))
    box = (-w, (top + 1) * G - G / 2 if hide else (top + 1) * G, w,
           (top - n) * G + G / 2 if hide else (top - n) * G)
    if hide:
        box = (-w, G * 0.8, w, -G * 0.8)
    return pins, box


F = lambda v: ("%.4f" % v).rstrip("0").rstrip(".") if v != 0 else "0"
EFF = '(effects (font (size 1.27 1.27))'


def sym_text(name, d, prefix):
    left, right, hide, refp, descr = d
    pins, (x0, y0, x1, y1) = geom(left, right, hide)
    full = f"{prefix}{name}"
    s = [f'  (symbol "{full}"' + (" (pin_names hide)" if hide else " (pin_names (offset 1.016))")
         + " (in_bom yes) (on_board yes)"]
    s.append(f'    (property "Reference" "{refp}" (at 0 {F(y0 + 1.27)} 0) {EFF}))')
    s.append(f'    (property "Value" "{name}" (at 0 {F(y1 - 1.27)} 0) {EFF}))')
    s.append(f'    (property "Footprint" "" (at 0 0 0) {EFF} hide))')
    s.append(f'    (property "Datasheet" "" (at 0 0 0) {EFF} hide))')
    s.append(f'    (property "ki_description" "{descr}" (at 0 0 0) {EFF} hide))')
    s.append(f'    (symbol "{name}_0_1"')
    s.append(f'      (rectangle (start {F(x0)} {F(y0)}) (end {F(x1)} {F(y1)}) '
             '(stroke (width 0.254) (type default)) (fill (type background)))')
    s.append("    )")
    s.append(f'    (symbol "{name}_1_1"')
    for num, pname, px, py, ang, L in pins:
        s.append(f'      (pin passive line (at {F(px)} {F(py)} {ang}) (length {F(L)}) '
                 f'(name "{pname}" {EFF})) (number "{num}" {EFF})))')
    s.append("    )")
    s.append("  )")
    return "\n".join(s)


# ---------------------------------------------------------------- layout
# symbol origin positions on an A3 sheet (mm, multiples of 2.54)
def g(v): return round(v / G) * G

PLACE = {
    "U1": (g(75), g(105)),
    "J1": (g(180), g(45)), "J2": (g(180), g(80)),
    "SW1": (g(270), g(40)), "SW2": (g(270), g(60)),
    "D1": (g(270), g(85)),
    "J3": (g(180), g(135)),
    "U2": (g(340), g(130)),
    "U3": (g(340), g(45)),
}
PASSIVES = ["R1", "R2", "C1", "C2", "R3", "R4", "R5", "R6", "C3", "C4", "R7", "R8",
            "R9", "C5", "C6", "C7", "C8", "C9", "R10", "R11", "R12", "R13"]
for i, r in enumerate(PASSIVES):
    col, row = divmod(i, 6)
    PLACE[r] = (g(55 + col * 95), g(195 + row * 15.24))

NOTES = [
    (g(30), g(45), "Tang Nano 20K carrier: the module plugs\\ninto two 1x20 female headers.\\n"
     "SD: 73/74/75/76/77/86 (full SDIO)\\nSNES: 25-30   Buttons: 71/72 (active high)\\n"
     "Unused Tang pins are left free."),
    (g(150), g(20), "SNES controller ports (3.3 V)"),
    (g(250), g(20), "Buttons and power LED"),
    (g(150), g(110), "microSD socket"),
    (g(315), g(20), "Optional Uzenet ESP-12F (own 3.3 V LDO from the Tang's 5 V)"),
    (g(30), g(183), "Pull-ups and decoupling"),
]


def build():
    board = pcbnew.LoadBoard(PCB)
    defs = symbol_defs(board)
    fps = {f.GetReference(): f for f in board.GetFootprints()}
    out = ['(kicad_sch (version 20230121) (generator eeschema)', "",
           f"  (uuid {ROOT})", "", '  (paper "A3")', "",
           '  (title_block (title "UzeTang Board") (date "2026-11-22") (rev "1.0")'
           ' (comment 1 "Tang Nano 20K carrier for the Uzebox case - UzeTang / SNESTang")'
           ' (comment 2 "Generated by gen/make_sch.py from gen/design.py"))', "",
           "  (lib_symbols"]
    for name, d in defs.items():
        out.append(sym_text(name, d, LIB + ":"))
    out.append("  )\n")

    for (x, y, txt) in NOTES:
        out.append(f'  (text "{txt}" (at {F(x)} {F(y)} 0) (effects (font (size 1.778 1.778)) '
                   f'(justify left bottom)) (uuid {uid("note", x, y)}))')

    for ref, (sx, sy) in PLACE.items():
        fp = fps[ref]
        fpid = fp.GetFPIDAsString()
        sname = sym_for(ref, fpid)
        left, right, hide, _, _ = defs[sname]
        pins, (x0, y0, x1, y1) = geom(left, right, hide)
        nets = {p.GetNumber(): p.GetNetname() for p in fp.Pads() if p.GetNumber()}
        su = uid("sym", ref)
        out.append(f'  (symbol (lib_id "{LIB}:{sname}") (at {F(sx)} {F(sy)} 0) (unit 1)'
                   f' (in_bom yes) (on_board yes) (dnp no)')
        out.append(f"    (uuid {su})")
        out.append(f'    (property "Reference" "{ref}" (at {F(sx)} {F(sy - y0 - 1.27)} 0) {EFF}))')
        out.append(f'    (property "Value" "{fp.GetValue()}" (at {F(sx)} {F(sy - y1 + 1.27)} 0) {EFF}))')
        out.append(f'    (property "Footprint" "{fpid}" (at {F(sx)} {F(sy)} 0) {EFF} hide))')
        out.append(f'    (property "Datasheet" "" (at {F(sx)} {F(sy)} 0) {EFF} hide))')
        for num, *_ in pins:
            out.append(f'    (pin "{num}" (uuid {uid("pin", ref, num)}))')
        out.append(f'    (instances (project "UzeTang-Board" (path "/{ROOT}" (reference "{ref}") (unit 1))))')
        out.append("  )")
        # wires, labels and no-connect flags
        for num, pname, px, py, ang, _ in pins:
            ax, ay = sx + px, sy - py
            net = nets.get(num, "")
            if not net:
                out.append(f'  (no_connect (at {F(ax)} {F(ay)}) (uuid {uid("nc", ref, num)}))')
                continue
            dx = -2 * G if ang == 0 else 2 * G
            bx = ax + dx
            out.append(f'  (wire (pts (xy {F(ax)} {F(ay)}) (xy {F(bx)} {F(ay)})) '
                       f'(stroke (width 0) (type default)) (uuid {uid("w", ref, num)}))')
            la, just = (180, "right bottom") if ang == 0 else (0, "left bottom")
            out.append(f'  (label "{net}" (at {F(bx)} {F(ay)} {la}) (fields_autoplaced) '
                       f'(effects (font (size 1.27 1.27)) (justify {just})) (uuid {uid("l", ref, num)}))')
        # link the footprint to this symbol
        fp.SetPath(pcbnew.KIID_PATH(f"/{su}"))

    out.append('\n  (sheet_instances (path "/" (page "1")))')
    out.append(")")
    open(SCH, "w").write("\n".join(out) + "\n")

    lib = ["(kicad_symbol_lib (version 20220914) (generator make_sch.py)"]
    for name, d in defs.items():
        lib.append(sym_text(name, d, ""))
    lib.append(")")
    open(SYMLIB, "w").write("\n".join(lib) + "\n")
    open(os.path.join(PROJ, "sym-lib-table"), "w").write(
        '(sym_lib_table\n  (version 7)\n  (lib (name "UzeTang-Board")(type "KiCad")'
        '(uri "${KIPRJMOD}/UzeTang-Board.kicad_sym")(options "")(descr "UzeTang Board symbols"))\n)\n')
    pcbnew.SaveBoard(PCB, board)
    print("wrote", SCH)


if __name__ == "__main__":
    build()
