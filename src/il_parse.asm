; ============================================================
; il_parse.asm - IEC 61131-3 Instruction List: mnemonics and line check
; ============================================================
; A line is entered as two fields: mnemonic and operand. il_check
; validates them and builds the normalised text "MNEM<TAB>OPERAND"
; (upper case, IEC operand form) in il_out.
; ============================================================
IC_NONE   EQU 0             ; no operand
IC_READ   EQU 1             ; any readable operand
IC_WRITE  EQU 2             ; writable operand (ST, STN)
IC_SETRES EQU 3             ; writable BOOL operand (S, R)
IC_LABEL  EQU 4             ; jump label
IC_CALL   EQU 5             ; FB instance (+ parameters) or POU
IF_PAREN  EQU 0x80          ; "(" modifier allowed
IL_TAB    EQU 9

; mnemonic table: 6-byte name (0 padded) + class
il_mnems:
        db "LD",0,0,0,0,     IC_READ
        db "LDN",0,0,0,      IC_READ
        db "ST",0,0,0,0,     IC_WRITE
        db "STN",0,0,0,      IC_WRITE
        db "S",0,0,0,0,0,    IC_SETRES
        db "R",0,0,0,0,0,    IC_SETRES
        db "AND",0,0,0,      IC_READ|IF_PAREN
        db "ANDN",0,0,       IC_READ|IF_PAREN
        db "OR",0,0,0,0,     IC_READ|IF_PAREN
        db "ORN",0,0,0,      IC_READ|IF_PAREN
        db "XOR",0,0,0,      IC_READ|IF_PAREN
        db "XORN",0,0,       IC_READ|IF_PAREN
        db "NOT",0,0,0,      IC_NONE
        db "ADD",0,0,0,      IC_READ|IF_PAREN
        db "SUB",0,0,0,      IC_READ|IF_PAREN
        db "MUL",0,0,0,      IC_READ|IF_PAREN
        db "DIV",0,0,0,      IC_READ|IF_PAREN
        db "MOD",0,0,0,      IC_READ|IF_PAREN
        db "GT",0,0,0,0,     IC_READ|IF_PAREN
        db "GE",0,0,0,0,     IC_READ|IF_PAREN
        db "EQ",0,0,0,0,     IC_READ|IF_PAREN
        db "NE",0,0,0,0,     IC_READ|IF_PAREN
        db "LE",0,0,0,0,     IC_READ|IF_PAREN
        db "LT",0,0,0,0,     IC_READ|IF_PAREN
        db "JMP",0,0,0,      IC_LABEL
        db "JMPC",0,0,       IC_LABEL
        db "JMPCN",0,        IC_LABEL
        db "CAL",0,0,0,      IC_CALL
        db "CALC",0,0,       IC_CALL
        db "CALCN",0,        IC_CALL
        db "RET",0,0,0,      IC_NONE
        db "RETC",0,0,       IC_NONE
        db "RETCN",0,        IC_NONE
        db ")",0,0,0,0,0,    IC_NONE
IL_NMNEM EQU ($-il_mnems)/7

; ---- il_mnem_find: HL = mnemonic (0-terminated, any case, optional trailing "(")
;      NC: il_mid = index, il_mclass = class (+IF_PAREN if "(" was used),
;          il_mtmp = canonical upper-case name without "("
;      C:  unknown / "(" not allowed
il_mnem_find:
        ld a,(hl)
        or a
        scf
        ret z
        ld de,il_mtmp
        ld b,7
.cp:    ld a,(hl)
        or a
        jr z,.cpe
        call to_upper
        ld (de),a
        inc hl
        inc de
        djnz .cp
        scf
        ret
.cpe:   ld (de),a
        xor a
        ld (il_paren),a
        dec de
        ld a,(de)
        cp '('
        jr nz,.np
        xor a
        ld (de),a
        inc a
        ld (il_paren),a
.np:    ld hl,il_mnems
        ld c,0
.s:     push hl
        ld de,il_mtmp
        ld b,6
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.ne
        or a
        jr z,.ne                ; both ended -> Z
        inc hl
        inc de
        djnz .cmp
        ld a,(de)               ; 6 chars matched, text must end
        or a
.ne:    pop hl
        jr z,.found
        ld de,7
        add hl,de
        inc c
        ld a,c
        cp IL_NMNEM
        jr c,.s
        scf
        ret
.found: ld de,6
        add hl,de
        ld b,(hl)
        ld a,(il_paren)
        or a
        jr z,.ok
        bit 7,b
        scf
        ret z                   ; "(" not allowed for this mnemonic
.ok:    ld a,b
        and 0x7F
        ld b,a
        ld a,(il_paren)
        rrca                    ; 1 -> 0x80
        or b
        ld (il_mclass),a
        ld a,c
        ld (il_mid),a
        or a
        ret

AR_LBL  EQU 12              ; operand = jump label (name follows); AR_SM = 13
; (il_check, il_check_label: src/il_check.asm, DATA bank)

err_il_unknown: db "Unknown instruction",0
err_il_opreq:   db "Operand required",0
err_il_noop:    db "No operand allowed",0
err_il_op:      db "Invalid operand",0
err_il_wr:      db "Operand is not writable",0
err_il_label:   db "Invalid label",0
err_il_call:    db "Invalid call",0

il_mtmp:   ds 8
il_paren:  db 0
il_mid:    db 0
il_mclass: db 0
il_err:    dw 0
ilc_op:    dw 0
ilc_dst:   dw 0
il_outlen: db 0
ilc_mem:   dw 0
ilc_area:  db 0
ilc_idx:   db 0
ilc_inst:  ds 20
