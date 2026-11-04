; ============================================================
; operand.asm - IEC 61131-3 operand parser and formatter
; ============================================================
; Accepts:  %IXb.n %Ib.n Ib.n | %QXb.n %Qb.n Qb.n (b = 0-1) | %MXn %Mn Mn | %MWn MWn
;           %SXb.n %Sb.n Sb.n (step flags, b = 0-7)
;           TRUE FALSE | integer -32768..32767 | T#..  TIME#.. (units m, s, ms)
;           TON0..TON3, TOF, TP, CTU, CTD, RT (R_TRIG), RF (F_TRIG), SR, RS (+ .member)
;           symbol name, POU name
; ============================================================
OP_TOKMAX EQU 31

; ---- op_parse: HL = text -> NC: A = area, C = index, DE = value, HL past operand
;                             C: error (HL undefined)
op_parse:
        call op_gettok
        ret c
        or a
        scf
        ret z
        ld (op_after),hl
        ld hl,op_err
        ld (op_fail),hl
        ld de,0
        ld (op_val),de
        ld hl,op_tok
        ld a,(hl)
        cp '%'
        jp z,.direct
        cp '-'
        jp z,.num
        call is_digit
        jp nc,.num
        ; keywords
        ld de,kw_true
        call tok_eq
        jr nz,.nt
        ld c,1
        jr .kb
.nt:    ld de,kw_false
        call tok_eq
        jr nz,.nf
        ld c,0
.kb:    ld a,AR_KB
        jp op_ok
.nf:    ld hl,op_tok
        ld de,kw_t
        call str_prefix
        jp z,.time
        ld de,kw_time
        call str_prefix
        jp z,.time
        ; short forms
        ld hl,.fb
        ld (op_fail),hl
        ld hl,op_tok
        ld a,(hl)
        inc hl
        ld b,AR_I
        cp 'I'
        jr z,.short_iq
        ld b,AR_Q
        cp 'Q'
        jr z,.short_iq
        cp 'S'
        jr z,.short_s
        cp 'M'
        jp nz,.fb
        ld a,(hl)
        cp 'W'
        jr nz,.short_m
        inc hl
        ld a,(hl)
        call is_digit
        jp c,.fb
        jp .mw
.short_m:
        call is_digit
        jp c,.fb
        jp .mx
.short_iq:
        ld a,(hl)
        call is_digit
        jp c,.fb
        jp .ioaddr
.short_s:
        ld a,(hl)
        call is_digit
        jp c,.fb
        jr .sxaddr

        ; ---- direct addresses %
.direct:
        inc hl
        ld a,(hl)
        inc hl
        ld b,AR_I
        cp 'I'
        jr z,.diq
        ld b,AR_Q
        cp 'Q'
        jr z,.diq
        cp 'S'
        jr z,.dsx
        cp 'M'
        jp nz,op_err
        ld a,(hl)
        cp 'W'
        jr z,.dmw
        cp 'X'
        jr nz,.mx
        inc hl
        jr .mx
.dmw:   inc hl
        jr .mw
.dsx:   ld a,(hl)
        cp 'X'
        jr nz,.sxaddr
        inc hl
.sxaddr:                        ; b.n -> index b*8+n
        ld a,(hl)
        sub '0'
        jp c,op_fail_jp
        cp N_SB
        jp nc,op_fail_jp
        add a,a
        add a,a
        add a,a
        ld c,a
        inc hl
        ld a,(hl)
        cp '.'
        jp nz,op_fail_jp
        inc hl
        ld a,(hl)
        sub '0'
        jp c,op_fail_jp
        cp 8
        jp nc,op_fail_jp
        or c
        ld c,a
        inc hl
        ld a,(hl)
        or a
        jp nz,op_fail_jp
        ld a,AR_SX
        jp op_ok
.diq:   ld a,(hl)
        cp 'X'
        jr nz,.ioaddr
        inc hl
.ioaddr:                        ; b.n -> index b*8+n
        ld a,(hl)
        sub '0'
        jp c,op_fail_jp
        cp N_IOB
        jp nc,op_fail_jp
        add a,a
        add a,a
        add a,a
        ld c,a
        inc hl
        ld a,(hl)
        cp '.'
        jp nz,op_fail_jp
        inc hl
        ld a,(hl)
        sub '0'
        jp c,op_fail_jp
        cp 8
        jp nc,op_fail_jp
        or c
        ld c,a
        inc hl
        ld a,(hl)
        or a
        jp nz,op_fail_jp
        ld a,b
        jp op_ok
.mx:    ld b,AR_M
        ld e,N_M
        jr .idxnum
.mw:    ld b,AR_MW
        ld e,N_MW
.idxnum:
        ld a,e
        ld (op_lim),a
        ld a,b
        ld (op_area),a
        call parse_uint
        jp c,op_fail_jp
        ld a,(hl)
        or a
        jp nz,op_fail_jp
        ld a,d
        or a
        jp nz,op_fail_jp
        ld a,(op_lim)
        ld b,a
        ld a,e
        cp b
        jp nc,op_fail_jp
        ld c,a
        ld a,(op_area)
        jp op_ok

        ; ---- number
.num:   ld a,(hl)
        cp '-'
        push af
        jr nz,.n1
        inc hl
.n1:    call parse_uint
        jr c,.nerr
        ld a,(hl)
        or a
        jr nz,.nerr
        pop af
        jr z,.neg
        bit 7,d
        jp nz,op_err
        jr .nok
.neg:   ld hl,32768
        or a
        sbc hl,de
        jp c,op_err
        ex de,hl
        call neg_hl
        ex de,hl
.nok:   ld (op_val),de
        ld a,AR_K16
        ld c,0
        jp op_ok
.nerr:  pop af
        jp op_err

        ; ---- time: HL past '#'
.time:  ld a,(hl)
        or a
        jp z,op_err
.tl:    ld a,(hl)
        or a
        jr z,.tdone
        call parse_uint
        jp c,op_err
        ld a,(hl)
        inc hl
        cp 'S'
        jr z,.ts
        cp 'M'
        jp nz,op_err
        ld a,(hl)
        cp 'S'
        jr z,.tms
        ; minutes: max 21
        ld a,d
        or a
        jp nz,op_err
        ld a,e
        cp 22
        jp nc,op_err
        ld bc,3000
        jr .tmul
.ts:    ; seconds: max 1310
        push hl
        ld hl,1310
        or a
        sbc hl,de
        pop hl
        jp c,op_err
        ld bc,50
.tmul:  push hl
        ex de,hl
        ld d,b
        ld e,c
        call mul16
        ex de,hl
        jr .tadd
.tms:   inc hl
        push hl
        ex de,hl
        ld de,20
        call div16u         ; HL = ms/20
        ex de,hl
.tadd:  ld hl,(op_val)
        add hl,de
        jp c,.tovf
        ld (op_val),hl
        pop hl
        jr .tl
.tovf:  pop hl
        jp op_err
.tdone: ld de,(op_val)
        ld a,AR_KT
        ld c,0
        jp op_ok

        ; ---- FB instances and members
.fb:    ld hl,.pou
        ld (op_fail),hl
        ld de,fb_names
        ld b,0
.fbl:   push bc
        push de
        ld hl,op_tok
        call str_prefix
        pop de
        pop bc
        jr z,.fbm
.fbn:   ld hl,7
        add hl,de
        ex de,hl
        inc b
        ld a,b
        cp FB_TYPES
        jr c,.fbl
        jp .pou
.fbm:   ld a,(hl)
        sub '0'
        jr c,.fbn
        cp FB_PER_TYPE
        jr nc,.fbn
        ld c,a
        ld a,b
        add a,a
        add a,a
        add a,c
        ld c,a              ; instance index
        inc hl
        ld a,(hl)
        or a
        jr nz,.fbmem
        ld a,AR_FBI
        jp op_ok
.fbmem: cp '.'
        jp nz,.pou
        inc hl
        ld (op_ptr),hl
        ; member table of type B: fb_members + B*20
        ld a,b
        add a,a
        add a,a
        ld l,a
        add a,a
        add a,a
        add a,l             ; B*20
        ld l,a
        ld h,0
        ld de,fb_members
        add hl,de
        ex de,hl
        ld b,0
.mem:   ld a,(de)
        or a
        jr z,.memn
        push de
        push bc
        ld hl,(op_ptr)
        call str_prefix
        pop bc
        pop de
        jr nz,.memn
        ld a,(hl)
        or a
        jr z,.memok
.memn:  inc de
        inc de
        inc de
        inc de
        inc b
        ld a,b
        cp 5
        jr c,.mem
        jp op_err
.memok: ld a,b
        add a,a
        add a,a
        add a,a
        add a,a
        or AR_FBM
        jp op_ok

        ; ---- symbol, then POU name
.pou:   ld hl,op_tok
        call sym_find_name
        jp nc,op_ok
        ; "SYMBOL.MEMBER": symbol of an FB instance + member
        ld hl,op_tok
.dot:   ld a,(hl)
        or a
        jr z,.pou2
        cp '.'
        jr z,.sdot
        inc hl
        jr .dot
.sdot:  ld (hl),0
        push hl
        ld hl,op_tok
        call sym_find_name
        pop hl
        ld (hl),'.'
        jr c,.pou2
        cp AR_FBI
        jr nz,.pou2
        ld a,c                  ; B = FB type, C = instance
        rrca
        rrca
        and 0x3F
        ld b,a
        ld a,'.'
        jp .fbmem
.pou2:  ld hl,op_tok
        call strlen
        cp 9
        jp nc,op_err
        call name_pad
        ld hl,name8
        call pou_find
        jp c,op_err
        ld c,a
        ld a,AR_POU
        jp op_ok

op_fail_jp:
        ld hl,(op_fail)
        jp (hl)
op_err: scf
        ret
op_ok:  ld de,(op_val)
        ld hl,(op_after)
        or a
        ret

; ---- op_gettok: HL = text -> op_tok (upper case), HL past token, A = length, C = too long
op_gettok:
        ld a,(hl)
        cp ' '
        jr nz,.st
        inc hl
        jr op_gettok
.st:    ld de,op_tok
        ld b,0
.c:     ld a,(hl)
        call to_upper
        cp '-'
        jr nz,.c2
        ld c,a
        ld a,b
        or a
        jr nz,.end
        ld a,c
        jr .take
.c2:    cp '%'
        jr z,.take
        cp '#'
        jr z,.take
        cp '.'
        jr z,.take
        cp '_'
        jr z,.take
        call is_digit
        jr nc,.take
        call is_alpha
        jr c,.end
.take:  ld c,a
        ld a,b
        cp OP_TOKMAX
        ccf
        ret c
        ld a,c
        ld (de),a
        inc de
        inc b
        inc hl
        jr .c
.end:   xor a
        ld (de),a
        ld a,b
        or a
        ret

; ---- parse_uint: HL = text -> DE = value, HL past digits; C = no digit / overflow
parse_uint:
        ld de,0
        ld a,(hl)
        call is_digit
        ret c
.lp:    ld a,(hl)
        sub '0'
        jr c,.end
        cp 10
        jr nc,.end
        push hl
        ld h,d
        ld l,e
        add hl,hl
        jr c,.ovf
        ld b,h
        ld c,l
        add hl,hl
        jr c,.ovf
        add hl,hl
        jr c,.ovf
        add hl,bc
        jr c,.ovf
        ld c,a
        ld b,0
        add hl,bc
        jr c,.ovf
        ex de,hl
        pop hl
        inc hl
        jr .lp
.ovf:   pop hl
        scf
        ret
.end:   or a
        ret

; ---- str_prefix: HL = text, DE = pattern (0) -> Z: text starts with pattern, HL past it; NZ: HL unchanged
str_prefix:
        push hl
.l:     ld a,(de)
        or a
        jr z,.yes
        cp (hl)
        jr nz,.no
        inc hl
        inc de
        jr .l
.yes:   inc sp
        inc sp
        ret                 ; Z from "or a"
.no:    pop hl
        or a                ; A = pattern char != 0 -> NZ
        ret

; ---- tok_eq: DE = word -> Z if op_tok == word
tok_eq:
        ld hl,op_tok
        call str_prefix
        ret nz
        ld a,(hl)
        or a
        ret

; ---- op_format: A = area, C = index, HL = value, DE = dest, B = style (0 IEC, 1 short)
;      output: DE points to the terminating 0
op_format:
        ld (op_area),a
        ld (op_val),hl
        ld a,c
        ld (op_idx),a
        ld a,b
        ld (op_style),a
        ld a,(op_area)
        and AR_MASK
        cp AR_POU+1
        jr c,.ok
        xor a
.ok:    ld hl,.tab
        jp jump_table
.tab:   dw .f_none,.f_i,.f_q,.f_m,.f_mw,.f_s,.f_kb,.f_k16,.f_kt,.f_fbi,.f_fbm,.f_pou

.f_none:
        ld hl,s_qq
        jp .str_end
.f_i:   ld hl,s_iec_i
        ld bc,s_sh_i
        jr .bit
.f_q:   ld hl,s_iec_q
        ld bc,s_sh_q
.bit:   call .style
        call put_str
        jr .bn
.f_m:   ld hl,s_iec_m
        ld bc,s_sh_m
        jr .numidx
.f_mw:  ld hl,s_iec_mw
        ld bc,s_sh_mw
        jr .numidx
.f_s:   ld hl,s_iec_s           ; %SXb.n / Sb.n
        ld bc,s_sh_s
        call .style
        call put_str
.bn:    ld a,(op_idx)           ; b.n
        rrca
        rrca
        rrca
        and 7
        add a,'0'
        ld (de),a
        inc de
        ld a,'.'
        ld (de),a
        inc de
        ld a,(op_idx)
        and 7
        add a,'0'
        ld (de),a
        inc de
        jp .end
.numidx:
        call .style
        call put_str
        ld a,(op_idx)
        ld l,a
        ld h,0
        jp utoa16
.f_kb:  ld hl,kw_false
        ld a,(op_idx)
        or a
        jr z,.str_end
        ld hl,kw_true
.str_end:
        call put_str
        jp .end
.f_k16: ld hl,(op_val)
        jp itoa16
.f_kt:  ld hl,kw_t
        call put_str
        ld hl,(op_val)
        push de
        ld de,50
        call div16u         ; HL = s, DE = remaining ticks
        ld (op_ms),de
        ex de,hl
        pop hl
        ex de,hl            ; HL = s, DE = dest
        ld a,h
        or l
        jr z,.nosec
        call utoa16
        ld a,'s'
        ld (de),a
        inc de
        ld hl,(op_ms)
        ld a,h
        or l
        jp z,.end
        jr .ms
.nosec: ld hl,(op_ms)
        ld a,h
        or l
        jr nz,.ms
        ld a,'0'
        ld (de),a
        inc de
        ld a,'s'
        ld (de),a
        inc de
        jp .end
.ms:    push de
        ld de,20
        call mul16
        pop de
        call utoa16
        ld a,'m'
        ld (de),a
        inc de
        ld a,'s'
        ld (de),a
        inc de
        jp .end
.f_fbi: call .fbname
        jp .end
.f_fbm: call .fbname
        ld a,'.'
        ld (de),a
        inc de
        ld a,(op_idx)
        rrca
        rrca
        and 0x3F            ; type
        ld l,a
        add a,a
        add a,a
        ld h,a
        add a,a
        add a,a
        add a,h             ; type*20
        ld l,a
        ld h,0
        ld bc,fb_members
        add hl,bc
        ld a,(op_area)
        rrca
        rrca
        and 0x1C            ; member*4
        add a,l
        ld l,a
        jr nc,.m1
        inc h
.m1:    jp .str_end
.f_pou: ld a,(op_idx)
        call pou_entry
        call pou_used_hl
        jp z,.f_none
        jp name_unpad
; writes type name + instance number
.fbname:
        ld a,(op_idx)
        rrca
        rrca
        and 0x3F
        ld l,a
        add a,a
        add a,a
        add a,a
        sub l               ; type*7
        ld l,a
        ld h,0
        ld bc,fb_names
        add hl,bc
        call put_str
        ld a,(op_idx)
        and 3
        add a,'0'
        ld (de),a
        inc de
        ret
; selects HL (IEC) or BC (short) by style
.style: ld a,(op_style)
        or a
        ret z
        ld h,b
        ld l,c
        ret
.end:   xor a
        ld (de),a
        ret

; pou_used_hl: HL = entry -> NZ if used
pou_used_hl:
        ld a,(hl)
        or a
        ret

; ---- put_str: HL = string (0) -> copied to DE (without 0), DE advanced
put_str:
        ld a,(hl)
        or a
        ret z
        ld (de),a
        inc hl
        inc de
        jr put_str

kw_true:  db "TRUE",0
kw_false: db "FALSE",0
kw_t:     db "T#",0
kw_time:  db "TIME#",0
s_qq:     db "???",0
s_iec_i:  db "%IX",0
s_iec_q:  db "%QX",0
s_iec_m:  db "%MX",0
s_iec_mw: db "%MW",0
s_iec_s:  db "%SX",0
s_sh_i:   db "I",0
s_sh_q:   db "Q",0
s_sh_m:   db "M",0
s_sh_mw:  db "MW",0
s_sh_s:   db "S",0

; FB type names, 7-byte records
FBT_TON    EQU 0
FBT_TOF    EQU 1
FBT_TP     EQU 2
FBT_CTU    EQU 3
FBT_CTD    EQU 4
FBT_RTRIG  EQU 5
FBT_FTRIG  EQU 6
FBT_SR     EQU 7
FBT_RS     EQU 8
fb_names:
        db "TON",0,0,0,0
        db "TOF",0,0,0,0
        db "TP",0,0,0,0,0
        db "CTU",0,0,0,0
        db "CTD",0,0,0,0
        db "RT",0,0,0,0,0          ; R_TRIG (rising edge)
        db "RF",0,0,0,0,0          ; F_TRIG (falling edge)
        db "SR",0,0,0,0,0
        db "RS",0,0,0,0,0
; members: 5 records of 4 B per type
fb_members:
        db "IN",0,0, "PT",0,0, "Q",0,0,0, "ET",0,0, 0,0,0,0     ; TON
        db "IN",0,0, "PT",0,0, "Q",0,0,0, "ET",0,0, 0,0,0,0     ; TOF
        db "IN",0,0, "PT",0,0, "Q",0,0,0, "ET",0,0, 0,0,0,0     ; TP
        db "CU",0,0, "R",0,0,0, "PV",0,0, "Q",0,0,0, "CV",0,0   ; CTU
        db "CD",0,0, "LD",0,0, "PV",0,0, "Q",0,0,0, "CV",0,0    ; CTD
        db "CLK",0,  "Q",0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0       ; R_TRIG
        db "CLK",0,  "Q",0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0       ; F_TRIG
        db "S1",0,0, "R",0,0,0, "Q1",0,0, 0,0,0,0, 0,0,0,0      ; SR
        db "S",0,0,0, "R1",0,0, "Q1",0,0, 0,0,0,0, 0,0,0,0      ; RS

op_tok:   ds OP_TOKMAX+1
op_after: dw 0
op_fail:  dw 0
op_val:   dw 0
op_ptr:   dw 0
op_ms:    dw 0
op_lim:   db 0
op_area:  db 0
op_idx:   db 0
op_style: db 0
