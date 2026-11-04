#!/usr/bin/env python3
"""Headless ZX Spectrum 48K runner for automated tests.

Usage: zxrun.py file.sna [-s script] [-o out.png] [-f frames]
Script: whitespace separated commands:
  wN        run N frames
  k:KEY     tap key (held 3 frames, then released 3 frames)
            KEY = A-Z 0-9 ENTER SPACE CS SS, combos with '+', e.g. k:CS+5
  t:TEXT    type text (letters/digits/space, uppercase via CS)
  shot:NAME save screenshot NAME.png
Requires the 'z80' python package and /usr/share/fuse/48.rom.
"""
import sys, argparse, struct, zlib
import z80
HL_KIND = z80.Z80Machine().index_rp_kind     # no index prefix pending

KEYMAP = {}
rows = ["CS Z X C V", "A S D F G", "Q W E R T", "1 2 3 4 5",
        "0 9 8 7 6", "P O I U Y", "ENTER L K J H", "SPACE SS M N B"]
for r, s in enumerate(rows):
    for b, k in enumerate(s.split()):
        KEYMAP[k] = (r, b)

class Spectrum:
    """48K or 128K Spectrum (the snapshot size decides)."""
    def __init__(self, sna, rom="/usr/share/fuse/48.rom"):
        self.m = z80.Z80Machine()
        self.pressed = set()
        self.border = 7
        self.is128 = False
        self.banks = None
        self.port7ffd = 0
        self.m.set_input_callback(self.inp)
        self.m.set_output_callback(self.out)
        data = open(sna, "rb").read()
        if len(data) > 49179:
            self.is128 = True
            self.roms = [open("/usr/share/fuse/128-0.rom", "rb").read(),
                         open("/usr/share/fuse/128-1.rom", "rb").read()]
        else:
            self.m.set_memory_block(0, open(rom, "rb").read())
        self.load_sna(data)
        self.frames = 0

    def load_sna(self, d):
        m = self.m
        m.i = d[0]
        m.alt_hl, m.alt_de, m.alt_bc, m.alt_af = struct.unpack("<4H", d[1:9])
        m.hl, m.de, m.bc, m.iy, m.ix = struct.unpack("<5H", d[9:19])
        m.iff2 = 1 if d[19] & 4 else 0
        m.iff1 = m.iff2
        m.r = d[20]
        m.af, m.sp = struct.unpack("<2H", d[21:25])
        self.m._Z80State__int_mode[0] = d[25]
        self.border = d[26]
        m.set_memory_block(0x4000, d[27:27 + 49152])
        if not self.is128:
            sp = m.sp
            mem = m.memory
            m.pc = mem[sp] | (mem[(sp + 1) & 0xFFFF] << 8)
            m.sp = (sp + 2) & 0xFFFF
            return
        # 128K: PC, port 0x7FFD, TR-DOS flag, then the remaining banks
        ext = 27 + 49152
        m.pc = d[ext] | (d[ext + 1] << 8)
        self.port7ffd = d[ext + 2]
        paged = self.port7ffd & 7
        self.banks = {5: bytearray(d[27:27 + 16384]), 2: bytearray(d[27 + 16384:27 + 32768]),
                      paged: bytearray(d[27 + 32768:27 + 49152])}
        pos = ext + 4
        for b in range(8):
            if b in self.banks:
                continue
            self.banks[b] = bytearray(d[pos:pos + 16384])
            pos += 16384
        self.cur_bank = paged
        self.set_rom()

    def set_rom(self):
        self.m.set_memory_block(0, self.roms[(self.port7ffd >> 4) & 1])

    def page(self, val):
        """port 0x7FFD write: swap the bank at 0xC000 and the ROM."""
        if self.port7ffd & 0x20:
            return                      # paging locked
        mem = self.m.memory
        new = val & 7
        if new != self.cur_bank:
            self.banks[self.cur_bank][:] = mem[0xC000:0x10000]
            self.m.set_memory_block(0xC000, bytes(self.banks[new]))
            self.cur_bank = new
        self.port7ffd = val
        self.set_rom()

    def bank_bytes(self, bank, addr, n):
        """read n bytes of a bank (addr 0xC000-0xFFFF) whether paged or not"""
        if bank == self.cur_bank:
            return bytes(self.m.memory[addr:addr + n])
        off = addr - 0xC000
        return bytes(self.banks[bank][off:off + n])

    def inp(self, port):
        if port & 1:
            return 0xFF
        hi = port >> 8
        v = 0x1F
        for (r, b) in self.pressed:
            if not (hi >> r) & 1:
                v &= ~(1 << b)
        return v | 0xA0

    def out(self, port, val):
        if not port & 1:
            self.border = val & 7
        if self.is128 and not (port & 0x8002):
            self.page(val)

    def frame(self):
        m = self.m
        m.ticks_to_stop = 69888
        while True:
            ev = m.run()
            if ev & m._TICKS_LIMIT_HIT:
                break
            if ev & m._BREAKPOINT_HIT:
                break
        # a real Z80 never takes an interrupt between a DD/FD prefix and its
        # opcode: finish a pending prefixed instruction first
        while m.index_rp_kind != HL_KIND:
            m.ticks_to_stop = 1
            m.run()
        # interrupt
        if m.iff1:
            if m.halted:
                m.halted = 0          # PC already points past HALT
            m.iff1 = m.iff2 = 0
            m.sp = (m.sp - 2) & 0xFFFF
            m.memory[m.sp] = m.pc & 0xFF
            m.memory[(m.sp + 1) & 0xFFFF] = m.pc >> 8
            im = self.m._Z80State__int_mode[0]
            if im == 2:
                v = (m.i << 8) | 0xFF
                m.pc = m.memory[v] | (m.memory[(v + 1) & 0xFFFF] << 8)
            else:
                m.pc = 0x38
        self.frames += 1

    def run(self, n):
        for _ in range(n):
            self.frame()

    def key(self, combo, hold=3, gap=6):
        ks = [KEYMAP[k] for k in combo.split("+")]
        self.pressed = set(ks)
        self.run(hold)
        self.pressed = set()
        self.run(gap)

    def type(self, text):
        for ch in text:
            if ch == " ":
                self.key("SPACE")
            elif ch.isalpha() and ch.isupper():
                self.key("CS+" + ch)
            elif ch.isalpha():
                self.key(ch.upper())
            elif ch in SYM:
                self.key("SS+" + SYM[ch])
            else:
                self.key(ch)

    def png(self, path):
        mem = self.m.memory
        pal = [(0,0,0),(0,0,0xD7),(0xD7,0,0),(0xD7,0,0xD7),(0,0xD7,0),(0,0xD7,0xD7),(0xD7,0xD7,0),(0xD7,0xD7,0xD7)]
        palb = [(0,0,0),(0,0,0xFF),(0xFF,0,0),(0xFF,0,0xFF),(0,0xFF,0),(0,0xFF,0xFF),(0xFF,0xFF,0),(0xFF,0xFF,0xFF)]
        B = 16
        W, H = 256 + 2 * B, 192 + 2 * B
        bc = pal[self.border]
        rows = []
        for y in range(H):
            row = bytearray()
            for x in range(W):
                sx, sy = x - B, y - B
                if 0 <= sx < 256 and 0 <= sy < 192:
                    addr = 0x4000 | ((sy & 0xC0) << 5) | ((sy & 7) << 8) | ((sy & 0x38) << 2) | (sx >> 3)
                    bit = (mem[addr] >> (7 - (sx & 7))) & 1
                    at = mem[0x5800 + (sy >> 3) * 32 + (sx >> 3)]
                    p = palb if at & 0x40 else pal
                    ink, paper = p[at & 7], p[(at >> 3) & 7]
                    if at & 0x80 and (self.frames // 16) & 1:
                        ink, paper = paper, ink
                    row += bytes(ink if bit else paper)
                else:
                    row += bytes(bc)
            rows.append(row)
        scale = 2
        raw = b""
        for row in rows:
            big = bytearray()
            for i in range(0, len(row), 3):
                big += row[i:i+3] * scale
            line = b"\x00" + bytes(big)
            raw += line * scale
        def chunk(t, data):
            c = struct.pack(">I", len(data)) + t + data
            return c + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W*scale, H*scale, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
        open(path, "wb").write(png)

SYM = {':': 'Z', '%': '5', '#': '3', '.': 'M', ',': 'N', '(': '8', ')': '9',
       '=': 'L', '_': '0', '+': 'K', '-': 'J', '*': 'B', '/': 'V', '<': 'R', '>': 'T', ';': 'O', '"': 'P'}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sna")
    ap.add_argument("-s", "--script", default="")
    ap.add_argument("-o", "--out", default=None)
    ap.add_argument("-f", "--frames", type=int, default=50)
    ap.add_argument("--peek", default=None, help="addr:len hexdump at end")
    a = ap.parse_args()
    z = Spectrum(a.sna)
    z.run(a.frames)
    for cmd in a.script.split():
        if cmd.startswith("w"):
            z.run(int(cmd[1:]))
        elif cmd.startswith("k:"):
            z.key(cmd[2:])
        elif cmd.startswith("t:"):
            z.type(cmd[2:].replace("~", " "))
        elif cmd.startswith("shot:"):
            z.png(cmd[5:] + ".png")
    if a.out:
        z.png(a.out)
    if a.peek:
        ad, ln = a.peek.split(":")
        ad, ln = int(ad, 16), int(ln)
        print(" ".join("%02X" % z.m.memory[(ad + i) & 0xFFFF] for i in range(ln)))
    print("border=%d pc=%04X frames=%d" % (z.border, z.m.pc, z.frames))

if __name__ == "__main__":
    main()
