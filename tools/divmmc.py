"""divMMC + SD card for zxrun.py, enough to run esxDOS.

divMMC: port 0xE3 control (bit 7 CONMEM, bits 0-3 the RAM bank at
0x2000), automap after the opcode fetch at 0x0000 / 0x0008 / 0x0038 /
0x0066 / 0x04C6 / 0x0562 and before it at 0x3D00-0x3DFF (esxDOS returns
from ROM calls there), unmap after an instruction at 0x1FF8-0x1FFF.
When mapped, 0x0000-0x1FFF is the EEPROM (esxDOS) and 0x2000-0x3FFF one
of 16 8K RAM banks. Port 0xE7 selects the card, 0xEB is the SPI data.
The SD card is an SDHC in SPI mode (block addresses) on an image file.
"""

AUTOMAP = (0x0000, 0x0008, 0x0038, 0x0066, 0x04C6, 0x0562)
INSTANT = range(0x3D00, 0x3E00)
UNMAP = range(0x1FF8, 0x2000)


class SDCard:
    def __init__(self, path):
        self.path = path
        self.img = bytearray(open(path, "rb").read())
        self.out = []                   # bytes the card sends next
        self.cmd = []                   # command being received
        self.idle = True
        self.app = False                # CMD55 seen: the next one is ACMD
        self.wstate = None              # None, 'token', 'data'
        self.wmulti = False
        self.wblock = 0
        self.wbuf = []
        self.rnext = None               # CMD18: the next block to send
        self.dirty = False

    def flush(self):
        if self.dirty:
            open(self.path, "wb").write(self.img)
            self.dirty = False

    def block(self, n):
        return self.img[n * 512:(n + 1) * 512]

    def read(self):
        if not self.out and self.rnext is not None:
            self.out += [0xFF, 0xFE] + list(self.block(self.rnext)) + [0xFF, 0xFF]
            self.rnext += 1
        return self.out.pop(0) if self.out else 0xFF

    def deselect(self):
        self.cmd = []

    def write(self, v):
        if self.wstate == 'token':
            if v == 0xFE or (self.wmulti and v == 0xFC):
                self.wstate, self.wbuf = 'data', []
            elif self.wmulti and v == 0xFD:     # stop transmission
                self.wstate = None
                self.out = [0xFF, 0x00, 0xFF]
            return
        if self.wstate == 'data':
            self.wbuf.append(v)
            if len(self.wbuf) == 514:           # 512 bytes + CRC
                n = self.wblock
                self.img[n * 512:(n + 1) * 512] = bytes(self.wbuf[:512])
                self.dirty = True
                self.out = [0x05, 0x00, 0xFF]   # accepted, busy, ready
                if self.wmulti:
                    self.wblock += 1
                    self.wstate = 'token'
                else:
                    self.wstate = None
            return
        if not self.cmd:
            if v & 0xC0 != 0x40:
                return                          # clock bytes (0xFF)
        self.cmd.append(v)
        if len(self.cmd) == 6:
            c, self.cmd = self.cmd, []
            self.command(c[0] & 0x3F, (c[1] << 24) | (c[2] << 16) | (c[3] << 8) | c[4])

    def command(self, n, arg):
        r1 = 0x01 if self.idle else 0x00
        app, self.app = self.app, False
        if n == 12:                             # stop the multi-block read
            self.rnext = None
            self.out = [0xFF, 0x00]
            return
        self.rnext = None
        if n == 0:
            self.idle = True
            self.out = [0xFF, 0x01]
        elif n == 8:
            self.out = [0xFF, r1, 0x00, 0x00, (arg >> 8) & 0x0F, arg & 0xFF]
        elif n == 55:
            self.app = True
            self.out = [0xFF, r1]
        elif n == 41 and app or n == 1:
            self.idle = False
            self.out = [0xFF, 0x00]
        elif n == 58:
            self.out = [0xFF, r1, 0xC0, 0xFF, 0x80, 0x00]   # powered up, CCS
        elif n in (16, 59):
            self.out = [0xFF, r1]
        elif n == 9:                            # CSD v2.0
            c = len(self.img) // (512 * 1024) - 1
            csd = [0x40, 0x0E, 0x00, 0x32, 0x5B, 0x59, 0x00, (c >> 16) & 0x3F,
                   (c >> 8) & 0xFF, c & 0xFF, 0x7F, 0x80, 0x0A, 0x40, 0x00, 0x01]
            self.out = [0xFF, r1, 0xFF, 0xFE] + csd + [0xFF, 0xFF]
        elif n == 10:                           # CID
            cid = [0x03, 0x53, 0x44] + list(b"ZXRUN") + [0x10, 0, 0, 0, 1, 0, 0x01, 0x01]
            self.out = [0xFF, r1, 0xFF, 0xFE] + cid + [0xFF, 0xFF]
        elif n == 13:
            self.out = [0xFF, r1, 0x00]
        elif n == 17:
            self.out = [0xFF, r1, 0xFF, 0xFE] + list(self.block(arg)) + [0xFF, 0xFF]
        elif n == 18:
            self.out = [0xFF, r1]
            self.rnext = arg
        elif n in (24, 25):
            self.out = [0xFF, r1]
            self.wstate, self.wmulti, self.wblock = 'token', n == 25, arg
        else:
            self.out = [0xFF, r1 | 0x04]        # illegal command


class DivMMC:
    def __init__(self, spec, rom, sd):
        self.s = spec
        self.eeprom = bytearray(open(rom, "rb").read()[:8192].ljust(8192, b"\xFF"))
        self.ram = [bytearray(8192) for _ in range(16)]
        self.sd = SDCard(sd) if sd else None
        self.ctl = 0
        self.automap = False
        self.mapped = False
        self.bank = 0                   # the RAM bank in memory while mapped
        self.cs = False                 # card 0 selected (port 0xE7 bit 0 = 0)
        for a in AUTOMAP:
            spec.m.set_breakpoint(a)
        for a in list(UNMAP) + list(INSTANT):
            spec.m.set_breakpoint(a)

    def map(self, on):
        mem = self.s.m.memory
        if on and not self.mapped:
            self.bank = self.ctl & 15
            self.s.m.set_memory_block(0, bytes(self.eeprom))
            self.s.m.set_memory_block(0x2000, bytes(self.ram[self.bank]))
            self.mapped = True
        elif not on and self.mapped:
            self.ram[self.bank][:] = mem[0x2000:0x4000]
            self.mapped = False
            self.s.set_rom()

    def control(self, val):
        if self.mapped and (val & 15) != self.bank:
            self.ram[self.bank][:] = self.s.m.memory[0x2000:0x4000]
            self.bank = val & 15
            self.s.m.set_memory_block(0x2000, bytes(self.ram[self.bank]))
        self.ctl = val
        self.map(bool(val & 0x80) or self.automap)

    def on_breakpoint(self):
        """at a breakpoint: maps / unmaps around the instruction at PC and
        executes it; returns the events of that step"""
        m = self.s.m
        pc = m.pc
        if pc in AUTOMAP and not self.automap:
            op = m.memory[pc]           # the opcode still comes from the ROM
            self.automap = True
            self.map(True)
            keep = m.memory[pc]
            m.memory[pc] = op
            ev = m.step_over_breakpoint()
            if self.mapped:
                m.memory[pc] = keep
            return ev
        if pc in INSTANT and not self.automap:
            self.automap = True
            self.map(True)
            return m.step_over_breakpoint()
        if pc in UNMAP and self.automap:
            ev = m.step_over_breakpoint()
            self.automap = False
            self.map(bool(self.ctl & 0x80))
            return ev
        return m.step_over_breakpoint()

    def inp(self, port):
        if port & 0xFF == 0xEB and self.sd:
            return self.sd.read() if self.cs else 0xFF
        return None

    def out(self, port, val):
        p = port & 0xFF
        if p == 0xE3:
            self.control(val)
        elif p == 0xE7 and self.sd:
            self.cs = not val & 1
            if not self.cs:
                self.sd.deselect()
        elif p == 0xEB and self.sd and self.cs:
            self.sd.write(val)
