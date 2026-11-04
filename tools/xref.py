#!/usr/bin/env python3
"""Cross-module label references of the ZX-PLC sources.

xref.py                  -> module -> module reference matrix (labels per pair)
xref.py --check MAP      -> MAP = "module:bank,..." ; reports references from a
                            module to a label in another *paged* bank that are
                            not made through BCALL/BJP (core = bank 'c')
"""
import re, sys, os, collections
kinds = {}

SRC = "src"
LBL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(:|\s+EQU\b|\s+equ\b|\s*=)")
TOK = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

def strip(line):
    out, q = [], None
    for ch in line:
        if q:
            if ch == q: q = None
            continue
        if ch in "\"'":
            q = ch; continue
        if ch == ";": break
        out.append(ch)
    return "".join(out)

def load(files):
    defs, uses = {}, collections.defaultdict(list)
    global kinds
    for f in files:
        mod = os.path.basename(f)[:-4]
        for n, line in enumerate(open(f, errors="ignore"), 1):
            s = strip(line)
            m = LBL.match(s)
            if m:
                if m.group(2) == ":":       # EQU constants have no bank
                    rest = s[m.end():].split()
                    kind = "data" if rest and rest[0].lower() in ("db","dw","ds","defb","defw","defs","dz","byte","word") else "code"
                    if not rest:            # label on its own line: look at the next one
                        kind = "?"
                    defs[m.group(1)] = mod
                    kinds[m.group(1)] = kind
                s = s[m.end():]
            uses[mod].append((n, s))
    return defs, uses

def main():
    files = sorted(os.path.join(SRC, f) for f in os.listdir(SRC) if f.endswith(".asm"))
    files.append("main.asm")
    defs, uses = load(files)
    if len(sys.argv) > 2 and sys.argv[1] == "--check":
        bank = dict(x.split(":") for x in sys.argv[2].split(","))
        bad = 0
        for mod, lines in uses.items():
            mb = bank.get(mod, "c")
            for n, s in lines:
                if re.search(r"\b(BCALL|BJP|BANKOF)\b", s):
                    continue
                for t in TOK.findall(s):
                    d = defs.get(t)
                    if not d or d == mod: continue
                    db = bank.get(d, "c")
                    if db != "c" and db != mb:
                        print(f"{mod}.asm:{n}: {kinds.get(t)} {t} ({d}, bank {db}) from bank {mb}")
                        bad += 1
        sys.exit(1 if bad else 0)
    pairs = collections.defaultdict(set)
    for mod, lines in uses.items():
        for n, s in lines:
            for t in TOK.findall(s):
                d = defs.get(t)
                if d and d != mod and d != "defs":
                    pairs[(mod, d)].add(t)
    for (a, b), ts in sorted(pairs.items()):
        print(f"{a:9} -> {b:9} {' '.join(sorted(ts))}")

main()
