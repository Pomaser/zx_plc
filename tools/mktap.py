#!/usr/bin/env python3
"""zxplc.sna -> zxplc.tap for a real ZX Spectrum 128K (or any emulator).

    python3 tools/mktap.py zxplc.sna zxplc.sym zxplc.tap [screen.scr]

The tape holds:
  1. a BASIC loader:  10 CLEAR VAL "24063": LOAD ""SCREEN$ : POKE VAL "23739",VAL "111":
                         LOAD ""CODE : RANDOMIZE USR VAL "24064"
     (without a loading screen the SCREEN$ and POKE parts are left out; the POKE
     stops the ROM from printing "Bytes: loader" over the picture)
  2. the loading screen (SCREEN$, 6912 bytes), if given
  3. a machine code loader (CODE at 24064 = 0x5E00, above RAMTOP). With interrupts
     off it copies itself over the BASIC line (PROG = 0x5CCB, BASIC is not needed
     any more), below its stack at 0x5DFE, out of the way of the screen and of the
     data it loads, and runs there. The system variables below stay intact for
     LD-BYTES and the ROM interrupt. (Not the printer buffer: LD-BYTES ends with EI
     and the 128K ROM 1 interrupt uses 0x5B88+ for the keypad.)
  4. headerless data blocks, loaded by the ROM routine LD-BYTES: one for every
     paged bank that holds code or data (the banks are cleared first and get
     the IM2 vector table + "JP isr" at 0xFDFD), then the fixed part from
     0x5E00 (the rest up to 0xBFFF is cleared).
With a loading screen the loader then fills the pixels of "STOP" in the picture
(row 11, columns 2-4) with noise for 2 s, with AY noise on channel A, then
copies the pixels of the hidden "RUN" label (white on white, character row 0,
columns 29-31) there (the attributes stay), so the PLC in the picture switches
to RUN, and waits for a key. Then it jumps to START. A failed block
(or BREAK) turns the border red.
"""
import os
import re
import subprocess
import sys
import tempfile

LOADER_ORG = 0x5E00                     # where LOAD ""CODE puts the loader
LOADER_RUN = 0x5CCB                     # where it runs (PROG, over the BASIC line)
FIXED = 0x5E00
IM2_AREA = 0x3DFD                       # bank offset of the IM2 stub (0xFDFD)
RUN_SRC = 0x4000 + 29                   # "RUN" label: row 0, columns 29-31
RUN_DST = 0x4800 + (11 - 8) * 32 + 2    # over "STOP": row 11, columns 2-4
RUN_W = 3
NOISE_FRAMES = 100                      # 2 s of noise before RUN appears


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


def basic_loader(screen):
    """the BASIC line (at PROG = 0x5CCB; the loader later runs over it)"""
    q = b'"'
    line = b"\xfd\xb0" + q + b"24063" + q + b":"                      # CLEAR VAL "24063":
    if screen:
        line += (b"\xef" + q + q + b"\xaa:"                            # LOAD ""SCREEN$ :
                 + b"\xf4\xb0" + q + b"23739" + q + b",\xb0" + q + b"111" + q + b":")
    line += (b"\xef" + q + q + b"\xaf:\xf9\xc0\xb0"                    # LOAD ""CODE : RANDOMIZE USR
             + q + str(LOADER_ORG).encode() + q + b"\r")
    return (10).to_bytes(2, "big") + len(line).to_bytes(2, "little") + line


def mc_loader(table, fixed_len, start, isr, start_bank, screen):
    src = """
        DEVICE NONE
        ORG {org}
        OUTPUT "{out}"
        di                      ; copy the rest to {run} and run it there
        ld hl,body
        ld de,{run}
        ld bc,end-loader
        ldir
        jp loader
body:
        DISP {run}
loader:
        ld sp,{fixed}-2         ; stack below the program
        ld hl,table
next:   ld a,(hl)
        cp 0xFF
        jp z,fixed
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
        jp nc,fail
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
        jp nc,fail
        IF {screen}
        ld de,0x08 * 256 + 15   ; AY: noise on channel A, full volume
        call ay
        ld de,0x07 * 256 + 0xF7
        call ay
        ld b,{nframes}          ; noise in the pixels of the STOP cells
noise:  ei                      ; (the ROM interrupt counts the frames)
        halt
        push bc
        ld a,r                  ; a new noise period every frame
        and 0x1F
        ld e,a
        ld d,6
        call ay
        ld de,{rdst}
        ld c,8
nline:  push de
        ld b,{rw}
ncell:  res 7,h                 ; random bytes: ROM contents xor R
        res 6,h
        ld a,r
        xor (hl)
        inc hl
        ld (de),a
        inc e
        djnz ncell
        pop de
        inc d
        dec c
        jr nz,nline
        pop bc
        djnz noise
        di
        ld de,0x08 * 256 + 0    ; AY silent
        call ay
        ld de,0x07 * 256 + 0xFF
        call ay
        ld hl,{rsrc}            ; "RUN" over "STOP", pixels only
        ld de,{rdst}
        ld a,8
pix:    push hl
        push de
        ld bc,{rw}
        ldir
        pop de
        pop hl
        inc h
        inc d
        dec a
        jr nz,pix
release:xor a                   ; wait until no key is held ...
        in a,(0xFE)
        cpl
        and 0x1F
        jr nz,release
press:  xor a                   ; ... then for a key press
        in a,(0xFE)
        cpl
        and 0x1F
        jr z,press
        jp {start}
ay:     ld bc,0xFFFD            ; AY register D = E
        out (c),d
        ld b,0xBF
        out (c),e
        ret
        ENDIF
        jp {start}
fail:   ld a,2
        out (0xFE),a
        jr fail
table:
{table}
        db 0xFF
end:
        ENT
""".format(org=LOADER_ORG, run=LOADER_RUN, screen=1 if screen else 0,
           rsrc=RUN_SRC, rdst=RUN_DST, rw=RUN_W, nframes=NOISE_FRAMES, fixed=FIXED, isr=isr, sbank=start_bank, flen=fixed_len,
           start=start, table="\n".join("        db %d\n        dw %d" % t for t in table),
           out="{out}")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "loader.bin")
        asm = os.path.join(tmp, "loader.asm")
        open(asm, "w").write(src.replace("{out}", out))
        r = subprocess.run(["sjasmplus", "--nologo", asm], capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        code = open(out, "rb").read()
    if LOADER_RUN + len(code) - 15 > FIXED - 0x20:         # 15: the copy stub
        sys.exit("loader too long for the area below its stack (%d bytes)" % len(code))
    return code


def main():
    sna, sym, out = sys.argv[1:4]
    screen = open(sys.argv[4], "rb").read() if len(sys.argv) > 4 else None
    if screen is not None and len(screen) != 6912:
        sys.exit("the loading screen must have 6912 bytes")
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
    loader = mc_loader(table, flen, start, isr, paged, screen is not None)
    prog = basic_loader(screen)
    tap = header(0, "ZX-PLC", len(prog), 10, len(prog)) + block(0xFF, prog)
    if screen:
        tap += header(3, "screen", 6912, 0x4000, 32768) + block(0xFF, screen)
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
