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
;      A = 0 (Z). Keeps BC, DE, HL. Table entries: [length][text]
lx_kwfind:
        push bc
        push de
        push hl
        call strlen
        ld (lx_wlen),a
        ld c,1                  ; C = id
        ld de,lx_kwtab
.l:     ld a,(de)
        or a
        jr z,.e
        ld b,a
        inc de                  ; DE = text
        ld a,(lx_wlen)
        cp b
        jr nz,.sk
        pop hl
        push hl
        push de
.c:     ld a,(de)
        cp (hl)
        jr nz,.ne
        inc de
        inc hl
        djnz .c
        pop de
        ld a,c                  ; found
        jr .e
.ne:    pop de
        ld a,(lx_wlen)
        ld b,a
.sk:    ld a,e                  ; DE += length
        add a,b
        ld e,a
        jr nc,.n
        inc d
.n:     inc c
        jr .l
.e:     pop hl
        pop de
        pop bc
        or a
        ret

; ---- st_vfind: A = POU slot, HL = name (upper case, 0) -> NC: a local
;      variable of that POU, C = its index in the VAR block, B = type (0
;      BOOL, 1 INT, 2 TIME, 0xFF: invalid); C (carry): not declared.
;      Always: vf_cnt = number of declarations, vf_end = line of END_VAR
;      (0: no VAR block). The block starts at line 0, one declaration
;      "Name : TYPE ..." per line. Keeps the tokenizer state (lx_p...)
st_vfind:
        ld (vf_slot),a
        ld de,vf_name
        call put_str
        xor a
        ld (de),a
        ld hl,lx_p
        ld de,vf_save
        ld bc,8
        ldir
        ld a,0xFF
        ld (vf_res),a
        xor a
        ld (vf_cnt),a
        ld h,a
        ld l,a
        ld (vf_end),hl
        ld (vf_line),hl
        ld a,(vf_slot)
        call pou_body
        ld (vf_rec),hl
        add hl,bc
        ld (vf_bend),hl
        call vf_load
        jp c,.done
        call vf_tok
        cp T_KW
        jp nz,.done
        ld a,(lx_kw)
        cp KW_VAR
        jr nz,.done
.l:     call vf_load
        jr c,.done
        ld hl,(vf_line)
        inc hl
        ld (vf_line),hl
        call vf_tok
        or a
        jr z,.l                 ; (empty / comment line)
        cp T_KW
        jr nz,.w
        ld a,(lx_kw)
        cp KW_END_VAR
        jr nz,.l
        ld hl,(vf_line)
        ld (vf_end),hl
        jr .done
.w:     cp T_WORD
        jr nz,.l
        ld hl,lx_word
        ld de,vf_name
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.cm
        inc hl
        inc de
        or a
        jr nz,.cmp
        inc a                   ; A = 1: the name
.cm:    ld (vf_m),a             ; (A = 1 only when equal)
        call vf_tok
        cp T_SYM
        jr nz,.l
        ld a,(lx_sym)
        cp ':'
        jr nz,.l
        call vf_tok
        ld b,0xFF
        cp T_KW
        jr nz,.w2
        ld a,(lx_kw)
        sub KW_BOOL
        cp 3
        jr nc,.w2
        ld b,a
.w2:    ld a,(vf_m)
        dec a
        jr nz,.w3
        ld a,(vf_res)           ; (the first declaration counts)
        inc a
        jr nz,.w3
        ld a,(vf_cnt)
        ld (vf_res),a
        ld a,b
        ld (vf_typ),a
.w3:    ld hl,vf_cnt
        inc (hl)
        jr .l
.done:  ld hl,vf_save
        ld de,lx_p
        ld bc,8
        ldir
        ld a,(vf_res)
        ld c,a
        inc a
        scf
        ret z
        ld a,(vf_typ)
        ld b,a
        or a
        ret

; vf_load: the line at vf_rec -> its text in vf_buf (lx_p), vf_rec = the
;      next line; C = past the end of the body
vf_load:
        ld hl,(vf_rec)
        ld de,(vf_bend)
        or a
        sbc hl,de
        ccf
        ret c
        add hl,de
        ld c,(hl)
        ld b,0
        push hl
        add hl,bc
        ld (vf_rec),hl
        pop hl
        inc hl
        ld a,(hl)
        inc hl
        inc hl
        ld de,vf_buf
        cp K_STXT
        jr nz,.e
        ld a,c
        sub 3
        jr z,.e
        jr c,.e
        cp 63
        jr c,.ok
        ld a,63
.ok:    ld c,a
        ldir
.e:     xor a
        ld (de),a
        ld hl,vf_buf
        ld (lx_p),hl
        ret

; vf_tok: the next token that is not a comment -> A = lx_type
vf_tok: call lx_next
        ld a,(lx_type)
        cp T_CMT
        jr z,vf_tok
        ret

lx_kwtab:
        db 2,"IF",4,"THEN",5,"ELSIF",4,"ELSE",6,"END_IF"
        db 4,"CASE",2,"OF",8,"END_CASE",3,"FOR",2,"TO"
        db 2,"BY",2,"DO",7,"END_FOR",5,"WHILE",9,"END_WHILE"
        db 6,"REPEAT",5,"UNTIL",10,"END_REPEAT",4,"EXIT",6,"RETURN"
        db 3,"AND",2,"OR",3,"XOR",3,"NOT",3,"MOD"
        db 3,"VAR",10,"VAR_GLOBAL",9,"VAR_INPUT",10,"VAR_OUTPUT",7,"END_VAR"
        db 4,"BOOL",3,"INT",4,"TIME"
        db 0
lx_syms: db "+-*/(),;&",0

lx_p:     dw 0
lx_start: dw 0
lx_type:  db 0
lx_kw:    db 0
lx_sym:   db 0
lx_bad:   db 0
lx_wlen:  db 0
lx_word:  ds LX_WMAX+1
vf_slot:  db 0
vf_res:   db 0
vf_typ:   db 0
vf_m:     db 0
vf_cnt:   db 0
vf_end:   dw 0
vf_line:  dw 0
vf_rec:   dw 0
vf_bend:  dw 0
vf_save:  ds 8
vf_name:  ds LX_WMAX+1
vf_buf:   ds 64
