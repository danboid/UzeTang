"""UzeTang Board - single source of truth for parts, placement and nets.

Coordinates: Uzebox V5.0 board coordinates in mm (origin at the front-left
corner, x to the right, y towards the back), so every position can be
checked against Uzebox-V5.0.brd. to_kicad() converts them to the KiCad page
coordinates used by the Uzebox Omega v1.5 KiCad board, so the two boards
overlay exactly.

Rotation is the KiCad footprint rotation in degrees.
"""

BOARD_W, BOARD_H = 100.0, 81.0
CORNER_R = 3.0                      # rounded corners, centred on the front mounting holes
X0, Y0 = 98.5011, 145.5036          # Uzebox (0,0) in Omega KiCad coordinates


def to_kicad(x, y):
    return (X0 + x, Y0 - y)


LIB = "UzeTang-Board"
R_FP = f"{LIB}:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"
C_FP = f"{LIB}:C_Disc_D3.8mm_W2.6mm_P2.50mm"
CP5_FP = f"{LIB}:CP_Radial_D5.0mm_P2.00mm"
CP63_FP = f"{LIB}:CP_Radial_D6.3mm_P2.50mm"

# Tang Nano 20K pin assignment (FPGA pin -> net). SNES pins are SNESTang's.
TANG = {
    "5V": "+5V", "GND_1": "GND", "GND_2": "GND", "GND_3": "GND",
    "3V3_1": "+3V3", "3V3_2": "+3V3",
    "28": "SNES1_LATCH", "27": "SNES1_CLK", "25": "SNES1_DATA",
    "29": "SNES2_LATCH", "26": "SNES2_CLK", "30": "SNES2_DATA",
    "73": "SD_CLK", "74": "SD_CMD", "75": "SD_DAT0", "76": "SD_DAT3",
    "77": "SD_DAT1", "86": "SD_DAT2",
    "71": "BTN_RESET", "72": "BTN_USER",
    "48": "ESP_RXD", "49": "ESP_TXD", "31": "ESP_RST",
    "52": "AUDIO_L_DAC", "53": "AUDIO_R_DAC",
}


def snes(n):
    return {"P$8": "+3V3", "P$9": f"SNES{n}_CLK", "P$10": f"SNES{n}_LATCH",
            "P$11": f"SNES{n}_DATA", "P$12": None, "P$13": None, "P$14": "GND"}


ESP = {1: "ESP_RST", 2: None, 3: "ESP_EN", 4: None, 5: None, 6: None,
       7: None, 8: "+3V3_ESP", 9: "GND", 10: "GND", 11: "ESP_IO2",
       12: "ESP_IO0", 13: None, 14: None, 15: "ESP_RXD", 16: "ESP_TXD"}
ESP_PADS = {str(k): v for k, v in ESP.items()}


def R(ref, value, a, b, x, y, rot, dk, note=""):
    return dict(ref=ref, value=value, fp=R_FP, x=x, y=y, rot=rot,
                pads={"1": a, "2": b}, sym="R", dk=dk, note=note)


def C(ref, value, a, b, x, y, rot, fp, dk, sym="C", note=""):
    return dict(ref=ref, value=value, fp=fp, x=x, y=y, rot=rot,
                pads={"1": a, "2": b}, sym=sym, dk=dk, note=note)


DK_10K = "10.0KXBK-ND"
DK_4K7 = "4.75KXBK-ND"
DK_330 = "332XBK-ND"
DK_100N = "478-3192-ND"
DK_10U = "P19607CT-ND"
DK_220U = "493-1041-ND"
DK_1K = "1.00KXBK-ND"
DK_10N = "478-3178-ND"          # AVX SR151C103KAR, X7R, 2.54 mm lead spacing
RCA_FP = f"{LIB}:RCA"

PARTS = [
    # ---- Tang Nano 20K: HDMI end at the back edge, USB-C towards the front
    dict(ref="U1", value="Tang Nano 20K", fp=f"{LIB}:TangNano20K", x=30.0, y=51.0,
         rot=180, pads=TANG, sym="TangNano20K",
         dk="S6104-ND", dkqty=2, mpn="Sullins PPTC201LFBN-RC (1x20 female header)",
         note="Sipeed Tang Nano 20K, plugged into two 1x20 female headers"),
    # ---- Uzebox positions: SNES ports, buttons, LED, SD socket, ESP-12
    dict(ref="J1", value="SNES P1", fp=f"{LIB}:SNES_CONNECTOR", x=21.59, y=0.0, rot=0,
         pads=snes(1), sym="SNES", dk=None,
         note="SNES controller socket, straight-pin version, as Uzebox (AliExpress)"),
    dict(ref="J2", value="SNES P2", fp=f"{LIB}:SNES_CONNECTOR", x=76.2, y=0.0, rot=0,
         pads=snes(2), sym="SNES", dk=None,
         note="SNES controller socket, straight-pin version, as Uzebox (AliExpress)"),
    dict(ref="SW1", value="RESET", fp=f"{LIB}:TACTILE-PTH", x=20.86, y=13.97, rot=0,
         pads={"1": "BTN_RESET", "2": "BTN_RESET", "3": "+3V3", "4": "+3V3"}, sym="SW4",
         dk="2223-TS02-66-43-BK-100-LCR-D-ND", mpn="CUI TS02-66-43-BK-100-LCR-D"),
    dict(ref="SW2", value="USER", fp=f"{LIB}:TACTILE-PTH", x=77.47, y=13.97, rot=0,
         pads={"1": "BTN_USER", "2": "BTN_USER", "3": "+3V3", "4": "+3V3"}, sym="SW4",
         dk="2223-TS02-66-43-BK-100-LCR-D-ND", mpn="CUI TS02-66-43-BK-100-LCR-D"),
    dict(ref="D1", value="Green", fp=f"{LIB}:LED3MM", x=50.8, y=2.54, rot=0,
         pads={"A": "LED_A", "K": "GND"}, sym="LED", dk="67-1056-ND",
         note="Power LED under the case light pipe"),
    dict(ref="J3", value="SD card", fp=f"{LIB}:SDCARD_4UCONN", x=83.82, y=52.07, rot=90,
         pads={"1": "SD_DAT3", "2": "SD_CMD", "3": "GND", "4": "+3V3", "5": "SD_CLK",
               "6": "GND", "7": "SD_DAT0", "8": "SD_DAT1", "9": "SD_DAT2",
               "CD": None, "WP": None, "SH@1": "GND", "SH@2": "GND"},
         sym="SD", dk="732-3816-1-ND", mpn="Wurth 693063020911",
         note="Same socket and position as the Uzebox"),
    dict(ref="U2", value="ESP-12F", fp=f"{LIB}:ESP-12F_Socket_2mm", x=87.0, y=30.5, rot=-90,
         pads=ESP_PADS, sym="ESP12", dk="1528-1438-ND", optional=True,
         note="Removable ESP-12F (Uzenet) on 2x 8-pin 2.0 mm receptacles, as on the Uzebox"),
    # Lies flat, tab down, with its body towards the back of the board.
    # The M3 hole in the tab can take a screw; there is no copper under the tab.
    dict(ref="U3", value="LD1117V33", fp=f"{LIB}:TO-220-3_Horizontal_TabDown",
         x=60.1, y=37.0, rot=0, pads={"1": "GND", "2": "+3V3_ESP", "3": "+5V"},
         sym="LDO", dk="497-1491-5-ND", optional=True,
         note="3.3 V for the ESP-12F (its current peaks are too much for the Tang's 3.3 V)"),
    # ---- analog audio (optional): FPGA 1-bit DAC -> 1k/10n low pass (16 kHz)
    #      -> 10u DC block -> RCA jack. Same RCA jacks as the Uzebox: the
    #      left one sits where the Uzebox has its AUDIO jack, the right one
    #      where it has its DC power jack (white left, red right from behind).
    dict(ref="J4", value="AUDIO L", fp=RCA_FP, x=47.2, y=75.5, rot=0,
         pads={"SIG": "AUDIO_L", "GND": "GND"}, sym="RCA", dk="CP-1420-ND",
         mpn="CUI RCJ-043 (white)", note="Left / mono audio out, as the Uzebox"),
    dict(ref="J5", value="AUDIO R", fp=RCA_FP, x=7.62, y=75.5, rot=0,
         pads={"SIG": "AUDIO_R", "GND": "GND"}, sym="RCA", dk="CP-1419-ND",
         mpn="CUI RCJ-042 (red)", note="Right audio out, where the Uzebox has its DC jack"),
    R("R14", "1k", "AUDIO_L_F", "AUDIO_L_DAC", 3.0, 51.5, 0, DK_1K, "Left DAC low pass"),
    R("R15", "1k", "AUDIO_R_F", "AUDIO_R_DAC", 3.0, 48.0, 0, DK_1K, "Right DAC low pass"),
    C("C10", "10n", "AUDIO_L_F", "GND", 3.0, 43.0, 0, C_FP, DK_10N, note="Left DAC low pass"),
    C("C11", "10n", "AUDIO_R_F", "GND", 9.0, 43.0, 0, C_FP, DK_10N, note="Right DAC low pass"),
    C("C12", "10u", "AUDIO_L_F", "AUDIO_L", 45.5, 64.0, 0, CP5_FP, DK_10U, sym="CP",
      note="Left DC block"),
    C("C13", "10u", "AUDIO_R_F", "AUDIO_R", 12.0, 64.0, 0, CP5_FP, DK_10U, sym="CP",
      note="Right DC block"),
    # ---- pull-ups
    R("R1", "4.7k", "+3V3", "SNES1_DATA", 26.5, 8.0, 0, DK_4K7, "SNES P1 data pull-up"),
    R("R2", "4.7k", "+3V3", "SNES2_DATA", 59.5, 12.0, 0, DK_4K7, "SNES P2 data pull-up"),
    R("R3", "10k", "+3V3", "SD_DAT0", 46.0, 44.0, 0, DK_10K, "SD DAT0 (MISO) pull-up"),
    R("R4", "10k", "+3V3", "SD_DAT3", 46.0, 47.5, 0, DK_10K, "SD DAT3 (CS) pull-up"),
    R("R5", "10k", "+3V3", "SD_DAT1", 46.0, 51.0, 0, DK_10K, "SD DAT1 pull-up"),
    R("R6", "10k", "+3V3", "SD_DAT2", 46.0, 54.5, 0, DK_10K, "SD DAT2 pull-up"),
    R("R7", "10k", "GND", "BTN_RESET", 9.0, 12.0, 90, DK_10K, "RESET button pull-down (active high, like the Tang's S1)"),
    R("R8", "10k", "GND", "BTN_USER", 92.0, 8.0, 90, DK_10K, "USER button pull-down (active high, like the Tang's S2)"),
    R("R9", "330", "+3V3", "LED_A", 44.5, 12.0, 0, DK_330, "Power LED"),
    R("R10", "10k", "+3V3_ESP", "ESP_EN", 46.0, 23.0, 0, DK_10K, "ESP EN pull-up", ),
    R("R11", "10k", "+3V3_ESP", "ESP_RST", 46.0, 26.5, 0, DK_10K, "ESP RST pull-up"),
    R("R12", "10k", "+3V3_ESP", "ESP_IO0", 46.0, 30.0, 0, DK_10K, "ESP GPIO0 pull-up"),
    R("R13", "10k", "+3V3_ESP", "ESP_IO2", 46.0, 33.5, 0, DK_10K, "ESP GPIO2 pull-up"),
    # ---- capacitors
    C("C1", "100n", "+3V3", "GND", 39.0, 8.0, 0, C_FP, DK_100N, note="SNES P1 supply"),
    C("C2", "100n", "+3V3", "GND", 61.0, 7.0, 0, C_FP, DK_100N, note="SNES P2 supply"),
    C("C3", "10u", "+3V3", "GND", 78.0, 45.5, 0, CP5_FP, DK_10U, sym="CP", note="SD card supply"),
    C("C4", "100n", "+3V3", "GND", 85.0, 45.5, 0, C_FP, DK_100N, note="SD card supply"),
    C("C5", "220u", "+5V", "GND", 9.0, 30.0, 0, CP63_FP, DK_220U, sym="CP", note="5 V bulk"),
    C("C6", "10u", "+5V", "GND", 58.9, 59.5, 0, CP5_FP, DK_10U, sym="CP", note="LD1117 input"),
    C("C7", "10u", "+3V3_ESP", "GND", 63.8, 64.5, 0, CP5_FP, DK_10U, sym="CP", note="LD1117 output"),
    C("C8", "220u", "+3V3_ESP", "GND", 70.0, 30.0, 0, CP63_FP, DK_220U, sym="CP",
      note="ESP-12F bulk (transmit current peaks)"),
    C("C9", "100n", "+3V3_ESP", "GND", 70.0, 25.0, 0, C_FP, DK_100N, note="ESP-12F supply"),
]
for p in PARTS:
    if p["ref"] in ("C6", "C7", "C8", "C9", "R10", "R11", "R12", "R13"):
        p["optional"] = True          # ESP-12F section
    if p["ref"] in ("J4", "J5", "R14", "R15", "C10", "C11", "C12", "C13"):
        p["optional"] = "audio"       # analog audio section

MECH = [
    dict(ref="H1", fp=f"{LIB}:MountingHole_3.3mm_Uzebox", x=3.0, y=3.0),
    dict(ref="H2", fp=f"{LIB}:MountingHole_3.3mm_Uzebox", x=97.0, y=3.0),
    dict(ref="H3", fp=f"{LIB}:MountingHole_3.3mm_Uzebox", x=55.136, y=71.154),
    dict(ref="H4", fp=f"{LIB}:Hole_2.2mm_LightPipe", x=44.45, y=2.54),
    dict(ref="H5", fp=f"{LIB}:Hole_2.2mm_LightPipe", x=57.15, y=2.54),
    dict(ref="BUMP1", fp=f"{LIB}:Bumpon", x=5.794, y=59.855),
    dict(ref="BUMP2", fp=f"{LIB}:Bumpon", x=6.048, y=5.921),
    dict(ref="BUMP3", fp=f"{LIB}:Bumpon", x=95.952, y=4.794),
    dict(ref="BUMP4", fp=f"{LIB}:Bumpon", x=93.825, y=73.825),
]

POWER_NETS = ["GND", "+5V", "+3V3", "+3V3_ESP"]

# no copper under the ESP-12F's PCB antenna (x1, y1, x2, y2, Uzebox coords)
ESP_ANTENNA_KEEPOUT = (93.5, 22.0, 100.0, 39.0)
# No top copper under U3's tab (the tab is VOUT and sits on the board)
U3_TAB_KEEPOUT = (57.4, 40.0, 67.9, 56.9)


def nets():
    s = set()
    for p in PARTS:
        for n in p["pads"].values():
            if n:
                s.add(n)
    return sorted(s)


# Hand-placed routes, fed to Freerouting as existing wiring.
# +3V3 from the Tang's 3V3 pin over to the SD socket decoupling (C3), which
# the autorouter otherwise fails to reach through the resistor bank.
PREROUTES = [
    {"net": "+3V3", "layer": "F", "w": 0.6,
     "pts": [(40.16, 72.59), (43.24, 69.51), (45.25, 67.5), (75.0, 67.5)],
     "vias": [(75.0, 67.5)]},
    {"net": "+3V3", "layer": "B", "w": 0.6,
     "pts": [(75.0, 67.5), (78.0, 64.5), (78.0, 45.5)]},
]
