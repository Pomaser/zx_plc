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

; ---- il_check: HL = mnemonic text, DE = operand text
;      NC: il_out = normalised line;  C: il_err = message
il_check:
        ld (ilc_op),de
        call il_mnem_find
        ld hl,err_il_unknown
        jp c,il_fail
        ld de,il_out
        ld hl,il_mtmp
        call put_str
        ld a,(il_mclass)
        bit 7,a
        jr z,.np
        ld a,'('
        ld (de),a
        inc de
.np:    ld (ilc_tab),de         ; TAB position (removed if no operand)
        ld a,IL_TAB
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld (ilc_dst),de
        ld hl,(ilc_op)
        call skip_sp
        ld (ilc_op),hl
        ld a,(il_mclass)
        and 0x7F
        ld hl,.tab
        jp jump_table
.tab:   dw .none,.read,.write,.setres,.label,.call

.none:  call ilc_empty
        ld hl,err_il_noop
        jp nz,il_fail
        jp ilc_notab

.read:  call ilc_empty
        jr nz,.r1
        ld a,(il_mclass)        ; "AND(" may stand alone
        bit 7,a
        jp nz,ilc_notab
        ld hl,err_il_opreq
        jp il_fail
.r1:    call ilc_operand
        ret c
        and AR_MASK
        cp AR_FBI
        jp z,ilc_badop
        cp AR_POU
        jp z,ilc_badop
        jp ilc_done

.write: call ilc_need
        ret c
        call ilc_operand
        ret c
        and AR_MASK
        cp AR_Q
        jp z,ilc_done
        cp AR_M
        jp z,ilc_done
        cp AR_MW
        jp z,ilc_done
        cp AR_FBM
        jp z,ilc_done
        jp ilc_notwr

.setres:
        call ilc_need
        ret c
        call ilc_operand
        ret c
        and AR_MASK
        cp AR_Q
        jp z,ilc_done
        cp AR_M
        jp z,ilc_done
        cp AR_FBM
        jp z,ilc_done
        jp ilc_notwr

.label: call ilc_need
        ret c
        ld hl,(ilc_op)
        ld de,(ilc_dst)
        call ident_copy
        jr nc,.lok
        ld hl,err_il_label
        jp il_fail
.lok:   ld (ilc_dst),de
        call skip_sp
        ld a,(hl)
        or a
        ld hl,err_il_label
        jp nz,il_fail
        jp ilc_done

.call:  call ilc_need
        ret c
        ld hl,(ilc_op)
        call op_parse
        jp c,ilc_badcall
        ld (ilc_op),hl
        ld (ilc_area),a
        ld (ilc_idx),bc
        ld de,(ilc_dst)
        ld h,0
        ld l,0
        ld b,0
        call op_format          ; instance / POU name
        ld (ilc_dst),de
        ld a,(ilc_area)
        and AR_MASK
        cp AR_POU
        jp z,.cend
        cp AR_FBI
        jp nz,ilc_badcall
        ; remember the instance name for member checks
        ld hl,(ilc_tab)
        inc hl
        ld de,ilc_inst
        call put_str
        ld a,'.'
        ld (de),a
        inc de
        ld (ilc_mem),de
        ld hl,(ilc_op)
        call skip_sp
        ld a,(hl)
        cp '('
        jp nz,.cend
        inc hl
        ld de,(ilc_dst)
        ld a,'('
        ld (de),a
        inc de
        ld (ilc_dst),de
        ; parameters: member := operand {, member := operand} )
.par:   call skip_sp
        ld de,(ilc_mem)
        call ident_copy         ; member name after "INST."
        jp c,ilc_badcall
        xor a
        ld (de),a
        push hl
        ld hl,ilc_inst
        call op_parse           ; must be a member of this instance
        pop hl
        jp c,ilc_badcall
        and AR_MASK
        cp AR_FBM
        jp nz,ilc_badcall
        push hl
        ld hl,(ilc_mem)
        ld de,(ilc_dst)
        call put_str
        ld a,':'
        ld (de),a
        inc de
        ld a,'='
        ld (de),a
        inc de
        ld (ilc_dst),de
        pop hl
        call skip_sp
        ld a,(hl)
        cp ':'
        jp nz,ilc_badcall
        inc hl
        ld a,(hl)
        cp '='
        jp nz,ilc_badcall
        inc hl
        ld (ilc_op),hl
        call ilc_operand_nt     ; operand, no end check
        ret c
        and AR_MASK
        cp AR_FBI
        jp z,ilc_badcall
        cp AR_POU
        jp z,ilc_badcall
        ld hl,(ilc_op)
        call skip_sp
        ld a,(hl)
        inc hl
        ld de,(ilc_dst)
        cp ')'
        jr z,.pend
        cp ','
        jp nz,ilc_badcall
        ld (de),a
        inc de
        ld a,' '
        ld (de),a
        inc de
        ld (ilc_dst),de
        jr .par
.pend:  ld (de),a
        inc de
        ld (ilc_dst),de
        ld (ilc_op),hl
.cend:  ld hl,(ilc_op)
        call skip_sp
        ld a,(hl)
        or a
        jp nz,ilc_badcall
        jp ilc_done

; ---- helpers of il_check
; Z if the operand text is empty
ilc_empty:
        ld hl,(ilc_op)
        ld a,(hl)
        or a
        ret

; C (+ error) if the operand is missing
ilc_need:
        call ilc_empty
        ret nz
        ld hl,err_il_opreq
        jp il_fail

; parse operand at ilc_op, must be followed only by spaces; writes IEC form.
; NC: A = area
ilc_operand:
        call ilc_operand_nt
        ret c
        push af
        ld hl,(ilc_op)
        call skip_sp
        ld a,(hl)
        or a
        jr nz,.bad
        pop af
        ret
.bad:   pop af
        jp ilc_badop

; parse operand at ilc_op (ilc_op advanced), write IEC form at ilc_dst. NC: A = area
ilc_operand_nt:
        ld hl,(ilc_op)
        call op_parse
        jp c,ilc_badop
        ld (ilc_op),hl
        ld (ilc_area),a
        ex de,hl                ; HL = value
        ld de,(ilc_dst)
        ld b,0
        call op_format
        ld (ilc_dst),de
        ld a,(ilc_area)
        or a
        ret

ilc_notab:
        ld hl,(ilc_tab)
        ld (hl),0
        or a
        ret
ilc_done:
        ld hl,(ilc_dst)
        ld (hl),0
        or a
        ret
ilc_badop:
        ld hl,err_il_op
        jr il_fail
ilc_notwr:
        ld hl,err_il_wr
        jr il_fail
ilc_badcall:
        ld hl,err_il_call
il_fail:
        ld (il_err),hl
        scf
        ret

; ---- il_check_label: HL = text "NAME:" -> NC: il_out = "NAME:"; C: il_err
il_check_label:
        ld de,il_out
        call ident_copy
        jr c,.bad
        ld a,(hl)
        cp ':'
        jr nz,.bad
        ld (de),a
        inc de
        inc hl
        call skip_sp
        ld a,(hl)
        or a
        jr nz,.bad
        ld (de),a
        ret
.bad:   ld hl,err_il_label
        jr il_fail

; ---- ident_copy: HL = text -> identifier [A-Z_][A-Z0-9_]* (max 8) upper case to DE
;      HL, DE advanced; C = not an identifier
ident_copy:
        ld a,(hl)
        call to_upper
        cp '_'
        jr z,.ok1
        call is_alpha
        ret c
.ok1:   ld b,0
.l:     ld a,(hl)
        call to_upper
        cp '_'
        jr z,.take
        call is_alpha
        jr nc,.take
        call is_digit
        jr nc,.take
        ld a,b
        cp 9
        ccf
        ret
.take:  ld (de),a
        inc hl
        inc de
        inc b
        jr .l

; ---- skip_sp: HL -> first non-space char
skip_sp:
        ld a,(hl)
        cp ' '
        ret nz
        inc hl
        jr skip_sp

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
il_out:    ds 64
ilc_op:    dw 0
ilc_dst:   dw 0
ilc_tab:   dw 0
ilc_mem:   dw 0
ilc_area:  db 0
ilc_idx:   dw 0
ilc_inst:  ds 20
