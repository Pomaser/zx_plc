; ============================================================
; globals.asm - the declarations of the Global vars page (DATA bank, BCALL):
; text <-> a record of the symbol table. Three kinds:
;   "AT %IX0.0"          a name on an address (I, Q, M, MW, SX, SM, SW)
;   "INT[ := value]"     a global variable (BOOL, BYTE, INT; AR_GV record)
;   "TON"                an FB instance (TON TOF TP CTU CTD R_TRIG F_TRIG SR RS)
; Texts and records in fixed memory only.
; ============================================================

; ---- gv_fmt: HL = record -> DE = its declaration text (0 at DE)
gv_fmt:
        inc hl
        ld a,(hl)               ; area
        inc hl
        ld c,(hl)               ; index
        cp AR_GV
        jr z,.n
        cp AR_FBI
        jr nz,gv_pfmt
        ld a,c                  ; an instance: its type
        rrca
        rrca
        and 0x3F
        ld c,a
        ld a,AR_FBI
        jr gv_pfmt
.n:     inc hl                  ; a global: the declaration after the name
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

; ---- gv_pfmt: A = area, C = index (an address);
;      AR_FBI: C = the FB type; AR_GV: sym_decl -> DE = the declaration text
gv_pfmt:
        cp AR_GV
        jr nz,.ng
        ld hl,sym_decl
        jr gv_fmtd
.ng:    cp AR_FBI
        jr nz,.adr
        ld a,c                  ; an FB instance: its type name
        ld l,a
        add a,a
        add a,a
        add a,a
        sub l                   ; * 7
        ld l,a
        ld h,0
        ld bc,gv_fbt
        add hl,bc
        call put_str
        jr gv_fmtd.e
.adr:   push af                 ; an address: "AT %IX0.0"
        ld hl,gv_at
        call put_str
        pop af
        ld hl,0
        ld b,0
        jp op_format

; ---- gv_parse: HL = a declaration -> NC: A = area, C = index (an
;      address), the FB type (AR_FBI) or sym_decl (AR_GV); C: il_err
gv_parse:
        call .sp
        ld (gp_txt),hl
        ld a,(hl)               ; "AT address"
        call to_upper
        cp 'A'
        jr nz,.word
        inc hl
        ld a,(hl)
        call to_upper
        cp 'T'
        jr nz,.word0
        inc hl
        ld a,(hl)
        cp ' '
        jr z,.at
        cp '%'
        jr nz,.word0
.at:    call .sp
        jr .adr
.word0: ld hl,(gp_txt)
.word:  ld de,op_tok            ; the type word (letters and '_')
        ld b,7
.w:     ld a,(hl)
        call to_upper
        cp '_'
        jr z,.wc
        call is_alpha
        jr c,.we
.wc:    ld (de),a
        inc hl
        inc de
        djnz .w
        jr .tryadr
.we:    xor a
        ld (de),a
        ld (gp_end),hl
        ld hl,gv_fbt            ; an FB type?
        ld c,0
.f:     push hl
        push bc
        ld de,op_tok
        call str_ieq
        pop bc
        pop hl
        jr z,.fb
        ld de,7
        add hl,de
        inc c
        ld a,c
        cp FB_TYPES
        jr c,.f
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
.tryadr:
        ld hl,(gp_txt)          ; an address without "AT"
.adr:   call op_parse
        jr c,.bad
        ld b,a
        cp AR_I
        jr z,.aok
        cp AR_Q
        jr z,.aok
        cp AR_M
        jr z,.aok
        cp AR_MW
        jr z,.aok
        cp AR_SX
        jr z,.aok
        cp AR_SM
        jr z,.aok
        cp AR_SW
        jr nz,.bad
.aok:   call .sp                ; (": BOOL" / ": INT" after it is ignored)
        ld a,(hl)
        or a
        jr z,.ret
        cp ':'
        jr nz,.bad
.ret:   ld a,b
        or a
        ret
.fb:    ld hl,(gp_end)          ; an FB type: nothing may follow
        call .sp
        ld a,(hl)
        or a
        jr nz,.bad
        ld a,AR_FBI             ; (C = the type)
        ret
.bad:   ld hl,err_gv_type
        jr .err
.tf:    ld a,c
        ld (sym_decl),a
        ld de,0
        ld (sym_decl+1),de
        ld hl,(gp_end)
        call .sp
        ld a,(hl)
        or a
        jr z,.gv                ; no init value
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
.gv:    ld a,AR_GV
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

gp_txt:   dw 0
gp_end:   dw 0
gv_types: db "BOOL",0,0,0,0, "INT",0,0,0,0,0, "TIME",0,0,0,0, "BYTE",0,0,0,0
gv_fbt:   db "TON",0,0,0,0, "TOF",0,0,0,0, "TP",0,0,0,0,0, "CTU",0,0,0,0, "CTD",0,0,0,0
          db "R_TRIG",0, "F_TRIG",0, "SR",0,0,0,0,0, "RS",0,0,0,0,0
gv_asg:   db " := ",0
gv_at:    db "AT ",0
