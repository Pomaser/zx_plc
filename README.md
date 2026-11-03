# ZX-PLC

A PLC program editor and simulator following IEC 61131-3 (IL, LD, FBD) for the **ZX Spectrum 48K**,
written in Z80 assembler. Programs are not downloaded to any real PLC; they run in a built-in simulation.
Projects can be saved to tape.

## Building

```
make            # -> zxplc.sna  (run in Fuse: make run)
make test       # test build + headless run (requires the Python package z80)
```

Requires `sjasmplus` (>= 1.18). Headless tests need the Python package `z80`:
`python3 -m venv .scratch/venv && .scratch/venv/bin/pip install z80` (used automatically by `make test`),
or `make test PYTHON=/path/to/python`. The `.scratch/` folder is ignored by Git.

## Controls (status: phase 1)

The top menu bar (`File  POU  Edit  Run  Help`) uses a proportional 6x8 font, black on white;
the selection is shown by inversion and the bar is separated from the content by a line. Each title opens a drop-down submenu.
The bottom status bar shows the current POU (left) and free project memory (right).
Messages, questions, name input and language choice appear in popup windows.
Keys are read in the interrupt into an 8-key queue, so typing ahead is not lost.

| Key | Function |
|---|---|
| BREAK (CS+SPACE) or EDIT (CS+1) | open the menu / close it |
| LEFT / RIGHT (CS+5 / CS+8) | previous / next submenu |
| UP / DOWN (CS+7 / CS+6) | move in a submenu or in the POU list |
| ENTER | execute the item / open the selected POU in the editor |
| letters | first letter of a title or item (hotkey); N / R / D / L in the POU list |

| Menu | Items |
|---|---|
| File | New project, Load..., Save... |
| POU | Manage, New..., Rename..., Language..., Delete |
| Edit | Edit POU, Symbols, Insert line, Delete line |
| Run | Run/Stop, Step, Reset |
| Help | Controls, About |

* `MAIN` always exists and is the only POU called by the scan cycle; other POUs are called from MAIN.
* Max. 8 POUs, name max. 8 chars (A-Z, 0-9, _), must not clash with an address or FB instance.

## IL editor

Opened by ENTER on an IL POU (or Edit > Edit POU).

* Left: 3-digit line numbers with leading zeros (black on bright white), separator line, then the program; one line = one character row.
* Type the instruction (lower case is fine) and press SPACE: a known mnemonic is converted to upper case
  and the cursor jumps to the operand column. Instructions are dark blue, operands black.
* `//` at the start of a line makes a comment line (dark green). `NAME:` makes a label line.
* ENTER stores the line (validated and normalised to the IEC form, e.g. `i0.3` -> `%IX0.3`); at the very
  start of a line it moves the line down (empty line above), otherwise it opens a
  new line below; UP/DOWN store and move; DELETE on an empty line removes it.
* Edit menu: Insert line, Delete line. Errors are shown in a popup and the cursor stays on the line.

Supported instructions: `LD LDN ST STN S R AND ANDN OR ORN XOR XORN NOT ADD SUB MUL DIV MOD
GT GE EQ NE LE LT JMP JMPC JMPCN CAL CALC CALCN RET RETC RETCN )`, with the `(` modifier where IEC allows
it (`AND(`, `ADD(` ...). FB calls: `CAL TON0(IN:=%IX0.0, PT:=T#2s)`; POU calls: `CAL PUMP`.

## Symbols

Edit > Symbols opens a fixed list of all addresses (%IX0.0-0.7, %QX0.0-0.7, %MX0-63). Each address can get
a symbolic name (max. 8 chars, identifier, dark blue) and a comment (max. 30 chars, dark green); the editor
works like the IL editor (SPACE jumps from the name to the comment, ENTER/UP/DOWN store the row).

Symbols can be typed in IL instead of addresses (`LD Start`); the program stores the address and the
editor and the simulation show the symbol, so renaming a symbol changes it everywhere. Names must be unique
and must not clash with addresses, keywords, FB instances, IL instructions or POU names.

## Simulation (Run)

Run > Run/Stop (or R on the Run screen) compiles all POUs to bytecode and runs MAIN once per frame (20 ms).
Compile errors are reported with the POU name and line number.

* Upper part: listing of the monitored IL POU (the current POU, or MAIN) with the live value of each
  operand on the right (`TRUE` inverted, `FALSE` - both dark magenta -, numbers; PT/ET of timers as
  `T#...`). UP/DOWN scroll.
* Lower part: input LEDs %IX0.0-0.7 (green) and output LEDs %QX0.0-0.7 (red).
* Keys: `1`-`8` toggle inputs, SYMBOL SHIFT + `1`-`8` push button (input on while held),
  `R` run/stop, `S` single scan, `E` reset all data. The status bar shows RUN / STOP.
* Standard FBs: TON, TOF, TP, CTU, CTD, R_TRIG, F_TRIG, SR, RS. Calls of other POUs: max. depth 8.
  A watchdog stops a scan that executes more than 30000 instructions.
* LD and FBD POUs are not compiled yet (a call of such a POU does nothing).

## Operands

| Area | IEC | Short | Range |
|---|---|---|---|
| Inputs | `%IX0.0` | `I0.0` | 0.0-0.7 |
| Outputs | `%QX0.0` | `Q0.0` | 0.0-0.7 |
| Bit memory | `%MX5` | `M5` | 0-63 |
| INT words | `%MW3` | `MW3` | 0-15 |
| Constants | `TRUE`, `FALSE`, `-123`, `T#1s500ms`, `T#2m` | | |
| FB instances | `TON0`...`TON3`, `TOF`, `TP`, `CTU`, `CTD`, `R_TRIG`, `F_TRIG`, `SR`, `RS` | | |
| FB members | `TON0.Q`, `CTU1.CV`, `R_TRIG2.CLK` ... | | |

The time base is 20 ms (one frame).

## Structure

* `main.asm` - entry point, interrupts, screen switching
* `src/` - modules (screen, keyboard, ui, ptext, menu, status, project, operand, pou, app, il_parse, il_edit,
  il_comp (IL -> bytecode), vm (interpreter + standard FBs), sim (Run screen), symbols, sym_edit, tests)
* `src/font6.asm` - generated from `tools/font6.txt` by `tools/mkfont.py` (edit the .txt, then run the script)
* `tools/zxrun.py` - headless emulator for tests and screenshots, `tools/fixjr.py` - converts out-of-range JR to JP

## Memory map

```
6000-BFFF  code      C000-EFFF  project (saved to tape)
F000-F7FF  bytecode  F800-FDFC  runtime   FDFD-FF00  IM2
```
