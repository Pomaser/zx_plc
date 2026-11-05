#!/usr/bin/env python3
"""Screenshots for docs/MANUAL.md, made with the headless emulator.

    .scratch/venv/bin/python tools/docshots.py [name ...]

Each scenario starts the snapshot zxplc.sna (the demo project, POU list) and
plays a zxrun.py key script; the screen is saved to docs/img/<name>.png
(without the border). Without arguments all scenarios are made.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "img")

D = "k:CS+6 w4 "                              # cursor down
CLR = "k:CS+0 w2 " * 6                        # clear a prompt
MENU = "w30 k:CS+SPACE w5 "                   # open the menu bar
IL = "w30 " + D + "k:ENTER w40 "              # open DEMO_IL
LD = "w30 " + D * 2 + "k:ENTER w40 "          # open DEMO_LD
FBD = "w30 " + D * 3 + "k:ENTER w40 "         # open DEMO_FBD
RUN = "k:CS+1 w10 k:R w10 k:R w80 "           # Run > Run

SHOTS = [
    ("pou_list", "w40"),
    ("menu_file", MENU + "k:F w20"),
    ("menu_pou", MENU + "k:P w20"),
    ("menu_edit", MENU + "k:E w20"),
    ("menu_view", MENU + "k:V w20"),
    ("menu_run", MENU + "k:R w20"),
    ("menu_help", MENU + "k:H w20"),
    ("pou_new", MENU + "k:P w5 k:N w20 t:MOTOR w10"),
    ("pou_lang", MENU + "k:P w5 k:N w20 t:MOTOR w10 k:ENTER w30"),
    ("il_editor", IL + D + D),
    ("ld_editor", LD + D + "k:CS+8 w20"),
    ("ld_picker", LD + D + "k:ENTER w30"),
    ("fbd_editor", FBD + D + "k:CS+8 w4 k:CS+8 w4 k:CS+8 w20"),
    ("fbd_picker", FBD + D + "k:ENTER w30"),
    ("fbd_pv", FBD + D * 6 + "k:CS+8 w4 " * 5 + "k:T w30"),
    ("symbols", MENU + "k:E w5 k:S w60"),
    ("sim_il", IL + RUN + "k:0 w150"),
    ("sim_ld", LD + RUN + "k:4 w60"),
    ("sim_fbd", FBD + RUN + "k:B w5 k:0 w5 k:2 w60"),
    ("sim_watch", FBD + RUN + "k:B w5 k:0 w5 k:2 w30 k:W w40 " + D + D + "k:F w40"),
    ("xref", IL + D + "k:SS+X w60"),
    ("add_watch", LD + D + "k:SS+W w40"),
    ("undo_none", "w30 k:SS+U w30"),
    ("file_save", MENU + "k:F w5 k:S w20"),
    ("help_controls", MENU + "k:H w5 k:C w30"),
    ("help_about", MENU + "k:H w5 k:A w30"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    py = os.path.join(ROOT, ".scratch", "venv", "bin", "python")
    if not os.path.exists(py):
        py = sys.executable
    want = set(sys.argv[1:])
    for name, script in SHOTS:
        if want and name not in want:
            continue
        path = os.path.join(OUT, name)
        subprocess.run([py, os.path.join(ROOT, "tools", "zxrun.py"),
                        os.path.join(ROOT, "zxplc.sna"), "-f", "30", "--noborder",
                        "-s", script + " shot:" + path],
                       check=True, stdout=subprocess.DEVNULL)
        print("docs/img/%s.png" % name)


if __name__ == "__main__":
    main()
