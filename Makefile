# ZX-PLC build
# PYTHON must have the "z80" package (pip install z80) for headless tests;
# a local venv in .scratch/venv is used automatically if it exists
PYTHON ?= $(if $(wildcard .scratch/venv/bin/python),.scratch/venv/bin/python,python3)
SRC := main.asm $(wildcard src/*.asm)

all: zxplc.sna

zxplc.sna: $(SRC)
	sjasmplus --nologo --fullpath --sym=zxplc.sym main.asm

zxplc_test.sna: $(SRC)
	sjasmplus --nologo --fullpath -DTEST main.asm

# run the test build headless and check the result (TEST_RES = 0x5B00)
test: zxplc_test.sna
	@$(PYTHON) tools/zxrun.py zxplc_test.sna -f 100 --peek 5B00:3 | tee .test.out
	@grep -q "^.. 00 A5" .test.out && echo "TESTS OK" || (echo "TESTS FAILED"; exit 1)

run: zxplc.sna
	fuse zxplc.sna &

run-test: zxplc_test.sna
	fuse zxplc_test.sna &

clean:
	rm -f *.sna *.sym *.lst .test.out

.PHONY: all test run run-test clean
