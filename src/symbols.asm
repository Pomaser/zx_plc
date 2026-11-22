; ============================================================
; symbols.asm - symbol table: symbolic names + comments for I, Q, M, FB instances
; ============================================================
; Body of the hidden POU slot SYM_SLOT, records sorted by (area, index):
;   [len][area][index][name...0][comment...]
; Globals (area AR_GV, index = g) come last and carry their declaration
; after the name: [len][AR_GV][g][name...0][type][init lo][init hi][comment...]
; (type = GT_* + GT_INIT if an init value was given).
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
        ld a,(sv_area)          ; a global (with a name): its declaration
        cp AR_GV
        jr nz,.nd
        ld a,(rec_buf+3)
        or a
        jr z,.nd
        ld hl,sym_decl
        ld bc,3
        ldir
.nd:    pop hl
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

; ---- sym_cmt: HL = past the name's 0 of a record of area A -> HL = its
;      comment (a global's declaration skipped); keeps BC, DE
sym_cmt:
        cp AR_GV
        ret nz
        inc hl
        inc hl
        inc hl
        ret

; ---- sym_stext: HL = symbol record -> DE: ST_SYM name ST_SYME comment, 0
;      (the status bar text of a symbol; a global's declaration skipped)
sym_stext:
        push de
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (ss_end),hl
        pop hl
        inc hl
        ld a,(hl)
        ld (ss_ar),a
        inc hl
        inc hl
        pop de
        ld a,ST_SYM
        ld (de),a
        inc de
.n:     ld a,(hl)
        inc hl
        or a
        jr z,.ne
        ld (de),a
        inc de
        jr .n
.ne:    ld a,ST_SYME
        ld (de),a
        inc de
        ld a,(ss_ar)
        call sym_cmt
.c:     push hl
        ld bc,(ss_end)
        or a
        sbc hl,bc
        pop hl
        jr nc,.e
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .c
.e:     xor a
        ld (de),a
        ret

; ---- gv_find: C = global number -> NC: A = type byte, DE = init value,
;      HL = record; C: no such global
gv_find:
        ld a,AR_GV
        call sym_find_addr
        ret c
        push hl
        inc hl
        inc hl
.n:     inc hl
        ld a,(hl)
        or a
        jr nz,.n
        inc hl
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
        or a                    ; (NC)
        ret

; ---- gv_top: A = 1 + the highest global number (0: no globals)
gv_top:
        call sym_first
        ld b,0
.l:     call sym_at_end
        jr nc,.e
        inc hl
        ld a,(hl)
        inc hl
        cp AR_GV
        jr nz,.n
        ld a,(hl)
        inc a
        ld b,a
.n:     dec hl
        dec hl
        call sym_next
        jr .l
.e:     ld a,b
        ret

err_gv_type: db "Type: BOOL, BYTE or INT",0
err_gv_val:  db "Invalid init value",0

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
sym_decl: ds 3
ss_end:  dw 0
ss_ar:   db 0              ; sym_store: the declaration of a global
