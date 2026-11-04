; ============================================================
; symbols.asm - symbol table: symbolic names + comments for I, Q, M, FB instances
; ============================================================
; Body of the hidden POU slot SYM_SLOT, records sorted by (area, index):
;   [len][area][index][name...0][comment...]
; Names: identifier, max 8 chars, case kept, compared case-insensitively.
; ============================================================
SYM_NMAX EQU 8
SYM_CMAX EQU 30

; ---- sym_first: HL = first record, sf_end = end of the table
sym_first:
        ld a,SYM_SLOT
        call pou_body
        push hl
        add hl,bc
        ld (sf_end),hl
        pop hl
        ret

; ---- sym_at_end: HL = record -> NC if HL >= end (keeps HL)
sym_at_end:
        push hl
        ld de,(sf_end)
        or a
        sbc hl,de
        pop hl
        ret

; ---- sym_next: HL = record -> next record
sym_next:
        ld e,(hl)
        ld d,0
        add hl,de
        ret

; ---- sym_find_addr: A = area, C = index -> NC: HL = record
;      C: not found, HL = insertion point (keeps the order)
sym_find_addr:
        ld (sf_area),a
        ld a,c
        ld (sf_idx),a
        call sym_first
.l:     call sym_at_end
        jr nc,.nf
        inc hl
        ld a,(sf_area)
        cp (hl)
        dec hl
        jr c,.nf
        jr nz,.n
        inc hl
        inc hl
        ld a,(sf_idx)
        cp (hl)
        dec hl
        dec hl
        jr c,.nf
        jr z,.found
.n:     call sym_next
        jr .l
.found: or a
        ret
.nf:    scf
        ret

; ---- sym_find_name: HL = name (0) -> NC: A = area, C = index; C: unknown
sym_find_name:
        ld (sf_name),hl
        ld a,(hl)
        or a
        scf
        ret z
        call sym_first
.l:     call sym_at_end
        jr nc,.nf
        push hl
        ld de,3
        add hl,de
        ld de,(sf_name)
        call str_ieq
        pop hl
        jr z,.found
        call sym_next
        jr .l
.found: inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        or a
        ret
.nf:    scf
        ret

; ---- sym_name_of: A = area, C = index -> NC: HL = name (non-empty); C: none
sym_name_of:
        call sym_find_addr
        ret c
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        or a
        ret nz
        scf
        ret

; ---- str_ieq: HL, DE strings -> Z if equal ignoring case
str_ieq:
        ld a,(de)
        call to_upper
        ld b,a
        ld a,(hl)
        call to_upper
        cp b
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr str_ieq

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

; ---- sym_store: A = area, C = index, HL = name, DE = comment
;      replaces the record of the address; empty name and comment -> removed
;      C = out of memory (message shown)
sym_store:
        ld (sv_area),a
        ld a,c
        ld (sv_idx),a
        ; build the record in rec_buf
        push de
        ld de,rec_buf+3
        call put_str
        xor a
        ld (de),a
        inc de
        pop hl
        call put_str
        ex de,hl
        ld de,rec_buf
        or a
        sbc hl,de
        ld a,l
        ld (rec_buf),a
        ld a,(sv_area)
        ld (rec_buf+1),a
        ld a,(sv_idx)
        ld (rec_buf+2),a
        ; remove the old record
        ld a,(sv_idx)
        ld c,a
        ld a,(sv_area)
        call sym_find_addr
        jr c,.new
        ld c,(hl)
        ld b,0
        call sym_offset
        ld a,SYM_SLOT
        call pou_delete
.new:   ld a,(rec_buf)
        cp 5                    ; [len][area][idx][0] = empty name and comment
        jr nc,.ins
        or a                    ; nothing to store
        ret
.ins:
        ld a,(sv_idx)
        ld c,a
        ld a,(sv_area)
        call sym_find_addr      ; HL = insertion point
        call sym_offset
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ld a,SYM_SLOT
        call pou_insert
        jr c,.mem
        ex de,hl
        ld hl,rec_buf
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ldir
        or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret

; HL = address in the symbol table -> DE = offset (keeps HL, BC)
sym_offset:
        push bc
        push hl
        ld a,SYM_SLOT
        call pou_body
        ex de,hl
        pop hl
        push hl
        or a
        sbc hl,de
        ex de,hl
        pop hl
        pop bc
        ret

sf_end:  dw 0
sf_area: db 0
sf_idx:  db 0
sf_name: dw 0
sv_area: db 0
sv_idx:  db 0
sv_name: dw 0
