import sys, pcbnew, re, collections
b = pcbnew.LoadBoard(sys.argv[1])
pcbnew.WriteDRCReport(b, "/tmp/drc.rpt", pcbnew.EDA_UNITS_MILLIMETRES, True)
t = open("/tmp/drc.rpt").read()
print("\n".join(l for l in t.splitlines() if l.startswith("**")))
c = collections.Counter(re.findall(r'^\[(\w+)\]', t, re.M))
print(dict(c))
