; ============================================================
; demo.asm - test program loaded into MAIN at start-up
; (build with -DNODEMO to start with an empty project)
; ============================================================
demo_main:
        db "// Sstart motor",0
        db "LD",9,"%IX0.0",0
        db "ST",9,"%QX0.0",0
        db 0
        db "// Set timer",0
        db "LD",9,"%QX0.0",0
        db "ST",9,"TON1.IN",0
        db "LD",9,"T#4s",0
        db "ST",9,"TON1.PT",0
        db "CAL",9,"TON1",0
        db 0
        db "// Stop motor",0
        db "LD",9,"TON1.Q",0
        db "R",9,"%QX0.0",0
        db 0
        db "// Current time",0
        db "LD",9,"TON1.ET",0
        db "ST",9,"%MW1",0
        db 0xFF
