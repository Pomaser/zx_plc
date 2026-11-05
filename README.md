# ZX-PLC

A PLC program editor and simulator following IEC 61131-3 (IL, LD, FBD) for the **ZX Spectrum 128K** (also +2 / +2A / +3),
written in Z80 assembler. Programs are not downloaded to any real PLC; they run in a built-in simulation.
Projects can be saved to tape.

## Demo project

The program starts with a demo project (also File > Open demo); File > New project starts an empty one.

* **MAIN** calls the three demo POUs.
* **DEMO_IL** - a traffic light as a step sequence: step flags `S_Off`, `S_Red`, `S_RedYel`, `S_Green`,
  `S_Yellow` (S0.0-S0.4), one TON per step (`T_Red` ...), lights `Red` / `Yellow` / `Green` (Q0.0-Q0.2).
  In the simulation `0` (TL_Start) starts it, `1` (TL_Stop) switches it off.
* **DEMO_LD** - a pump with self-holding (`4` Start, `5` Stop as a normally closed contact, Q0.4), a fan
  running on 5 s after the pump (TOF, Q0.5), a fault memory set by the rising edge of `6` (Fault) and
  reset by `7` (Ack), and a fault lamp blinking with two TP pulse timers (Q0.6).
* **DEMO_FBD** - uses only I/O byte 1 (press `B` in the simulation, then `0`-`4`):
  - an inlet valve with nested gates: `Valve` = `Auto` AND (`Manual` OR (`LowLvl` AND NOT `HighLvl`))
    with a 2 s run-on (TOF) (I1.0-I1.3 -> Q1.0),
  - an overflow horn: the rising edge of `HighLvl` (RT) sets an SR flip-flop, `HornAck` (I1.4) resets it
    (Q1.1).
* Each demo has its own I/O: DEMO_IL I0.0-0.1 / Q0.0-0.2, DEMO_LD I0.4-0.7 / Q0.4-0.6, DEMO_FBD byte 1.
* A complete symbol table for all inputs, outputs, flags, steps and timers.

## Saving to tape

File > Save asks for a tape name (max. 10 characters), then waits for a key to start ("Start the tape
recorder..."). The project is saved as a standard CODE file: a header (name, length, start 0x9000) and a
data block with the project memory, in the normal ROM speed and format, so it can be copied and checked
with any tape tool. SPACE (BREAK) interrupts the saving.

File > Load (after "Discard current project?") waits for the tape: other files are skipped, the first
CODE file with start 0x9000 that fits the project area is loaded and checked (signature, length). The
current project is kept in bank 7 meanwhile and comes back when loading fails, the data is not a ZX-PLC
project or SPACE interrupts it.

`tools/zxrun.py --tap file.tap` decodes what the program saved into a .tap file; the script command
`play:file.tap` plays a .tap file into the EAR input.

## Sound

The AY chip of the 128K plays a short soft click (noise with a fast envelope decay) for every key and a quiet two-note warning on input
errors (unknown instruction or operand, invalid name, ...). Both are played by the interrupt, so the
program never waits for them; View > Sound switches them off.

## Building

```
make            # -> zxplc.sna  (run in Fuse: make run)
make test       # two test builds (TPART=1, 2) + headless runs (requires the Python package z80)
```

Requires `sjasmplus` (>= 1.18). Headless tests need the Python package `z80`:
`python3 -m venv .scratch/venv && .scratch/venv/bin/pip install z80` (used automatically by `make test`),
or `make test PYTHON=/path/to/python`. The `.scratch/` folder is ignored by Git.

## Controls (status: phase 1)

The top menu bar (`File  POU  Edit  View  Run  Help`) uses a proportional 6x8 font, black on white;
the selection is shown by inversion and the bar is separated from the content by a line. Each title opens a drop-down submenu.
The name and language of the current POU are shown at the right end of the menu bar.
The bottom status bar shows, in the editors, the symbol name of the current operand (inverted) and its comment
(left) and free project memory (right); in the simulation the keys (left) and RUN / STOP (right).
Messages, questions, name input and language choice appear in popup windows.
Keys are read in the interrupt into an 8-key queue, so typing ahead is not lost.

| Key | Function |
|---|---|
| BREAK (CS+SPACE) or EDIT (CS+1) | open the menu / close it |
| LEFT / RIGHT (CS+5 / CS+8) | previous / next submenu |
| UP / DOWN (CS+7 / CS+6) | move in a submenu or in the POU list |
| SS + LEFT / RIGHT (CS+SS+5 / 8) | start / end of the line (IL: instruction / end of operand, symbols: name / end of comment, LD: first position / coil) |
| SS + UP / DOWN (CS+SS+7 / 6) | one screen up / down in the editors, first / last POU in the POU list |
| SS + ENTER | IL editor: new empty line below (also with the cursor at the start of a line), LD editor: start of the next row |
| ENTER | execute the item / open the selected POU in the editor |
| letters | first letter of a title or item (hotkey); N / R / D / L in the POU list |

| Menu | Items |
|---|---|
| File | New project, Open demo, Load..., Save... |
| POU | Manage, New..., Rename/Comment..., Language..., Delete |
| Edit | Edit POU, Symbols, Insert line, Delete line |
| View | Symbols, Addresses (how operands are shown in the IL editor and the simulation), Sound (on/off) |
| Run | Run, Stop, Step, Reset |
| Help | Controls, About |

* `MAIN` always exists and is the only POU called by the scan cycle; other POUs are called from MAIN.
* Max. 8 POUs, name max. 8 chars (A-Z, 0-9, _), must not clash with an address or FB instance.
* Every POU can have a comment (max. 20 chars), asked for when the POU is created, shown in the POU list.

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
(`-| |-`, `-( )-`), the middle cell its content and, in the simulation, its state (black on bright green = active, the same colour as TRUE in the IL and FBD simulation).
The operand label above the element follows View (symbol clipped to the element width, or `I0.0`, `Q0.1`...);
the full symbol name and comment of the selected element are shown in the status bar.

ENTER on a position opens the element picker: a window listing the elements as their LD symbols
(contacts, wire and vertical link on positions 0-8, coils on the coil position); choose with UP/DOWN and
ENTER, then type the operand (choosing "Vertical link" toggles the link at the right edge of the position).
The current element is preselected, so ENTER on an element also changes its type or operand.
After a new element is placed on an empty position the cursor moves on to the next position, SS+RIGHT
jumps to the coil position and SS+ENTER to the start of the next row, so a rung is entered without moving
the cursor by hand.
The letter keys below work as shortcuts both in the editor and in the picker.

| Key | Contact positions 0-8 | Coil position 9 |
|---|---|---|
| `C` | normally open contact `-| |-` | coil `-( )-` |
| `/` (SS+V) | normally closed contact `-|/|-` | negated coil `-(/)-` |
| `P` / `N` | rising / falling edge contact | |
| `S` / `R` | | set / reset coil |
| `-` (SS+J) | wire | |
| `T` / `F` / `U` | TON / TOF / TP timer box (`T` on an existing timer box: edit only its PT) | |

Timer boxes `[TON]`, `[TOF]`, `[TP]` sit on a contact position: the power from the left is the input IN, the
output Q powers the rest of the row. The box asks for the instance (`TON1` or its symbol) and the preset time
PT (`T#4s`); the instance is shown above the box, PT in the status bar, and in the simulation the middle cell
shows Q.

Network comments: type `//` at the start of an empty row (position 0) and then the text; the row becomes a dark
green comment above the network. ENTER, LEFT, RIGHT, DELETE or typing on a comment row edit it in place (an empty comment is removed). A single `/` followed by
another key still places a normally closed contact (the key starts its operand).

Arrows move. DELETE removes the element and the rest of the row moves one position to the left (with
links at or right of it in this row or the row above it only clears the position). SYMBOL SHIFT + `I`
inserts an element (chosen in the picker) in front of the cursor element: the whole rung moves one position
to the right (position 8 must be free or a wire), branches get a wire in the new column where needed. `V`
toggles a vertical link at the right edge of the position (parallel branches); a new branch gets an empty
row inserted below when the row below is a comment or another rung. Edit > Insert line / Delete line insert
or delete a row. Placing an element fills the empty positions to its left with wires (up to the previous element, the
rail or an incoming link). Rungs (rows joined by links) are compiled column by column; P/N contacts keep their
edge memory (max. 32 per project).

## FBD editor

Opened by ENTER on an FBD POU. The grid, cursor keys, SS+arrows, SS+ENTER, `//` comments, DELETE and the
status bar work as in the LD editor. Positions 0-8 hold inputs, wires, blocks and outputs, position 9
only outputs. Input and output names are written on the signal line (`Start--`, `-Pump`); an input name
may reach into empty cells on its left, an output name into empty cells on its right.
ENTER opens the picker (shortcut keys in brackets):

| Positions 0-8 | Position 9 |
|---|---|
| input (I), negated input (N, the `o` is drawn at the block input it leads to), wire (-) | output (Q), negated output (N, the `o` is drawn at the output of the block it comes from) |
| AND (A), OR (O), XOR (X) with 2-4 inputs, NOT (!) | |
| SR (S), RS (R), RT rising edge (P), RF falling edge (E) - an FB instance | |
| output (Q), negated output (W) - e.g. right behind a block | |
| TON (T), TOF (F), TP (U) - two rows: IN and the PT input (`T#4s--PT` on the left of the second row); ENTER or `T` on the PT input or `T` on the timer edits PT | |

A block with h inputs covers h rows: input k comes from the left on the k-th row, the output leaves on the
top row to the right, so blocks can be chained (e.g. an OR one row lower feeding the second input of an
AND). The cursor stands only on the cells that make sense around a block: its inputs on the left, the
block itself and its output on the right - cells inside a block and the empty space behind its lower rows
are skipped. Outputs are not offered on a block input (a cell whose signal goes, through wires, straight into a
block). An output or a wire needs a signal coming from the left (an element, possibly over empty
cells that are then filled with wires). Placing a block needs free cells below it; DELETE on a block
removes the whole block. A block placed on an input inserts itself behind it: the network moves one
position to the right, the input feeds the first input of the new block and the cursor goes to the
second input. If a block does not fit, it is not placed ("No room for the block"). Wires are
added automatically between a new block or output and the element on its left. In the simulation inputs,
outputs (their names) and FB blocks are coloured black on bright green when their variable is TRUE (a negation is shown
only by the `o`); logic blocks (AND, OR, XOR, NOT) are coloured inside when their result is TRUE.

## Symbols

Edit > Symbols opens the list of defined symbols, sorted by address, with an empty row at the end for a new
one. Each row: line number (like the IL editor), symbolic name (max. 8 chars, identifier, dark blue),
physical address (`%IX0.0`, `i0.0`, `%QX0.1`, `m0.5`, `ton1`, `ctu0`, `s0.1` ... I, Q, M, step flags and FB instances, black) and comment (max. 30 chars,
dark green). SPACE moves name -> address -> comment, ENTER/UP/DOWN store the row (the list is re-sorted);
ENTER at the very start of a row opens an empty row above it (a new symbol is sorted in when stored),
clearing the name and the comment removes the symbol, Edit > Delete line deletes it too.

Symbols can be typed in IL instead of addresses (`LD Start`, `CAL Delay1`, `LD Delay1.Q` for an FB instance); the program stores the address and the
editor and the simulation show the address (default View > Addresses) or, with View > Symbols, the symbol, so
renaming a symbol changes it everywhere. In the IL editor the status bar shows the symbol and comment of the operand on the current line. Names must be unique
and must not clash with addresses, keywords, FB instances, IL instructions or POU names.

## Simulation (Run)

Run > Run (or R on the Run screen) compiles all POUs to bytecode and runs MAIN once per frame (20 ms).
Compile errors are reported with the POU name and line number.

* Upper part: listing of the monitored IL or LD POU (the current POU, or MAIN) with the live value of each
  operand on the right (`TRUE` black on bright green, `FALSE`, numbers; PT/ET of timers as
  `T#...`; a `CAL` of a timer shows its running ET). UP/DOWN scroll.
* Lower part: input LEDs %IX0.0-1.7 (green) and output LEDs %QX0.0-1.7 (red), one row each, full width:
  bit numbers 0-7 of byte 0, then 0-7 of byte 1; the input byte the keys act on has a line over it.
* Keys: `0`-`7` toggle inputs %IXb.0-b.7 of the selected byte b (key = bit number), `B` selects byte 0 / 1,
  SYMBOL SHIFT + `0`-`7` push button (input on while held),
  `R` run/stop, `S` single scan, `E` reset all data. The status bar shows these keys and RUN / STOP.
* Standard FBs: TON, TOF, TP, CTU, CTD, R_TRIG (instances `RT0`-`RT3`), F_TRIG (`RF0`-`RF3`), SR, RS. Calls of other POUs: max. depth 8.
  A watchdog stops a scan that executes more than 30000 instructions.
* FBD POUs are not compiled yet (a call of such a POU does nothing).

## Operands

| Area | IEC | Short | Range |
|---|---|---|---|
| Inputs | `%IX0.0` | `I0.0` | 0.0-1.7 |
| Outputs | `%QX0.0` | `Q0.0` | 0.0-1.7 |
| Bit memory | `%MX0.5` | `M0.5` | 0.0-7.7 |
| Step flags | `%SX0.2` | `S0.2` | 0.0-7.7 |
| INT words | `%MW3` | `MW3` | 0-15 |
| System flags (read only) | `%SM6` | `SM6` | 0-7 |
| Constants | `TRUE`, `FALSE`, `-123`, `T#1s500ms`, `T#2m` | | |
| FB instances | `TON0`...`TON3`, `TOF`, `TP`, `CTU`, `CTD`, `RT` (R_TRIG), `RF` (F_TRIG), `SR`, `RS` | | |
| FB members | `TON0.Q`, `CTU1.CV`, `RT2.CLK` ... | | |

System flags, written before every scan: `SM0` first scan after Run / Reset, `SM1` always TRUE, `SM2`
always FALSE, clock pulses (50 % duty) `SM3` 10 Hz, `SM4` 5 Hz, `SM5` 2 Hz, `SM6` 1 Hz, `SM7` 0.5 Hz.
They can only be read (contacts, inputs, LD / AND ...).

The time base is 20 ms (one frame).

### Step flags

`S0`-`S7` are 8 step bytes for step sequences: in each byte only one bit can be set. Writing TRUE to a
bit (`ST`, `S`, an LD coil or set coil) clears the other 7 bits of its byte; writing FALSE clears only that
bit. All step flags are cleared by Reset.

```
LD   S0.0      // step 0: waiting for start
AND  %IX0.0
S    S0.1      // -> step 1 (S0.0 goes off automatically)
LD   S0.1
ST   %QX0.0    // step 1: pump on
AND  %IX0.1
S    S0.2      // -> step 2
```

## Structure

* `main.asm` - entry point, interrupts, screen switching, placement of the modules in memory banks
* `src/sound.asm` - AY sound effects (key click, error)
* `src/bank.asm` - bank paging (`BCALL` calls a routine in another bank), `src/shared.asm` - data and
  routines used from more than one bank
* `src/` - modules (screen, keyboard, ui, ptext, menu, status, project, operand, pou, app, il_parse, il_edit,
  il_comp (IL -> bytecode), vm (interpreter + standard FBs), sim (Run screen), symbols, sym_edit, tests)
* `src/font6.asm` - generated from `tools/font6.txt` by `tools/mkfont.py` (edit the .txt, then run the script)
* `src/demo.asm` - builds the demo project (`-DMKDEMO` build), `tools/mkdemo.py` - runs it and saves the
  project image `src/demo_proj.bin` (`make` does both when the sources change)
* `tools/zxrun.py` - headless 48K/128K emulator for tests and screenshots (`--ay` lists AY writes), `tools/fixjr.py` - converts
  out-of-range JR to JP, `tools/xref.py --check MAP` - reports references across banks not made through `BCALL`

## Memory map

```
fixed     5B00-5DFF  test results, stack
          5E00-89FF  core: main loop, ISR, bank switching, screen, keyboard, ui, text, menu,
                     status bar, project access, operands, IL parser, symbols, shared data, font
          8A00-8FFF  runtime data
          9000-BFFF  project, 12 KB (saved to tape)
C000-FFFF paged banks (each with the IM2 table at FDFD-FF00):
          bank 0  EDIT  IL / LD / symbol editors, simulation screen (tests in test builds)
          bank 4  RUN   IL, LD and FBD compilers, VM, bytecode (F000-F7FF), POU list, tape save/load
          bank 1  DATA  cells saved under popup windows
          bank 3  DEMO  demo project image (src/demo_proj.bin)
          bank 6  FBD   FBD editor
          bank 7  SPARE copy of the project while loading from tape
```
The build prints the free space of the core and of each bank.
