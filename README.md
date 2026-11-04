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

The top menu bar (`File  POU  Edit  View  Run  Help`) uses a proportional 6x8 font, black on white;
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
| View | Symbols, Addresses (how operands are shown in the IL editor and the simulation) |
| Run | Run, Stop, Step, Reset |
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

Instruction lines are stored in binary form (instruction code + 2-3 bytes per operand, FB call parameters
included), comments and labels as text; the editor turns them back into text for display.

Supported instructions: `LD LDN ST STN S R AND ANDN OR ORN XOR XORN NOT ADD SUB MUL DIV MOD
GT GE EQ NE LE LT JMP JMPC JMPCN CAL CALC CALCN RET RETC RETCN )`, with the `(` modifier where IEC allows
it (`AND(`, `ADD(` ...). FB calls: `CAL TON0(IN:=%IX0.0, PT:=T#2s)`; POU calls: `CAL PUMP`.

## LD editor

Opened by ENTER on an LD POU. A row is: left rail, 9 positions for contacts / wires, the coil position on the
right, right rail. Every element takes 3 character cells: the outer cells hold the leads and the symbol
(`-| |-`, `-( )-`), the middle cell its content and, in the simulation, its state (green = active).
The operand label above the element follows View (symbol clipped to the element width, or `I0.0`, `Q0.1`...);
the full symbol name and comment of the selected element are shown in the status bar.

ENTER on a position opens the element picker: a window listing the elements as their LD symbols
(contacts, wire and vertical link on positions 0-8, coils on the coil position); choose with UP/DOWN and
ENTER, then type the operand (choosing "Vertical link" toggles the link at the right edge of the position).
The current element is preselected, so ENTER on an element also changes its type or operand.
The letter keys below work as shortcuts both in the editor and in the picker.

| Key | Contact positions 0-8 | Coil position 9 |
|---|---|---|
| `C` | normally open contact `-| |-` | coil `-( )-` |
| `/` (SS+V) | normally closed contact `-|/|-` | negated coil `-(/)-` |
| `P` / `N` | rising / falling edge contact | |
| `S` / `R` | | set / reset coil |
| `-` (SS+J) | wire | |

Arrows move, DELETE clears the position, `V` toggles a vertical
link at the right edge of the position (parallel branches), Edit > Insert line / Delete line insert or delete
a row. Placing an element fills the empty positions to its left with wires (up to the previous element, the
rail or an incoming link). Rungs (rows joined by links) are compiled column by column; P/N contacts keep their
edge memory (max. 32 per project).

## Symbols

Edit > Symbols opens the list of defined symbols, sorted by address, with an empty row at the end for a new
one. Each row: line number (like the IL editor), symbolic name (max. 8 chars, identifier, dark blue),
physical address (`%IX0.0`, `i0.0`, `%QX0.1`, `m5`, `ton1`, `ctu0` ... I, Q, M and FB instances, black) and comment (max. 30 chars,
dark green). SPACE moves name -> address -> comment, ENTER/UP/DOWN store the row (the list is re-sorted);
ENTER at the very start of a row opens an empty row above it (a new symbol is sorted in when stored),
clearing the name and the comment removes the symbol, Edit > Delete line deletes it too.

Symbols can be typed in IL instead of addresses (`LD Start`, `CAL Delay1`, `LD Delay1.Q` for an FB instance); the program stores the address and the
editor and the simulation show the symbol, so renaming a symbol changes it everywhere (View > Addresses shows
the addresses instead). In the IL editor the status bar shows the comment of the operand on the current line after the POU name. Names must be unique
and must not clash with addresses, keywords, FB instances, IL instructions or POU names.

## Simulation (Run)

Run > Run (or R on the Run screen) compiles all POUs to bytecode and runs MAIN once per frame (20 ms).
Compile errors are reported with the POU name and line number.

* Upper part: listing of the monitored IL or LD POU (the current POU, or MAIN) with the live value of each
  operand on the right (`TRUE` inverted, `FALSE` - both dark magenta -, numbers; PT/ET of timers as
  `T#...`). UP/DOWN scroll.
* Lower part: input LEDs %IX0.0-0.7 (green) and output LEDs %QX0.0-0.7 (red).
* Keys: `1`-`8` toggle inputs, SYMBOL SHIFT + `1`-`8` push button (input on while held),
  `R` run/stop, `S` single scan, `E` reset all data. The status bar shows RUN / STOP.
* Standard FBs: TON, TOF, TP, CTU, CTD, R_TRIG, F_TRIG, SR, RS. Calls of other POUs: max. depth 8.
  A watchdog stops a scan that executes more than 30000 instructions.
* FBD POUs are not compiled yet (a call of such a POU does nothing).

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
6000-CFFF  code      D000-EFFF  project, 8 KB (saved to tape)
F000-F7FF  bytecode  F800-FDFC  runtime   FDFD-FF00  IM2
```
