#!/usr/bin/env python3
"""Write bom/UzeTang-Board-BOM-DigiKey.xlsx."""
import os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bom",
                   "UzeTang-Board-BOM-DigiKey.xlsx")
# (Digi-Key PN, qty, description, references, notes)
CORE = [
    ("S6104-ND", 2, "CONN HDR 20POS 0.1\" FEMALE TH (Sullins PPTC201LFBN-RC)", "U1",
     "Two 1x20 sockets for the Tang Nano 20K, so the module stays removable"),
    ("2223-TS02-66-43-BK-100-LCR-D-ND", 2, "6MM LIGHT TOUCH SWITCH 100GF", "SW1, SW2",
     "RESET and USER buttons, same switch and position as the Uzebox"),
    ("732-3816-1-ND", 1, "CONN SD CARD PUSH-PUSH R/A SMD (Wurth 693063020911)", "J3",
     "Same socket and position as the Uzebox; the only SMD part"),
    ("67-1056-ND", 1, "LED 3MM SHORT LENS GREEN DIFF", "D1", "Power LED under the case light pipe"),
    ("478-3192-ND", 3, "CAP CER .10UF 50V 20% RADIAL", "C1, C2, C4", ""),
    ("P19607CT-ND", 1, "CAP ALUM 10UF RADIAL 5MM DIA 2MM PITCH", "C3", "SD card supply"),
    ("493-1041-ND", 1, "CAP ALUM 220UF RADIAL 6.3MM DIA 2.5MM PITCH", "C5", "5 V bulk"),
    ("10.0KXBK-ND", 6, "RES 10K OHM 1/4W 1% METAL FILM", "R3, R4, R5, R6, R7, R8",
     "SD pull-ups (R3-R6), button pull-downs (R7, R8)"),
    ("4.75KXBK-ND", 2, "RES 4.75K OHM 1/4W 1% METAL FILM", "R1, R2", "SNES data pull-ups"),
    ("332XBK-ND", 1, "RES 332 OHM 1/4W 1% METAL FILM", "R9", "LED resistor"),
    ("SJ5303-7-ND", 1, "BUMPON HEMISPHERE 0.44X0.20 BLACK (sheet)", "BUMP1-4",
     "Feet, as on the Uzebox; one sheet covers the board"),
]
OPT = [
    ("1528-1438-ND", 1, "ESP-12F WIFI MODULE (ESP8266)", "U2", "Uzenet; removable"),
    ("2057-2RS1-08-G-ND", 2, "CONN RCPT 8POS 2MM TH", "U2",
     "Receptacles soldered to the board, as on the Uzebox"),
    ("952-2278-ND", 2, "CONN HEADER 8POS 2MM TH", "U2", "Solder these to the ESP-12F's castellated pads"),
    ("497-1491-5-ND", 1, "IC REG LDO 3.3V 0.8A TO220 (LD1117V33)", "U3",
     "Powers the ESP-12F from the Tang's 5 V"),
    ("P19607CT-ND", 2, "CAP ALUM 10UF RADIAL 5MM DIA 2MM PITCH", "C6, C7", "LDO input and output"),
    ("493-1041-ND", 1, "CAP ALUM 220UF RADIAL 6.3MM DIA 2.5MM PITCH", "C8", "ESP transmit peaks"),
    ("478-3192-ND", 1, "CAP CER .10UF 50V 20% RADIAL", "C9", ""),
    ("10.0KXBK-ND", 4, "RES 10K OHM 1/4W 1% METAL FILM", "R10, R11, R12, R13", "ESP EN/RST/IO0/IO2 pull-ups"),
    ("S1011EC-40-ND", 1, "CONN HEADER VERT 40POS 2.54MM (break off 2)", "J4", "ESP flash-mode jumper"),
    ("S9001-ND", 1, "CONN JUMPER SHORTING 2.54MM", "J4", "Fit to boot the ESP-12F into flash mode"),
]
OTHER = [
    ("Sipeed Tang Nano 20K (with pin headers fitted)", 1, "U1", "Sipeed / AliExpress; not sold by Digi-Key"),
    ("SNES controller socket, straight pins (same as Uzebox)", 2, "J1, J2", "AliExpress, as for the Uzebox"),
    ("Short USB-C extension cable (male to female panel mount)", 1, "-", "Brings the Tang's USB-C to the back of the case"),
    ("Short HDMI extension (optional)", 1, "-", "Only if the Tang's HDMI does not reach the case opening"),
]

wb = Workbook()
ws = wb.active
ws.title = "BOM"
A = "Arial"
hfont = Font(name=A, bold=True, color="FFFFFF")
hfill = PatternFill("solid", start_color="305496")
sfill = PatternFill("solid", start_color="D9E1F2")
thin = Side(style="thin", color="BFBFBF")
bd = Border(top=thin, bottom=thin, left=thin, right=thin)
base = Font(name=A, size=10)

ws["A1"] = "UzeTang Board v1.0 Digi-Key BOM. Last updated 22nd November 2026."
ws["A1"].font = Font(name=A, bold=True, size=13)
ws["A2"] = ("Columns A-B and D paste straight into Digi-Key's BOM Manager / Quick Add "
            "(part number, quantity, customer reference). Board quantity in F3 scales the order.")
ws["A2"].font = Font(name=A, italic=True, size=9)
ws["E3"] = "Boards to build:"
ws["E3"].font = Font(name=A, bold=True); ws["E3"].alignment = Alignment(horizontal="right")
ws["F3"] = 1
ws["F3"].font = Font(name=A, bold=True, color="0000FF")
ws["F3"].fill = PatternFill("solid", start_color="FFFF00")
ws["G3"] = "<- edit"
ws["G3"].font = Font(name=A, italic=True, size=9)

hdr = ["Digi-Key Part Number", "Qty per board", "Description", "References", "Notes", "Order qty"]
r = 5
for c, h in enumerate(hdr, 1):
    x = ws.cell(r, c, h); x.font = hfont; x.fill = hfill; x.border = bd
    x.alignment = Alignment(vertical="center", wrap_text=True)
r += 1

def section(title):
    global r
    ws.cell(r, 1, title).font = Font(name=A, bold=True)
    for c in range(1, 7):
        ws.cell(r, c).fill = sfill; ws.cell(r, c).border = bd
    r += 1

def rows(items):
    global r
    first = r
    for pn, q, d, ref, note in items:
        vals = [pn, q, d, ref, note, f"=B{r}*$F$3"]
        for c, v in enumerate(vals, 1):
            x = ws.cell(r, c, v); x.font = base; x.border = bd
            x.alignment = Alignment(vertical="top", wrap_text=c in (3, 5))
        r += 1
    return first, r - 1

section("Core parts (required)")
c0, c1 = rows(CORE)
section("Optional: removable ESP-12F for Uzenet (leave out for a board without WiFi)")
o0, o1 = rows(OPT)
r += 1
ws.cell(r, 3, "Digi-Key lines, core").font = Font(name=A, bold=True)
ws.cell(r, 2, f"=COUNTA(A{c0}:A{c1})").font = Font(name=A, bold=True)
r += 1
ws.cell(r, 3, "Digi-Key lines, ESP option").font = Font(name=A, bold=True)
ws.cell(r, 2, f"=COUNTA(A{o0}:A{o1})").font = Font(name=A, bold=True)
r += 2

section("Not from Digi-Key")
for d, q, ref, note in OTHER:
    vals = ["-", q, d, ref, note, f"=B{r}*$F$3"]
    for c, v in enumerate(vals, 1):
        x = ws.cell(r, c, v); x.font = base; x.border = bd
        x.alignment = Alignment(vertical="top", wrap_text=c in (3, 5))
    r += 1
r += 1
notes = [
    "Part numbers marked as in the Uzebox / Omega v1.5 Digi-Key BOMs are reused unchanged (switch, SD socket, LED, 100n, ESP-12F parts).",
    "All parts are through-hole except the SD socket, which is the same SMD socket the Uzebox uses.",
    "4.75k (E96) is used for the 4.7k SNES pull-ups and 332 R for the 330 R LED resistor; either nominal value works.",
    "Check stock and pricing in Digi-Key before ordering: part numbers can be superseded.",
]
for n in notes:
    ws.cell(r, 1, n).font = Font(name=A, size=9, italic=True); r += 1

for col, w in zip("ABCDEF", (27, 13, 52, 24, 52, 11)):
    ws.column_dimensions[col].width = w
ws.freeze_panes = "A6"
wb.save(OUT)
print(OUT)
