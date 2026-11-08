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

; ---- wx_edit: A = type, B = 1: start from the element in ld_gext
;      -> NC: WD_EXT = the operator and operands; C: cancelled.
;      The operator is chosen from a list, then the values are asked one by
;      one (A, B, and the result D of a compute element). WD_LINK = 1: A is
;      given by the editor (FBD chaining) and not asked.
wx_edit:
        ld (wx_t),a
        ld a,b
        ld (wx_old),a
        ld hl,ld_gext           ; the old values (or nothing)
        ld de,WD_EXT
        ld bc,9
        or a
        jr z,.clr
        ldir
        jr .op
.clr:   ld hl,WD_EXT            ; a new element: no values yet
        ld de,WD_EXT+1
        ld bc,8
        ld (hl),0
        ldir
.op:    call wx_choose          ; the operator
        jr c,.end
        ld (WD_EXT+3),a
        ld a,(WD_LINK)          ; A
        or a
        jr nz,.b
        ld hl,txt_wx_qa
        ld de,WD_EXT
        call wx_ask
        jr c,.end
.b:     ld a,(WD_EXT+3)         ; B (not for MOVE)
        cp OP_LD
        jr z,.d
        ld hl,txt_wx_qb
        ld de,WD_EXT+4
        call wx_ask
        jr c,.end
.d:     ld a,(wx_t)             ; the result D (compute)
        and LT_MASK
        cp LT_MATH
        jr nz,.ok
        ld hl,txt_wx_qd
        ld de,WD_EXT+7
        call wx_ask
        jr c,.end
.ok:    or a
.end:   push af
        xor a
        ld (WD_LINK),a
        pop af
        ret

; ---- wx_ask: HL = prompt, DE = slot in WD_EXT -> NC: the slot holds the
;      typed value (D slot: an MW only); C: cancelled
wx_ask: ld (wx_q),hl
        ld (wx_slot),de
        ld hl,(wx_slot)         ; start text: the value in the slot
        ld de,WD_TEXT
        xor a
        ld (de),a
        ld a,(hl)
        or a
        jr z,.ask
        BCALL il_fmt_short
        xor a
        ld (de),a
.ask:   ld hl,(wx_q)
        call popup_open
        ld a,(win_r)
        add a,2
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
        ld hl,WD_TEXT
        ld de,WX_PBUF
        ld bc,24
        ldir
        ld hl,WX_PBUF
        ld de,(wx_slot)
        ld a,e
        cp (WD_EXT+7)&0xFF
        jr z,.dst
        call wx_operand
        jr nc,.ret
.bad:   call ui_error           ; HL = message
        jr .ask
.dst:   call op_parse           ; D: a word variable (MW)
        jr c,.bd
        ld b,a
        ld a,(hl)
        or a
        jr nz,.bd
        ld a,b
        cp AR_MW
        jr nz,.bd
        ld (WD_EXT+7),a
        ld a,c
        ld (WD_EXT+8),a
.ret:   or a
        ret
.bd:    ld hl,txt_wx_bdst
        jr .bad

; ---- wx_choose: the operator list of wx_t (the current one selected when
;      editing) -> NC: A = op; C: cancelled
wx_choose:
        ld hl,wx_cl_cmp
        ld a,(wx_t)
        and LT_MASK
        cp LT_MATH
        jr nz,.l
        ld hl,wx_cl_math
.l:     ld (wx_list),hl
        ld de,popup_buf         ; popup text: the labels, one per line
        ld c,0                  ; C = items
.t:     ld a,(hl)
        cp 0xFF
        jr z,.te
        inc hl
        inc c
        call put_str
        inc hl
        xor a
        ld (de),a
        inc de
        jr .t
.te:    xor a
        ld (de),a
        ld a,c
        ld (wx_n),a
        xor a                   ; selection: the current operator
        ld (wx_sel),a
        ld a,(wx_old)
        or a
        jr z,.open
        ld hl,(wx_list)
        ld b,0
.f:     ld a,(hl)
        cp 0xFF
        jr z,.open
        ld c,a
        ld a,(WD_EXT+3)
        cp c
        jr z,.fs
        inc b
        inc hl
.fz:    ld a,(hl)
        inc hl
        or a
        jr nz,.fz
        jr .f
.fs:    ld a,b
        ld (wx_sel),a
.open:  ld hl,popup_buf
        call popup_open
.bar:   call .inv
.k:     call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.dn
        cp K_ENTER
        jr z,.ok
        cp K_BREAK
        jr z,.can
        cp K_EDIT
        jr z,.can
        jr .k
.up:    ld a,(wx_sel)
        or a
        jr z,.k
        call .inv
        ld hl,wx_sel
        dec (hl)
        jr .bar
.dn:    ld a,(wx_n)
        dec a
        ld hl,wx_sel
        cp (hl)
        jr z,.k
        call .inv
        ld hl,wx_sel
        inc (hl)
        jr .bar
.can:   call win_close
        scf
        ret
.ok:    call win_close
        ld hl,(wx_list)         ; the operator of item wx_sel
        ld a,(wx_sel)
        ld b,a
        inc b
.o:     dec b
        jr z,.oe
        inc hl
.oz:    ld a,(hl)
        inc hl
        or a
        jr nz,.oz
        jr .o
.oe:    ld a,(hl)
        or a
        ret
.inv:   ld a,(win_r)            ; the selection bar (XOR)
        inc a
        ld hl,wx_sel
        add a,(hl)
        ld b,a
        ld a,(win_bx)
        add a,4
        ld c,a
        ld a,(win_bw)
        sub 8
        ld d,a
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

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
wx_old: db 0
wx_q:   dw 0
wx_slot: dw 0
wx_list: dw 0
wx_n:   db 0
wx_sel: db 0

; operator lists: op, label (with a tab to the formula), 0; 0xFF ends
wx_cl_cmp:
        db OP_GT,"GT",PT_TAB,"A > B",0
        db OP_GE,"GE",PT_TAB,"A >= B",0
        db OP_EQ,"EQ",PT_TAB,"A = B",0
        db OP_NE,"NE",PT_TAB,"A <> B",0
        db OP_LE,"LE",PT_TAB,"A <= B",0
        db OP_LT,"LT",PT_TAB,"A < B",0
        db 0xFF
wx_cl_math:
        db OP_ADD,"ADD",PT_TAB,"D := A + B",0
        db OP_SUB,"SUB",PT_TAB,"D := A - B",0
        db OP_MUL,"MUL",PT_TAB,"D := A * B",0
        db OP_DIV,"DIV",PT_TAB,"D := A / B",0
        db OP_LD,"MOVE",PT_TAB,"D := A",0
        db 0xFF
wx_a:   dw 0
wx_b:   dw 0

wx_ops: db OP_ADD,"+",0, OP_SUB,"-",0, OP_MUL,"*",0, OP_DIV,"/",0
        db OP_GT,">",0, OP_GE,">=",0, OP_EQ,"=",0, OP_NE,"<>",0
        db OP_LE,"<=",0, OP_LT,"<",0
txt_wx_asg:  db ":=",0
txt_wx_qa:   db "Value A (MW / number / T#.. / ET / CV):",0," ",0," ",0,0
txt_wx_qb:   db "Value B (MW / number / T#.. / ET / CV):",0," ",0," ",0,0
txt_wx_qd:   db "Result D (MW):",0," ",0," ",0,0
txt_wx_bdst: db "MW expected (e.g. MW3)",0
txt_wx_bad:  db "Word operand expected (MW / value / ET)",0
