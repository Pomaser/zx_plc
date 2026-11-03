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
;      NC: il_out = binary instruction, il_outlen = its length; C: il_err = message
; Binary instruction: [op][operand]
;   op: bits 0-5 mnemonic index (il_mnems), bit 7 "(" modifier
;   operand (optional): [area][index] or [area][value lo][value hi] (AR_K16,
;   AR_KT) or [AR_LBL][label name...]; an FB call may be followed by
;   parameters [member][operand]...
AR_LBL  EQU 12              ; operand = jump label (name follows)
il_check:
        ld (ilc_op),de
        call il_mnem_find
        ld hl,err_il_unknown
        jp c,il_fail
        ld a,(il_mclass)
        and 0x80
        ld b,a
        ld a,(il_mid)
        or b
        ld (il_out),a
        ld hl,il_out+1
        ld (ilc_dst),hl
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
        jp ilc_done

.read:  call ilc_empty
        jr nz,.r1
        ld a,(il_mclass)        ; "AND(" may stand alone
        bit 7,a
        jp nz,ilc_done
        ld hl,err_il_opreq
        jp il_fail
.r1:    call ilc_operand
        ret c
        cp AR_FBI
        jp z,ilc_badop
        cp AR_POU
        jp z,ilc_badop
        jp ilc_done

.write: call ilc_need
        ret c
        call ilc_operand
        ret c
        cp AR_MW
        jp z,ilc_done
        jr .wr
.setres:
        call ilc_need
        ret c
        call ilc_operand
        ret c
.wr:    cp AR_Q
        jp z,ilc_done
        cp AR_M
        jp z,ilc_done
        cp AR_FBM
        jp z,ilc_done
        jp ilc_notwr

.label: call ilc_need
        ret c
        ld de,(ilc_dst)
        ld a,AR_LBL
        ld (de),a
        inc de
        ld hl,(ilc_op)
        call ident_copy
        jr c,.lbad
        ld (ilc_dst),de
        call skip_sp
        ld a,(hl)
        or a
        jp z,ilc_done
.lbad:  ld hl,err_il_label
        jp il_fail

.call:  call ilc_need
        ret c
        call ilc_operand_nt
        ret c
        cp AR_POU
        jp z,.cend
        cp AR_FBI
        jp nz,ilc_badcall
        ; instance name "TON0." for member checks
        ld a,(ilc_idx)
        ld c,a
        ld a,AR_FBI
        ld de,ilc_inst
        ld hl,0
        ld b,0
        call op_format
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
        ld b,a
        and AR_MASK
        cp AR_FBM
        jp nz,ilc_badcall
        ld a,b                  ; member number
        rrca
        rrca
        rrca
        rrca
        and 7
        ld de,(ilc_dst)
        ld (de),a
        inc de
        ld (ilc_dst),de
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
        cp AR_FBI
        jp z,ilc_badcall
        cp AR_POU
        jp z,ilc_badcall
        ld hl,(ilc_op)
        call skip_sp
        ld a,(hl)
        inc hl
        cp ','
        jr z,.par
        cp ')'
        jp nz,ilc_badcall
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

; parse operand at ilc_op, must be followed only by spaces. NC: A = area type
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

; parse operand at ilc_op (ilc_op advanced) and append its binary form.
; NC: A = area type (AR_MASK applied)
ilc_operand_nt:
        ld hl,(ilc_op)
        call op_parse
        jp c,ilc_badop
        ld (ilc_op),hl
        ld (ilc_area),a
        ld b,a
        ld a,c
        ld (ilc_idx),a
        ld hl,(ilc_dst)
        ld (hl),b               ; area (with member bits)
        inc hl
        ld a,b
        and AR_MASK
        cp AR_K16
        jr z,.val
        cp AR_KT
        jr z,.val
        ld (hl),c               ; index
        jr .end
.val:   ld (hl),e               ; value
        inc hl
        ld (hl),d
.end:   inc hl
        ld (ilc_dst),hl
        ld a,(ilc_area)
        and AR_MASK
        or a
        ret

ilc_done:
        ld hl,(ilc_dst)
        ld de,il_out
        or a
        sbc hl,de
        ld a,l
        ld (il_outlen),a
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
ilc_op:    dw 0
ilc_dst:   dw 0
il_outlen: db 0
ilc_mem:   dw 0
ilc_area:  db 0
ilc_idx:   db 0
ilc_inst:  ds 20
