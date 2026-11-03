# ZX-PLC

A PLC program editor and simulator following IEC 61131-3 (IL, LD, FBD) for the **ZX Spectrum 48K**,
written in Z80 assembler. Programs are not downloaded to any real PLC; they run in a built-in simulation.
Projects can be saved to tape.

## Building

```
make            # -> zxplc.sna  (run in Fuse: make run)
make test       # test build + headless run (requires the Python package z80)
```

Requires `sjasmplus` (>= 1.18). Headless tests: `pip install z80`, then `make test PYTHON=/path/to/python`.

## Controls (status: phase 1)

| Key | Function |
|---|---|
| BREAK (CS+SPACE) or EDIT (CS+1) | top menu (POU / EDIT / RUN / FILE), LEFT/RIGHT select, ENTER |
| UP / DOWN (CS+7 / CS+6) | move in the POU list |
| ENTER / E | open the POU in the editor |
| N / R / D / L | new POU / rename / delete / change language (empty POU only) |

* `MAIN` always exists and is the only POU called by the scan cycle; other POUs are called from MAIN.
* Max. 8 POUs, name max. 8 chars (A-Z, 0-9, _), must not clash with an address or FB instance.

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
* `src/` - modules (screen, keyboard, ui, project, operand, pou, app, tests)
* `tools/zxrun.py` - headless emulator for tests and screenshots, `tools/fixjr.py` - converts out-of-range JR to JP

## Memory map

```
6000-BFFF  code      C000-EFFF  project (saved to tape)
F000-F7FF  bytecode  F800-FDFC  runtime   FDFD-FF00  IM2
```
