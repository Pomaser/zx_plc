; ============================================================
; wexpr.asm - word compare / arithmetic elements of LD and FBD (DEMO bank)
; ============================================================
; LT_CMP  (LD contact, FBD input):  A op B         op: > >= = <> <= <
; LT_MATH (LD coil, FBD output):    D := A op B    op: + - * /, or D := A
; The record holds [A area lo hi][op][B area lo hi][D area idx] after
; [row][pos][type] (ld_gext, defs.asm). The editors call wx_edit for the
; expression (one input line) and wx_fmt for the label / status text.
; ============================================================

; ---- wx_fmt: A = type -> HL = WD_TEXT: "MW1>=5" / "MW2:=MW1+5" from ld_gext
wx_fmt: ld (wx_t),a
        ld de,WD_TEXT
        and LT_MASK
        cp LT_MATH
        jr nz,.ab
        ld hl,ld_gext+7         ; D :=
        BCALL il_fmt_short
        ld hl,txt_wx_asg
        call put_str
.ab:    ld hl,ld_gext           ; A
        BCALL il_fmt_short
        ld a,(ld_gext+3)
        cp OP_LD
        jr z,.e                 ; MOVE
        call wx_opstr
        call put_str
        ld hl,ld_gext+4         ; B
        BCALL il_fmt_short
.e:     xor a
        ld (de),a
        ld hl,WD_TEXT
        ret

; ---- wx_opstr: A = op -> HL = its text
wx_opstr:
        ld hl,wx_ops
.l:     cp (hl)
        inc hl
        ret z
.s:     ld b,(hl)
        inc hl
        inc b
        djnz .s
        jr .l

; ---- wx_edit: A = type, B = 1: start with the expression in ld_gext
;      -> NC: WD_EXT = the new operands; C: cancelled
wx_edit:
        ld (wx_t),a
        ld a,b
        or a
        jr z,.empty
        ld a,(wx_t)
        call wx_fmt
        jr .ask
.empty: xor a
        ld (WD_TEXT),a
.ask:   ld hl,txt_wx_cq
        ld a,(wx_t)
        and LT_MASK
        cp LT_MATH
        jr nz,.q
        ld hl,txt_wx_mq
.q:     call popup_open
        ld a,(win_r)
        add a,3
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,WD_TEXT
        ld de,0x1401            ; 20 chars, upper case
        call ui_input
        push af
        call win_close
        pop af
        ret c
        call wx_parse
        ret nc
        call ui_error           ; HL = message
        jr .ask

; ---- wx_parse: WD_TEXT -> NC: WD_EXT; C: HL = error message
;      (a copy in WX_PBUF is cut into pieces; WD_TEXT stays for a retry)
wx_parse:
        ld hl,WD_TEXT
        ld de,WX_PBUF
        ld bc,64
        ldir
        ld hl,WX_PBUF
        ld a,(wx_t)
        and LT_MASK
        cp LT_MATH
        jr nz,.expr
        ld b,0                  ; D := ...
.fd:    ld a,(hl)
        or a
        jr z,.syn
        cp ':'
        jr nz,.fn
        inc hl
        ld a,(hl)
        dec hl
        cp '='
        jr z,.fdd
.fn:    inc hl
        jr .fd
.fdd:   ld (hl),0
        push hl
        ld hl,WX_PBUF
        call op_parse
        jr c,.bdp
        ld b,a
        ld a,(hl)
        or a
        jr nz,.bdp
        ld a,b
        cp AR_MW                ; the target: a word variable
        jr nz,.bdp
        ld (WD_EXT+7),a
        ld a,c
        ld (WD_EXT+8),a
        pop hl
        inc hl
        inc hl
.expr:  ld (wx_a),hl            ; A op B: the operator after the first char
        ld a,(hl)
        or a
        jr z,.syn
        inc hl
.fo:    ld a,(hl)
        or a
        jr z,.noop
        call wx_isop
        jr z,.op
        inc hl
        jr .fo
.noop:  ld a,(wx_t)             ; no operator: MOVE (arithmetic only)
        and LT_MASK
        cp LT_MATH
        jr nz,.syn
        ld a,OP_LD
        ld (WD_EXT+3),a
        ld hl,(wx_a)
        ld de,WD_EXT
        jp wx_operand
.op:    ld (WD_EXT+3),a         ; A = op, B = its length
        ld (hl),0
        ld e,b
        ld d,0
        add hl,de
        ld (wx_b),hl
        ld hl,(wx_a)
        ld de,WD_EXT
        call wx_operand
        ret c
        ld hl,(wx_b)
        ld de,WD_EXT+4
        jp wx_operand
.bdp:   pop hl
        ld hl,txt_wx_bad
        scf
        ret
.syn:   ld hl,txt_wx_csyn
        ld a,(wx_t)
        and LT_MASK
        cp LT_MATH
        jr nz,.se
        ld hl,txt_wx_msyn
.se:    scf
        ret

; ---- wx_isop: HL = text -> Z: an operator of wx_t, A = op, B = length
wx_isop:
        ld b,1
        ld a,(wx_t)
        and LT_MASK
        cp LT_MATH
        ld a,(hl)
        jr nz,.cmp
        ld c,OP_ADD
        cp '+'
        jr z,.c
        inc c
        cp '-'
        jr z,.c
        inc c
        cp '*'
        jr z,.c
        inc c
        cp '/'
        jr z,.c
        ret
.cmp:   ld c,OP_EQ
        cp '='
        jr z,.c
        cp '>'
        jr z,.gt
        cp '<'
        ret nz
        inc hl                  ; < <= <>
        ld a,(hl)
        dec hl
        ld c,OP_LE
        cp '='
        jr z,.c2
        ld c,OP_NE
        cp '>'
        jr z,.c2
        ld c,OP_LT
        jr .c
.gt:    inc hl                  ; > >=
        ld a,(hl)
        dec hl
        ld c,OP_GE
        cp '='
        jr z,.c2
        ld c,OP_GT
.c:     ld a,c
        cp a                    ; Z
        ret
.c2:    inc b
        jr .c

; ---- wx_operand: HL = text, DE = slot -> [area][lo][hi]; C: HL = error
wx_operand:
        push de
        call op_parse
        pop ix                  ; IX = slot
        jr c,.bad
        ld b,a
        ld a,(hl)
        or a
        jr nz,.bad
        ld a,b                  ; a word: MW, constant, FB member
        and AR_MASK
        cp AR_MW
        jr z,.ok
        cp AR_FBM
        jr z,.ok
        cp AR_K16
        jr z,.k
        cp AR_KT
        jr nz,.bad
.k:     ld c,e                  ; constant: value
        ld a,d
        jr .st
.ok:    xor a                   ; variable: index
.st:    ld (ix+0),b
        ld (ix+1),c
        ld (ix+2),a
        or a
        ret
.bad:   ld hl,txt_wx_bad
        scf
        ret

WX_PBUF EQU rd_c                ; (64 bytes, free in the editors)
wx_t:   db 0
wx_a:   dw 0
wx_b:   dw 0

wx_ops: db OP_ADD,"+",0, OP_SUB,"-",0, OP_MUL,"*",0, OP_DIV,"/",0
        db OP_GT,">",0, OP_GE,">=",0, OP_EQ,"=",0, OP_NE,"<>",0
        db OP_LE,"<=",0, OP_LT,"<",0
txt_wx_asg:  db ":=",0
txt_wx_cq:   db "Compare A with B (e.g. MW1>=5):",0
             db "operators  > >= = <> <= <",0," ",0," ",0,0
txt_wx_mq:   db "Compute D:=A op B (e.g. MW2:=MW1+5):",0
             db "operators  + - * /   D:=A copies",0," ",0," ",0,0
txt_wx_csyn: db "Write it as A>B (> >= = <> <= <)",0
txt_wx_msyn: db "Write it as D:=A+B (+ - * /)",0
txt_wx_bad:  db "Word operand expected (MW / value / ET)",0
