#!/usr/bin/env python3
"""Trace until PC leaves RAM code; print last PCs with symbols."""
import sys, re
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from zxrun import Spectrum
sna, sym = sys.argv[1], sys.argv[2]
syms = []
for l in open(sym):
    m = re.match(r"(\S+):\s+EQU\s+0x([0-9A-F]+)", l)
    if m: syms.append((int(m.group(2), 16), m.group(1)))
syms.sort()
def name(a):
    best = None
    for v, n in syms:
        if v <= a and v >= 0x6000: best = (v, n)
    return "%04X %s+%d" % (a, best[1], a - best[0]) if best else "%04X" % a
z = Spectrum(sna); m = z.m
hist = []
t = 0
while True:
    m.ticks_to_stop = 1; m.run(); t += 1
    hist.append((m.pc, m.sp))
    if m.pc < 0x4000 and m.pc != 0x38: break
    if len(sys.argv) > 3 and m.sp > int(sys.argv[3], 16): break
    if m.pc >= 0xC000 and m.pc < 0xFDFD: break
    if t > 20000000: break
for pc, sp in hist[-30:]: print(name(pc), "SP=%04X" % sp)
