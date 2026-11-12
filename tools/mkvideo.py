#!/usr/bin/env python3
"""A video of ZX-PLC: a small project typed in step by step.

    .scratch/venv/bin/python tools/mkvideo.py [-o .scratch/zxplc_demo.mp4]
            [--scale 3] [--filter soft] [--no-audio] [--shots DIR]

The snapshot zxplc.sna runs in the headless emulator of tools/zxrun.py with a
Kempston mouse; the SCENARIO below is played into it (keys typed at a human
pace, smooth mouse moves and clicks). Every frame goes to ffmpeg (50 fps,
scaled with sharp pixels); the AY register writes are turned into sound.
The application itself is not changed in any way.

--shots DIR: no video, only a PNG at every "shot:NAME" (to tune the scenario).
The video starts with the end of the tape loading of zxplc.tap (from a 128K reset
snapshot, --reset) and the program starting; --no-intro leaves it out.
"""
import argparse
import bisect
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
#   x:N        from now on only every N-th frame goes to the video (fast forward)
#   hold:N     N frames at normal speed (to look at a result), then fast again
#   go!:X,Y cl!:L  the same as go / cl, but at normal speed with a short stop on
#              the target: for menus and pickers, so that the choice is visible
# Mouse coordinates are screen pixels (0-255, 0-191) of the pointer tip.

SCENARIO = [
    # preparation (not recorded): the mouse on (View > Mouse)
    "w60 k:CS+1 w10 k:H w10 k:O w10 k:M w30",
    "rec x:5 hold:25",
    # ---- a new project: File > New project (mouse)
    "go!:8,3 cl!:L w30 go!:30,12 cl!:L w40",
    "go:85,100 w20 cl:L w40",
    "go:140,92 w20 cl:L w60 shot:new hold:20",
    # ---- POU > New...: LAMP in LD
    "go!:36,3 cl!:L w30 go!:40,20 cl!:L w30",
    "t:LAMP w15 k:ENTER w30",
    "go!:140,100 cl!:L w30",
    "t:running~lamp w15 k:ENTER w60",
    "go:20,36 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go!:130,52 cl!:L w30",
    "t:Q0.0 w10 k:ENTER w40",
    "go:44,36 w15 cl:L w30 go!:130,100 cl!:L w30",
    "t:TON0 w10 k:ENTER w40",
    "k:CS+0 k:CS+0 t:2s w10 k:ENTER w40",
    "go:236,36 w15 cl:L w30 cl:L w30",
    "go!:130,76 cl!:L w30 t:Q0.1 w10 k:ENTER w60 shot:ld go:200,150 hold:120",
    # ---- POU > New...: FAN in FBD
    "go!:36,3 cl!:L w30 go!:40,20 cl!:L w30",
    "t:FAN w15 k:ENTER w30 go!:140,108 cl!:L w30",
    "t:cooling~fan w15 k:ENTER w60",
    "go:20,44 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go!:110,20 cl!:L w30 t:Q0.0 w10 k:ENTER w40",
    "go:44,36 w15 cl:L w30 go!:110,108 cl!:L w40 shot:fbd0",
    "t:TON2 w10 k:ENTER w40 k:CS+0 k:CS+0 t:3s w10 k:ENTER w40",
    "go:68,36 w15 cl:L w30 go!:110,164 cl!:L w30 t:Q0.2 w10 k:ENTER w50 shot:fbd1",
    "go:20,68 w15 cl:L w30 cl:L w30 go!:110,20 cl!:L w30 t:I0.2 w10 k:ENTER w40",
    "go:44,68 w15 cl:L w30 go!:110,132 cl!:L w40 t:CTU1 w10 k:ENTER w40",
    "k:CS+0 k:CS+0 t:3 w10 k:ENTER w50 shot:fbd2",
    "go:20,84 w15 cl:L w30 cl:L w30 go!:110,28 cl!:L w30 t:I0.1 w10 k:ENTER w40",
    "go:68,68 w15 cl:L w30 cl:L w30 go!:110,164 cl!:L w30 t:Q0.5 w10 k:ENTER w60 shot:fbd go:200,150 hold:120",
    # ---- MAIN in IL: the motor latch and the calls
    "go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,28 w15 cl:L w30 cl:L w30 go:200,140 w30",
    "t://~Motor~start/stop w10 k:ENTER w20",
    "t:LD~I0.0 w10 k:ENTER w20",
    "t:OR~Q0.0 w10 k:ENTER w20",
    "t:ANDN~I0.1 w10 k:ENTER w20",
    "t:ST~Q0.0 w10 k:ENTER w20",
    "t://~Service~lamp~after~5~s w10 k:ENTER w20",
    "t:CAL~TON1(IN:=Q0.0,~PT:=T#5s) w10 k:ENTER w20",
    "t:LD~TON1.Q w10 k:ENTER w20",
    "t:ST~Q0.3 w10 k:ENTER w20",
    "t://~Count~the~starts w10 k:ENTER w20",
    "t:CAL~CTU0(CU:=I0.0,~R:=I0.1,~PV:=3) w10 k:ENTER w20",
    "t:LD~CTU0.Q w10 k:ENTER w20",
    "t:ST~Q0.4 w10 k:ENTER w20",
    "t:CAL~LAMP w10 k:ENTER w20",
    "t:CAL~FAN w10 k:ENTER w60 shot:il hold:120",
    # ---- symbols: Edit > Symbols
    "go!:60,3 cl!:L w30 go!:70,44 cl!:L w30 go:200,150 w20",
    "t:start k:SPACE t:I0.0 k:SPACE t:start~button k:ENTER w20",
    "t:stop k:SPACE t:I0.1 k:SPACE t:stop~button k:ENTER w20",
    "t:sensor k:SPACE t:I0.2 k:SPACE t:part~sensor k:ENTER w20",
    "t:motor k:SPACE t:Q0.0 k:SPACE t:conveyor~motor k:ENTER w20",
    "t:runLamp k:SPACE t:Q0.1 k:SPACE t:running~lamp k:ENTER w20",
    "t:fanOn k:SPACE t:Q0.2 k:SPACE t:cooling~fan k:ENTER w20",
    "t:service k:SPACE t:Q0.3 k:SPACE t:service~lamp k:ENTER w20",
    "t:starts3 k:SPACE t:Q0.4 k:SPACE t:3~starts~done k:ENTER w20",
    "t:parts3 k:SPACE t:Q0.5 k:SPACE t:3~parts~counted k:ENTER w20",
    "w20 hold:120",
    # ---- back to MAIN: symbols instead of addresses (View > Symbols), and back
    "go!:60,3 cl!:L w30 go!:70,12 cl!:L w30 go:200,150 w60",
    "go!:80,3 cl!:L w30 go!:90,12 cl!:L w30 go:200,150 w20 shot:vsym hold:60",
    "go!:80,3 cl!:L w30 go!:90,20 cl!:L w30 go:200,150 w20 hold:40",
    "go!:80,3 cl!:L w30 go!:90,12 cl!:L w30 go:200,150 w50",
    # ---- simulation of MAIN (IL): Run > Run, the inputs by clicks on the LEDs
    "go!:103,3 cl!:L w30 go!:110,12 cl!:L w100",
    "go:6,174 w20 cl:L w50 cl:L w60 hold:20 w250 shot:sim2 hold:50",
    "cl:L w40 cl:L w60 cl:L w40 cl:L w60 shot:sim3 hold:50",
    "go:22,174 w20 cl:L w60 cl:L w60 hold:30",
    # ---- simulation of LAMP (LD)
    "go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,36 w15 cl:L w30 cl:L w60",
    "go!:103,3 cl!:L w30 go!:110,12 cl!:L w100",
    "go:6,174 w20 cl:L w50 cl:L w120 hold:60",
    # ---- simulation of FAN (FBD): the fan 3 s after the motor, 3 parts counted
    "go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,44 w15 cl:L w30 cl:L w60",
    "go!:103,3 cl!:L w30 go!:110,12 cl!:L w100",
    "go:6,174 w20 cl:L w50 cl:L w180 shot:f1 hold:30",
    "go:38,174 w20 cl:L w30 cl:L w40 cl:L w30 cl:L w40 cl:L w30 cl:L w60 shot:f2 hold:60",
    # ---- the watch page (W), operands added with ENTER on its last row
    "go:200,140 w20 k:W w60",
    "k:ENTER w30 t:Q0.0 w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:TON2.ET w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:CTU1.CV w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:I0.1 w10 k:ENTER w60 shot:w1 hold:30",
    # force Stop TRUE: the motor stops, the counter is reset; then release it
    "w30 k:F w100 shot:w2 hold:60 k:F w60 k:F w60 shot:w3",
    # ---- the trend page (T on the watch page): the watched signals as time charts,
    # drawn live at normal speed: start (motor, the fan timer), three parts, stop
    "k:T w40 x:1 w40",
    "go:6,174 w20 cl:L w20 cl:L w170",
    "go:38,174 w20 cl:L w20 cl:L w30 cl:L w20 cl:L w30 cl:L w20 cl:L w60",
    "go:22,174 w20 cl:L w20 cl:L w80 shot:trend hold:60 x:5",
    "k:G w60 hold:20",
    # ---- the end: the POU list with the three POUs
    "w50 go!:36,3 cl!:L w30 go!:40,12 cl!:L w30 go:200,140 w20 shot:end hold:80",
    # ---- Help > About (the release number) stays to the end
    "go!:165,3 cl!:L w30 go!:168,20 cl!:L w40 go:220,150 w20 shot:about hold:200",
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
        self.speed = 1                      # every N-th frame is recorded
        self.tick = 0
        self.rec_frames = []                # the emulated frames in the video
        self.tape_audio = []                # per video frame: EAR levels or None
        self.blog = []                      # border writes in this frame (T, colour)
        self.fborder = self.border          # the border at the start of the frame

    def out(self, port, val):
        if not port & 1:
            self.blog.append((69888 - self.m.ticks_to_stop, val & 7))
        super().out(port, val)

    def frame(self):
        self.fborder = self.border
        self.blog = []
        super().frame()
        if not self.rec:
            return
        self.tick += 1
        if self.tick >= self.speed:
            self.tick = 0
            self.rec_frames.append(self.frames)
            self.tape_audio.append(self.ear_levels() if self.tape else None)
            if self.sink:
                self.sink(self.rgb())

    def ear_levels(self):
        """the tape signal (EAR) of the last frame, one level per audio sample"""
        t0 = (self.frames - 1) * 69888
        if self.tape_i >= len(self.tape) and self.tape and self.tape[-1] < t0:
            return None
        n = RATE // 50
        return [bisect.bisect_right(self.tape, t0 + i * 69888 // n) & 1 for i in range(n)]

    # fast RGB of the screen with a border: (bitmap byte, attribute, flash) -> 8 pixels
    PAL = [(0, 0, 0), (0, 0, 0xD7), (0xD7, 0, 0), (0xD7, 0, 0xD7), (0, 0xD7, 0), (0, 0xD7, 0xD7),
           (0xD7, 0xD7, 0), (0xD7, 0xD7, 0xD7)]
    PALB = [(0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF), (0, 0xFF, 0), (0, 0xFF, 0xFF),
            (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)]
    BORDER = 24

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

    def borders(self):
        """the border of every picture line: a colour, or the RGB bytes of the
        whole line when the colour changes inside it (the loading stripes, the
        About scroller); from the writes to port 0xFE during the frame, with the
        128K timing: 228 T per line, the paper from T 14361, 2 pixels per T"""
        B = self.BORDER
        W, H = 256 + 2 * B, 192 + 2 * B
        pal = [bytes(p) for p in self.PAL]
        rows, c, i, log = [], self.fborder, 0, self.blog
        for y in range(H):
            t0 = 14361 + (y - B) * 228 - B // 2
            t1 = t0 + W // 2
            while i < len(log) and log[i][0] <= t0:
                c = log[i][1]
                i += 1
            if i < len(log) and log[i][0] < t1:
                row, x = [], 0
                while i < len(log) and log[i][0] < t1:
                    xe = (log[i][0] - t0) * 2
                    row.append(pal[c] * (xe - x))
                    x, c = xe, log[i][1]
                    i += 1
                row.append(pal[c] * (W - x))
                rows.append(b"".join(row))
            else:
                rows.append(c)
        return rows

    def rgb(self):
        mem = self.m.memory
        B = self.BORDER
        W = 256 + 2 * B
        brow = self.borders()
        pal = [bytes(p) for p in self.PAL]
        fl = (self.frames // 16) & 1
        line = lambda r: pal[r] * W if isinstance(r, int) else r
        out = [line(r) for r in brow[:B]]
        cell = self.cell
        for y in range(192):
            base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
            ab = 0x5800 + (y >> 3) * 32
            r = brow[B + y]
            if isinstance(r, int):
                left = right = pal[r] * B
            else:
                left, right = r[:3 * B], r[-3 * B:]
            out.append(left + b"".join(cell(mem[base + c], mem[ab + c], fl) for c in range(32)) + right)
        out += [line(r) for r in brow[B + 192:]]
        return b"".join(out)

    # ---- input at a human pace
    def press(self, combo):
        self.key(combo, hold=2 + self.rnd.randint(0, 1), gap=3 + self.rnd.randint(0, 2))

    def typ(self, text):
        for ch in text:
            Spectrum.type(self, ch)
            self.run(self.rnd.randint(0, 1))

    def glide(self, x, y, px=6):
        """moves the pointer smoothly (ease in / out) to screen pixel x, y,
        about px pixels per frame"""
        x0, y0 = self.px, self.py
        dist = math.hypot(x - x0, y - y0)
        n = max(4, int(dist / px))
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
        if line == "STOP":
            break
        for cmd in line.split():
            if cmd == "rec":
                z.rec = True
                z.ay_log = []
                z.rec_f0 = z.frames
            elif cmd.startswith("x:"):
                z.speed = int(cmd[2:])
            elif cmd.startswith("hold:"):
                sp, z.speed = z.speed, 1
                z.run(int(cmd[5:]))
                z.speed = sp
            elif cmd.startswith("w"):
                z.run(int(cmd[1:]))
            elif cmd.startswith("k:"):
                z.press(cmd[2:])
            elif cmd.startswith("t:"):
                z.typ(cmd[2:].replace("~", " "))
            elif cmd.startswith("go!:"):
                sp, z.speed = z.speed, 1
                x, y = map(int, cmd[4:].split(","))
                z.glide(x, y, 8)
                z.run(15)
                z.speed = sp
            elif cmd.startswith("cl!:"):
                sp, z.speed = z.speed, 1
                z.click(cmd[4:], hold=5, gap=5)
                z.speed = sp
            elif cmd.startswith("go:"):
                x, y = map(int, cmd[3:].split(","))
                z.glide(x, y)
            elif cmd.startswith("cl:"):
                z.click(cmd[3:], hold=6, gap=6)
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


def ay_render(log, rec_frames, tape=None):
    """log: (frame, reg, value), rec_frames: the emulated frames in the video ->
    16-bit mono samples, one video frame (1/50 s) each; tape: per video frame
    the EAR levels to mix in (the loading sound) or None"""
    regs = [0] * 16
    regs[7] = 0xFF
    per_frame = RATE / 50.0
    out = bytearray()
    step = AY_CLOCK / 8.0 / RATE            # tone / noise counters tick at clock / 8 (/16 per half)
    tc = [0.0, 0.0, 0.0]
    tout = [1, 1, 1]
    nc, nout, lfsr = 0.0, 1, 1
    ec, epos, ehold = 0.0, 0, False
    log = [(fr, r, v) for fr, r, v in log if isinstance(r, int)]
    li = 0
    acc = 0.0
    for fi, f in enumerate(rec_frames):
        ear = tape[fi] if tape else None
        k = 0
        while li < len(log) and log[li][0] <= f:
            _, r, v = log[li]
            li += 1
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
            v = s / 3 * 80000
            if ear is not None and k < len(ear):
                v += 6000 if ear[k] else -6000
            k += 1
            out += struct.pack("<h", max(-32767, min(32767, int(v))))
    return bytes(out)


# the look of the pixels (ffmpeg filters; {s} = scale)
FILTERS = {
    "sharp": "scale=iw*{s}:ih*{s}:flags=neighbor",
    "soft": "scale=iw*{s}:ih*{s}:flags=neighbor,gblur=sigma=0.8",
    "hq": "hqx={s}",
    "xbr": "xbr={s}",
}


INTRO_LOAD = 200        # frames of the tape loading shown before its end
INTRO_WAIT = 300        # frames of the loading effect before a key is pressed
INTRO_START = 150       # frames after the key (the program starts)


def intro(reset, tap, scale, sink):
    """the end of the tape loading (with its border stripes and sound), the
    loader effect, a key, the program starting"""
    z = Recorder(reset, scale, sink)
    z.mouse = False
    z.run(150)
    z.key("ENTER")                          # Tape Loader in the 128 menu
    z.run(20)
    t_end = z.play_tap(tap) - 3500000       # the last edge of the tape
    end = t_end // 69888
    z.run(max(0, end - INTRO_LOAD - z.frames))
    z.rec = True
    z.ay_log = []
    z.rec_f0 = z.frames
    z.run(end - z.frames + INTRO_WAIT)
    z.key("SPACE")
    z.run(INTRO_START)
    return z


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, ".scratch", "zxplc_demo.mp4"))
    ap.add_argument("--sna", default=os.path.join(ROOT, "zxplc.sna"))
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--no-audio", action="store_true")
    ap.add_argument("--filter", choices=sorted(FILTERS), default="soft",
                    help="pixel look: sharp, soft (a slight blur, default), hq (hqx), xbr")
    ap.add_argument("--shots", default=None, help="only checkpoint PNGs into this folder")
    ap.add_argument("--no-intro", action="store_true", help="without the tape loading at the start")
    ap.add_argument("--reset", default=os.path.join(ROOT, ".scratch", "reset128.sna"),
                    help="snapshot of a 128K just after reset (the 128 menu), for the intro")
    ap.add_argument("--tap", default=os.path.join(ROOT, "zxplc.tap"))
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
         "-vf", FILTERS[a.filter].format(s=a.scale),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", silent],
        stdin=subprocess.PIPE)
    segs = []
    if not a.no_intro:
        if os.path.exists(a.reset) and os.path.exists(a.tap):
            segs.append(intro(a.reset, a.tap, a.scale, ff.stdin.write))
        else:
            print("no intro: %s or %s missing" % (a.reset, a.tap))
    z = Recorder(a.sna, a.scale, ff.stdin.write)
    play(z, SCENARIO)
    segs.append(z)
    ff.stdin.close()
    ff.wait()
    n = sum(len(s.rec_frames) for s in segs)
    print("video frames: %d (%.1f s)" % (n, n / 50))
    if a.no_audio:
        os.replace(silent, a.out)
        return
    wav = a.out + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        for s in segs:
            w.writeframes(ay_render(s.ay_log, s.rec_frames, s.tape_audio))
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", silent, "-i", wav,
                           "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", a.out])
    os.remove(silent)
    os.remove(wav)
    print("written:", a.out)


if __name__ == "__main__":
    main()
