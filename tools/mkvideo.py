#!/usr/bin/env python3
"""A video of ZX-PLC: a small project typed in step by step.

    .scratch/venv/bin/python tools/mkvideo.py [-o .scratch/zxplc_demo.mp4]
            [--scale 3] [--no-audio] [--shots DIR]

The snapshot zxplc.sna runs in the headless emulator of tools/zxrun.py with a
Kempston mouse; the SCENARIO below is played into it (keys typed at a human
pace, smooth mouse moves and clicks). Every frame goes to ffmpeg (50 fps,
scaled with sharp pixels); the AY register writes are turned into sound.
The application itself is not changed in any way.

--shots DIR: no video, only a PNG at every "shot:NAME" (to tune the scenario).
"""
import argparse
import math
import os
import random
import struct
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zxrun import Spectrum          # noqa: E402  (the emulator, unchanged)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- the scenario ------------------------------------------------------------
# Commands (space separated, like zxrun scripts):
#   k:KEY      press a key (CS+5, SS+U, ENTER ...)      t:TEXT  type (~ = space)
#   wN         wait N frames                            go:X,Y  glide the mouse
#   cl:L/R     click                                    shot:N  checkpoint PNG
#   rec        start recording (everything before is a silent preparation)
# Mouse coordinates are screen pixels (0-255, 0-191) of the pointer tip.

SCENARIO = [
    # preparation (not recorded): the mouse on (View > Mouse)
    "w60 k:CS+1 w10 k:V w10 k:M w30",
    "rec w50",
    # ---- a new project: File > New project (mouse)
    "go:8,3 w15 cl:L w30 go:30,12 w15 cl:L w40",
    "go:85,100 w20 cl:L w40",
    "go:140,92 w20 cl:L w60 shot:new",
    # ---- POU > New...: LAMP in LD
    "go:36,3 w15 cl:L w30 go:40,20 w15 cl:L w30",
    "t:LAMP w15 k:ENTER w30",
    "go:140,100 w15 cl:L w30",
    "t:Running~lamp w15 k:ENTER w60",
    "go:20,36 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go:130,52 w15 cl:L w30",
    "t:Q0.0 w10 k:ENTER w40",
    "go:44,36 w15 cl:L w30 go:130,100 w15 cl:L w30",
    "t:TON0 w10 k:ENTER w40",
    "k:CS+0 k:CS+0 t:2s w10 k:ENTER w40",
    "go:236,36 w15 cl:L w20 cl:L w30",
    "go:130,76 w15 cl:L w30 t:Q0.1 w10 k:ENTER w60 shot:ld",
    # ---- POU > New...: FAN in FBD
    "go:36,3 w15 cl:L w30 go:40,20 w15 cl:L w30",
    "t:FAN w15 k:ENTER w30 go:140,108 w15 cl:L w30",
    "t:Cooling~fan w15 k:ENTER w60",
    "go:20,44 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go:110,20 w15 cl:L w30 t:Q0.0 w10 k:ENTER w40",
    "go:44,36 w15 cl:L w30 go:110,44 w15 cl:L w40 k:2 w50 shot:fbd0",
    "go:20,52 w15 cl:L w20 cl:L w30",
    "go:110,28 w15 cl:L w30 t:I0.2 w10 k:ENTER w40",
    "go:68,36 w15 cl:L w20 cl:L w30",
    "go:110,164 w15 cl:L w30 t:Q0.2 w10 k:ENTER w60 shot:fbd",
    # ---- MAIN in IL: the motor latch and the calls
    "go:36,3 w15 cl:L w30 go:40,12 w15 cl:L w60",
    "go:20,28 w15 cl:L w20 cl:L w30 go:200,140 w30",
    "t://~Motor~start/stop w10 k:ENTER w20",
    "t:LD~I0.0 w10 k:ENTER w20",
    "t:OR~Q0.0 w10 k:ENTER w20",
    "t:ANDN~I0.1 w10 k:ENTER w20",
    "t:ST~Q0.0 w10 k:ENTER w20",
    "t:CAL~LAMP w10 k:ENTER w20",
    "t:CAL~FAN w10 k:ENTER w60 shot:il",
    # ---- the end: the POU list with the three POUs
    "w50 go:36,3 w15 cl:L w30 go:40,12 w15 cl:L w30 go:200,140 w250 shot:end",
]


# ---- the emulator with recording -----------------------------------------------
class Recorder(Spectrum):
    def __init__(self, sna, scale, sink):
        super().__init__(sna)
        self.mouse = True
        self.sink = sink                    # callable(frame_bytes) or None
        self.rec = False
        self.scale = scale
        self.cache = {}
        self.rnd = random.Random(1)

    def frame(self):
        super().frame()
        if self.rec and self.sink:
            self.sink(self.rgb())

    # fast RGB of the screen with a border: (bitmap byte, attribute, flash) -> 8 pixels
    PAL = [(0, 0, 0), (0, 0, 0xD7), (0xD7, 0, 0), (0xD7, 0, 0xD7), (0, 0xD7, 0), (0, 0xD7, 0xD7),
           (0xD7, 0xD7, 0), (0xD7, 0xD7, 0xD7)]
    PALB = [(0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF), (0, 0xFF, 0), (0, 0xFF, 0xFF),
            (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)]
    BORDER = 16

    def cell(self, b, at, fl):
        k = (b, at, fl)
        v = self.cache.get(k)
        if v is None:
            p = self.PALB if at & 0x40 else self.PAL
            ink, paper = bytes(p[at & 7]), bytes(p[(at >> 3) & 7])
            if at & 0x80 and fl:
                ink, paper = paper, ink
            v = b"".join(ink if (b >> (7 - i)) & 1 else paper for i in range(8))
            self.cache[k] = v
        return v

    def rgb(self):
        mem = self.m.memory
        B = self.BORDER
        bc = bytes(self.PAL[self.border])
        side = bc * B
        full = bc * (256 + 2 * B)
        fl = (self.frames // 16) & 1
        out = [full] * B
        for y in range(192):
            base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
            ab = 0x5800 + (y >> 3) * 32
            cell = self.cell
            out.append(side + b"".join(cell(mem[base + c], mem[ab + c], fl) for c in range(32)) + side)
        out += [full] * B
        return b"".join(out)

    # ---- input at a human pace
    def press(self, combo):
        self.key(combo, hold=3 + self.rnd.randint(0, 2), gap=4 + self.rnd.randint(0, 4))

    def typ(self, text):
        for ch in text:
            Spectrum.type(self, ch)
            self.run(self.rnd.randint(0, 3))

    def glide(self, x, y):
        """moves the pointer smoothly (ease in / out) to screen pixel x, y"""
        x0, y0 = self.px, self.py
        dist = math.hypot(x - x0, y - y0)
        n = max(4, int(dist / 6))
        for i in range(1, n + 1):
            t = i / n
            e = t * t * (3 - 2 * t)
            tx, ty = round(x0 + (x - x0) * e), round(y0 + (y - y0) * e)
            dx, dy = tx - self.px, ty - self.py
            self.mx = (self.mx + dx) & 255
            self.my = (self.my - dy) & 255
            self.px, self.py = tx, ty
            self.run(1)


def play(z, scenario, shots=None):
    for line in scenario:
        for cmd in line.split():
            if cmd == "rec":
                z.rec = True
                z.ay_log = []
                z.rec_f0 = z.frames
            elif cmd.startswith("w"):
                z.run(int(cmd[1:]))
            elif cmd.startswith("k:"):
                z.press(cmd[2:])
            elif cmd.startswith("t:"):
                z.typ(cmd[2:].replace("~", " "))
            elif cmd.startswith("go:"):
                x, y = map(int, cmd[3:].split(","))
                z.glide(x, y)
            elif cmd.startswith("cl:"):
                z.click(cmd[3:], hold=3, gap=4)
            elif cmd.startswith("shot:"):
                if shots:
                    z.png(os.path.join(shots, cmd[5:] + ".png"))
            else:
                raise SystemExit("unknown command: " + cmd)


# ---- AY-3-8912 -------------------------------------------------------------------
AY_CLOCK = 1773400
RATE = 44100
VOL = [0, 0.0105, 0.0154, 0.0216, 0.0316, 0.0461, 0.0646, 0.1073, 0.1265, 0.2049, 0.2927,
       0.3729, 0.4925, 0.6353, 0.8056, 1.0]


def ay_render(log, f0, frames):
    """log: (frame, reg, value) -> 16-bit mono samples, 50 frames per second"""
    regs = [0] * 16
    regs[7] = 0xFF
    per_frame = RATE / 50.0
    out = bytearray()
    step = AY_CLOCK / 8.0 / RATE            # tone / noise counters tick at clock / 8 (/16 per half)
    tc = [0.0, 0.0, 0.0]
    tout = [1, 1, 1]
    nc, nout, lfsr = 0.0, 1, 1
    ec, epos, ehold = 0.0, 0, False
    ev = {}
    for fr, r, v in log:
        if isinstance(r, int):
            ev.setdefault(fr - f0, []).append((r, v))
    acc = 0.0
    for f in range(frames):
        for r, v in ev.get(f, []):
            regs[r] = v
            if r == 13:
                epos, ehold, ec = 0, False, 0.0
        acc += per_frame
        n = int(acc)
        acc -= n
        tp = [max(1, (regs[2 * c] | (regs[2 * c + 1] & 15) << 8)) for c in range(3)]
        npr = max(1, regs[6] & 31)
        epr = max(1, regs[11] | regs[12] << 8)
        mix = regs[7]
        shape = regs[13] & 15
        for _ in range(n):
            for c in range(3):
                tc[c] += step
                half = tp[c]
                while tc[c] >= half:
                    tc[c] -= half
                    tout[c] ^= 1
            nc += step / 2
            while nc >= npr:
                nc -= npr
                bit = (lfsr ^ (lfsr >> 3)) & 1
                lfsr = (lfsr >> 1) | (bit << 16)
                nout = lfsr & 1
            ec += step / 2
            while ec >= epr and not ehold:
                ec -= epr
                epos += 1
                if epos >= 32:
                    if shape & 8 and not shape & 1:
                        epos = 0
                    else:
                        epos, ehold = 31, True
            s = 0.0
            for c in range(3):
                t_on = tout[c] or (mix >> c) & 1
                n_on = nout or (mix >> (c + 3)) & 1
                if t_on and n_on:
                    a = regs[8 + c]
                    if a & 16:
                        e = epos >> 1
                        att = shape & 4
                        if shape < 8:
                            lvl = (e if att else 15 - e) if not ehold else 0
                        else:
                            alt = shape & 2 and (epos // 32) & 1
                            lvl = e if (att != 0) ^ bool(alt) else 15 - e
                            if ehold and shape & 1:
                                lvl = 15 if ((att != 0) ^ bool(shape & 2)) else 0
                        s += VOL[lvl]
                    else:
                        s += VOL[a & 15]
            out += struct.pack("<h", max(-32767, min(32767, int(s / 3 * 80000))))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, ".scratch", "zxplc_demo.mp4"))
    ap.add_argument("--sna", default=os.path.join(ROOT, "zxplc.sna"))
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--no-audio", action="store_true")
    ap.add_argument("--shots", default=None, help="only checkpoint PNGs into this folder")
    a = ap.parse_args()

    if a.shots:
        os.makedirs(a.shots, exist_ok=True)
        z = Recorder(a.sna, a.scale, None)
        z.noborder = True
        play(z, SCENARIO, a.shots)
        print("frames:", z.frames)
        return

    W, H = 256 + 2 * Recorder.BORDER, 192 + 2 * Recorder.BORDER
    silent = a.out + ".video.mp4"
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (W, H), "-r", "50", "-i", "-",
         "-vf", "scale=%d:%d:flags=neighbor" % (W * a.scale, H * a.scale),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", silent],
        stdin=subprocess.PIPE)
    z = Recorder(a.sna, a.scale, ff.stdin.write)
    play(z, SCENARIO)
    ff.stdin.close()
    ff.wait()
    n = z.frames - z.rec_f0
    print("recorded frames: %d (%.1f s)" % (n, n / 50))
    if a.no_audio:
        os.replace(silent, a.out)
        return
    wav = a.out + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(ay_render(z.ay_log, z.rec_f0, n))
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", silent, "-i", wav,
                           "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", a.out])
    os.remove(silent)
    os.remove(wav)
    print("written:", a.out)


if __name__ == "__main__":
    main()
