#!/usr/bin/env python3
"""zxplc.sna -> zxplc.tap for a real ZX Spectrum 128K (or any emulator).

    python3 tools/mktap.py zxplc.sna zxplc.sym zxplc.tap [screen.scr]

The tape holds:
  1. a BASIC loader:  10 CLEAR VAL "24063": LOAD ""CODE : RANDOMIZE USR VAL "24064"
  2. a machine code loader (CODE at 24064 = 0x5E00, above RAMTOP). With interrupts
     off it copies itself over the BASIC line (PROG = 0x5CCB, BASIC is not needed
     any more), below its stack at 0x5DFE, out of the way of the screen and of the
     data it loads, and runs there. The system variables below stay intact for
     LD-BYTES and the ROM interrupt. (Not the printer buffer: LD-BYTES ends with EI
     and the 128K ROM 1 interrupt uses 0x5B88+ for the keypad.)
  3. headerless data blocks, all packed with ZX0 (tools/zx0): the loading screen
     (if given), one block for every paged bank that holds code or data (the
     banks are cleared first and get the IM2 vector table + "JP isr" at 0xFDFD),
     then the fixed part from 0x5E00 (the rest up to 0xBFFF is cleared).
     LD-BYTES loads each block at the top of the fixed memory (0xC000 - packed
     length), then dzx0_standard unpacks it to its place; the fixed block's
     buffer is cleared afterwards. Unpacking runs into the next block's pilot
     tone, which is long enough for that.
With a loading screen the fixed block also carries the effect code right after
the program (that memory is zero in the snapshot); the loader calls it, then
clears it again. The effect fills the pixels of "STOP" in the picture (row 11,
columns 2-4, plus the empty blue cells 1 and 5) with noise for 2 s, with AY
noise on channel A, then copies the pixels of the hidden "RUN" label (white on
white, character row 0, columns 29-31) there and clears cells 1 and 5 again
(the attributes stay), so the PLC in the picture switches to RUN, and writes
MESSAGE bottom left in the app font (tools/font6.txt). While it
waits for a key, the BRIGHT bit of the green LED cells (row 9, columns 18-23
and 26-31) toggles at random times (100-720 ms, each cell on its own). When
the key is pressed and released again, the loader jumps to START.
A failed block (or BREAK) turns the border red.
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
BUF_END = 0xC000                        # packed blocks are loaded just below this
HERE = os.path.dirname(os.path.abspath(__file__))
RUN_SRC = 0x4000 + 29                   # "RUN" label: row 0, columns 29-31
RUN_DST = 0x4800 + (11 - 8) * 32 + 2    # over "STOP": row 11, columns 2-4
RUN_W = 3
NOISE_FRAMES = 100                      # 2 s of noise before RUN appears
LED_ATTR = 0x5800 + 9 * 32 + 18         # green LEDs: row 9, columns 18-23 and 26-31
MESSAGE = [(22, 2, "Press any key to start"),   # (row, x px, text) in the app font,
           (23, 2, "ZX PLC Editor")]           # in the free area left of the wires


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
    """the BASIC line (at PROG = 0x5CCB; the loader later runs over it)"""
    q = b'"'
    line = b"\xfd\xb0" + q + b"24063" + q + b":"                      # CLEAR VAL "24063":
    line += (b"\xef" + q + q + b"\xaf:\xf9\xc0\xb0"                    # LOAD ""CODE : RANDOMIZE USR
             + q + str(LOADER_ORG).encode() + q + b"\r")
    return (10).to_bytes(2, "big") + len(line).to_bytes(2, "little") + line


def zx0(data):
    """data packed by tools/zx0/zx0 (ZX0 forward format, for dzx0_standard)"""
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, "in.bin"), os.path.join(tmp, "out.zx0")
        open(src, "wb").write(data)
        r = subprocess.run([os.path.join(HERE, "zx0", "zx0"), "-f", src, dst],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit("zx0: " + r.stdout + r.stderr)
        return open(dst, "rb").read()


def font6():
    """the glyphs of tools/font6.txt (the app font): char -> rows of '#'/'.'"""
    glyphs, cur = {}, None
    for line in open(os.path.join(HERE, "font6.txt")):
        line = line.rstrip("\n")
        if not line or line.startswith("#") and not set(line) <= set("#."):
            continue
        if line.startswith(": "):
            cur = {"SP": " "}.get(line[2:], line[2:])
            glyphs[cur] = []
        else:
            glyphs[cur].append(line)
    return glyphs


def message_data():
    """MESSAGE rendered for the loader: per text line [screen address][cells]
    and 8 pixel lines of that many bytes, then a 0 word"""
    glyphs = font6()
    out = []
    for row, x, text in MESSAGE:
        px = [[0] * 256 for _ in range(8)]
        for ch in text:
            g = glyphs[ch]
            for y, r in enumerate(g):               # glyph line 0 is blank
                for i, c in enumerate(r):
                    if c == "#":
                        px[y + 1][x + i] = 1
            x += len(g[0]) + 1
        cells = (x + 7) // 8
        if cells > 32:
            sys.exit("message line too long: " + text)
        addr = 0x4000 | ((row & 0x18) << 8) | ((row & 7) << 5)
        out += ["        dw 0x%04X" % addr, "        db %d" % cells]
        for line in px:
            out.append("        db " + ",".join(
                str(int("".join(map(str, line[c * 8:c * 8 + 8])), 2)) for c in range(cells)))
    out.append("        dw 0")
    return "\n".join(out)


def mc_loader(table, fixed_len, fixed_plen, screen_plen, start, isr, start_bank, screen):
    """the loader and the effect code; the lengths are the packed ones (the
    fixed block's packed length is only known after a first pass with 0)"""
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
        IF {screen}
        ld hl,0x4000            ; the loading screen
        ld de,{splen}
        call ldpack
        ENDIF
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
        ld hl,0xC000
        call nz,ldpack
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
        ld hl,{fixed}
        ld de,{fplen}
        call ldpack
        ld hl,{bufend}-{fplen}  ; its buffer cleared again
        ld de,{bufend}-{fplen}+1
        ld bc,{fplen}-1
        ld (hl),0
        ldir
        IF {screen}
        call effect             ; picture effect, waits for a key
        di
        ld hl,effect            ; its code cleared again (the memory after
        ld de,effect+1          ; the program is all zero in the snapshot)
        ld bc,effect_end-effect-1
        ld (hl),0
        ldir
        ENDIF
        jp {start}
fail:   ld a,2
        out (0xFE),a
        jr fail
; LD-BYTES loads DE packed bytes just below {bufend}, then they are unpacked to HL
ldpack: push hl
        ld hl,{bufend}
        or a
        sbc hl,de
        push hl
        push hl
        pop ix
        ld a,0xFF
        scf
        call 0x0556
        jp nc,fail
        pop hl
        pop de
        INCLUDE "{dzx0}"        ; (ends with ret)
table:
{table}
        db 0xFF
end:
        ENT

; The effect after the load is appended to the fixed block: it is loaded
; right after the program, run once, then cleared.
        OUTPUT "{eout}"
        ORG {fixed}+{flen}
effect:
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
        ld de,{rdst}-1          ; one more cell on both sides
        ld c,8
nline:  push de
        ld b,{rw}+2
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
        ex de,hl                ; the empty cells on both sides cleared
        dec l
        ld (hl),0
        inc l
        ex de,hl
        ld bc,{rw}
        ldir
        ex de,hl
        ld (hl),b
        pop de
        pop hl
        inc h
        inc d
        dec a
        jr nz,pix
        ld hl,message           ; "Press any key..." bottom left
mline:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or a
        jr z,release
        ld c,(hl)               ; cells per pixel line
        inc hl
        ld a,8
mpix:   push de
        push bc
        ld b,0
        ldir
        pop bc
        pop de
        inc d
        dec a
        jr nz,mpix
        jr mline
release:xor a                   ; wait until no key is held
        in a,(0xFE)
        cpl
        and 0x1F
        jr nz,release
blink:  ei                      ; the LEDs blink until a key is pressed
        halt
        ld hl,cnt               ; one frame countdown per LED cell
        ld de,{led}
        ld b,12
led:    dec (hl)
        jr nz,lnext
        ld a,(de)               ; BRIGHT toggled
        xor 0x40
        ld (de),a
        ld a,(seed)             ; next count: 5-36 frames (LCG xor R)
        ld c,a
        add a,a
        add a,a
        add a,c
        inc a
        ld (seed),a
        ld c,a
        ld a,r
        xor c
        rrca
        rrca
        and 0x1F
        add a,5
        ld (hl),a
lnext:  inc hl
        inc e
        ld a,b
        cp 7                    ; 6 IN cells, a gap of 2, 6 OUT cells
        jr nz,lgap
        inc e
        inc e
lgap:   djnz led
        xor a
        in a,(0xFE)
        cpl
        and 0x1F
        jr z,blink
up:     ei                      ; the key released first, so that the
        halt                    ; program does not see it (ENTER would open
        xor a                   ; a POU)
        in a,(0xFE)
        cpl
        and 0x1F
        jr nz,up
        ret
cnt:    db 3, 17, 9, 25, 6, 13, 21, 4, 11, 28, 7, 15
message:
{message}
seed:   db 0x5A
ay:     ld bc,0xFFFD            ; AY register D = E
        out (c),d
        ld b,0xBF
        out (c),e
        ret
        ENDIF
effect_end:
""".format(org=LOADER_ORG, run=LOADER_RUN, screen=1 if screen else 0,
           rsrc=RUN_SRC, rdst=RUN_DST, rw=RUN_W, nframes=NOISE_FRAMES, led=LED_ATTR, message=message_data(), fplen=fixed_plen, splen=screen_plen, bufend=BUF_END,
           dzx0=os.path.join(HERE, "zx0", "dzx0_standard.asm"), fixed=FIXED, isr=isr, sbank=start_bank, flen=fixed_len,
           start=start, table="\n".join("        db %d\n        dw %d" % t for t in table),
           out="{out}", eout="{eout}")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "loader.bin")
        eout = os.path.join(tmp, "effect.bin")
        asm = os.path.join(tmp, "loader.asm")
        open(asm, "w").write(src.replace("{out}", out).replace("{eout}", eout))
        r = subprocess.run(["sjasmplus", "--nologo", asm], capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        code = open(out, "rb").read()
        effect = open(eout, "rb").read() if os.path.exists(eout) else b""
    if LOADER_RUN + len(code) - 15 > FIXED - 0x20:         # 15: the copy stub
        sys.exit("loader too long for the area below its stack (%d bytes)" % len(code))
    if FIXED + fixed_len + len(effect) > 0xC000:
        sys.exit("no room for the effect code after the program")
    return code, effect


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
    if screen:
        data.append(zx0(screen))
    for b in (0, 1, 3, 4, 6, 7):
        n = used(banks[b], IM2_AREA)
        if n:
            data.append(zx0(banks[b][:n]))
        table.append((b, len(data[-1]) if n else 0))
    splen = len(data[0]) if screen else 0
    args = (start, isr, paged, screen is not None)
    _, effect = mc_loader(table, flen, 0, splen, *args)     # pass 1: the effect code
    fixed_data += effect
    fixed_packed = zx0(fixed_data)
    loader, effect2 = mc_loader(table, flen, len(fixed_packed), splen, *args)
    assert effect2 == effect
    if FIXED + len(fixed_data) > BUF_END - len(fixed_packed):
        sys.exit("the unpacked fixed block would overrun its packed data")
    prog = basic_loader()
    tap = header(0, "ZX-PLC", len(prog), 10, len(prog)) + block(0xFF, prog)
    tap += header(3, "loader", len(loader), LOADER_ORG, 32768) + block(0xFF, loader)
    for d in data:
        tap += block(0xFF, d)
    tap += block(0xFF, fixed_packed)
    open(out, "wb").write(tap)
    print("%s: %d bytes, loader %d; packed: %sbanks %s, fixed %d -> %d" % (
        out, len(tap), len(loader), "screen 6912 -> %d, " % splen if screen else "",
        ", ".join("%d:%d" % t for t in table if t[1]), len(fixed_data), len(fixed_packed)))


if __name__ == "__main__":
    main()
