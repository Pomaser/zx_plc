# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ZX-PLC is a PLC editor and simulator (IEC 61131-3: IL, LD, FBD) for the ZX Spectrum 128K. It is written
in Z80 assembler for sjasmplus. Programs only run in the built-in simulation (optionally with real I/O
through a UR-4 interface); projects are saved and loaded on tape or on an SD card (divMMC with esxDOS).
There is also a browser version (GitHub Pages, JSSpeccy). README.md and docs/MANUAL.md describe every
editor and key for users.

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
  - The test builds and the demo builder (`-DMKDEMO`) leave out `src/sim.asm` (`WITH_SIM` in main.asm,
    `scr_run` is a stub there) to make room in the EDIT bank.
- `make run`: runs the build in Fuse.
- `make tap`: `zxplc.tap` (tools/mktap.py: BASIC, then a machine code loader that copies itself over the
  BASIC line (0x5CCB). It loads the loading screen `img/zxplc_load.scr` (its source `img/zxplc_load.json` is
  for the SEIE editor), every used bank and the fixed part from the snapshot, all packed with ZX0
  (`tools/zx0`, vendored C packer built by make, plus `dzx0_standard.asm`), rebuilds the IM2 stubs, runs the
  picture effect, then jumps to START). The loader must stay below 0x5DE0; mktap.py checks it.
- `tools/mkvideo.py`: a demo video (`.scratch/zxplc_demo.mp4`, ffmpeg, ~2:20) of a small project typed in
  from scratch, then symbols, the simulation in IL / LD / FBD, watch and force, the trend page (drawn
  live with `x:1`) and Help > About at the end. `x:N` fast-forwards (every N-th frame), `hold:N` shows
  results at normal speed, `go!:` / `cl!:` move and click slowly in menus. The SCENARIO in the script is
  played into `zxplc.sna` by the zxrun emulator (keys, smooth mouse), every frame is recorded and the AY
  writes become the sound. `--shots DIR` only saves the
  checkpoint PNGs (to tune the scenario after UI changes), `--filter sharp/soft/hq/xbr` the pixel look
  (default soft). The video starts with the end of the tape loading of `zxplc.tap` (border stripes,
  tape sound, loader effect) from `.scratch/reset128.sna` (a 128K at the 128 menu); `--no-intro` skips
  it. The application is not changed for it.
- Releases (`gh release create vX.Y`, assets `zxplc.tap`, `zxplc.sna`, and `zxplc_demo.mp4` when the UI
  changed): the release number is in the file `VERSION` (no newline; Help > About includes it with
  `INCBIN`). Steps: set `VERSION`; `make`, `make tap`, `make test`; load the tape in zxrun from
  `.scratch/reset128.sna` (`k:ENTER`, `play:zxplc.tap`, ~16000 frames) and check About; regenerate
  `docs/img/help_about.png` (`tools/docshots.py help_about`); render the video (its last frame is the
  About box); commit "Version X.Y", push, release with notes ("Changes since ..."). The release starts
  the Pages deployment (see `make web`); check that the web tape equals the new one.
- `make web`: copies the tape and the loading screen into `web/` (the browser version: `web/index.html` +
  JSSpeccy 3, vendored in `web/jsspeccy/`, GPL-3, rebuilt from source with `web/jsspeccy/zxplc.patch`:
  a Kempston mouse in the wasm core + the PC pointer position mapped to the counters (option
  `kempstonMouse`, no pointer lock: Esc stays BREAK), and the standard
  0xD7 / 0xFF palette of zxrun; `web/jsspeccy/README.md` has the build steps). Test it with `python3 -m http.server -d web`. The
  emulator runs with `sandbox`, its File / Machine menus and Open file / Start tape buttons hidden. The
  page maps extra PC keys (Esc = BREAK, Tab = EDIT, symbols = SS + key; JSSpeccy listens on its own
  container, so synthetic key events go to the focused element). `.github/workflows/pages.yml` publishes
  `web/` with the `zxplc.tap` of the latest release to GitHub Pages on every release (and on changes in
  `web/`). The github-pages environment only lets `main` deploy, so a release run just starts the
  workflow again on `main` (`gh workflow run`; separate concurrency groups, so it is not cancelled).
  The page loads `zxplc.tap?<time>.tap` (past the browser cache; JSSpeccy needs the `.tap` ending).
- `make docs`: regenerates the screenshots of `docs/MANUAL.md` (`tools/docshots.py`: one zxrun key script
  per image, `--noborder`). Update the manual and the scripts when the UI changes.
- `python3 tools/fixjr.py main.asm`: builds and converts every out-of-range `jr` to `jp` in the source,
  then prints the remaining errors. Run it after edits that make code longer.
- `python3 tools/xref.py --check "pou:R,app:E,il_edit:E,sym_edit:E,ld_edit:E,sim:E,demo:E,il_comp:R,vm:R,ld_comp:R,fbd_comp:R,tape:R,tests:E,fbd_edit:F,tools:D,clip:D,wexpr:D,mouse:D,undo:S,ur4:D,trend:D,sd:R"`:
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
  `--peek addr:len` dumps memory, `--mouse` / `--ur4` / `--divmmc` attach those interfaces (see below).
  `Spectrum.bank_bytes(bank, addr, n)` reads paged banks from Python.
  Full redraws take 15–20 frames, so wait long enough before a screenshot.

## Memory architecture (128K)
- **Fixed memory:**
  - 0x5B00 TEST_RES; the stack below 0x5E00.
  - Core code at 0x5E00. The build prints the free space: about 115 B are left. New code goes into
    the banks; the menu tables and texts (src/menu.asm) are core too (the command dispatcher
    `menu_cmd` is in the DEMO bank, tools.asm).
  - RT runtime data at 0x8A00. These are EQUs in `src/vm.asm`: I/Q (2 bytes each, %IX0.0-1.7)/M/MW, FB instances, scratch bits,
    step flags, and the shared buffers `popup_buf`, `st_buf`, `rec_buf`, `il_out`, `cp_text`
    (FMT_BUF).
    The RT area is full (RT_END = PROJ); new runtime data goes into the core (e.g. `RT_SW`, the
    scan time words %SW0-2 = last / max / min, in shared.asm, written by `vm_sw_upd`).
  - The project at 0x9000-0xBFFF (12 KB).
- **Paged banks at 0xC000.** `main.asm` decides which module goes where:
  - EDIT 0: IL, LD and symbol editors, simulation screen, tests (~2.8 KB free).
  - RUN 4: compilers, VM, bytecode at 0xF000, POU list, tape, SD card (`src/sd.asm`). It is uncontended,
    which tape timing needs (~3.6 KB free).
  - DATA 1: the popup save buffer and the clipboard (`clip_buf`, filled by `src/clip.asm`).
  - DEMO 3: `src/tools.asm` (cross references, watch / force page of the simulation, Help texts),
    `src/clip.asm` (mark / copy / cut / paste, called by the editors with `BCALL cl_cmd` / `mk_draw`),
    `src/wexpr.asm`, `src/mouse.asm`, `src/ur4.asm`, `src/trend.asm`, `menu_cmd` / `menu_active` (menu commands, check marks), the About box with twinkling stars and the top-border scroller (`tl_about`, `bd_*`) and the demo image (~3.7 KB free).
  - FBD 6: the FBD editor (~7.5 KB free).
  - SPARE 7: undo / redo (`src/undo.asm`): the code, the history records growing up from `UM_REC`, and
    the shadow copy of the project ending at the IM2 stub. The tape load copies the project to `UM_BAK`
    (= `UM_REC`) and calls `um_reset`.

  Every paged bank carries the IM2 table + `JP isr` (`IM2STUB`); I = 0xFE.
- **Cross-bank calls:** use `BCALL label` (macro in `src/defs.asm`, `bcall_` in `src/bank.asm`).
  AF/BC/DE/HL pass through in both directions.
  - Pointers passed across banks must point to fixed memory.
  - Data shared by two banks lives in `src/shared.asm` (core); the jump target of the cross
    references (xr_jf / xr_jl / xr_jp) too.
  - Calls within one bank, or from a bank into the core, are plain `call`.
- Kempston mouse: `src/mouse.asm` (DEMO bank), state in the RT area (`ms_*`, vm.asm). `kb_get` polls it
  while waiting and returns `K_MOUSE` (position `ms_cx` / `ms_cy`, button `ms_btn`); a click on a menu
  title becomes `K_EDIT` with `ms_menu`. The pointer is hidden before a key is returned. Screens handle
  `K_MOUSE` with `ms_item` / `ms_grid` / `ms_crow` / `ms_pou`. zxrun: `--mouse`, `at:x,y`, `cl:L`.
- Trend page of the simulation (`src/trend.asm`, DEMO bank; sim page 2, key G / Run > Trend): the BOOL
  entries and the timer / counter ET / CV members of the watch list (max 8) are sampled as levels 0-9
  (ET / CV scaled by PT / PV, the word before them in the instance) into one 256-byte ring buffer per
  trace (`tr_buf` + t*256, aligned) by `tr_tick`, called once per simulation loop with the page in A. A loop can take several
  frames, so it adds one sample per `tr_rate` frames passed. 200-pixel chart, scrolled by 8 pixels.
- SD card (`src/sd.asm`, RUN bank):
  - File > Load SD... / Save SD... call `tape_load` / `tape_save` with A = CMD_LOAD_SD / CMD_SAVE_SD,
    which branch to `sd_load` / `sd_save`.
  - esxDOS calls: `ESX` macro (RST 8 + function byte; HL and IX = name / buffer, A = drive `'*'` or
    handle, CF + A = error code). The file is `NAME.PLC` in the current folder with the project bytes
    (as the tape data block). Loading lists `.PLC` files (F_OPENDIR "." / F_READDIR: [attr][name 0]...),
    reads into PROJ and joins `tape_load.chk` (the same checks; `tape_load.rest` restores the old
    project from UM_BAK).
  - Detection before any RST 8 (a divMMC without esxDOS or without automap would crash): `sd_present`
    maps the EEPROM (CONMEM) and looks for the text "ESXDOS", then `sd_probe` calls M_DOSVERSION with
    ERR_SP pointing at its own return: without automap (EEPROM write enabled) RST 8 is the 48K ROM
    error report, which returns there. Otherwise "No esxDOS (divMMC) found". The program always runs
    with the 48K ROM paged (BANK_ROM48), which esxDOS's RST 8 entry expects.
  - Tested with real esxDOS 0.8.9 in zxrun (`tools/divmmc.py`: delayed automap at 0x0000 / 0x0008 /
    0x0038 / 0x0066 / 0x04C6 / 0x0562, the instant 0x3D00-0x3DFF area esxDOS returns from ROM calls
    through, unmap at 0x1FF8-0x1FFF, port 0xE3 RAM banks and EEPROM flashing, an SDHC card in SPI mode
    on an image file): `--divmmc ESXMMC.BIN --sd sd.img --boot .scratch/reset128.sna --boot-frames 300`
    boots esxDOS (it ends in 48K BASIC), then loads the program snapshot; `--divmmc-noauto` = write
    enabled (no automap). esxDOS is not in the repo: `.scratch/esx/` (esxdos.org, esxdos089.zip; card
    image 64 MB, MBR + FAT16: `mkfs.fat --offset 2048`, `mcopy -i sd.img@@1M -s SYS BIN TMP ::/`; for
    Fuse convert it with `raw2hdf`). Fuse automaps only with divMMC write protection on and does not
    keep the EEPROM between runs (only in SZX snapshots, chunk `DMMC`).
- About box border scroller (`bd_*` in src/tools.asm): a 3x5 font, each font pixel one `OUT (C),r`
  (12 T = 24 px) x 4 lines in the top border; 5 row routines of exactly 228 T (128K line) chained by
  RET through `bd_tab` (SP points at it). While About is open the IM2 stub of the DEMO bank jumps to
  `ab_isr` (constant length) and the loop calls `kb_isr` / `snd_isr` after `bd_draw`. The start delay
  (`BD_DLY` / `BD_FINE`) was tuned in JSSpeccy (128K: paper from T 14361); mkvideo draws the border
  per line segment with that timing (BORDER 24).
- UR-4 interface (8255; PA 0x1F, PB 0x3F, PC 0x5F, CWR 0x7F): `src/ur4.asm` (DEMO bank, Options > UR-4 I/O,
  `ur_toggle` with a PC read-back detection), state `ur_on` (vm.asm). `sim_inputs` ORs PA / PB into RT_I,
  `ur_out` (sim.asm) writes %QX0 to PC in RUN, 0 otherwise. zxrun: `--ur4`, `ur:AA,BB`.
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
  - The status bar drops the glyphs' descender line (text 1 px below the separator gap), so `st_print`
    maps g j p q y to short-descender glyphs (130-134, `CH_SDESC`, font6.txt `SDg`...).
  - The POU name is drawn by `menu_pou` at the right end of the menu bar (redrawn only on change).
  - The status bar has two parts: `status_left` with the `st_left` text, and `status_right` (from cell
    `st_rcol`, reset by `screen_begin`; the simulation moves it right for its key hints). Each redraws
    only when its text changes. `st_left` markers: ST_SYM/ST_SYME = inverted symbol name,
    ST_TAB = column. The simulation hints must fit left of cell SM_RCOL (26) and differ per page
    (program / watch: T Trend / trend: W Watch).
  - Menu tables (src/menu.asm): `command, hotkey, label`. The hotkey is not shown; it must match the
    item name (normally its first letter; the user rejected unrelated letters). The open drop-down takes
    item hotkeys first, so an item key equal to a title letter (F P E V R O H) hides that title while
    the menu is open (Run > Reset E, Edit > Paste P, POU > Rename R are accepted). A new item must not
    take R in the File / Edit / View menus (EDIT, R, R starts the program).
  - The menu bar title (`menu_pou`) shows the POU name, or Symbols / Watch / Trend (`mp_alt`).
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
  - An FBD network (`fb_net_rows`, used by moving, closing up and copying) is the rows joined by blocks
    (`fb_join`: a block from row r or above covers row r+1). Rows that are only adjacent are separate.
  - Word compare / compute (`LT_CMP` / `LT_MATH` = `FT_CMP` / `FT_MATH`, defs.asm): 10 / 12 B records with
    the operands `[A area lo hi][op][B area lo hi][D area idx]`. `ld_get` copies them to `ld_gext`,
    `ld_put` writes them back. The operator list, value prompts and expression text are `src/wexpr.asm` (DEMO bank). In LD a compare
    is a contact and compute a coil; in FBD a compare is a 2-row block (A, B on the left of its rows)
    and compute a 2-row block (A, B; the result D drawn in the cell on its right, kept free); their value
    rows are handled like preset cells by `fb_prow`. Placing an FBD block only chooses the operator
    (`wx_opsel`); the values are asked one at a time on their cells (`wx_value`). A block right behind a compute result takes D as its
    A (`fc_link` in fbd_comp.asm, the same when placed).
- **Compile and run:**
  - `il_compile` (RUN) compiles every POU to 5-byte bytecode `[op][mode][arg lo][arg hi][arg3]`:
    IL in two passes, LD and FBD column by column with scratch bits S[row] (src/ld_comp.asm,
    src/fbd_comp.asm share the `lc_*` helpers).
  - The VM (src/vm.asm) runs one scan per frame. Only MAIN runs; it calls the other POUs.
  - `vm_store` keeps only one bit set per step byte (S0-S7).
- **Demo project:** `src/demo.asm` is only assembled with `-DMKDEMO`. It builds the project with the normal
  editor routines; its watch list starts with the traffic light (each timer ET followed by its light),
  shown first on the trend page, and ends with the scan time words %SW0-2 (symbols ScanLast / ScanMax /
  ScanMin). `tools/mkdemo.py` runs that snapshot and saves the project memory to `src/demo_proj.bin`
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
  A new in-place write needs it too. `kb_get` sets `um_arm` on every key / click, so one step = the
  changes after one key. `um_save` keeps a shadow copy; at the next step, undo or redo `um_fin` turns
  the difference shadow -> project into a record (header byte runs + body prefix / suffix diff, both
  sides, so the same record serves undo and redo). The oldest records are dropped when the bank is full.
- The tape routines (`tp_sa_bytes` / `tp_ld_bytes`) are cycle-exact copies of the ROM. Do not add
  instructions inside their timing loops.
