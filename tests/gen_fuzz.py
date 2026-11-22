#!/usr/bin/env python3
"""
Random AVR instruction-stream generator for UzeTang lock-step testing.

Generates an ATmega644 assembly program that exercises (almost) every
instruction in random combinations, with Timer1 interrupts firing at a
random rate, so that interrupt entry is tested at every possible point.
Assemble with avr-gcc and run in sim/obj_dir/Vavr_soc against CUzeBox.
"""
import random, sys

def gen(seed, nblk=400):
    R = random.Random(seed)
    out = []
    L = out.append
    lab = [0]
    def newlab():
        lab[0] += 1
        return "L%d" % lab[0]

    GEN  = list(range(0, 26))          # general registers (pointers excluded)
    HI   = list(range(16, 26))         # immediate-capable
    MULR = list(range(16, 24))         # mulsu/fmul operands
    IOS  = [0x1E, 0x07, 0x08, 0x16, 0x06, 0x03, 0x09]  # GPIOR0, DDRC, PORTC, TIFR1, PINC, PINB, PIND
    INR  = [0x1E, 0x16, 0x3F, 0x3D, 0x3E, 0x2A, 0x2B, 0x08, 0x07, 0x2D, 0x2E, 0x06, 0x09, 0x03]
    OUTR = [0x1E, 0x2A, 0x2B, 0x08, 0x07, 0x3F, 0x06, 0x2E, 0x2D, 0x2C, 0x09]
    LDSA = [0x3E, 0x4A, 0x4B, 0x84, 0x85, 0x36, 0x88, 0x89, 0x8A, 0x8B, 0x5F, 0x6F,
            0xC0, 0xC1, 0xC2, 0xC6, 0x4D, 0x4E]
    STSA = [0x3E, 0x4A, 0x4B, 0x8A, 0x8B, 0x28, 0x27, 0x89, 0x88, 0x85, 0x84, 0x6F,
            0xC0, 0xC1, 0xC2, 0xC4, 0xC5, 0xC6, 0xC6, 0x4C, 0x4E, 0x26, 0x29]

    def r(): return R.choice(GEN)
    def h(): return R.choice(HI)
    def k8(): return R.randrange(256)

    L(".section .text")
    L(".global main")
    L("vectors:")
    L("  jmp start")
    for i in range(1, 31):
        L("  jmp isr")
    L("start:")
    L("  ldi r16, 0x10\n  out 0x3E, r16\n  ldi r16, 0xFF\n  out 0x3D, r16")
    # Timer1: CTC, clk/1, random period, random interrupt enables
    ocra = R.choice([R.randrange(40, 120), R.randrange(120, 600), R.randrange(600, 3000)])
    ocrb = R.randrange(0, ocra + 50)
    timsk = R.choice([0x02, 0x06, 0x07, 0x03, 0x02])
    L("  ldi r16, %d\n  sts 0x89, r16\n  ldi r16, %d\n  sts 0x88, r16" % (ocra >> 8, ocra & 0xFF))
    L("  ldi r16, %d\n  sts 0x8B, r16\n  ldi r16, %d\n  sts 0x8A, r16" % (ocrb >> 8, ocrb & 0xFF))
    L("  ldi r16, 0x09\n  sts 0x81, r16")
    L("  ldi r16, %d\n  sts 0x6F, r16" % timsk)
    L("  ldi r16, 0xFF\n  out 0x07, r16")     # DDRC = 0xFF
    L("  ldi r16, 0x0C\n  out 0x01, r16\n  out 0x02, r1")   # DDRA/PORTA init (PINA latched in emulators)
    # USART transmitter with TX complete interrupt, SPI master with interrupt
    if R.random() < 0.7:
        L("  ldi r16, %d\n  sts 0xC4, r16\n  ldi r16, %d\n  sts 0xC2, r16" % (R.randrange(0, 12), R.choice([6, 6, 0x0E, 0x26, 0x02])))
        L("  ldi r16, %d\n  sts 0xC1, r16" % R.choice([0x48, 0x48, 0x08, 0x4C]))
    if R.random() < 0.7:
        L("  ldi r16, %d\n  out 0x2C, r16\n  ldi r16, %d\n  out 0x2D, r16" % (R.choice([0xD0, 0xD1, 0xD2, 0xD3, 0x50]), R.randrange(2)))
    for i in range(26):
        L("  ldi r16, %d\n  mov r%d, r16" % (k8(), i) if i < 16 else "  ldi r%d, %d" % (i, k8()))
    L("  sei")
    L("mainloop:")
    L("  ldi r26, lo8(0x0400)\n  ldi r27, hi8(0x0400)")
    L("  ldi r28, lo8(0x0800)\n  ldi r29, hi8(0x0800)")
    L("  ldi r30, lo8(0x0C00)\n  ldi r31, hi8(0x0C00)")
    L("  ldi r16, 0xFF\n  out 0x3D, r16\n  ldi r16, 0x10\n  out 0x3E, r16")

    def one(allow2=True):
        """Return a list of asm lines for one random instruction (or tiny sequence)."""
        c = R.randrange(100)
        if c < 18:
            op = R.choice(["add","adc","sub","sbc","and","or","eor","mov","cp","cpc"])
            return ["  %s r%d, r%d" % (op, r(), r())]
        if c < 28:
            op = R.choice(["subi","sbci","andi","ori","cpi","ldi"])
            return ["  %s r%d, %d" % (op, h(), k8())]
        if c < 36:
            op = R.choice(["com","neg","swap","inc","dec","asr","lsr","ror"])
            return ["  %s r%d" % (op, r())]
        if c < 40:
            op = R.choice(["mul","muls","mulsu","fmul","fmuls","fmulsu","movw"])
            if op == "mul":   return ["  mul r%d, r%d" % (r(), r())]
            if op == "muls":  return ["  muls r%d, r%d" % (h(), h())]
            if op == "movw":  return ["  movw r%d, r%d" % (R.randrange(0, 13) * 2, R.randrange(0, 13) * 2)]
            return ["  %s r%d, r%d" % (op, R.choice(MULR), R.choice(MULR))]
        if c < 44:
            op = R.choice(["bst","bld"])
            return ["  %s r%d, %d" % (op, r(), R.randrange(8))]
        if c < 47:
            b = R.randrange(8)
            if R.random() < 0.5: return ["  bset %d" % b]
            return ["  bclr %d" % b]
        if c < 52:   # forward conditional branch
            return ["BR"]
        if c < 56:   # skip instruction followed by a (possibly 2-word) instruction
            op = R.choice(["cpse","sbrc","sbrs","sbic","sbis"])
            if op == "cpse": s = "  cpse r%d, r%d" % (r(), r())
            elif op in ("sbrc","sbrs"): s = "  %s r%d, %d" % (op, r(), R.randrange(8))
            else: s = "  %s 0x%02X, %d" % (op, R.choice(IOS), R.randrange(8))
            nxt = R.choice(["  lds r%d, 0x%04X" % (r(), R.randrange(0x100, 0x1000)),
                            "  sts 0x%04X, r%d" % (R.randrange(0x100, 0x1000), r()),
                            "  inc r%d" % r(), "  nop", "  ldi r%d, %d" % (h(), k8())])
            return [s, nxt]
        if c < 64:   # loads / stores via pointer
            op = R.choice(["ld","st","ldd","std"])
            if op in ("ld","st"):
                p = R.choice(["X","X+","-X","Y+","-Y","Z+","-Z","X"])
                return ["  ld r%d, %s" % (r(), p)] if op == "ld" else ["  st %s, r%d" % (p, r())]
            pq = "%s+%d" % (R.choice("YZ"), R.randrange(64))
            return ["  ldd r%d, %s" % (r(), pq)] if op == "ldd" else ["  std %s, r%d" % (pq, r())]
        if c < 69:
            if R.random() < 0.5:
                a = R.choice(LDSA) if R.random() < 0.5 else R.randrange(0x100, 0x1000)
                return ["  lds r%d, 0x%04X" % (r(), a)]
            a = R.choice(STSA) if R.random() < 0.3 else R.randrange(0x100, 0x1000)
            return ["  sts 0x%04X, r%d" % (a, r())]
        if c < 73:
            if R.random() < 0.5: return ["  in r%d, 0x%02X" % (r(), R.choice(INR))]
            a = R.choice(OUTR)
            return ["  out 0x%02X, r%d" % (a, r())]
        if c < 76:
            return ["  %s 0x%02X, %d" % (R.choice(["sbi","cbi"]), R.choice(IOS), R.randrange(8))]
        if c < 79:
            return ["  push r%d" % r(), "  pop r%d" % r()] if R.random() < 0.5 else ["  push r%d" % r()]
        if c < 81:
            return ["  pop r%d" % r()]
        if c < 85:
            return ["  %s r24, %d" % (R.choice(["adiw","sbiw"]), R.randrange(64))]
        if c < 88:
            op = R.choice(["rcall","call","icall"])
            sub = "sub%d" % R.randrange(4)
            if op == "icall":
                return ["  push r30", "  push r31", "  ldi r30, pm_lo8(%s)" % sub,
                        "  ldi r31, pm_hi8(%s)" % sub, "  icall", "  pop r31", "  pop r30"]
            return ["  %s %s" % (op, sub)]
        if c < 91:
            q = R.randrange(64)
            return ["  push r30", "  push r31", "  ldi r30, lo8(tbl+%d)" % q,
                    "  ldi r31, hi8(tbl+%d)" % q,
                    R.choice(["  lpm r%d, Z" % r(), "  lpm r%d, Z+" % r(), "  lpm"]),
                    "  pop r31", "  pop r30"]
        if c < 93:
            return ["RJ"]
        if c < 94:
            return ["JM"]
        if c < 95:
            return [R.choice(["  wdr", "  sts 0xC6, r%d" % r(), "  out 0x2E, r%d" % r(),
                              "  in r%d, 0x2D" % r(), "  in r%d, 0x2E" % r()])]
        if c < 96:
            return ["IJ"]
        return ["  nop"]

    # Body: a list of instruction groups, each labelled so branches can jump forward
    body = []
    for _ in range(nblk):
        body.append(one())
    labels = [newlab() for _ in range(len(body) + 1)]
    for i, grp in enumerate(body):
        L("%s:" % labels[i])
        tgt = labels[min(len(body), i + 1 + R.randrange(4))]
        for ins in grp:
            if ins == "BR":
                op = R.choice(["brbs","brbc"])
                L("  %s %d, %s" % (op, R.randrange(8), tgt))
            elif ins == "RJ":
                L("  rjmp %s" % tgt)
            elif ins == "JM":
                L("  jmp %s" % tgt)
            elif ins == "IJ":
                L("  push r30\n  push r31\n  ldi r30, pm_lo8(%s_ij)\n  ldi r31, pm_hi8(%s_ij)\n  ijmp" % (labels[i], labels[i]))
                L("%s_ij:\n  pop r31\n  pop r30" % labels[i])
            else:
                L(ins)
    L("%s:" % labels[-1])
    L("  jmp mainloop")

    # subroutines
    for sidx in range(4):
        L("sub%d:" % sidx)
        for _ in range(R.randrange(1, 6)):
            g = one()
            if any(x in ("BR","RJ","JM","IJ") or "call" in x or "push" in x or "pop" in x for x in g):
                continue
            for x in g: L(x)
        L("  ret")

    # interrupt service routine
    L("isr:")
    L("  push r16\n  in r16, 0x3F\n  push r16\n  push r17")
    for _ in range(R.randrange(0, 8)):
        op = R.choice(["inc r17","lds r16, 0x84","lds r17, 0x85","in r16, 0x16","sts 0x0F00, r16",
                       "lds r16, 0x0F01","add r16, r17","nop","sbi 0x1E, 3","in r17, 0x1E"])
        L("  " + op)
    L("  pop r17\n  pop r16\n  out 0x3F, r16\n  pop r16\n  reti")

    L("tbl:")
    L("  .byte " + ",".join(str(R.randrange(256)) for _ in range(80)))
    return "\n".join(out) + "\n"

if __name__ == "__main__":
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    nblk = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    sys.stdout.write(gen(seed, nblk))
