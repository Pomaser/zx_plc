; ============================================================
; sym_valid.asm - the name check of the Global vars (EDIT bank; also in the
; test and demo builds, which leave out sym_edit.asm)
; ============================================================

; ---- sym_validate: HL = name, A = area, C = index of its own address
;      NC = valid (or empty); C = error, il_err = message
sym_validate:
        ld (sv_area),a
        ld a,c
        ld (sv_idx),a
        ld (sv_name),hl
        ld a,(hl)
        or a
        ret z                   ; empty name: comment only
        ; identifier: letter or "_", then letters, digits, "_"; max 8
        call to_upper
        cp '_'
        jr z,.c1
        call is_alpha
        jr c,.bad
.c1:    ld b,0
.ch:    ld a,(hl)
        or a
        jr z,.len
        call to_upper
        inc hl
        inc b
        cp '_'
        jr z,.ch
        call is_alpha
        jr nc,.ch
        call is_digit
        jr nc,.ch
.bad:   ld hl,err_bad_name
        jr .fail
.len:   ld a,b
        cp SYM_NMAX+1
        jr nc,.bad
        ; not an IL instruction
        ld hl,(sv_name)
        call il_mnem_find
        jr nc,.res
        ; not an address, keyword, FB, POU or another symbol
        ld hl,(sv_name)
        call op_parse
        ccf
        ret nc                  ; unknown word: valid
        ld b,a
        and AR_MASK
        cp AR_I
        jr z,.sym
        cp AR_Q
        jr z,.sym
        cp AR_M
        jr z,.sym
        cp AR_SX
        jr z,.sym
        cp AR_LV                ; (a global)
        jr z,.sym
        cp AR_FBI
        jr nz,.res
.sym:   ; a symbol (or address) of the same name: fine only if it is our own
        ld a,(sv_idx)
        cp c
        jr nz,.used
        ld a,(sv_area)
        cp b
        jr nz,.used
        ld hl,(sv_name)         ; only if it resolved by name, not as an address
        call sym_find_name
        ret nc
.res:   ld hl,err_reserved
        jr .fail
.used:  ld hl,err_name_used
.fail:  ld (il_err),hl
        scf
        ret

