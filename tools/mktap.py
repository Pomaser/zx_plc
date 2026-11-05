#!/usr/bin/env python3
"""zxplc.sna -> zxplc.tap for a real ZX Spectrum 128K (or any emulator).

    python3 tools/mktap.py zxplc.sna zxplc.sym zxplc.tap

The tape holds:
  1. a BASIC loader:  10 CLEAR VAL "24063": LOAD ""CODE : RANDOMIZE USR VAL "20480"
  2. a machine code loader (CODE at 20480, in the screen memory)
  3. headerless data blocks, loaded by the ROM routine LD-BYTES: one for every
     paged bank that holds code or data (the banks are cleared first and get
     the IM2 vector table + "JP isr" at 0xFDFD), then the fixed part from
     0x5E00 (the rest up to 0xBFFF is cleared).
The machine code loader then jumps to START. A failed block (or BREAK) turns
the border red.
"""
import os
import re
import subprocess
import sys
import tempfile

LOADER_ORG = 0x5000
FIXED = 0x5E00
IM2_AREA = 0x3DFD                       # bank offset of the IM2 stub (0xFDFD)


def read_sna(path):
    d = open(path, "rb").read()
    if len(d) < 49179 + 4:
        sys.exit("not a 128K snapshot")
    mem = d[27:27 + 49152]
    ext = 27 + 49152
    port = d[ext + 2]
    paged = port & 7
    banks = {5: mem[0:0x4000], 2: mem[0x4000:0x8000], paged: mem[0x8000:0xC000]}
    i = ext + 4
    for b in range(8):
        if b in banks:
            continue
        banks[b] = d[i:i + 0x4000]
        i += 0x4000
    return banks, paged


def symbols(path):
    sy = {}
    for line in open(path):
        m = re.match(r"(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
        if m:
            sy[m.group(1)] = int(m.group(2), 16)
    return sy


def used(data, end):
    """length of data[0:end] without the trailing zeros"""
    n = end
    while n > 0 and data[n - 1] == 0:
        n -= 1
    return n


def block(flag, data):
    body = bytes([flag]) + bytes(data)
    x = 0
    for c in body:
        x ^= c
    body += bytes([x])
    return len(body).to_bytes(2, "little") + body


def header(typ, name, length, p1, p2):
    h = bytes([typ]) + name.ljust(10)[:10].encode() + length.to_bytes(2, "little") \
        + p1.to_bytes(2, "little") + p2.to_bytes(2, "little")
    return block(0, h)


def basic_loader():
    q = b'"'
    line = (b"\xfd\xb0" + q + b"24063" + q + b":\xef" + q + q + b"\xaf:\xf9\xc0\xb0"
            + q + str(LOADER_ORG).encode() + q + b"\r")
    return (10).to_bytes(2, "big") + len(line).to_bytes(2, "little") + line


def mc_loader(table, fixed_len, start, isr, start_bank):
    src = """
        DEVICE NONE
        ORG {org}
        OUTPUT "{out}"
loader: di
        ld sp,{fixed}-2         ; stack below the program
        ld hl,table
next:   ld a,(hl)
        cp 0xFF
        jr z,fixed
        inc hl
        or 0x10                 ; (48K ROM for LD-BYTES)
        ld bc,0x7FFD
        out (c),a
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        push de
        ld hl,0xC000            ; bank cleared
        ld de,0xC001
        ld bc,0x3FFF
        ld (hl),0
        ldir
        pop de
        ld a,d
        or e
        jr z,im2
        ld ix,0xC000
        ld a,0xFF
        scf
        call 0x0556
        jr nc,fail
im2:    ld hl,0xFE00            ; IM2 vector table + JP isr
        ld de,0xFE01
        ld bc,256
        ld (hl),0xFD
        ldir
        ld a,0xC3
        ld (0xFDFD),a
        ld hl,{isr}
        ld (0xFDFE),hl
        pop hl
        jr next
fixed:  ld a,0x10|{sbank}
        ld bc,0x7FFD
        out (c),a
        ld hl,{fixed}           ; fixed memory cleared up to 0xBFFF
        ld de,{fixed}+1
        ld bc,0xBFFF-{fixed}
        ld (hl),0
        ldir
        ld ix,{fixed}
        ld de,{flen}
        ld a,0xFF
        scf
        call 0x0556
        jr nc,fail
        jp {start}
fail:   ld a,2
        out (0xFE),a
        jr fail
table:
{table}
        db 0xFF
""".format(org=LOADER_ORG, fixed=FIXED, isr=isr, sbank=start_bank, flen=fixed_len,
           start=start, table="\n".join("        db %d\n        dw %d" % t for t in table),
           out="{out}")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "loader.bin")
        asm = os.path.join(tmp, "loader.asm")
        open(asm, "w").write(src.replace("{out}", out))
        r = subprocess.run(["sjasmplus", "--nologo", asm], capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        return open(out, "rb").read()


def main():
    sna, sym, out = sys.argv[1:4]
    banks, paged = read_sna(sna)
    sy = symbols(sym)
    start, isr = sy["START"], sy["isr"]
    fixed_mem = banks[5] + banks[2]                         # 0x4000-0xBFFF
    flen = used(fixed_mem, 0x8000) - (FIXED - 0x4000)
    fixed_data = fixed_mem[FIXED - 0x4000:FIXED - 0x4000 + flen]
    table, data = [], []
    for b in (0, 1, 3, 4, 6, 7):
        n = used(banks[b], IM2_AREA)
        table.append((b, n))
        if n:
            data.append(banks[b][:n])
    loader = mc_loader(table, flen, start, isr, paged)
    prog = basic_loader()
    tap = header(0, "ZX-PLC", len(prog), 10, len(prog)) + block(0xFF, prog)
    tap += header(3, "loader", len(loader), LOADER_ORG, 32768) + block(0xFF, loader)
    for d in data:
        tap += block(0xFF, d)
    tap += block(0xFF, fixed_data)
    open(out, "wb").write(tap)
    total = sum(len(d) for d in data) + flen
    print("%s: %d bytes (banks %s, fixed %d bytes)" % (out, len(tap),
          ", ".join("%d:%d" % t for t in table), flen))


if __name__ == "__main__":
    main()
