; ============================================================
; ur4.asm - UR-4 interface (TESLA, 8255): physical I/O (DEMO bank)
; ============================================================
; Ports: PA 0x1F, PB 0x3F, PC 0x5F, control word 0x7F. Options > UR-4 I/O
; switches it on (ur_toggle; only when the interface answers). Then the
; simulation ORs PA into %IX0 and PB into %IX1 (sim_inputs) and writes
; %QX0 to PC while it runs (ur_out in sim.asm; 0 in STOP and outside).
; ============================================================

UR_PA   EQU 0x1F
UR_PB   EQU 0x3F
UR_PC   EQU 0x5F
UR_CWR  EQU 0x7F
UR_CFG  EQU 0x92                ; PA in, PB in, PC out (mode 0)
UR_INS  EQU 0x9B                ; all in (the state after a reset)

; ---- ur_toggle: Options > UR-4 I/O
ur_toggle:
        ld a,(ur_on)
        or a
        jr z,.on
        xor a                   ; off: outputs off, all ports inputs
        ld (ur_on),a
        out (UR_PC),a
        ld a,UR_INS
        out (UR_CWR),a
        ret
.on:    ld a,UR_CFG             ; PC is an output: its latch reads back
        out (UR_CWR),a
        ld a,0x55
        call .chk
        jr nz,.no
        ld a,0xAA
        call .chk
        jr nz,.no
        xor a
        out (UR_PC),a
        inc a
        ld (ur_on),a
        ret
.no:    ld a,UR_INS             ; (in case something is there)
        out (UR_CWR),a
        ld hl,txt_ur_none
        jp ui_error
.chk:   ld b,a
        out (UR_PC),a
        in a,(UR_PC)
        cp b
        ret

txt_ur_none: db "No UR-4 interface",0
