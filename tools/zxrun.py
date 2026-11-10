#!/usr/bin/env python3
"""Headless ZX Spectrum 48K runner for automated tests.

Usage: zxrun.py file.sna [-s script] [-o out.png] [-f frames] [--noborder]
Script: whitespace separated commands:
  wN        run N frames
  k:KEY     tap key (held 3 frames, then released 3 frames)
            KEY = A-Z 0-9 ENTER SPACE CS SS, combos with '+', e.g. k:CS+5
  t:TEXT    type text (letters/digits/space, uppercase via CS)
  shot:NAME save screenshot NAME.png
  (with --mouse, a Kempston mouse:)
  mv:DX,DY  move the mouse by DX, DY screen pixels (Y down)
  at:X,Y    move it so that the program's pointer is at screen pixel X, Y
            (tracked from 128,96, where the program puts it when switched on)
  cl:L/R    click the left / right button
  (with --ur4, a UR-4 8255 interface; its PC writes are printed at the end:)
  ur:AA,BB  set the inputs PA, PB (hex)
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
        self.ay_reg = 0
        self.mic = 0
        self.tape = []                  # EAR edge times of a playing .tap
        self.tape_i = 0
        self.edges = []                 # T-state times of MIC edges (saving)
        self.ay_log = []                # (frame, register, value)
        self.mouse = False              # Kempston mouse attached (--mouse)
        self.ur4 = False                # UR-4 (8255) attached (--ur4)
        self.ur_a = self.ur_b = 0       #   inputs PA, PB (script ur:AA,BB)
        self.ur_c = 0                   #   output latch PC
        self.ur_cwr = 0x9B
        self.ur_log = []                #   (frame, value) of every PC change
        self.mx = self.my = 0           # its X / Y counters
        self.mb = 0xFF                  # its buttons (active low)
        self.px, self.py = 128, 96      # tracked pointer position
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
        if self.ur4 and port & 0xFF in (0x1F, 0x3F, 0x5F):
            return {0x1F: self.ur_a, 0x3F: self.ur_b, 0x5F: self.ur_c}[port & 0xFF]
        if self.mouse and port & 0xFF == 0xDF:
            hi = port >> 8
            if hi == 0xFA:
                return self.mb
            if hi == 0xFB:
                return self.mx
            if hi == 0xFF:
                return self.my
        if port & 1:
            return 0xFF
        hi = port >> 8
        v = 0x1F
        for (r, b) in self.pressed:
            if not (hi >> r) & 1:
                v &= ~(1 << b)
        if self.tape:                   # EAR (bit 6) from the playing tape
            now = self.frames * 69888 + 69888 - self.m.ticks_to_stop
            while self.tape_i < len(self.tape) and self.tape[self.tape_i] <= now:
                self.tape_i += 1
            return v | 0xA0 | (0x40 if self.tape_i & 1 else 0)
        return v | 0xA0

    def out(self, port, val):
        if self.ur4 and port & 0xFF == 0x5F:
            if val != self.ur_c:
                self.ur_log.append((self.frames, val))
            self.ur_c = val
        if self.ur4 and port & 0xFF == 0x7F:
            self.ur_cwr = val
        if not port & 1:
            self.border = val & 7
            mic = val & 8
            if mic != self.mic:         # tape output: time of each MIC edge
                self.mic = mic
                self.edges.append(self.frames * 69888 + 69888 - self.m.ticks_to_stop)
        if self.is128 and not (port & 0x8002):
            self.page(val)
        if self.is128 and not (port & 2) and port & 0x8000:
            if port & 0x4000:
                self.ay_reg = val & 15          # 0xFFFD: select
            else:                               # 0xBFFD: write
                self.ay_log.append((self.frames, self.ay_reg, val))

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

    def tap_blocks(self):
        """decodes the saved MIC signal into tape blocks (lists of bytes)"""
        d = [b - a for a, b in zip(self.edges, self.edges[1:])]
        blocks, i = [], 0
        while i < len(d):
            n = 0                       # pilot: many half periods ~2168 T
            while i < len(d) and 1900 < d[i] < 2450:
                n += 1
                i += 1
            if n < 200:
                i += 1
                continue
            i += 2                      # sync pulses
            bits = []
            while i + 1 < len(d) and d[i] < 2000 and d[i + 1] < 2000:
                bits.append(1 if d[i] + d[i + 1] > 2560 else 0)
                i += 2
            data = [int("".join(map(str, bits[k:k + 8])), 2) for k in range(0, len(bits) - 7, 8)]
            blocks.append(data)
        return blocks

    def play_tap(self, path):
        """starts playing a .tap file (standard ROM timing) into EAR"""
        d = open(path, "rb").read()
        t = self.frames * 69888 + 700000
        edges, i = [], 0
        while i + 2 <= len(d):
            n = d[i] | (d[i + 1] << 8)
            blk = d[i + 2:i + 2 + n]
            i += 2 + n
            for _ in range(8063 if blk[0] < 128 else 3223):
                t += 2168
                edges.append(t)
            t += 667
            edges.append(t)
            t += 735
            edges.append(t)
            for byte in blk:
                for k in range(7, -1, -1):
                    p = 1710 if (byte >> k) & 1 else 855
                    t += p
                    edges.append(t)
                    t += p
                    edges.append(t)
            t += 3500000                # 1 s pause
        self.tape, self.tape_i = edges, 0
        return t

    def save_tap(self, path):
        out = bytearray()
        for b in self.tap_blocks():
            out += bytes([len(b) & 255, len(b) >> 8]) + bytes(b)
        open(path, "wb").write(out)
        return self.tap_blocks()

    def run(self, n):
        for _ in range(n):
            self.frame()

    def key(self, combo, hold=3, gap=6):
        ks = [KEYMAP[k] for k in combo.split("+")]
        self.pressed = set(ks)
        self.run(hold)
        self.pressed = set()
        self.run(gap)

    def mouse_move(self, dx, dy):
        """moves the mouse in steps the program can follow (|delta| < 128)"""
        while dx or dy:
            sx = max(-60, min(60, dx))
            sy = max(-60, min(60, dy))
            self.mx = (self.mx + sx) & 255
            self.my = (self.my - sy) & 255      # Kempston: Y grows upward
            self.px = max(0, min(255, self.px + sx))
            self.py = max(0, min(191, self.py + sy))
            dx -= sx
            dy -= sy
            self.run(2)

    def mouse_at(self, x, y):
        self.mouse_move(x - self.px, y - self.py)
        self.run(2)

    def click(self, button="L", hold=3, gap=6):
        self.mb = 0xFF & ~(2 if button == "L" else 1)
        self.run(hold)
        self.mb = 0xFF
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
        B = 0 if getattr(self, "noborder", False) else 16
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
    ap.add_argument("--ay", action="store_true", help="print AY volume/mixer writes")
    ap.add_argument("--tap", default=None, help="save the tape output as a .tap file")
    ap.add_argument("--noborder", action="store_true", help="screenshots without the border")
    ap.add_argument("--mouse", action="store_true", help="attach a Kempston mouse")
    ap.add_argument("--ur4", action="store_true", help="attach a UR-4 (8255) interface; prints its PC writes")
    a = ap.parse_args()
    z = Spectrum(a.sna)
    z.noborder = a.noborder
    z.mouse = a.mouse
    z.ur4 = a.ur4
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
        elif cmd.startswith("play:"):
            z.play_tap(cmd[5:])
        elif cmd.startswith("mv:"):
            dx, dy = map(int, cmd[3:].split(","))
            z.mouse_move(dx, dy)
        elif cmd.startswith("at:"):
            x, y = map(int, cmd[3:].split(","))
            z.mouse_at(x, y)
        elif cmd.startswith("cl:"):
            z.click(cmd[3:])
        elif cmd.startswith("ur:"):
            z.ur_a, z.ur_b = (int(v, 16) for v in cmd[3:].split(","))
        elif cmd == "mark":
            z.ay_log.append((z.frames, "mark", 0))
    if a.out:
        z.png(a.out)
    if a.ur4:
        print("UR-4 CWR %02X, PC: %s" % (z.ur_cwr, " ".join("%d:%02X" % e for e in z.ur_log)))
    if a.peek:
        ad, ln = a.peek.split(":")
        ad, ln = int(ad, 16), int(ln)
        print(" ".join("%02X" % z.m.memory[(ad + i) & 0xFFFF] for i in range(ln)))
    if a.ay:        # changes of the volumes A/B (regs 8, 9) and periods
        last = {}
        for fr, r, v in z.ay_log:
            if r == "mark":
                print("%5d ---- mark" % fr)
            elif r in (0, 1, 2, 3, 7, 8, 9) and last.get(r) != v:
                last[r] = v
                print("%5d R%d=%02X" % (fr, r, v))
    if a.tap:
        for b in z.save_tap(a.tap):
            x = 0
            for v in b:
                x ^= v
            print("tap block: %d bytes, flag %02X, checksum %s" % (len(b), b[0], "ok" if x == 0 else "BAD"))
    print("border=%d pc=%04X frames=%d" % (z.border, z.m.pc, z.frames))

if __name__ == "__main__":
    main()
