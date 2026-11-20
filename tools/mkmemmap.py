#!/usr/bin/env python3
"""The memory map of ZX-PLC as an SVG infographic, from the symbols of the
build (zxplc.sym), so it can be redrawn after code changes.

    python3 tools/mkmemmap.py [zxplc.sym] [docs/img/memory_map.svg]

Left: the 64 KB address space of the Z80. Middle: the fixed code (core) in
detail. Right: the six RAM banks that are paged in at 0xC000 (banks 5 and 2
are the fixed memory at 0x4000 / 0x8000). Module sizes come from the first
label of each source file, as main.asm includes them.
"""
import os
import re
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

# ---- palette: the ZX Spectrum colours, normal (D7) and BRIGHT (FF); one colour per kind of
#      content, neighbouring modules of the same kind alternate normal / bright
C = {
    "sys":   ("#0000D7", "#0000FF"),   # ROM, screen, system: blue
    "core":  ("#D700D7", "#FF00FF"),   # fixed code: magenta
    "edit":  ("#00D7D7", "#00FFFF"),   # editors and screens: cyan
    "comp":  ("#00D700", "#00FF00"),   # compilers, VM, runtime: green
    "tool":  ("#D7D700", "#FFFF00"),   # tools and services: yellow
    "data":  ("#D7D7D7", "#FFFFFF"),   # buffers, work areas: white
    "proj":  ("#D70000", "#FF0000"),   # the user's project and its copies: red
    "im2":   ("#000000", "#000000"),   # IM2 vector table + JP isr: black (outlined)
}
INK = {"sys": "#FFFFFF", "core": "#FFFFFF", "proj": "#FFFFFF", "im2": "#FFFFFF"}   # else black
BG, PANEL, LINE, TEXT, MUTED = "#D7D7D7", "#000000", "#000000", "#000000", "#3A3A3A"
PTEXT, PMUTED = "#FFFFFF", "#A8A8A8"           # text on the black panels
SANS = "Inter, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif"
MONO = "'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace"


def symbols(path):
    s = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 3 and p[1] == "EQU":
            s[p[0].rstrip(":")] = int(p[2], 16)
    return s


def first_label(src, sym):
    txt = open(os.path.join(ROOT, src)).read()
    for lb in re.findall(r"^([a-z_][A-Za-z0-9_]*):", txt, re.M):
        if lb in sym:
            return sym[lb]
    return None


def kb(n):
    return "%d B" % n if n < 1000 else "%.1f KB" % (n / 1024)


def layout(sym):
    """the regions: (start, end, label, kind) per column"""
    f = lambda name: first_label(name, sym)
    IM2 = 0xFDFD
    space = [
        (0x0000, 0x4000, "ROM (48K BASIC)", "sys"),
        (0x4000, 0x5B00, "Screen", "sys"),
        (0x5B00, 0x5E00, "System vars, stack", "data"),
        (0x5E00, sym["CORE_END"], "Core code", "core"),
        (sym["CORE_END"], 0x8A00, None, "free"),
        (0x8A00, 0x9000, "Runtime data", "data"),
        (0x9000, 0xC000, "Project (12 KB)", "proj"),
        (0xC000, 0x10000, "Paged RAM bank", "edit"),
    ]
    core = [
        (0x5E00, f("src/ui.asm"), "Main loop, keyboard, sound", "core"),
        (f("src/ui.asm"), f("src/project.asm"), "Windows, menus, status bar", "core"),
        (f("src/project.asm"), f("src/font6.asm"), "Project, operands, symbols", "core"),
        (f("src/font6.asm"), sym["CORE_END"], "Font 6×8", "core"),
        (sym["CORE_END"], 0x8A00, "free", "free"),
        (0x8A00, 0x9000, "Runtime: I/O, timers, buffers", "data"),
    ]
    banks = [
        ("Bank 0", "EDIT", [
            (0xC000, f("src/sym_edit.asm"), "IL editor", "edit"),
            (f("src/sym_edit.asm"), f("src/ld_edit.asm"), "Symbol editor", "edit"),
            (f("src/ld_edit.asm"), f("src/st_view.asm"), "LD editor", "edit"),
            (f("src/st_view.asm"), f("src/sim.asm"), "ST view", "edit"),
            (f("src/sim.asm"), sym["EDIT_END"], "Simulation screen", "edit"),
            (sym["EDIT_END"], IM2, "free", "free")]),
        ("Bank 1", "DATA", [
            (0xC000, f("src/il_check.asm"), "Popup save area", "data"),
            (f("src/il_check.asm"), f("src/globals.asm"), "IL line check", "edit"),
            (f("src/globals.asm"), sym["DATA_END"], "Global declarations", "edit"),
            (sym["clip_buf"], IM2, "Clipboard", "data")]),
        ("Bank 3", "DEMO", [
            (0xC000, f("src/clip.asm"), "Watch, xref, help", "tool"),
            (f("src/clip.asm"), f("src/wexpr.asm"), "Mark, copy, paste", "tool"),
            (f("src/wexpr.asm"), f("src/mouse.asm"), "Word expressions", "tool"),
            (f("src/mouse.asm"), f("src/trend.asm"), "Mouse, UR-4 I/O", "tool"),
            (f("src/trend.asm"), f("src/complete.asm"), "Trend charts", "tool"),
            (f("src/complete.asm"), sym["demo_unpack"], "Completion, palette", "tool"),
            (sym["demo_unpack"], sym["DEMO_END"], "Demo project (ZX0)", "proj"),
            (sym["DEMO_END"], IM2, "free", "free")]),
        ("Bank 4", "RUN", [
            (0xC000, f("src/vm.asm"), "IL compiler", "comp"),
            (f("src/vm.asm"), f("src/ld_comp.asm"), "Virtual machine", "comp"),
            (f("src/ld_comp.asm"), f("src/st_comp.asm"), "LD + FBD compilers", "comp"),
            (f("src/st_comp.asm"), f("src/pou.asm"), "ST compiler", "comp"),
            (f("src/pou.asm"), f("src/tape.asm"), "POU list", "edit"),
            (f("src/tape.asm"), sym["RUN_END"], "Tape, SD card", "tool"),
            (sym["RUN_END"], 0xF000, "free", "free"),
            (0xF000, 0xF800, "Bytecode", "data"),
            (0xF800, 0xFC00, "ST tokenizer", "comp"),
            (0xFC00, IM2, "Globals, ST locals", "data")]),
        ("Bank 6", "FBD", [
            (0xC000, f("src/st_edit.asm"), "FBD editor", "edit"),
            (f("src/st_edit.asm"), sym["FBD_END"], "ST editor", "edit"),
            (sym["FBD_END"], IM2, "free", "free")]),
        ("Bank 7", "SPARE", [
            (0xC000, sym["UM_REC"], "Undo / redo", "tool"),
            (sym["UM_REC"], IM2, "History + project copy", "proj")]),
    ]
    for _, _, segs in banks:
        segs.append((IM2, 0x10000, "IM2", "im2"))
    return space, core, banks


def main():
    sym_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "zxplc.sym")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "img", "memory_map.svg")
    sym = symbols(sym_path)
    version = open(os.path.join(ROOT, "VERSION")).read().strip()
    space, core, banks = layout(sym)

    W, H = 1700, 1030
    TOP, HGT = 170, 720                     # the bars
    o = []
    a = o.append
    a('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
      'font-family="%s">' % (W, H, W, H, SANS))
    a('<defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
      'patternTransform="rotate(45)"><rect width="6" height="6" fill="#000000"/>'
      '<line x1="0" y1="0" x2="0" y2="6" stroke="#4A4A4A" stroke-width="1.6"/></pattern></defs>')
    a('<rect width="%d" height="%d" fill="%s"/>' % (W, H, BG))

    # ---- title
    a('<text x="56" y="62" font-size="30" font-weight="700" fill="%s" letter-spacing="-0.3">'
      'ZX-PLC memory map</text>' % TEXT)
    a('<text x="56" y="92" font-size="15" fill="%s">ZX Spectrum 128K · 64 KB address space of the Z80 '
      '· eight 16 KB RAM banks, paged in at C000 through port 7FFD · build %s</text>' % (MUTED, escape(version)))

    last = {"kind": None, "b": 1}

    def column():
        last["kind"], last["b"] = None, 1

    def seg(x, w, y0, y1, label, kind, size, mono_addr=None, small=False):
        h = y1 - y0
        if kind == last["kind"]:                # the same kind again: the other brightness
            last["b"] ^= 1
        else:
            last["kind"], last["b"] = kind, 0
        fill = "url(#hatch)" if kind == "free" else C[kind][last["b"]]
        stroke = ' stroke="#4A4A4A" stroke-width="1"' if kind == "free" else \
            ' stroke="#6A6A6A" stroke-width="1"' if kind == "im2" else ""
        a('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"%s/>' % (x, y0, w, max(h, 0.8), fill, stroke))
        if kind not in ("free", "im2") and h > 0.8:
            a('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#000000" stroke-opacity="0.6" '
              'stroke-width="1"/>' % (x, y0, x + w, y0))
        if not label:
            return
        col = PMUTED if kind == "free" else INK.get(kind, "#000000")
        if h >= 30:
            a('<text x="%.1f" y="%.1f" font-size="12.5" font-weight="600" fill="%s">%s</text>'
              % (x + 9, y0 + h / 2 - 2, col, escape(label)))
            a('<text x="%.1f" y="%.1f" font-size="11" fill="%s" fill-opacity="0.85" font-family="%s">%s</text>'
              % (x + 9, y0 + h / 2 + 13, col, MONO, size))
        elif h >= 13:
            a('<text x="%.1f" y="%.1f" font-size="11" font-weight="600" fill="%s">%s'
              '<tspan font-weight="400" fill-opacity="0.85" font-family="%s">  %s</tspan></text>'
              % (x + 9, y0 + h / 2 + 4, col, escape(label), MONO, size))

    def panel(x, y, w, h):
        a('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="10" fill="%s" stroke="%s"/>'
          % (x, y, w, h, PANEL, LINE))

    def head(x, y, title, sub):
        a('<text x="%.1f" y="%.1f" font-size="15" font-weight="700" fill="%s">%s</text>' % (x, y - 14, PTEXT, title))
        a('<text x="%.1f" y="%.1f" font-size="11.5" fill="%s" font-family="%s">%s</text>' % (x, y + 3, PMUTED, MONO, sub))

    # ---- column 1: the 64 KB address space
    X1, W1 = 120, 150
    panel(40, TOP - 66, 300, HGT + 90)
    head(56, TOP - 22, "Address space", "0000–FFFF")
    ys = lambda adr: TOP + adr / 0x10000 * HGT
    column()
    for s0, s1, lab, kind in space:
        seg(X1, W1, ys(s0), ys(s1), lab, kind, kb(s1 - s0))
    for adr in (0x0000, 0x4000, 0x5E00, 0x8A00, 0x9000, 0xC000, 0x10000):
        y = ys(adr)
        a('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>' % (X1 - 8, y, X1, y, PMUTED))
        a('<text x="%d" y="%.1f" font-size="11" text-anchor="end" fill="%s" font-family="%s">%s</text>'
          % (X1 - 12, y + 4, PMUTED, MONO, "%04X" % min(adr, 0xFFFF)))
    # brackets: which RAM bank is behind each 16 KB of the address space
    for a0, a1, lab in ((0x0000, 0x4000, "ROM"), (0x4000, 0x8000, "bank 5"), (0x8000, 0xC000, "bank 2"),
                        (0xC000, 0x10000, "banks 0–7")):
        y0, y1 = ys(a0) + 3, ys(a1) - 3
        bx = X1 + W1 + 10
        a('<path d="M%d %.1f h5 V%.1f h-5" fill="none" stroke="%s"/>' % (bx, y0, y1, PMUTED))
        a('<text transform="translate(%d %.1f) rotate(-90)" font-size="10.5" text-anchor="middle" '
          'letter-spacing="0.6" fill="%s">%s</text>' % (bx + 18, (y0 + y1) / 2, PMUTED, lab.upper()))

    # ---- column 2: the core in detail
    X2, W2 = 420, 190
    panel(380, TOP - 66, 270, HGT + 90)
    head(396, TOP - 22, "Fixed code and data", "5E00–8FFF")
    c0, c1 = 0x5E00, 0x9000
    yc = lambda adr: TOP + (adr - c0) / (c1 - c0) * HGT
    column()
    for s0, s1, lab, kind in core:
        seg(X2, W2, yc(s0), yc(s1), lab, kind, kb(s1 - s0))
    for adr in (0x5E00, 0x8A00, 0x9000):
        y = yc(adr)
        a('<text x="%d" y="%.1f" font-size="11" text-anchor="end" fill="%s" font-family="%s">%04X</text>'
          % (X2 - 8, y + 4, PMUTED, MONO, adr))
    # zoom lines from column 1
    for adr_a, adr_b in ((0x5E00, 0x5E00), (0x9000, 0x9000)):
        a('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-dasharray="3 3"/>'
          % (X1 + W1 + 34, ys(adr_a), X2 - 44, yc(adr_b), "#808080"))

    # ---- columns 3: the paged banks
    X3, W3, G3 = 700, 144, 14
    panel(670, TOP - 66, 6 * (W3 + G3) + 28, HGT + 90)
    yb = lambda adr: TOP + (adr - 0xC000) / 0x4000 * HGT
    for i, (bank, name, segs) in enumerate(banks):
        x = X3 + i * (W3 + G3)
        head(x, TOP - 22, "%s · %s" % (bank, name), "C000–FFFF")
        column()
        for s0, s1, lab, kind in segs:
            seg(x, W3, yb(s0), yb(s1), lab if kind != "im2" else None, kind, kb(s1 - s0))

    # ---- legend and notes
    ly = TOP + HGT + 64
    items = [("sys", "System"), ("core", "Fixed code"), ("edit", "Editors, screens"),
             ("comp", "Compilers, VM"), ("tool", "Tools, services"), ("data", "Buffers, data"),
             ("proj", "Project data"), ("im2", "IM2 vectors"), ("free", "Free")]
    x = 56
    for kind, lab in items:
        if kind == "free":
            a('<rect x="%d" y="%d" width="14" height="14" fill="url(#hatch)" stroke="#4A4A4A"/>' % (x, ly - 11))
        else:                                   # normal | bright
            a('<rect x="%d" y="%d" width="7" height="14" fill="%s" stroke="#000000" stroke-width="0.6"/>'
              '<rect x="%d" y="%d" width="7" height="14" fill="%s" stroke="#000000" stroke-width="0.6"/>'
              % (x, ly - 11, C[kind][0], x + 7, ly - 11, C[kind][1]))
        a('<text x="%d" y="%d" font-size="13" fill="%s">%s</text>' % (x + 21, ly, TEXT, lab))
        x += 34 + 7.3 * len(lab)
    free = "Free: core %s · bank 0 %s · bank 4 %s · bank 6 %s · bank 3 %s" % (
        kb(0x8A00 - sym["CORE_END"]), kb(0xFDFD - sym["EDIT_END"]), kb(0xF000 - sym["RUN_END"]),
        kb(0xFDFD - sym["FBD_END"]), kb(0xFDFD - sym["DEMO_END"]))
    a('<text x="56" y="%d" font-size="12.5" fill="%s">%s. Every paged bank keeps the IM2 vector table '
      'and JP isr at FDFD; calls between banks go through BCALL in the fixed code.</text>' % (ly + 30, MUTED, free))
    a('</svg>')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write("\n".join(o) + "\n")
    print("written:", out)


if __name__ == "__main__":
    main()
