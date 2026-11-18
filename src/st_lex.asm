; ============================================================
; st_lex.asm - Structured Text tokenizer and keyword table
; ============================================================
; Included twice, inside MODULE ste (FBD bank: the ST editor) and
; MODULE stc (RUN bank: the ST compiler), so each bank has its own copy.
; lx_next reads the next token of the 0-terminated line at (lx_p):
;   lx_type  T_END / T_WORD / T_KW / T_SYM / T_CMT / T_BAD (defs.asm)
;   lx_start first char of the token, lx_p past it
;   lx_word  T_WORD / T_KW: the word in upper case (0-terminated)
;   lx_kw    T_KW: KW_* id;  lx_sym  T_SYM: the char, or S_* for
;            := => <= >= <> ..
;   lx_bad   1: T_CMT "(*" without "*)" (the comment runs to the end)
; A word starts with a letter, digit, _ or % and goes on with letters,
; digits, _ % # and "." (not ".."): %IX0.1, T#1m30s, TON0.Q, 16#FF.
; ============================================================
LX_WMAX EQU 31

lx_next:
        xor a
        ld (lx_bad),a
        ld hl,(lx_p)
.sp:    ld a,(hl)
        cp ' '
        jr nz,.ns
        inc hl
        jr .sp
.ns:    ld (lx_start),hl
        or a
        ld b,T_END
        jp z,.done
        inc hl                  ; HL = next char, A = this char
        ld c,(hl)
        cp '/'
        jr nz,.nc1
        ld a,c
        cp '/'
        ld a,'/'
        jp nz,.sym1
.toend: ld a,(hl)               ; "//": comment to the end of the line
        or a
        jr z,.cmt
        inc hl
        jr .toend
.cmt:   ld b,T_CMT
        jp .done
.nc1:   cp '('
        jr nz,.nc2
        ld a,c
        cp '*'
        ld a,'('
        jr nz,.sym1
        inc hl                  ; "(*" ... "*)"
.ce:    ld a,(hl)
        or a
        jr z,.unc
        inc hl
        cp '*'
        jr nz,.ce
        ld a,(hl)
        cp ')'
        jr nz,.ce
        inc hl
        jr .cmt
.unc:   ld a,1
        ld (lx_bad),a
        jr .cmt
.nc2:   call lx_wfirst
        jr c,.word
        ; ---- two-char symbols
        ld b,S_ASG
        cp ':'
        jr nz,.t1
        ld a,c
        cp '='
        jr z,.sym2
        ld a,':'
        jr .sym1
.t1:    cp '='
        jr nz,.t2
        ld b,S_OUT
        ld a,c
        cp '>'
        jr z,.sym2
        ld a,'='
        jr .sym1
.t2:    cp '<'
        jr nz,.t3
        ld b,S_LE
        ld a,c
        cp '='
        jr z,.sym2
        ld b,S_NE
        cp '>'
        jr z,.sym2
        ld a,'<'
        jr .sym1
.t3:    cp '>'
        jr nz,.t4
        ld b,S_GE
        ld a,c
        cp '='
        jr z,.sym2
        ld a,'>'
        jr .sym1
.t4:    cp '.'
        jr nz,.t5
        ld b,S_RNG
        ld a,c
        cp '.'
        jr z,.sym2
        jr .bad
.t5:    ld de,lx_syms           ; one-char symbols
        ld b,a
.ts:    ld a,(de)
        or a
        jr z,.bad
        inc de
        cp b
        jr nz,.ts
.sym1:  ld (lx_sym),a
        ld b,T_SYM
        jr .done
.sym2:  inc hl
        ld a,b
        jr .sym1
.bad:   ld b,T_BAD
.done:  ld (lx_p),hl
        ld a,b
        ld (lx_type),a
        ret
        ; ---- a word
.word:  dec hl
        ld de,lx_word
        ld b,LX_WMAX
.wl:    ld a,(hl)
        call lx_wchar
        jr nc,.we
        call to_upper
        ld (de),a
        inc de
        inc hl
        djnz .wl                ; (too long: the rest is a new word)
.we:    xor a
        ld (de),a
        push hl
        ld hl,lx_word
        call lx_kwfind
        pop hl
        ld b,T_WORD
        jr z,.done
        ld (lx_kw),a
        ld b,T_KW
        jr .done

; lx_wfirst: A = char -> C if it starts a word (keeps A, BC, DE, HL)
lx_wfirst:
        cp '_'
        scf
        ret z
        cp '%'
        scf
        ret z
lx_alnum:
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

; lx_wchar: A = char at (HL) -> C if it continues a word (keeps A, BC, DE, HL)
lx_wchar:
        cp '#'
        scf
        ret z
        cp '.'
        jr nz,lx_wfirst
        inc hl                  ; "." but not ".."
        ld a,(hl)
        dec hl
        cp '.'
        ld a,'.'
        scf
        ret nz
        or a
        ret

; ---- lx_kwfind: HL = word (upper case, 0) -> A = keyword id (NZ), or
;      A = 0 (Z). Keeps BC, DE, HL
lx_kwfind:
        push bc
        push de
        push hl
        ld de,lx_kwtab
        ld c,1
.l:     ld a,(de)
        or a
        jr z,.e
        pop hl
        push hl
.c:     ld a,(de)
        cp (hl)
        jr nz,.ne
        inc de
        inc hl
        or a
        jr nz,.c
        ld a,c                  ; both ended: found
        jr .e
.ne:    ld a,(de)
        inc de
        or a
        jr nz,.ne
        inc c
        jr .l
.e:     pop hl
        pop de
        pop bc
        or a
        ret

lx_kwtab:
        db "IF",0,"THEN",0,"ELSIF",0,"ELSE",0,"END_IF",0
        db "CASE",0,"OF",0,"END_CASE",0
        db "FOR",0,"TO",0,"BY",0,"DO",0,"END_FOR",0
        db "WHILE",0,"END_WHILE",0,"REPEAT",0,"UNTIL",0,"END_REPEAT",0
        db "EXIT",0,"RETURN",0
        db "AND",0,"OR",0,"XOR",0,"NOT",0,"MOD",0
        db "VAR",0,"VAR_GLOBAL",0,"VAR_INPUT",0,"VAR_OUTPUT",0,"END_VAR",0
        db "BOOL",0,"INT",0,"TIME",0
        db 0
lx_syms: db "+-*/(),;&",0

lx_p:     dw 0
lx_start: dw 0
lx_type:  db 0
lx_kw:    db 0
lx_sym:   db 0
lx_bad:   db 0
lx_word:  ds LX_WMAX+1
