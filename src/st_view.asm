; ============================================================
; st_view.asm - ST text shown after View > Symbols / Addresses, and the
;               status bar text of the word at the cursor (EDIT bank,
;               BCALLed by the ST editor in the FBD bank)
; ============================================================
XF_MAX  EQU 60                  ; max. characters of a converted line

; ---- st_xform: HL = ST line text, DE = output (both fixed memory), A =
;      POU slot -> the line with every I / Q / M / SX / MW / FB operand
;      written as its symbol (view_sym = 1, if it has one) or as its IEC
;      address (il_fmt_one); comments, keywords, constants and the locals
;      of the POU stay as they are. At most XF_MAX characters (C: cut).
st_xform:
        ld (xf_slot),a
        xor a
        ld (xf_n),a
        ld (xf_ovf),a
.l:     ld a,(hl)
        or a
        jr z,.end
        cp '/'                  ; "//": the rest is a comment
        jr nz,.n1
        inc hl
        ld a,(hl)
        dec hl
        cp '/'
        jr z,.rest
        jr .ch
.n1:    cp '('                  ; "(* ... *)"
        jr nz,.n2
        inc hl
        ld a,(hl)
        dec hl
        cp '*'
        jr nz,.ch
.cm:    ld a,(hl)
        or a
        jr z,.end
        call xf_put
        cp '*'
        jr nz,.cm
        ld a,(hl)
        cp ')'
        jr nz,.cm
.ch:    call xf_put
        jr .l
.rest:  ld a,(hl)
        or a
        jr z,.end
        call xf_put
        jr .rest
.n2:    call xf_wfirst
        jr nc,.ch
        ld (xf_ws),hl           ; a word: upper case copy in cp_text
        push de
        ld de,cp_text
        ld b,31
.wl:    ld a,(hl)
        call xf_wch
        jr nc,.we
        call to_upper
        ld (de),a
        inc de
        inc hl
        djnz .wl
.we:    xor a
        ld (de),a
        ld (xf_we),hl
        call xf_word            ; NC: HL = the new text
        pop de
        jr c,.keep
.rl:    ld a,(hl)
        or a
        jr z,.rd
        call xf_put
        jr .rl
.rd:    ld hl,(xf_we)
        jr .l
.keep:  ld hl,(xf_ws)
.kl:    push de
        ld de,(xf_we)
        or a
        sbc hl,de
        add hl,de
        pop de
        jr z,.l
        call xf_put
        jr .kl
.end:   xor a
        ld (de),a
        ld a,(xf_ovf)           ; C: it did not fit (cut)
        rra
        ret

; ---- st_canon: the stored form of a line: every operand that has an
;      address as its IEC address (st_xform with View = Addresses), so the
;      text does not depend on the view and follows renamed symbols.
;      HL, DE, A as st_xform; C: it did not fit
st_canon:
        push af
        ld a,(view_sym)
        ld (xf_vs),a
        xor a
        ld (view_sym),a
        pop af
        call st_xform
        push af
        ld a,(xf_vs)
        ld (view_sym),a
        pop af
        ret

; xf_put: (HL) -> (DE) if there is room; HL, DE advanced, A = the char
xf_put: ld a,(xf_n)
        cp XF_MAX
        jr c,.p
        ld a,1
        ld (xf_ovf),a
        jr .s
.p:
        inc a
        ld (xf_n),a
        ld a,(hl)
        ld (de),a
        inc de
.s:     ld a,(hl)
        inc hl
        ret

; xf_wfirst: A = char -> C if it starts a word (letter, digit, _ %)
xf_wfirst:
        cp '_'
        scf
        ret z
        cp '%'
        scf
        ret z
xf_alnum:
        cp '0'
        ccf
        ret nc
        cp '9'+1
        ret c
        push af
        call to_upper
        cp 'A'
        jr c,.no
        cp 'Z'+1
        jr nc,.no
        pop af
        scf
        ret
.no:    pop af
        or a
        ret

; xf_wch: A = char at (HL) -> C if it goes on with a word (also # and a
;      "." that is not "..")
xf_wch: cp '#'
        scf
        ret z
        cp '.'
        jr nz,xf_wfirst
        inc hl
        ld a,(hl)
        dec hl
        cp '.'
        ld a,'.'
        scf
        ret nz
        or a
        ret

; xf_word: cp_text = a word (upper case) -> NC: HL = its text after View,
;      C: keep it as written
xf_word:
        ld hl,cp_text
        call xf_op              ; NC: B = area, C = index
        ret c
        ld a,b
        ld (xf_rec),a
        ld a,c
        ld (xf_rec+1),a
        ld hl,xf_rec
        ld de,xf_buf
        xor a
        ld (fo_style),a         ; IEC: %MW0
        call il_fmt_one
        xor a                   ; (its symbol path leaves no 0)
        ld (de),a
        ld hl,xf_buf
        or a
        ret

; xf_op: HL = a word (upper case, fixed memory) -> NC: B = area, C = index
;      of an I / Q / M / SX / MW / FB operand that is not a local of the
;      POU; C: none
xf_op:  push hl
        call op_parse
        pop de
        ret c
        ld b,a
        ld a,(hl)               ; the whole word
        or a
        scf
        ret nz
        ld a,b
        and AR_MASK
        cp AR_I
        jr z,.ok
        cp AR_Q
        jr z,.ok
        cp AR_M
        jr z,.ok
        cp AR_SX
        jr z,.ok
        cp AR_MW
        jr z,.ok
        cp AR_FBI
        jr z,.ok
        cp AR_FBM
        scf
        ret nz
.ok:    ld a,(de)               ; a name: a local of the POU hides it
        cp '%'
        ret z                   ; (NC)
        push bc
        ex de,hl
        ld a,(xf_slot)
        BCALL st_lvaddr
        pop bc
        ccf                     ; (a local: C)
        ret

; ---- st_symline: HL = the word at the cursor (fixed memory, may be
;      empty), A = POU slot -> st_left = its symbol (inverted) and comment,
;      or "local" and the type of a local; none: empty. status_left
st_symline:
        ld (xf_slot),a
        ld de,0
        ld (st_left),de
        ld a,(hl)
        or a
        jp z,status_left
        push hl
        ld de,cp_text           ; upper case copy
        ld b,31
.u:     ld a,(hl)
        call to_upper
        ld (de),a
        inc hl
        inc de
        or a
        jr z,.u2
        djnz .u
.u2:    pop hl
        ld a,(xf_slot)          ; a local
        ld hl,cp_text
        BCALL st_lvaddr
        jr c,.glob
        ld de,rec_buf
        ld a,ST_SYM
        ld (de),a
        inc de
        ld hl,cp_text
        call put_str
        ld a,ST_SYME
        ld (de),a
        inc de
        ld hl,txt_sv_loc
        call put_str
        ld a,b                  ; the type
        ld hl,txt_sv_bool
        or a
        jr z,.t
        ld hl,txt_sv_int
        dec a
        jr z,.t
        ld hl,txt_sv_time
.t:     call put_str
        jr .fin
.glob:  ld hl,cp_text
        call xf_op
        jp c,status_left
        ld a,b                  ; a member: the symbol of its instance
        and AR_MASK
        cp AR_FBM
        ld a,b
        jr nz,.f
        ld a,AR_FBI
.f:     call sym_find_addr
        jp c,status_left
        ld de,rec_buf
        call sym_stext          ; symbol name (inverted), then the comment
        jr .fin2
.fin:   xor a
        ld (de),a
.fin2:  ld hl,rec_buf
        ld (st_left),hl
        jp status_left

txt_sv_loc:  db " local ",0
txt_sv_bool: db "BOOL",0
txt_sv_int:  db "INT",0
txt_sv_time: db "TIME",0
xf_slot: db 0
xf_n:    db 0
xf_ovf:  db 0
xf_vs:   db 0
xf_ws:   dw 0
xf_we:   dw 0
xf_rec:  ds 2
xf_buf:  ds 40
