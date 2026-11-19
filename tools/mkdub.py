#!/usr/bin/env python3
"""A second (dubbed) audio track for a rendered tour video.

    .scratch/venv/bin/python tools/mkdub.py --scenario yt_scenario2 \\
        --video .scratch/youtube/zxplc_tour2_el.mp4 \\
        --el-voice 15CVCzDByBinCIoCblXo --el-speed 1.05 \\
        --dub-voice MpbYQvoTmXjHkaxtLiSh [--lang cs] [--out FILE.mp4]

The scenario is played again without video, with the voice of the video
(--el-voice / --el-speed: the cached cues, so the cue times are those of the
video). Every cue of the other language (--lang, the second texts of
NARRATION) starts with its original, or right after the previous one when that
is still speaking; when it is longer than the time to the next original cue,
it is sped up (ffmpeg atempo, at most MAX_TEMPO), and the rest of the delay is
caught up in the pauses that follow. The AY
sound of the run is mixed in as in mkyoutube. The result: the video with its
first audio track (English), the dubbed one (Czech) and both subtitles
(English from the video's .en.srt, Czech timed to the dubbed voice), tagged.
"""
import argparse
import array
import os
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkyoutube as my                                  # noqa: E402
from mkvideo import RATE, ay_render                     # noqa: E402

GAP = 0.25                          # s kept free before the next cue
MAX_TEMPO = 1.25                    # at most this much faster (then it starts later)


def fit(smp, slot, tmp):
    """samples -> sped up (atempo) to at most slot samples"""
    if len(smp) <= slot or slot <= 0:
        return smp, 1.0
    t = min(MAX_TEMPO, len(smp) / slot)
    a, b = tmp + ".in.wav", tmp + ".out.wav"
    with wave.open(a, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(smp.tobytes())
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", a,
                           "-af", "atempo=%.4f" % t, "-ar", str(RATE), "-ac", "1", b])
    with wave.open(b) as w:
        out = array.array("h", w.readframes(w.getnframes()))
    os.remove(a)
    os.remove(b)
    return out, t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", default="yt_scenario2")
    ap.add_argument("--video", required=True)
    ap.add_argument("--el-voice", required=True, help="the voice of the video (cue times)")
    ap.add_argument("--el-speed", type=float, default=1.0)
    ap.add_argument("--dub-voice", required=True)
    ap.add_argument("--lang", choices=("cs",), default="cs")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    my.load_scenario(a.scenario)
    my.EL.update(speed=a.el_speed)
    cache = os.path.join(my.SCR, "youtube", "voice")

    # ---- the run of the video, without video: cue times + AY sound
    my.LANG = 0
    tour = my.Tour("el:" + a.el_voice, 1.0, None, True, os.path.join(my.SCR, "youtube", "sd.img"))
    z = my.TourRecorder(os.path.join(my.SCR, "reset128.sna"), 1, None)
    z.glide_px, z.badge = my.GLIDE_PX, my.BADGE
    z.ur4 = True
    tour.play(z)
    n = tour.now()
    print("run: %d video frames (%s), %d cues" % (n, my.ts(n / 50, False), len(tour.cues)))

    # ---- the dubbed cues at the same starts
    my.LANG = 1
    per = RATE // 50
    gap = int(GAP * 50)
    cues, starts = [], [c[1] for c in tour.cues] + [n]
    free, worst = 0, 0                  # the frame after the previous dubbed cue
    for i, (cid, start, _) in enumerate(tour.cues):
        smp = my.tts(my.NARRATION[cid][1], "el:" + a.dub_voice, cache, 1.0)
        st = max(start, free)
        slot = (starts[i + 1] - st - gap) * per
        smp, t = fit(smp, slot, os.path.join(cache, "fit"))
        free = st + (len(smp) + per - 1) // per + gap
        late = st - start
        worst = max(worst, late)
        if t > 1.0 or late:
            print("  %-8s %s x%.2f%s" % (cid, my.ts(start / 50, False), t,
                                        ", %.1f s late" % (late / 50) if late else ""))
        cues.append((cid, st, smp))
    if free > n:
        print("the dub ends %.1f s after the video" % ((free - n) / 50))
    print("largest delay: %.1f s" % (worst / 50))

    base = os.path.splitext(a.out or a.video)[0]
    ayw, vw, mix = base + ".dub.ay.wav", base + ".dub.voice.wav", base + ".dub.m4a"
    for path, data in ((ayw, ay_render(z.ay_log, z.rec_frames, z.tape_audio)),
                       (vw, my.voice_track(cues, n).tobytes())):
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(data)
    fc = ("[0:a]volume=0.35[ay];[1:a]asplit[sc][v];"
          "[ay][sc]sidechaincompress=threshold=0.02:ratio=8:attack=30:release=400[d];"
          "[d][v]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]")
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", ayw, "-i", vw,
                           "-filter_complex", fc, "-map", "[a]", "-c:a", "aac", "-b:a", "192k",
                           "-ar", str(RATE), mix])
    # subtitles: English as the video's, Czech timed to the dubbed voice
    vbase = os.path.splitext(a.video)[0]
    en_srt = vbase + ".en.srt"
    cs_srt = base + "_" + a.lang + "dub.cs.srt"
    my.write_srt(cs_srt, cues, 1)
    out = a.out or base + "_" + a.lang + "dub.mp4"
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", a.video, "-i", mix,
                           "-i", en_srt, "-i", cs_srt,
                           "-map", "0:v", "-map", "0:a", "-map", "1:a", "-map", "2", "-map", "3",
                           "-c:v", "copy", "-c:a", "copy", "-c:s", "mov_text",
                           "-metadata:s:a:0", "language=eng", "-metadata:s:a:0", "title=English",
                           "-metadata:s:a:1", "language=ces", "-metadata:s:a:1", "title=Čeština",
                           "-metadata:s:s:0", "language=eng", "-metadata:s:s:0", "title=English",
                           "-metadata:s:s:1", "language=ces", "-metadata:s:s:1", "title=Čeština",
                           "-disposition:a:0", "default", "-disposition:a:1", "0",
                           "-disposition:s:0", "0", "-disposition:s:1", "0",
                           "-movflags", "+faststart", out])
    for p in (ayw, vw):
        os.remove(p)
    print("written:", out, "and", mix)


if __name__ == "__main__":
    main()
