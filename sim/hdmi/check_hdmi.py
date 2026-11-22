#!/usr/bin/env python3
"""Independent checker for the HDMI symbol stream written by tb_hdmi.v.

Decodes the three TMDS channels the way a sink does and checks, against the
HDMI 1.4 / CEA-861 rules:
  - period structure: control >= 12 characters before every preamble,
    8-character preambles, 2-character guard bands, packets of 32 characters
  - TMDS video decode equals the test picture, sync timing of 720x480p
  - TERC4 channel 0 bit 3 (0 only on the first character of an island)
  - BCH ECC of every header and subpacket
  - InfoFrame checksums, ACR N/CTS, audio samples (values, order, parity,
    channel status, B flags)
"""
import sys

CTRL = {0b1101010100: 0, 0b0010101011: 1, 0b0101010100: 2, 0b1010101011: 3}
TERC4 = [0b1010011100, 0b1001100011, 0b1011100100, 0b1011100010,
         0b0101110001, 0b0100011110, 0b0110001110, 0b0100111100,
         0b1011001100, 0b0100111001, 0b0110011100, 0b1011000110,
         0b1010001110, 0b1001110001, 0b0101100011, 0b1011000011]
TERC4_INV = {v: i for i, v in enumerate(TERC4)}
VG = [0b1011001100, 0b0100110011, 0b1011001100]
DG12 = 0b0100110011

errors = []
def err(msg):
    errors.append(msg)
    if len(errors) < 30:
        print("ERROR:", msg)

def tmds_decode(q):
    d = (~q & 0xFF) if (q >> 9) & 1 else (q & 0xFF)
    out = d & 1
    for i in range(1, 8):
        b = ((d >> i) ^ (d >> (i - 1))) & 1
        if not (q >> 8) & 1:
            b ^= 1
        out |= b << i
    return out

def ecc(bits):
    e = 0
    for b in bits:
        e = (e >> 1) ^ (0b10000011 if ((e ^ b) & 1) else 0)
    return e

def main():
    syms = []
    with open("sym.txt") as f:
        for line in f:
            if line.startswith("#"):
                continue
            a, b, c = line.split()
            syms.append((int(a), int(b), int(c)))
    audio_in = [tuple(int(x) for x in l.split()) for l in open("audio_in.txt")]

    # locate the first video period: 2 video guard chars then data
    i0 = None
    for i in range(len(syms) - 2):
        if all(syms[i][c] == VG[c] for c in range(3)) and all(syms[i + 1][c] == VG[c] for c in range(3)) \
           and syms[i + 2][0] not in CTRL:
            i0 = i + 2
            break
    if i0 is None:
        err("no video period found"); return 1
    # i0 is pixel 0 of an active line; find which line from the vsync phase later
    n = len(syms)
    state = "ctrl"
    ctrl_run = 0
    k = i0
    # walk lines starting at i0
    stats = dict(lines=0, video_lines=0, islands=0, packets=0)
    packets = []          # (header bytes, [sub bytes x4])
    hs_hist = []          # per line: list of hsync levels
    vs_track = []
    line_idx = 0
    while k + 858 <= n:
        line = syms[k:k + 858]
        stats["lines"] += 1
        # ---- classify the line
        pos = 0
        hsv = []
        vsv = []
        is_video = line[0][0] not in CTRL and not (line[0][1] in CTRL)
        if is_video:
            stats["video_lines"] += 1
            for x in range(720):
                for c in range(3):
                    if line[x][c] in CTRL:
                        err(f"line {line_idx} px {x}: control char in video period")
            pos = 720
        ctrl_run = 0
        x = pos
        while x < 858:
            s = line[x]
            if all(v in CTRL for v in s):
                c0 = CTRL[s[0]]; c1 = CTRL[s[1]]; c2 = CTRL[s[2]]
                hsv.append((x, c0 & 1)); vsv.append((x, (c0 >> 1) & 1))
                if c1 == 1 and c2 in (0, 1):
                    # preamble start: needs 8 identical characters
                    pre = line[x:x + 8]
                    if any(p != s for p in pre[:8] if all(v in CTRL for v in p) and CTRL[p[1]] == c1 and CTRL[p[2]] == c2) or \
                       not all(all(v in CTRL for v in p) and CTRL[p[1]] == c1 and CTRL[p[2]] == c2 for p in pre):
                        err(f"line {line_idx} x {x}: preamble shorter than 8")
                    if ctrl_run < 12 and x != 0:
                        err(f"line {line_idx} x {x}: only {ctrl_run} control chars before preamble")
                    for p in pre:
                        c0p = CTRL[p[0]]
                        hsv.append((x, c0p & 1)); vsv.append((x, (c0p >> 1) & 1)); x += 1
                    if c2 == 1:
                        # ---- data island
                        g = line[x:x + 2]
                        for gg in g:
                            if gg[1] != DG12 or gg[2] != DG12 or TERC4_INV.get(gg[0], -1) < 12:
                                err(f"line {line_idx} x {x}: bad leading guard band")
                            t = TERC4_INV.get(gg[0], 0)
                            hsv.append((x, t & 1)); vsv.append((x, (t >> 1) & 1)); x += 1
                        stats["islands"] += 1
                        first = True
                        while True:
                            if x + 32 > 858:
                                err(f"line {line_idx}: island runs past line end"); break
                            pk = line[x:x + 32]
                            if all(TERC4_INV.get(v, -1) >= 0 for p in pk for v in p) and pk[0][1] != DG12:
                                nib = [[TERC4_INV[p[c]] for c in range(3)] for p in pk]
                                for j, nb in enumerate(nib):
                                    b3 = (nb[0] >> 3) & 1
                                    if first and j == 0 and b3 != 0:
                                        err(f"line {line_idx} x {x}: ch0 bit3 must be 0 on first island char")
                                    if not (first and j == 0) and b3 != 1:
                                        err(f"line {line_idx} x {x + j}: ch0 bit3 must be 1")
                                    hsv.append((x + j, nb[0] & 1)); vsv.append((x + j, (nb[0] >> 1) & 1))
                                first = False
                                hdr_bits = [(nb[0] >> 2) & 1 for nb in nib]
                                sub_bits = [[0] * 64 for _ in range(4)]
                                for j, nb in enumerate(nib):
                                    for s_ in range(4):
                                        sub_bits[s_][2 * j] = (nb[1] >> s_) & 1
                                        sub_bits[s_][2 * j + 1] = (nb[2] >> s_) & 1
                                if ecc(hdr_bits[:24]) != sum(b << i for i, b in enumerate(hdr_bits[24:])):
                                    err(f"line {line_idx} x {x}: header ECC mismatch")
                                subs = []
                                for s_ in range(4):
                                    bb = sub_bits[s_]
                                    if ecc(bb[:56]) != sum(b << i for i, b in enumerate(bb[56:])):
                                        err(f"line {line_idx} x {x}: subpacket {s_} ECC mismatch")
                                    subs.append(bytes(sum(bb[8 * y + i] << i for i in range(8)) for y in range(7)))
                                hdr = bytes(sum(hdr_bits[8 * y + i] << i for i in range(8)) for y in range(3))
                                packets.append((line_idx, x, hdr, subs))
                                stats["packets"] += 1
                                x += 32
                            else:
                                break
                        g = line[x:x + 2]
                        for gg in g:
                            if gg[1] != DG12 or gg[2] != DG12 or TERC4_INV.get(gg[0], -1) < 12:
                                err(f"line {line_idx} x {x}: bad trailing guard band")
                            t = TERC4_INV.get(gg[0], 0)
                            hsv.append((x, t & 1)); vsv.append((x, (t >> 1) & 1)); x += 1
                        ctrl_run = 0
                        continue
                    else:
                        # video preamble: guard band must follow at x (= 856)
                        if x != 856:
                            err(f"line {line_idx}: video preamble ends at {x}, expected 856")
                        for gg in line[x:x + 2]:
                            if list(gg) != VG:
                                err(f"line {line_idx} x {x}: bad video guard band")
                        x += 2
                        continue
                ctrl_run += 1
                x += 1
            else:
                err(f"line {line_idx} x {x}: unexpected non-control character {s}")
                x += 1
        # ---- sync checks (hsync active low 736..797)
        for (xx, h) in hsv:
            exp = 0 if 736 <= xx < 798 else 1
            if h != exp:
                err(f"line {line_idx} x {xx}: hsync {h} expected {exp}"); break
        vs_track.append(vsv)
        # ---- video data check
        if is_video:
            vline = stats["video_lines"] - 1
        k += 858
        line_idx += 1

    # ---- vertical structure: find vsync lines
    vs_lines = []
    for li, vsv in enumerate(vs_track):
        lows = [xx for (xx, v) in vsv if v == 0]
        if lows:
            vs_lines.append((li, min(lows), max(lows)))
    # group into pulses and check alignment with hsync start (736)
    pulses = []
    for li, a, b in vs_lines:
        if pulses and li == pulses[-1][-1][0] + 1:
            pulses[-1].append((li, a, b))
        else:
            pulses.append([(li, a, b)])
    for p in pulses:
        if len(p) != 7:
            err(f"vsync pulse spans {len(p)} lines (expected 7 partial: 6 lines total)")
        if p[0][1] != 736 or p[-1][2] >= 736:
            err(f"vsync not aligned with hsync: starts at x {p[0][1]}, ends before {p[-1][2] + 1}")
    # active line count between pulses
    if len(pulses) >= 2:
        span = pulses[1][0][0] - pulses[0][0][0]
        if span != 525:
            err(f"frame period {span} lines, expected 525")
    # lines from the end of vsync to the first video line (back porch 30 + 1 line partial)
    # video data: compute expected using line numbering derived from vsync
    if pulses:
        first_vs_line = pulses[0][0][0]           # this is cy = 488
        # check pixel data on all video lines
        for li in range(line_idx):
            cy = (li - first_vs_line + 488) % 525
            line = syms[i0 + li * 858: i0 + li * 858 + 720]
            if cy < 480:
                for xx in range(720):
                    r, g, b = (tmds_decode(line[xx][2]), tmds_decode(line[xx][1]), tmds_decode(line[xx][0]))
                    exp = ((cy & 0xFF) ^ 0x5A, xx & 0xFF, ((xx >> 8) ^ (cy & 0xF)) & 0xFF)
                    if (r, g, b) != exp:
                        err(f"cy {cy} px {xx}: video {(r, g, b)} expected {exp}")
                        break
            elif line[0][0] not in CTRL:
                err(f"cy {cy}: video data on a blank line")

    # ---- packets
    kinds = {}
    samples = []
    fc_expect = None
    cs_l = {}; cs_r = {}
    for (li, x, hdr, subs) in packets:
        t = hdr[0]
        kinds[t] = kinds.get(t, 0) + 1
        if t == 0x82 or t == 0x84:
            ln = hdr[2]
            body = b"".join(subs)
            pb = [body[0]] + list(body[1:ln + 1])
            # InfoFrame bytes are 7 per subpacket: PB0..PB6, PB7..PB13 ...
            pbytes = []
            for s_ in subs:
                pbytes += list(s_)
            if (sum(hdr) + sum(pbytes[:ln + 1])) & 0xFF != 0:
                err(f"InfoFrame {t:02X}: checksum wrong")
            if t == 0x82 and (pbytes[4] & 0x7F) != 2:
                err("AVI: VIC is not 2")
        elif t == 0x01:
            for s_ in subs:
                cts = (s_[1] & 0xF) << 16 | s_[2] << 8 | s_[3]
                nn = (s_[4] & 0xF) << 16 | s_[5] << 8 | s_[6]
                if (cts, nn) != (27000, 6144):
                    err(f"ACR: CTS {cts} N {nn}")
        elif t == 0x02:
            sp = hdr[1] & 0xF
            if hdr[1] & 0x10:
                err("audio: layout 1")
            bflags = hdr[2] >> 4
            for s_ in range(4):
                if not (sp >> s_) & 1:
                    continue
                d = subs[s_]
                l = d[0] | d[1] << 8 | d[2] << 16
                r = d[3] | d[4] << 8 | d[5] << 16
                st = d[6]
                vl, ul, cl, pl = st & 1, (st >> 1) & 1, (st >> 2) & 1, (st >> 3) & 1
                vr, ur, cr, pr = (st >> 4) & 1, (st >> 5) & 1, (st >> 6) & 1, (st >> 7) & 1
                if (bin(l).count("1") + vl + ul + cl + pl) & 1:
                    err("audio: left parity")
                if (bin(r).count("1") + vr + ur + cr + pr) & 1:
                    err("audio: right parity")
                if vl or vr:
                    err("audio: sample marked invalid")
                idx = len(samples)
                b = (bflags >> s_) & 1
                if b:
                    fc_expect = 0
                if fc_expect is not None:
                    cs_l[fc_expect] = cl; cs_r[fc_expect] = cr
                    fc_expect = (fc_expect + 1) % 192
                samples.append((l >> 8, r >> 8))
    print("packet types:", {f"{k:02X}": v for k, v in sorted(kinds.items())})
    # audio values must be the input sequence (possibly not yet complete)
    if not samples:
        err("no audio samples")
    else:
        start = audio_in.index(samples[0]) if samples[0] in audio_in else -1
        if start < 0:
            err("first audio sample not in input")
        else:
            got = samples
            exp = audio_in[start:start + len(got)]
            if got != exp:
                bad = next(i for i in range(len(got)) if got[i] != exp[i])
                err(f"audio sample {bad}: {got[bad]} expected {exp[bad]}")
        print(f"audio: {len(samples)} samples received, {len(audio_in)} produced")
    # channel status: bits 2, 25, 33 and channel number 20 (L) / 21 (R)
    for f in range(192):
        el = int(f in (2, 25, 33, 20)); er = int(f in (2, 25, 33, 21))
        if f in cs_l and (cs_l[f] != el or cs_r[f] != er):
            err(f"channel status bit {f}: L {cs_l[f]} R {cs_r[f]}, expected {el} {er}")
    if len(cs_l) < 192:
        err(f"channel status: only {len(cs_l)} of 192 frames seen")
    print("stats:", stats, "frames with vsync:", len(pulses))
    if errors:
        print(f"FAILED: {len(errors)} errors")
        return 1
    print("PASSED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
