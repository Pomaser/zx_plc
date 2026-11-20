; ============================================================
; st_var.asm - ST local variables (RUN bank, above the bytecode)
; ============================================================
; A POU declares its locals in a block at its start:
;     VAR
;       Name : BOOL | INT | TIME [:= constant];
;     END_VAR
; one declaration per line (st_vfind in st_lex.asm reads them). Every
; local is one word at LV_BASE + 2 * LV index (BOOL: bit 0); the LV
; indices of a POU follow those of the ST POUs in the slots before it
; (lv_first). The compiler writes the initial values to LV_INIT, vm_reset
; copies them to LV_BASE. Operands: area AR_LV + type * 16, index = LV
; index.
; ============================================================

; ---- sc_var: the VAR block at the start of the POU (current token VAR)
sc_var:
        ld a,(cp_slot)
        call lv_first
        ld (vd_base),a
        xor a
        ld (vd_idx),a
        call tk_next
.l:     ld a,(stc.lx_type)
        cp T_WORD
        jr z,.d
        ld a,KW_END_VAR
        call sc_expect_kw
        jp sc_optsemi
.d:     ld hl,stc.lx_word       ; Name : TYPE [:= constant];
        ld de,sc_wbuf
        call put_str
        xor a
        ld (de),a
        ld a,(cp_slot)
        ld hl,sc_wbuf
        call stc.st_vfind       ; the first declaration of the name
        jp c,sc_syntax          ; (not "Name : ..." on one line)
        ld a,(vd_idx)
        cp c
        ld hl,err_sc_dup
        jp nz,sc_err
        ld a,(vd_base)
        add a,c
        cp LV_MAX
        ld hl,err_sc_many
        jp nc,sc_err
        ld (vd_g),a
        call tk_next
        ld a,':'
        call sc_expect
        ld a,(stc.lx_type)
        cp T_KW
        jr nz,.terr
        ld a,(stc.lx_kw)
        sub KW_BOOL
        cp 3
        jr nc,.terr
        call tk_next
        ld hl,0
        ld a,S_ASG
        call sc_issym
        jr nz,.st
        call tk_next
        call sc_initk
.st:    ex de,hl                ; the initial value
        ld a,(vd_g)
        ld l,a
        ld h,0
        add hl,hl
        ld bc,LV_INIT
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,vd_idx
        inc (hl)
        call sc_semi
        jp .l
.terr:  ld hl,err_sc_type
        jp sc_err

; sc_initk: the initial value: [-] INT, TRUE / FALSE, T#... -> HL; next token
sc_initk:
        ld a,'-'
        call sc_issym
        jp z,sc_const
        call sc_word
        cp AR_K16
        jr z,.v
        cp AR_KT
        jr z,.v
        cp AR_KB
        ld hl,err_sc_const
        jp nz,sc_err
        ld a,(sc_oi)
        ld l,a
        ld h,0
        ret
.v:     ld hl,(sc_ov)
        ret

; ---- sc_lvop: C = index in the VAR block, B = type -> sc_oa / sc_oi
sc_lvop:
        ld a,b
        cp 3
        ld hl,err_sc_type
        jp nc,sc_err
        push bc
        ld a,(cp_slot)
        call lv_first
        pop bc
        add a,c
        ld (sc_oi),a
        ld a,b
        rlca
        rlca
        rlca
        rlca
        or AR_LV
        ld (sc_oa),a
        ret

; ---- sc_lvmode: the operand sc_oa / sc_oi (AR_LV) -> cp_mode / cp_arg /
;      cp_arg3 / cp_istime (BOOL: bit 0 of the word, INT / TIME: the word)
sc_lvmode:
        ld a,(sc_oi)
        ld l,a
        ld h,0
        add hl,hl
        ld de,LV_BASE
        add hl,de
        ld (cp_arg),hl
        ld a,(sc_oa)
        and 0x30
        ld bc,VM_MB*256+1
        jr z,.s
        ld bc,VM_MBY*256+0
        cp 0x30                 ; BYTE (a global)
        jr z,.s
        ld bc,VM_MW*256+0
.s:     ld e,a
        ld a,c
        ld (cp_arg3),a
        ld a,b
        ld (cp_mode),a
        ld a,e
        cp 0x20                 ; TIME
        ld a,0
        jr nz,.t
        inc a
.t:     ld (cp_istime),a
        ret

; ---- sc_gvop: C = global number -> A = AR_LV + type * 16 (C kept)
sc_gvop:
        push bc
        call gv_find
        pop bc
        ld hl,err_il_op
        jp c,sc_err
        and 0x03
        rlca
        rlca
        rlca
        rlca
        or AR_LV
        ret

; ---- lv_first: A = slot -> A = the first LV index of its locals (the
;      locals of the ST POUs in the slots before it come first)
lv_first:
        ld (lf_n),a
        call gv_top             ; the globals come first (LV index = g)
        ld (lf_sum),a
        xor a
        ld (lf_s),a
.l:     ld a,(lf_s)
        ld hl,lf_n
        cp (hl)
        jr nc,.e
        call pou_lang
        cp LANG_ST
        jr nz,.n
        ld a,(lf_s)
        ld hl,lf_none
        call stc.st_vfind
        ld a,(stc.vf_cnt)
        ld hl,lf_sum
        add a,(hl)
        ld (hl),a
.n:     ld hl,lf_s
        inc (hl)
        jr .l
.e:     ld a,(lf_sum)
        ret

; ---- gv_init: the initial values of the globals -> LV_INIT (compiling)
gv_init:
        ld c,0
.l:     push bc
        call gv_find
        jr c,.n
        ld hl,0
        bit 7,a                 ; (GT_INIT)
        jr z,.z
        ex de,hl
.z:     ex de,hl
        pop bc
        push bc
        ld l,c
        ld h,0
        add hl,hl
        ld bc,LV_INIT
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
.n:     pop bc
        inc c
        ld a,c
        cp GV_MAX
        jr c,.l
        ret

; ---- lv_reset: the locals get their initial values (after compiling,
;      vm_reset). NC
lv_reset:
        ld hl,LV_INIT
        ld de,LV_BASE
        ld bc,LV_MAX*2
        ldir
        or a
        ret

; ---- st_lvaddr: A = POU slot, HL = name (upper case, fixed memory) ->
;      NC: a local of that POU, HL = its address, B = type; C: not one
;      (simulation monitor, BCALL from the EDIT bank)
st_lvaddr:
        push af
        call stc.st_vfind
        jr c,.no
        ld a,b
        cp 3
        jr nc,.no
        pop af
        push bc
        call lv_first
        pop bc
        add a,c
        ld l,a
        ld h,0
        add hl,hl
        ld de,LV_BASE
        add hl,de
        or a
        ret
.no:    pop af
        scf
        ret

; ---- st_lvrd: HL = address of a local -> its word copied to rd_c (fixed
;      memory), HL = rd_c (simulation monitor)
st_lvrd:
        ld de,rd_c
        ldi
        ldi
        ld hl,rd_c
        ret

err_sc_dup:    db "Duplicate name",0
err_sc_many:   db "Too many variables",0
err_sc_type:   db "BOOL, INT or TIME expected",0
err_sc_vfirst: db "VAR only at the start",0
lf_none: db 0
lf_n:    db 0
lf_s:    db 0
lf_sum:  db 0
vd_base: db 0
vd_idx:  db 0
vd_g:    db 0

