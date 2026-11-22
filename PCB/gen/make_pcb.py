#!/usr/bin/env python3
"""Build UzeTang-Board.kicad_pcb from design.py with the KiCad 7 pcbnew API.

  make_pcb.py place      placed, unrouted board + Specctra DSN for Freerouting
  make_pcb.py finish     import Freerouting's SES, add GND pours, fill, save
"""
import os, sys
import pcbnew
sys.path.insert(0, os.path.dirname(__file__))
import design as D

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PCB = os.path.join(PROJ, "UzeTang-Board.kicad_pcb")
SYSFP = "/usr/share/kicad/footprints"


def mm(v):
    return pcbnew.FromMM(v)


def vec(x, y):
    return pcbnew.VECTOR2I(mm(x), mm(y))


def load_fp(libname):
    nick, name = libname.split(":")
    path = os.path.join(PROJ, "UzeTang-Board.pretty") if nick == D.LIB else os.path.join(SYSFP, nick + ".pretty")
    fp = pcbnew.FootprintLoad(path, name)
    if fp is None:
        raise SystemExit(f"footprint {libname} not found")
    fp.SetFPID(pcbnew.LIB_ID(nick, name))
    return fp


def add_line(board, layer, x1, y1, x2, y2, w=0.1):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(vec(x1, y1)); s.SetEnd(vec(x2, y2))
    s.SetLayer(layer); s.SetWidth(mm(w))
    board.Add(s)


def add_text(board, text, x, y, size=1.2, layer=pcbnew.F_SilkS, rot=0, thick=0.18):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(vec(x, y))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(thick))
    t.SetTextAngleDegrees(rot)
    if layer in (pcbnew.B_SilkS, pcbnew.B_Cu):
        t.SetMirrored(True)
    board.Add(t)


def place():
    board = pcbnew.NewBoard(PCB)
    ds = board.GetDesignSettings()
    ds.SetCopperLayerCount(2)
    ds.m_TrackMinWidth = mm(0.2)
    ds.m_MinClearance = mm(0.2)
    ds.m_CopperEdgeClearance = mm(0.3)
    ds.m_HoleClearance = mm(0.25)

    # net classes
    nc = ds.m_NetSettings.m_DefaultNetClass
    nc.SetTrackWidth(mm(0.3)); nc.SetClearance(mm(0.25))
    nc.SetViaDiameter(mm(0.8)); nc.SetViaDrill(mm(0.4))
    pw = pcbnew.NETCLASS("Power")
    pw.SetTrackWidth(mm(0.6)); pw.SetClearance(mm(0.25))
    pw.SetViaDiameter(mm(1.0)); pw.SetViaDrill(mm(0.5))
    ds.m_NetSettings.m_NetClasses["Power"] = pw

    nets = {}
    for n in D.nets():
        ni = pcbnew.NETINFO_ITEM(board, n)
        board.Add(ni)
        if n in D.POWER_NETS:
            ni.SetNetClass(pw)
        nets[n] = ni

    # outline
    x0, y0 = D.to_kicad(0, D.BOARD_H)
    x1, y1 = D.to_kicad(D.BOARD_W, 0)
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        add_line(board, pcbnew.Edge_Cuts, a[0], a[1], b[0], b[1], 0.1)

    for p in D.PARTS + D.MECH:
        fp = load_fp(p["fp"])
        fp.SetReference(p["ref"])
        fp.SetValue(p.get("value", p["fp"].split(":")[1]))
        x, y = D.to_kicad(p["x"], p["y"])
        fp.SetPosition(vec(x, y))
        fp.SetOrientationDegrees(p.get("rot", 0))
        board.Add(fp)
        for pad in fp.Pads():
            name = pad.GetName()
            if "pads" in p and name in p["pads"]:
                n = p["pads"][name]
                if n:
                    pad.SetNet(nets[n])
    board.BuildListOfNets()

    # silkscreen
    def T(text, x, y, size=1.2, rot=0, layer=pcbnew.F_SilkS):
        kx, ky = D.to_kicad(x, y)
        add_text(board, text, kx, ky, size, layer, rot)
    T("SNES P1", 21.59, 7.0, 1.2)
    T("SNES P2", 76.2, 7.0, 1.2)
    T("RESET", 20.86, 18.6, 1.0)
    T("USER", 77.47, 18.6, 1.0)
    T("ESP-12F (optional, Uzenet)", 87.0, 41.0, 0.9)
    T("SD CARD", 83.0, 77.0, 1.2)
    T("HDMI ^ back of case", 30.0, 79.6, 1.0)
    T("UzeTang Board v1.0", 51.0, 77.0, 1.3)
    T("UzeTang Board v1.0", 50.0, 40.0, 1.5, 0, pcbnew.B_SilkS)
    T("Tang Nano 20K carrier - UzeTang / SNESTang", 50.0, 37.5, 1.0, 0, pcbnew.B_SilkS)
    T("Fits the Uzebox 3D-printed case", 50.0, 35.5, 1.0, 0, pcbnew.B_SilkS)
    T("CERN-OHL-S-2.0", 50.0, 33.5, 1.0, 0, pcbnew.B_SilkS)

    # copper keep-out under the ESP-12F's PCB antenna (both layers)
    ka = D.ESP_ANTENNA_KEEPOUT
    z = pcbnew.ZONE(board)
    z.SetIsRuleArea(True)
    z.SetDoNotAllowCopperPour(True); z.SetDoNotAllowTracks(True); z.SetDoNotAllowVias(True)
    z.SetDoNotAllowPads(False); z.SetDoNotAllowFootprints(False)
    ls = pcbnew.LSET(); ls.AddLayer(pcbnew.F_Cu); ls.AddLayer(pcbnew.B_Cu)
    z.SetLayerSet(ls)
    z.SetZoneName("ESP antenna keep-out")
    ol = z.Outline(); ol.NewOutline()
    for (x, y) in ((ka[0], ka[1]), (ka[2], ka[1]), (ka[2], ka[3]), (ka[0], ka[3])):
        kx, ky = D.to_kicad(x, y)
        ol.Append(mm(kx), mm(ky))
    board.Add(z)

    # hand pre-routes (Freerouting keeps them; see design.PREROUTES)
    for pr in D.PREROUTES:
        net = board.FindNet(pr["net"])
        pts = [D.to_kicad(x, y) for (x, y) in pr["pts"]]
        layer = pcbnew.F_Cu if pr["layer"] == "F" else pcbnew.B_Cu
        for a, b in zip(pts, pts[1:]):
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(vec(*a)); t.SetEnd(vec(*b))
            t.SetWidth(mm(pr["w"])); t.SetLayer(layer); t.SetNet(net)
            board.Add(t)
        for (x, y) in pr.get("vias", []):
            v = pcbnew.PCB_VIA(board)
            v.SetPosition(vec(*D.to_kicad(x, y)))
            v.SetWidth(mm(1.0)); v.SetDrill(mm(0.5))
            v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetNet(net)
            board.Add(v)

    pcbnew.SaveBoard(PCB, board)
    # assign power nets to the Power net class in the project file afterwards
    dsn = os.path.join(PROJ, "gen", "UzeTang-Board.dsn")
    ok = pcbnew.ExportSpecctraDSN(board, dsn)
    fix_dsn_classes(dsn)
    print("saved", PCB, "dsn", ok)


def fix_dsn_classes(dsn):
    """KiCad 7's DSN export leaves the Power class empty: move the power nets
    from the default class into it so Freerouting uses 0.6 mm tracks."""
    import re
    s = open(dsn).read()
    m = re.search(r'\(class kicad_default ""(.*?)\n\s*\(circuit', s, re.S)
    names = m.group(1).split()
    keep = [n for n in names if n not in D.POWER_NETS]
    s = s[:m.start(1)] + " " + " ".join(keep) + s[m.end(1):]
    s = s.replace("(class Power", "(class Power " + " ".join(D.POWER_NETS), 1)
    open(dsn, "w").write(s)


def finish():
    board = pcbnew.LoadBoard(PCB)
    # the SES holds every wire (pre-routes included, possibly split): drop ours
    for t in [t for t in board.GetTracks()]:
        board.Delete(t)
    ses = os.path.join(PROJ, "gen", "UzeTang-Board.ses")
    import_ses(board, ses)
    gnd = board.FindNet("GND")
    x0, y0 = D.to_kicad(0, D.BOARD_H)
    x1, y1 = D.to_kicad(D.BOARD_W, 0)
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNet(gnd)
        z.SetIsRuleArea(False)
        z.SetLocalClearance(mm(0.4))
        z.SetMinThickness(mm(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(mm(0.4))
        z.SetThermalReliefSpokeWidth(mm(0.5))
        z.SetAssignedPriority(0)
        ol = z.Outline()
        ol.NewOutline()
        m = 0.5
        for (x, y) in ((x0 + m, y0 + m), (x1 - m, y0 + m), (x1 - m, y1 - m), (x0 + m, y1 - m)):
            ol.Append(mm(x), mm(y))
        board.Add(z)
    filler = pcbnew.ZONE_FILLER(board)
    filler.Fill(board.Zones())
    pcbnew.SaveBoard(PCB, board)
    print("finished", PCB)


def import_ses(board, ses):
    """Add Freerouting's wires and vias (Specctra session file) to the board.
    SES units: (resolution um 10), i.e. 0.1 um; y axis points up."""
    import re
    txt = open(ses).read()
    out = txt[txt.index("(network_out"):]
    layers = {"F.Cu": pcbnew.F_Cu, "B.Cu": pcbnew.B_Cu}
    vias = {}
    for vm in re.finditer(r'\(padstack "?([^"\s]+)"?\s+\(shape \(circle (\S+) (\d+)', txt):
        vias.setdefault(vm.group(1), int(vm.group(3)))
    ntr = nvia = 0
    for nm in re.finditer(r'\(net ("[^"]*"|\S+)\s(.*?)(?=\n      \(net |\n    \)\n)', out, re.S):
        name = nm.group(1).strip('"')
        net = board.FindNet(name)
        body = nm.group(2)
        for wm in re.finditer(r'\(path (\S+) (\d+)\s+([-\d\s]+)\)', body):
            layer = layers[wm.group(1)]
            w = int(wm.group(2)) / 10.0
            pts = [int(v) for v in wm.group(3).split()]
            xy = [(pts[i] / 10.0, -pts[i + 1] / 10.0) for i in range(0, len(pts), 2)]
            for a, b in zip(xy, xy[1:]):
                t = pcbnew.PCB_TRACK(board)
                t.SetStart(pcbnew.VECTOR2I(int(a[0] * 1000), int(a[1] * 1000)))
                t.SetEnd(pcbnew.VECTOR2I(int(b[0] * 1000), int(b[1] * 1000)))
                t.SetWidth(int(w * 1000)); t.SetLayer(layer); t.SetNet(net)
                board.Add(t); ntr += 1
        for vm in re.finditer(r'\(via "?([^"\s]+)"?\s+(-?\d+) (-?\d+)', body):
            m2 = re.search(r'_(\d+):(\d+)_um', vm.group(1))
            dia, drill = (int(m2.group(1)), int(m2.group(2))) if m2 else (800, 400)
            v = pcbnew.PCB_VIA(board)
            v.SetPosition(pcbnew.VECTOR2I(int(vm.group(2)) * 100, -int(vm.group(3)) * 100))
            v.SetWidth(dia * 1000); v.SetDrill(drill * 1000)
            v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetNet(net)
            board.Add(v); nvia += 1
    print(f"imported {ntr} track segments, {nvia} vias")


if __name__ == "__main__":
    {"place": place, "finish": finish}[sys.argv[1]]()
