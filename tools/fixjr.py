#!/usr/bin/env python3
"""Run sjasmplus and convert out-of-range JR to JP in reported lines."""
import subprocess, re, sys, os
args = sys.argv[1:] or ["main.asm"]
for _ in range(10):
    out = subprocess.run(["sjasmplus", "--nologo", "--msg=war", "--color=off", "--fullpath"] + args, capture_output=True, text=True)
    txt = out.stdout + out.stderr
    hits = re.findall(r"^(\S+?)\((\d+)\): error: \[JR\] Target out of range", txt, re.M)
    if not hits:
        # show every error/warning plus the code size line
        for line in txt.splitlines():
            if "error" in line or "warning" in line or "Code end" in line:
                print(line)
        break
    for f, ln in hits:
        path = f if os.path.exists(f) else os.path.join("src", os.path.basename(f))
        lines = open(path).read().split("\n")
        i = int(ln) - 1
        lines[i] = re.sub(r"\bjr\b", "jp", lines[i], count=1)
        open(path, "w").write("\n".join(lines))
        print("fixed", path, ln)
