#!/usr/bin/env python3
"""Runs zxplc_mkdemo.sna (the demo project builder) headless and saves the
built project memory to src/demo_proj.bin (put into the DEMO bank by the
normal build)."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from zxrun import Spectrum

PROJ, P_LEN, TEST_RES = 0x9000, 8, 0x5B00

def main():
    sna = sys.argv[1] if len(sys.argv) > 1 else "zxplc_mkdemo.sna"
    out = sys.argv[2] if len(sys.argv) > 2 else "src/demo_proj.bin"
    z = Spectrum(sna)
    mem = z.m.memory
    for _ in range(100):                # wait for the end marker (max. 2000 frames)
        z.run(20)
        if mem[TEST_RES + 2]:
            break
    if mem[TEST_RES + 2] != 0xA5:
        sys.exit("demo build failed (marker %02X, step %d)" % (mem[TEST_RES + 2], mem[TEST_RES + 3]))
    n = mem[PROJ + P_LEN] | (mem[PROJ + P_LEN + 1] << 8)
    open(out, "wb").write(bytes(mem[PROJ:PROJ + n]))
    print("demo project: %d bytes -> %s" % (n, out))

main()
