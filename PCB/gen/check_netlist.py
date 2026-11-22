#!/usr/bin/env python3
"""Compare the schematic's netlist (kicad-cli) with the board's pad nets."""
import os, re, subprocess, sys
import pcbnew
P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
subprocess.run(["kicad-cli", "sch", "export", "netlist", "-o", "/tmp/uzetang.net",
                os.path.join(P, "UzeTang-Board.kicad_sch")], check=True, capture_output=True)
t = open("/tmp/uzetang.net").read()
sch = {}
for m in re.finditer(r'\(net \(code "?\d+"?\) \(name "([^"]*)"\)(.*?)(?=\(net \(code|\Z)', t, re.S):
    for r, p in re.findall(r'\(node \(ref "([^"]+)"\) \(pin "([^"]+)"\)', m.group(2)):
        sch[(r, p)] = m.group(1).lstrip("/")
b = pcbnew.LoadBoard(os.path.join(P, "UzeTang-Board.kicad_pcb"))
bad = n = 0
for f in b.GetFootprints():
    for pad in f.Pads():
        if not pad.GetNumber():
            continue
        n += 1
        k, v = (f.GetReference(), pad.GetNumber()), pad.GetNetname()
        s = sch.get(k, "")
        ok = s.startswith("unconnected") or s == "" if v == "" else s == v
        if not ok:
            print("MISMATCH", k, "pcb:", v, "sch:", s); bad += 1
print(f"{n} pads checked, {bad} mismatches")
sys.exit(1 if bad else 0)
