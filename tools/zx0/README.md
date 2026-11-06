# ZX0

ZX0 compressor by Einar Saukas (BSD 3-Clause, see LICENSE), from
https://github.com/einar-saukas/ZX0 (commit ecde3a2, Dec 2021), unchanged:

- `zx0.c`, `compress.c`, `optimize.c`, `memory.c`, `zx0.h`: the compressor, built by `make` as `tools/zx0/zx0`
  and used by `tools/mktap.py` to pack the tape blocks.
- `dzx0.c`: the reference decompressor (`tools/zx0/dzx0`), for checks.
- `dzx0_standard.asm`: the Z80 decompressor (68 bytes) that `tools/mktap.py` puts into the tape loader.
