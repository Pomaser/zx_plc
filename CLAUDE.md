# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ZX-PLC is a PLC editor and simulator (IEC 61131-3: IL, LD, FBD) for the ZX Spectrum 128K. It is written
in Z80 assembler for sjasmplus. Programs only run in the built-in simulation; projects are saved and loaded
on tape. See README.md for the user-facing description of every editor and key.

## Conventions
- Code comments, README, commit messages and all other git texts are in English.
- Talk to the user in Czech.
- Temporary files (Python venv, screenshots) go to `.scratch/`, which is git-ignored.

## Commands
- `make`: builds `zxplc.sna` (128K snapshot). It also regenerates `src/demo_proj.bin` when sources change
  (see "Demo project").
- `make test`: builds the two test snapshots (`-DTEST -DTPART=1/2`) and runs them headless.
  - The result is 3 bytes at TEST_RES 0x5B00: pass count, fail count, 0xA5 marker.
  - It prints `TESTS OK`. Failing cases are printed on the emulated screen; take a screenshot to see them.
  - Tests live in `src/tests.asm` and are split by `IF TPART==1/2` because of space in the EDIT bank.
- `make run`: runs the build in Fuse.
- `make tap`: `zxplc.tap` (tools/mktap.py: BASIC, then a machine code loader that copies itself over the
  BASIC line (0x5CCB). It loads the loading screen `img/zxplc_load.scr` (its source `img/zxplc_load.json` is
  for the SEIE editor), every used bank and the fixed part from the snapshot, all packed with ZX0
  (`tools/zx0`, vendored C packer built by make, plus `dzx0_standard.asm`), rebuilds the IM2 stubs, runs the
  picture effect, then jumps to START). The loader must stay below 0x5DE0; mktap.py checks it.
- `make docs`: regenerates the screenshots of `docs/MANUAL.md` (`tools/docshots.py`: one zxrun key script
  per image, `--noborder`). Update the manual and the scripts when the UI changes.
- `python3 tools/fixjr.py main.asm`: builds and converts every out-of-range `jr` to `jp` in the source,
  then prints the remaining errors. Run it after edits that make code longer.
- `python3 tools/xref.py --check "pou:R,app:E,il_edit:E,sym_edit:E,ld_edit:E,sim:E,demo:E,il_comp:R,vm:R,ld_comp:R,fbd_comp:R,tape:R,tests:E,fbd_edit:F,tools:D"`:
  reports labels referenced across paged banks without `BCALL`. Unlisted modules are core. The
  `run_tests` / `demo_build` hits in main.asm are expected. Extend the map when a module moves.
- Headless emulator: `.scratch/venv/bin/python tools/zxrun.py zxplc.sna -f 30 -s "<script>"`
  (needs the `z80` pip package in `.scratch/venv`). Script commands, space separated:
  - `k:CS+6`: press a key combo. CS+5..8 are the arrows, CS+SPACE is BREAK, CS+0 is DELETE,
    `SS+…` is symbol shift.
  - `t:text`: type text; `~` stands for a space.
  - `wN`: run N frames.
  - `shot:path`: screenshot to `path.png`. `-o file.png` saves one at the end.
  - `play:file.tap`: play a tape into EAR.

  Options: `--tap out.tap` decodes what the program saved to tape, `--ay` logs AY writes,
  `--peek addr:len` dumps memory. `Spectrum.bank_bytes(bank, addr, n)` reads paged banks from Python.
  Full redraws take 15–20 frames, so wait long enough before a screenshot.

## Memory architecture (128K)
- **Fixed memory:**
  - 0x5B00 TEST_RES; the stack below 0x5E00.
  - Core code at 0x5E00. The build prints the free space; it is small, keep the core lean.
  - RT runtime data at 0x8A00. These are EQUs in `src/vm.asm`: I/Q (2 bytes each, %IX0.0-1.7)/M/MW, FB instances, scratch bits,
    step flags, and the shared buffers `popup_buf`, `st_buf`, `rec_buf`, `il_out`, `cp_text`
    (FMT_BUF).
  - The project at 0x9000-0xBFFF (12 KB).
- **Paged banks at 0xC000.** `main.asm` decides which module goes where:
  - EDIT 0: IL, LD and symbol editors, simulation screen, tests.
  - RUN 4: compilers, VM, bytecode at 0xF000, POU list, tape. It is uncontended, which tape timing needs.
  - DATA 1: the popup save buffer.
  - DEMO 3: `src/tools.asm` (cross references, watch / force page of the simulation) and the demo image.
  - FBD 6: the FBD editor.
  - SPARE 7: the project copy while loading from tape.

  Every paged bank carries the IM2 table + `JP isr` (`IM2STUB`); I = 0xFE.
- **Cross-bank calls:** use `BCALL label` (macro in `src/defs.asm`, `bcall_` in `src/bank.asm`).
  AF/BC/DE/HL pass through in both directions.
  - Pointers passed across banks must point to fixed memory.
  - Data shared by two banks lives in `src/shared.asm` (core); the jump target of the cross
    references (xr_jf / xr_jl / xr_jp) too.
  - Calls within one bank, or from a bank into the core, are plain `call`.
- `bank_copy` (core) copies with another bank paged in. Core routines that page a bank (`win_open` /
  `win_close` → DATA) restore the caller's bank.

## Program structure
- `main.asm`: START, main loop and ISR (frame counter + `kb_isr` key queue + `snd_isr` AY sounds). The main
  loop calls `BCALL scr_dispatch` (src/app.asm) and gets a menu command back; `cmd_target` picks the next
  screen.
  - Screens return CMD_* codes (defs.asm).
  - `menu_handle` (core, src/menu.asm) runs the top menu.
- **UI:**
  - Text is drawn in a proportional 6x8 font (`src/ptext.asm`, generated by `tools/mkfont.py`
    from `tools/font6.txt`).
  - Popups save the cells under them.
  - The POU name is drawn by `menu_pou` at the right end of the menu bar (redrawn only on change).
  - The status bar has two parts: `status_left` with the `st_left` text, and `status_right` (from cell
    `st_rcol`, reset by `screen_begin`; the simulation moves it right for its key hints). Each redraws
    only when its text changes. `st_left` markers: ST_SYM/ST_SYME = inverted symbol name,
    ST_TAB = column.
- **Project format** (src/project.asm, defs.asm):
  - A header with "ZXPLC" and P_LEN, then a table of 8 POU slots + a hidden slot 8 (the symbol table),
    32 B each: name, language, length, comment, plus a hidden slot 9 (watch list, PROJ_VER 2;
    tape_load converts version 1). Bodies follow in slot order.
  - Grow or shrink a body only with `pou_insert` / `pou_delete`.
- **IL body:** binary line records `[len][kind][...]`. `il_check` (src/il_parse.asm, core) turns text
  into a record, `il_split` (il_edit) turns a record back into text. Operands are encoded by `op_parse` /
  `op_format` (src/operand.asm, core), which also resolve symbols.
- **LD and FBD bodies:**
  - Records `[nrows]` + `[row][pos][type][area][idx]`; timer boxes add `[PT lo][PT hi]`. They are sorted
    by (row, pos), positions 0-9.
  - Comment rows are `[row][0][14][n][text]`.
  - Storage access (`ld_find`, `ld_get`, `ld_rlen`…) is in shared.asm. Writing (`ld_put`, `ld_put_cmt`,
    row insert/delete) is in ld_edit and is called through BCALL by the FBD editor.
  - FBD type codes (FT_*, defs.asm) reuse the LD codes for wire, timers and comment, so the shared
    record-length logic works. Bit 7 means negation in FBD and the vertical link in LD.
  - An FBD block with h inputs covers h rows. Timers have 2 rows (IN, PT).
- **Compile and run:**
  - `il_compile` (RUN) compiles every POU to 5-byte bytecode `[op][mode][arg lo][arg hi][arg3]`:
    IL in two passes, LD and FBD column by column with scratch bits S[row] (src/ld_comp.asm,
    src/fbd_comp.asm share the `lc_*` helpers).
  - The VM (src/vm.asm) runs one scan per frame. Only MAIN runs; it calls the other POUs.
  - `vm_store` keeps only one bit set per step byte (S0-S7).
- **Demo project:** `src/demo.asm` is only assembled with `-DMKDEMO`. It builds the project with the normal
  editor routines. `tools/mkdemo.py` runs that snapshot and saves the project memory to `src/demo_proj.bin`
  (committed), which the normal build includes into bank 3. Edit the demo in `src/demo.asm`, never the
  .bin.

## Pitfalls seen in this code
- Many routines document which registers they keep ("keeps BC, DE, HL"). Clobbered registers are the
  most common bug. Check the callee before relying on a register after a call.
- Local labels (`.x`) belong to the previous global label. Inserting a global label splits a routine and
  breaks its local jumps. Label names are global across all banks, so names like `fb_tp` (VM) can clash.
- Text patches done with Python string replacement must anchor on exact code lines, not on comment
  headers.
- Undo: every change of the project must call `undo_save` (core) first; `pou_insert`, `pou_delete`,
  `ld_put`, `ld_ins_row` / `ld_del_row`, `pou_add`, POU rename / language / comment and `proj_new` do.
  A new in-place write needs it too. The snapshot is in BANK_SPARE (also used by the tape load).
- The tape routines (`tp_sa_bytes` / `tp_ld_bytes`) are cycle-exact copies of the ROM. Do not add
  instructions inside their timing loops.
