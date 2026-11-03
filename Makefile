# ZX-PLC build
# PYTHON musí mít balíček "z80" (pip install z80) pro headless testy
PYTHON ?= python3
SRC := main.asm $(wildcard src/*.asm)

all: zxplc.sna

zxplc.sna: $(SRC)
	sjasmplus --nologo --fullpath --sym=zxplc.sym main.asm

zxplc_test.sna: $(SRC)
	sjasmplus --nologo --fullpath -DTEST main.asm

# spustí testovací build headless a ověří výsledek (TEST_RES = 0x5B00)
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
