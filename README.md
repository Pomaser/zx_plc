# ZX-PLC

Editor a simulátor PLC programů podle IEC 61131-3 (IL, LD, FBD) pro **ZX Spectrum 48K**,
napsaný v assembleru Z80. Program se nenahrává do žádného skutečného PLC, spouští se v simulaci.
Projekty jde ukládat na kazetu.

## Sestavení

```
make            # -> zxplc.sna  (spustit ve Fuse: make run)
make test       # testovací build + headless běh (vyžaduje Python balíček z80)
```

Vyžaduje `sjasmplus` (≥ 1.18). Headless testy: `pip install z80`, pak `make test PYTHON=/cesta/k/python`.

## Ovládání (stav: fáze 1)

| Klávesa | Funkce |
|---|---|
| BREAK (CS+SPACE) nebo EDIT (CS+1) | horní menu (POU / EDIT / RUN / FILE), ←/→ výběr, ENTER |
| ↑ ↓ (CS+7 / CS+6) | pohyb v seznamu POU |
| ENTER / E | otevřít POU v editoru |
| N / R / D / L | nová POU / přejmenovat / smazat / změnit jazyk (jen prázdná POU) |

* `MAIN` existuje vždy a jako jediná se volá scan‑cyklem; ostatní POU se volají z MAIN.
* Max. 8 POU, jméno max. 8 znaků (A–Z, 0–9, _), nesmí kolidovat s adresou ani FB instancí.

## Operandy

| Oblast | IEC | Krátce | Rozsah |
|---|---|---|---|
| Vstupy | `%IX0.0` | `I0.0` | 0.0–0.7 |
| Výstupy | `%QX0.0` | `Q0.0` | 0.0–0.7 |
| Bitová paměť | `%MX5` | `M5` | 0–63 |
| Slova INT | `%MW3` | `MW3` | 0–15 |
| Konstanty | `TRUE`, `FALSE`, `-123`, `T#1s500ms`, `T#2m` | | |
| FB instance | `TON0`…`TON3`, `TOF`, `TP`, `CTU`, `CTD`, `R_TRIG`, `F_TRIG`, `SR`, `RS` | | |
| Členy FB | `TON0.Q`, `CTU1.CV`, `R_TRIG2.CLK` … | | |

Časová báze je 20 ms (1 snímek).

## Struktura

* `main.asm` – vstupní bod, přerušení, přepínání obrazovek
* `src/` – moduly (screen, keyboard, ui, project, operand, pou, app, tests)
* `tools/zxrun.py` – headless emulátor pro testy a screenshoty, `tools/fixjr.py` – převod JR mimo rozsah na JP

## Mapa paměti

```
6000–BFFF  kód      C000–EFFF  projekt (ukládá se na kazetu)
F000–F7FF  bytekód  F800–FDFC  runtime   FDFD–FF00  IM2
```
