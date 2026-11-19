#!/usr/bin/env python3
"""A narrated tour of ZX-PLC for YouTube: the program at normal speed with a
spoken English commentary (Piper TTS, offline) and Czech + English subtitles.

    .scratch/venv/bin/python tools/mkyoutube.py [--draft] [--only CHAPTER]
            [--shots DIR] [--script-only] [--voice en_US-ryan-high]

The scenario and the commentary are in tools/yt_scenario.py. It is played into
the zxrun emulator like the one of tools/mkvideo.py (whose Recorder, AY sound
and pixel filters are used), with these extra commands:

    say:ID     start the cue ID of NARRATION (waits for the cue before first);
               the following commands run while it is spoken
    ws         wait until the current cue has ended (+ a short pause)
    ch:Title   a chapter (YouTube chapters, --only); ~ = space
    tape:F     play the tape file F into EAR    seek:N  run (unrecorded) to N
               frames before the end of that tape
    rec        start recording (ignored with --only)
    sd         attach a divMMC with esxDOS (booted aside) and an SD card image
    ur:AA,BB   UR-4 inputs PA, PB (hex)         mouse:0/1  Kempston mouse

Outputs (default .scratch/youtube/): zxplc_tour.mp4, zxplc_tour.en.srt,
zxplc_tour.cs.srt, chapters.txt (for the YouTube description) and script.md
(the commentary with its times). --script-only writes script.md with the cue
lengths only, without the emulation. The application is not changed.

TTS: Piper in its own venv (.scratch/piper-venv, Python 3.12) and its voice
models in .scratch/piper/ (python -m piper.download_voices); every cue is
cached as .scratch/youtube/voice/<hash>.wav (44.1 kHz mono).
"""
import argparse
import array
import bisect
import hashlib
import os
import re
import shutil
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkvideo                      # noqa: E402
from mkvideo import Recorder, ay_render, FILTERS, RATE   # noqa: E402
import importlib                    # noqa: E402

SCENARIO = NARRATION = PRONOUNCE = PRONOUNCE_EL = None
PRONOUNCE_CS, CHAPTERS_CS = [], {}
LANG = 0                            # the spoken language: 0 English, 1 Czech (--lang)
GLIDE_PX = 6                        # mouse glide speed (go:)
BADGE = False                       # the ">>" mark in fast-forward parts


def load_scenario(name):
    """the scenario module (tools/<name>.py): SCENARIO, NARRATION, PRONOUNCE(_EL)
    and optionally PAUSE, GLIDE_PX, BADGE"""
    global SCENARIO, NARRATION, PRONOUNCE, PRONOUNCE_EL, PAUSE, GLIDE_PX, BADGE
    global PRONOUNCE_CS, CHAPTERS_CS
    m = importlib.import_module(name)
    PRONOUNCE_CS = getattr(m, "PRONOUNCE_CS", [])
    CHAPTERS_CS = getattr(m, "CHAPTERS_CS", {})
    SCENARIO, NARRATION = m.SCENARIO, m.NARRATION
    PRONOUNCE, PRONOUNCE_EL = m.PRONOUNCE, m.PRONOUNCE_EL
    PAUSE = getattr(m, "PAUSE", 20)
    GLIDE_PX = getattr(m, "GLIDE_PX", 6)
    BADGE = getattr(m, "BADGE", False)

ROOT = mkvideo.ROOT
SCR = os.path.join(ROOT, ".scratch")
PIPER = os.path.join(SCR, "piper-venv", "bin", "python")
VOICES = os.path.join(SCR, "piper")
ESX_ROM = os.path.join(SCR, "esx", "x", "ESXMMC.BIN")
ESX_SD = os.path.join(SCR, "esx", "sd_clean.img")


class Done(Exception):
    pass


PAUSE = 20                          # frames after a cue before ws goes on


# ---- TTS -------------------------------------------------------------------------
# voice "en_US-ryan-high": Piper; voice "el:VOICE_ID": ElevenLabs (the API key only from
# $ELEVENLABS_API_KEY or .scratch/elevenlabs.key, never written anywhere else)
EL_KEY_FILE = os.path.join(SCR, "elevenlabs.key")
EL_API = "https://api.elevenlabs.io/v1"
EL = {"model": "eleven_multilingual_v2", "stability": 0.5, "similarity": 0.75, "speed": 1.0}


def spoken(text, el=False):
    """the text as the TTS should say it (the PRONOUNCE regex replacements)"""
    for k, v in (PRONOUNCE_CS if LANG else PRONOUNCE_EL if el else PRONOUNCE):
        text = re.sub(k, v, text)
    return text


def el_key():
    k = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not k and os.path.exists(EL_KEY_FILE):
        k = open(EL_KEY_FILE).read().strip()
    if not k:
        sys.exit("no ElevenLabs API key: set ELEVENLABS_API_KEY or write it to .scratch/elevenlabs.key")
    return k


def el_request(path, body=None, tries=5):
    """an ElevenLabs API call -> response bytes (errors without the key)"""
    import json
    import time
    import urllib.error
    import urllib.request
    data = json.dumps(body).encode() if body is not None else None
    for i in range(tries):
        req = urllib.request.Request(EL_API + path, data=data, method="POST" if data else "GET")
        req.add_header("xi-api-key", el_key())
        if data:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503, 504) and i < tries - 1:
                time.sleep(2 ** i * 2)
                continue
            sys.exit("ElevenLabs: HTTP %d %s" % (e.code, msg))
        except urllib.error.URLError as e:
            if i < tries - 1:
                time.sleep(2 ** i * 2)
                continue
            sys.exit("ElevenLabs: %s" % e.reason)


def el_voices():
    import json
    d = json.loads(el_request("/voices"))
    for v in d.get("voices", []):
        lb = v.get("labels") or {}
        print("%-22s %-24s %s" % (v["voice_id"], v["name"][:24],
                                  ", ".join(str(x) for x in lb.values() if x)))


def tts(text, voice, cache, scale):
    """the cue as 16-bit mono samples at RATE (cached)"""
    el = voice.startswith("el:")
    s = spoken(text, el)
    tag = ("%s|%s|%s|%s" % (voice, EL["model"], EL["stability"], EL["similarity"])) if el \
        else "%s|%s" % (voice, scale)
    if el and EL["speed"] != 1.0:           # (1.0: the cache keys of the first tour)
        tag += "|%s" % EL["speed"]
    h = hashlib.sha1(("%s|%s" % (tag, s)).encode()).hexdigest()[:16]
    path = os.path.join(cache, h + ".wav")
    if not os.path.exists(path):
        if el:
            raw = path + ".el.mp3"
            mp3 = el_request("/text-to-speech/%s?output_format=mp3_44100_128" % voice[3:], {
                "text": s, "model_id": EL["model"],
                "voice_settings": dict({"stability": EL["stability"],
                                        "similarity_boost": EL["similarity"]},
                                       **({"speed": EL["speed"]} if EL["speed"] != 1.0 else {}))})
            open(raw, "wb").write(mp3)
        else:
            raw = path + ".piper.wav"
            subprocess.run([PIPER, "-m", "piper", "-m", os.path.join(VOICES, voice + ".onnx"),
                            "-f", raw, "--length-scale", str(scale), "--sentence-silence", "0.35"],
                           input=s.encode(), check=True, capture_output=True)
        subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", raw,
                               "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", path])
        os.remove(raw)
    with wave.open(path) as w:
        return array.array("h", w.readframes(w.getnframes()))


# ---- the recorder ------------------------------------------------------------------
class TourRecorder(Recorder):
    """+ the tape output (MIC) as sound, for saving to tape"""
    def frame(self):
        n = len(self.tape_audio)
        super().frame()
        if len(self.tape_audio) > n and self.tape_audio[-1] is None:
            self.tape_audio[-1] = self.mic_levels()

    def mic_levels(self):
        t0 = (self.frames - 1) * 69888
        e = self.edges
        if not e or e[-1] < t0 - 69888:
            return None
        n = RATE // 50
        i0 = bisect.bisect_right(e, t0)
        return [bisect.bisect_right(e, t0 + i * 69888 // n, i0) & 1 for i in range(n)]


def attach_sd(z, img):
    """boots esxDOS on a 128K aside, then moves its divMMC to z"""
    from zxrun import Spectrum
    from divmmc import DivMMC, AUTOMAP, UNMAP, INSTANT
    zb = Spectrum(os.path.join(SCR, "reset128.sna"))
    zb.dm = DivMMC(zb, ESX_ROM, img)
    zb.run(300)
    dm = zb.dm
    dm.automap = False
    dm.map(bool(dm.ctl & 0x80))
    dm.s = z
    for a in list(AUTOMAP) + list(UNMAP) + list(INSTANT):
        z.m.set_breakpoint(a)
    z.dm = dm


class Tour:
    """the extra commands, the cue timeline and the chapters"""
    def __init__(self, voice, scale, only=None, intro=True, sd_img=None):
        self.voice, self.scale = voice, scale
        self.only, self.intro = only, intro
        self.cache = os.path.join(SCR, "youtube", "voice")
        os.makedirs(self.cache, exist_ok=True)
        self.cues = []                  # (id, start frame, samples)
        self.chapters = []              # (frame, title)
        self.cur = None                 # (end frame) of the cue being spoken
        self.chapter = None
        self.skip = False               # the intro left out (--no-intro)
        self.done = False               # --only: the chapter is over
        self.tape_end = 0
        self.sd_img = sd_img
        self.z = None

    def now(self):
        return len(self.z.rec_frames)

    def wait_cue(self):
        if self.cur is None:
            return
        while self.z.rec and self.now() < self.cur + PAUSE:
            self.z.run(1)
        self.cur = None

    def ext(self, z, cmd):
        if cmd.startswith("ch:"):
            self.wait_cue()
            title = cmd[3:].replace("~", " ")
            if self.only:
                if self.chapter == self.only:
                    self.done = True
                    raise Done
                if title == self.only:
                    z.rec = True
            self.chapter = title
            self.skip = not self.intro and title == "Intro"
            if z.rec:
                self.chapters.append((self.now(), title))
            return True
        if self.skip:
            return True
        if cmd == "rec":
            if not self.only:
                z.rec = True
                if not self.chapters and self.chapter:
                    self.chapters.append((0, self.chapter))
            return True
        if cmd.startswith("say:"):
            self.wait_cue()
            if not z.rec:
                return True
            cid = cmd[4:]
            smp = tts(NARRATION[cid][LANG], self.voice, self.cache, self.scale)
            self.cues.append((cid, self.now(), smp))
            self.cur = self.now() + (len(smp) * 50 + RATE - 1) // RATE
            return True
        if cmd == "ws":
            self.wait_cue()
            return True
        if cmd.startswith("tape:"):
            self.tape_end = z.play_tap(os.path.join(ROOT, cmd[5:]))
            return True
        if cmd.startswith("seek:"):
            end = self.tape_end // 69888 - int(cmd[5:])
            rec, z.rec = z.rec, False
            z.run(max(0, end - z.frames))
            z.rec = rec
            return True
        if cmd == "sd":
            img = self.sd_img
            shutil.copy(ESX_SD, img)
            attach_sd(z, img)
            return True
        if cmd.startswith("ur:"):
            z.ur_a, z.ur_b = (int(v, 16) for v in cmd[3:].split(","))
            return True
        if cmd.startswith("mouse:"):
            z.mouse = cmd[6:] == "1"
            return True
        return False

    def play(self, z, shots=None):
        self.z = z
        try:
            mkvideo.play(z, SCENARIO, shots, self.ext)
        except Done:
            pass
        self.wait_cue()


# ---- subtitles, chapters, script -----------------------------------------------------
def chunks(text, n=84):
    """the text split at sentence / clause ends into pieces of at most n chars"""
    words, out, cur = text.split(), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > n:
            out.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
        if cur.endswith((".", "?", "!", ":")) and len(cur) > n // 2:
            out.append(cur)
            cur = ""
    if cur:
        out.append(cur)
    return out


def wrap2(s, n=42):
    """one subtitle in up to two lines"""
    if len(s) <= n:
        return s
    i = s.rfind(" ", 0, len(s) // 2 + 8)
    return s[:i] + "\n" + s[i + 1:] if i > 0 else s


def ts(sec, srt=True):
    ms = int(round(sec * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms) if srt else \
        ("%d:%02d:%02d" % (h, m, s) if h else "%d:%02d" % (m, s))


def write_srt(path, cues, lang):
    n = 0
    with open(path, "w") as f:
        for cid, start, smp in cues:
            t0 = start / 50
            dur = len(smp) / RATE
            parts = chunks(NARRATION[cid][lang])
            total = sum(len(p) for p in parts)
            for p in parts:
                d = dur * len(p) / total
                n += 1
                f.write("%d\n%s --> %s\n%s\n\n" % (n, ts(t0), ts(t0 + d - 0.05), wrap2(p)))
                t0 += d


def write_script(path, cues, chapters, timed=True):
    ch = list(chapters)
    with open(path, "w") as f:
        f.write("# ZX-PLC tour: commentary\n\n")
        for cid, start, smp in cues:
            while ch and ch[0][0] <= start:
                f.write("\n## %s %s\n\n" % (ts(ch[0][0] / 50, False) if timed else "", ch[0][1]))
                ch.pop(0)
            f.write("**%s** `%s` (%.1f s)  \n%s  \n*%s*\n\n" % (
                ts(start / 50, False) if timed else "", cid, len(smp) / RATE,
                NARRATION[cid][0], NARRATION[cid][1]))


# ---- sound ---------------------------------------------------------------------------
VOICE_RMS = 0.11                    # speech level of the voice track (about -19 dBFS)


def voice_track(cues, nframes):
    """the cues at their start times, scaled to VOICE_RMS (the TTS engines differ)"""
    per = RATE // 50
    v = array.array("h", bytes(2 * nframes * per))
    n = sum(len(c[2]) for c in cues)
    if n:
        rms = (sum(x * x for c in cues for x in c[2]) / n) ** 0.5 / 32768
        g = VOICE_RMS / rms if rms else 1
        cues = [(c, s, array.array("h", (max(-32767, min(32767, int(x * g))) for x in smp)))
                for c, s, smp in cues]
    for _, start, smp in cues:
        a = start * per
        b = min(len(v), a + len(smp))
        v[a:b] = smp[:b - a]
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-d", "--dir", default=os.path.join(SCR, "youtube"))
    ap.add_argument("--scenario", default="yt_scenario", help="the scenario module in tools/")
    ap.add_argument("--name", default="zxplc_tour", help="the prefix of the output files")
    ap.add_argument("--el-speed", type=float, default=1.0, help="ElevenLabs speech speed (0.7-1.2)")
    ap.add_argument("--lang", choices=("en", "cs"), default="en",
                    help="the spoken language (cs: the Czech texts, PRONOUNCE_CS, CHAPTERS_CS)")
    ap.add_argument("--voice", default="en_US-ryan-high", help="Piper voice model")
    ap.add_argument("--tts", choices=("piper", "elevenlabs"), default="piper")
    ap.add_argument("--el-voice", default=None, help="ElevenLabs voice_id")
    ap.add_argument("--el-model", default=EL["model"])
    ap.add_argument("--el-stability", type=float, default=EL["stability"])
    ap.add_argument("--el-similarity", type=float, default=EL["similarity"])
    ap.add_argument("--el-voices", action="store_true", help="list the ElevenLabs voices of the account")
    ap.add_argument("--el-samples", default=None, help="voice_id,... -> samples/el_<id>.wav")
    ap.add_argument("--speed", type=float, default=1.05, help="Piper length scale (>1 slower)")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--filter", choices=sorted(FILTERS), default="soft")
    ap.add_argument("--draft", action="store_true", help="quick preview: 720p, fast encoding")
    ap.add_argument("--only", default=None, help="only this chapter (the ones before run unrecorded)")
    ap.add_argument("--no-intro", action="store_true", help="start from zxplc.sna, without the tape")
    ap.add_argument("--shots", default=None, help="no video: PNGs at shot:NAME + the cue times")
    ap.add_argument("--script-only", action="store_true", help="only script.md (cue texts + lengths)")
    a = ap.parse_args()
    load_scenario(a.scenario)
    global LANG
    LANG = 1 if a.lang == "cs" else 0
    os.makedirs(a.dir, exist_ok=True)
    EL.update(model=a.el_model, stability=a.el_stability, similarity=a.el_similarity,
              speed=a.el_speed)
    if a.el_voices:
        el_voices()
        return
    if a.el_samples:
        sd = os.path.join(a.dir, "samples")
        os.makedirs(sd, exist_ok=True)
        text = " ".join(NARRATION[c][0] for c in ("intro1", "ld5", "il2"))
        for vid in a.el_samples.split(","):
            smp = tts(text, "el:" + vid, os.path.join(a.dir, "voice"), 1)
            out = os.path.join(sd, "el_%s.wav" % vid)
            with wave.open(out, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(RATE)
                w.writeframes(smp.tobytes())
            print(out, "%.1f s" % (len(smp) / RATE))
        return
    if a.tts == "elevenlabs":
        if not a.el_voice:
            sys.exit("--tts elevenlabs needs --el-voice VOICE_ID (see --el-voices)")
        a.voice = "el:" + a.el_voice
    sfx = "_el" if a.tts == "elevenlabs" else ""
    tour = Tour(a.voice, a.speed, a.only, not a.no_intro, os.path.join(a.dir, "sd.img"))

    if a.script_only:
        cues, t = [], 0
        for line in SCENARIO:
            for cmd in line.split():
                if cmd.startswith("say:"):
                    smp = tts(NARRATION[cmd[4:]][LANG], a.voice, tour.cache, a.speed)
                    cues.append((cmd[4:], t, smp))
                    t += len(smp) * 50 // RATE
        chs = []
        write_script(os.path.join(a.dir, "%s_script%s.md" % (a.name, sfx)), cues, chs, timed=False)
        print("cues: %d, speech %.1f min -> %s" % (len(cues), t / 3000, os.path.join(a.dir, "%s_script%s.md" % (a.name, sfx))))
        return

    sna = os.path.join(SCR, "reset128.sna") if tour.intro and not a.only else os.path.join(ROOT, "zxplc.sna")
    if a.only or not tour.intro:
        tour.intro = False

    if a.shots:
        os.makedirs(a.shots, exist_ok=True)
        z = TourRecorder(sna, a.scale, None)
        z.glide_px, z.badge = GLIDE_PX, BADGE
        z.noborder = True
        z.ur4 = True
        tour.play(z, a.shots)
        for cid, start, smp in tour.cues:
            print("%s %-14s %.1f s" % (ts(start / 50, False), cid, len(smp) / RATE))
        print("frames: %d, recorded %d (%s)" % (z.frames, tour.now(), ts(tour.now() / 50, False)))
        return

    scale = 2 if a.draft else a.scale
    W, H = 256 + 2 * Recorder.BORDER, 192 + 2 * Recorder.BORDER
    ow, oh = (1280, 720) if a.draft else (1920, 1080)
    if W * scale > ow or H * scale > oh:
        sys.exit("scale too big for %dx%d" % (ow, oh))
    vf = FILTERS[a.filter].format(s=scale) + ",pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=0x101014" % (ow, oh)
    out = os.path.join(a.dir, a.name + sfx + ("_" + re.sub(r"\W", "", a.only) if a.only else "") + ".mp4")
    silent = out + ".video.mp4"
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "%dx%d" % (W, H), "-r", "50", "-i", "-", "-vf", vf,
         "-c:v", "libx264", "-pix_fmt", "yuv420p"] +
        (["-crf", "28", "-preset", "ultrafast"] if a.draft else ["-crf", "16", "-preset", "slow", "-g", "100"]) +
        [silent], stdin=subprocess.PIPE)
    z = TourRecorder(sna, scale, ff.stdin.write)
    z.glide_px, z.badge = GLIDE_PX, BADGE
    z.ur4 = True
    tour.play(z)
    ff.stdin.close()
    ff.wait()
    n = tour.now()
    print("video: %d frames (%s)" % (n, ts(n / 50, False)))

    base = os.path.splitext(out)[0]
    ayw, vw = base + ".ay.wav", base + ".voice.wav"
    for path, data in ((ayw, ay_render(z.ay_log, z.rec_frames, z.tape_audio)),
                       (vw, voice_track(tour.cues, n).tobytes())):
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(data)
    # the AY / tape sound quieter, and ducked under the voice
    fc = ("[0:a]volume=0.35[ay];[1:a]asplit[sc][v];"
          "[ay][sc]sidechaincompress=threshold=0.02:ratio=8:attack=30:release=400[d];"
          "[d][v]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]")
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", ayw, "-i", vw, "-i", silent,
                           "-filter_complex", fc, "-map", "2:v", "-map", "[a]",
                           "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", str(RATE),
                           "-movflags", "+faststart", "-shortest", out])
    for p in (silent, ayw, vw):
        os.remove(p)
    write_srt(base + ".en.srt", tour.cues, 0)
    write_srt(base + ".cs.srt", tour.cues, 1)
    with open(os.path.join(a.dir, a.name + ("_chapters%s.txt" if not a.only else "_chapters_only%s.txt") % sfx), "w") as f:
        for fr, t in tour.chapters:
            f.write("%s %s\n" % (ts(fr / 50, False), CHAPTERS_CS.get(t, t) if LANG else t))
    write_script(os.path.join(a.dir, a.name + ("_script%s.md" if not a.only else "_script_only%s.md") % sfx),
                 tour.cues, tour.chapters)
    print("written:", out)


if __name__ == "__main__":
    main()
