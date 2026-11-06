# ZX-PLC build
# PYTHON must have the "z80" package (pip install z80) for headless tests;
# a local venv in .scratch/venv is used automatically if it exists
PYTHON ?= $(if $(wildcard .scratch/venv/bin/python),.scratch/venv/bin/python,python3)
SRC := main.asm $(wildcard src/*.asm)

all: zxplc.sna

zxplc.sna: $(SRC) src/demo_proj.bin
	sjasmplus --nologo --fullpath --sym=zxplc.sym main.asm

# demo project: built by the program itself (src/demo.asm), saved as an image
zxplc_mkdemo.sna: $(SRC)
	sjasmplus --nologo --fullpath -DMKDEMO main.asm

src/demo_proj.bin: zxplc_mkdemo.sna
	$(PYTHON) tools/mkdemo.py zxplc_mkdemo.sna $@

zxplc_test1.sna: $(SRC) src/demo_proj.bin
	sjasmplus --nologo --fullpath -DTEST -DTPART=1 main.asm

zxplc_test2.sna: $(SRC) src/demo_proj.bin
	sjasmplus --nologo --fullpath -DTEST -DTPART=2 main.asm

# run both test builds headless and check the results (TEST_RES = 0x5B00)
test: zxplc_test1.sna zxplc_test2.sna
	@for t in 1 2; do $(PYTHON) tools/zxrun.py zxplc_test$$t.sna -f 150 --peek 5B00:3 | tee .test.out; \
	  grep -q "^.. 00 A5" .test.out || { echo "TESTS FAILED (part $$t)"; exit 1; }; done; echo "TESTS OK"

run: zxplc.sna
	fuse zxplc.sna &

# tape image for a real ZX Spectrum 128K (BASIC + machine code loader)
zxplc.tap: zxplc.sna tools/mktap.py img/zxplc_load.scr
	python3 tools/mktap.py zxplc.sna zxplc.sym $@ img/zxplc_load.scr

tap: zxplc.tap

# screenshots for docs/MANUAL.md (docs/img/*.png)
docs: zxplc.sna
	$(PYTHON) tools/docshots.py

run-test: zxplc_test1.sna
	fuse zxplc_test1.sna &

clean:
	rm -f *.sna *.sym *.lst *.tap .test.out

.PHONY: all test docs tap run run-test clean
