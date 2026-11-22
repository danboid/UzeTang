#!/usr/bin/env python3
"""
Build an Uzebox demo/game from the Uzebox repository with avr-gcc, without
running the repository's Makefile: the makefile is parsed for its variables
(KERNEL_OPTIONS, CFLAGS, LDFLAGS, OBJECTS, ...) and object -> source rules,
and the compiler is invoked directly. Data generation steps (gconvert etc.)
are not run, so only demos with pre-generated data files build.

usage: build_demo.py <uzebox repo> <demo name> <output dir>
"""
import os, re, shlex, subprocess, sys

def parse_makefile(path):
    vars_, rules = {}, {}
    lines = open(path, errors="replace").read().replace("\\\n", " ").split("\n")
    cur = None
    for ln in lines:
        if ln.startswith("\t"):
            if cur: rules[cur]["recipe"].append(ln.strip())
            continue
        s = ln.split("#", 1)[0].rstrip()
        if not s.strip():
            continue
        m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(\+=|:=|\?=|=)\s*(.*)$", s)
        if m:
            k, op, v = m.groups()
            if op == "+=":
                vars_[k] = (vars_.get(k, "") + " " + v).strip()
            elif op == "?=":
                vars_.setdefault(k, v)
            else:
                vars_[k] = v
            cur = None
            continue
        m = re.match(r"^([^:=]+):([^=].*|)$", s)
        if m:
            tgt = m.group(1).strip()
            pre = m.group(2).split()
            rules[tgt] = {"pre": pre, "recipe": []}
            cur = tgt
    return vars_, rules

BASEDIR = '.'

def expand(s, vars_, depth=0):
    if depth > 20:
        return s
    def rep(m):
        name = m.group(1)
        return expand(vars_.get(name, ""), vars_, depth + 1)
    out = re.sub(r"\$\((?:realpath|abspath)\s+([^)]*)\)",
                 lambda m: os.path.realpath(os.path.join(BASEDIR, m.group(1).strip())), s)
    out = re.sub(r"\$\(([A-Za-z_][A-Za-z0-9_]*)\)", rep, out)
    out = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", rep, out)
    return out

def clean_flags(flags):
    toks = shlex.split(flags)
    res, skip = [], 0
    for i, t in enumerate(toks):
        if skip:
            skip -= 1
            continue
        if t in ("-MD", "-MP"):
            continue
        if t in ("-MT", "-MF"):
            skip = 1
            continue
        if t.startswith("-Wl,-Map"):
            continue
        res.append(t)
    return res

def main():
    repo, demo, outdir = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
    ddir = os.path.join(repo, "demos", demo, "default")
    mk = os.path.join(ddir, "Makefile")
    global BASEDIR
    BASEDIR = ddir
    vars_, rules = parse_makefile(mk)
    vars_.setdefault("OBJDIR", ".")
    os.makedirs(outdir, exist_ok=True)
    objs = expand(vars_.get("OBJECTS", ""), vars_).split()
    incl = expand(vars_.get("INCLUDES", ""), vars_)
    cflags = clean_flags(expand(vars_.get("CFLAGS", ""), vars_))
    asmflags = clean_flags(expand(vars_.get("ASMFLAGS", ""), vars_))
    ldflags = clean_flags(expand(vars_.get("LDFLAGS", ""), vars_))
    libs = expand(vars_.get("LIBDIRS", "") + " " + vars_.get("LIBS", ""), vars_).split()
    hexflags = expand(vars_.get("HEX_FLASH_FLAGS", "-R .eeprom"), vars_).split()
    game = expand(vars_.get("GAME", vars_.get("PROJECT", demo)), vars_)
    objpaths = []
    for o in objs:
        key = None
        for k in rules:
            if expand(k, vars_) == o:
                key = k
                break
        if key is None:
            print("no rule for", o); return 1
        src = expand(rules[key]["pre"][0], vars_)
        srcp = os.path.normpath(os.path.join(ddir, src))
        isasm = src.endswith((".s", ".S"))
        objp = os.path.join(outdir, os.path.basename(o))
        cmd = ["avr-gcc"] + shlex.split(incl) + \
              (asmflags if isasm else cflags) + ["-c", srcp, "-o", objp]
        r = subprocess.run(cmd, cwd=ddir, capture_output=True, text=True)
        if r.returncode:
            print(r.stderr[-3000:]); return 1
        objpaths.append(objp)
    elf = os.path.join(outdir, game + ".elf")
    r = subprocess.run(["avr-gcc"] + ldflags + objpaths + libs + ["-o", elf],
                       cwd=ddir, capture_output=True, text=True)
    if r.returncode:
        print(r.stderr[-3000:]); return 1
    hexf = os.path.join(outdir, game + ".hex")
    subprocess.run(["avr-objcopy", "-O", "ihex"] + hexflags + [elf, hexf], check=True)
    print("built", hexf)
    return 0

if __name__ == "__main__":
    sys.exit(main())
