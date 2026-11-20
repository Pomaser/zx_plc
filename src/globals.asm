; ============================================================
; globals.asm - declarations of the global variables (DATA bank, BCALL):
; "TYPE[ := value]" text <-> the type byte and init value of a record.
; Texts and records in fixed memory only.
; ============================================================

; ---- gv_fmt: HL = record of a global -> DE = "TYPE[ := value]" (0 at DE)
gv_fmt:
        inc hl
        inc hl
.n:     inc hl
        ld a,(hl)
        or a
        jr nz,.n
        inc hl
; gv_fmtd: HL = declaration [type][lo][hi] -> DE = its text
gv_fmtd:
        ld a,(hl)               ; type byte
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        push bc
        push af
        and 3
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld bc,gv_types
        add hl,bc
        call put_str
        pop af
        pop hl                  ; HL = init value
        bit 7,a                 ; (GT_INIT)
        jr z,.e
        push af
        push hl
        ld hl,gv_asg
        call put_str
        pop hl
        pop af
        and 3                   ; BOOL: TRUE / FALSE
        jr nz,.num
        ld a,l
        or a
        ld hl,kw_false
        jr z,.s
        ld hl,kw_true
.s:     call put_str
        jr .e
.num:   call itoa16
.e:     xor a
        ld (de),a
        ret

; ---- gv_parse: HL = "TYPE[ := value]" -> NC: sym_decl; C: il_err = message
gv_parse:
        call .sp
        ld de,op_tok            ; the type word (letters only)
        ld b,5
.w:     ld a,(hl)
        call to_upper
        call is_alpha
        jr c,.we
        ld (de),a
        inc hl
        inc de
        djnz .w
        jr .bad
.we:    xor a
        ld (de),a
        push hl
        ld c,0
.t:     ld a,c                  ; BOOL 0, INT 1, BYTE 3 (TIME 2 not offered)
        cp 2
        jr z,.tn
        add a,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,gv_types
        add hl,de
        ld de,op_tok
        push bc
        call str_ieq
        pop bc
        jr z,.tf
.tn:    inc c
        ld a,c
        cp 4
        jr c,.t
        pop hl
.bad:   ld hl,err_gv_type
        jr .err
.tf:    pop hl
        ld a,c
        ld (sym_decl),a
        ld de,0
        ld (sym_decl+1),de
        call .sp
        ld a,(hl)
        or a
        ret z                   ; no init value (NC)
        cp ':'
        jr nz,.bad
        inc hl
        ld a,(hl)
        cp '='
        jr nz,.bad
        inc hl
        call .sp
        call op_parse
        jr c,.bval
        push af
        call .sp
        ld a,(hl)
        or a
        jr nz,.bv2
        pop af
        cp AR_KB
        jr nz,.k
        ld e,c                  ; TRUE / FALSE: 1 / 0
        ld d,0
        jr .ck
.k:     cp AR_K16
        jr nz,.bval
.ck:    ld a,(sym_decl)
        or a
        jr nz,.nb
        ld a,d                  ; BOOL: 0 / 1
        or a
        jr nz,.bval
        ld a,e
        cp 2
        jr nc,.bval
        jr .ok
.nb:    cp GT_BYTE
        jr nz,.ok
        ld a,d                  ; BYTE: 0-255
        or a
        jr nz,.bval
.ok:    ld (sym_decl+1),de
        ld hl,sym_decl
        set 7,(hl)              ; GT_INIT
        or a
        ret
.bv2:   pop af
.bval:  ld hl,err_gv_val
.err:   ld (il_err),hl
        scf
        ret
.sp:    ld a,(hl)
        cp ' '
        ret nz
        inc hl
        jr .sp

gv_types: db "BOOL",0,0,0,0, "INT",0,0,0,0,0, "TIME",0,0,0,0, "BYTE",0,0,0,0
gv_asg:   db " := ",0
