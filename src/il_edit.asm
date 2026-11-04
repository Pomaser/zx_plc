; ============================================================
; il_edit.asm - Instruction List editor
; ============================================================
; POU body = line records [len][kind][text...], len = whole record.
;   kind 0 empty, 1 instruction ("MNEM<TAB>operand"), 2 label ("NAME:"),
;   kind 3 comment ("//...").
; Screen: rows 1-22, one line per char row. Cells 0-2 line number
; (bright white paper), separator at x=23, mnemonic cells 3-7 (dark
; blue), operand from cell 8 (black), comment rows dark green.
; ============================================================
IL_ROW0   EQU 1
IL_ROWS   EQU 22
IL_X_NUM  EQU 21            ; right edge of the line number
IL_NUM_PITCH EQU 5          ; fixed digit pitch of line numbers
IL_X_SEP  EQU 23
IL_X_MNEM EQU 28
IL_X_OPER EQU 64            ; = cell 8
IL_X_MAX  EQU 254
IL_MAXLN  EQU 999
ED_MLEN   EQU 10
ED_OLEN   EQU 48
ED_CLEN   EQU 48
F_MNEM    EQU 0
F_OPER    EQU 1
F_COMM    EQU 2
K_EMPTY   EQU 0
K_INSTR   EQU 1
K_LABEL   EQU 2
K_COMM    EQU 3
K_NONE    EQU 0xFF          ; row below the last line

; ---- il_editor: screen handler for an IL POU, returns a command in A
il_editor:
        call screen_begin
        ld a,(cur_pou)
        ld hl,il_pou
        cp (hl)
        jr z,.same
        ld (hl),a
        ld hl,0
        ld (il_cur),hl
        ld (il_top),hl
.same:  call il_count
        ld hl,(il_n)
        ld a,h
        or l
        jr nz,.has
        ld de,0
        call il_ins_empty       ; an IL POU always has at least one line
.has:   ld hl,(il_cur)
        ld de,(il_n)
        or a
        sbc hl,de
        jr c,.okc
        ld hl,(il_n)
        dec hl
        ld (il_cur),hl
.okc:   call il_load
        call il_fix_top
.full:  call il_redraw_all
.loop:  call il_key
        cp K_ENTER
        jp z,.enter
        cp K_UP
        jp z,.up
        cp K_DOWN
        jp z,.down
        cp K_LEFT
        jp z,.left
        cp K_RIGHT
        jp z,.right
        cp K_DEL
        jp z,.del
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        cp K_HOME
        jp z,.home
        cp K_END
        jp z,.end
        cp K_PGUP
        jp z,.pgup
        cp K_PGDN
        jp z,.pgdn
        cp K_SSENTER
        jp z,.ssent
        cp 32
        jr c,.loop
        cp 128
        jr nc,.loop
        ld (il_ch),a
        ld a,(ed_field)
        cp F_MNEM
        jr nz,.ins
        ld a,(il_ch)
        cp ' '
        jp z,.space
        cp '/'
        jr nz,.ins
        ; "//" at the start of the line -> comment
        ld a,(ed_m)
        cp '/'
        jr nz,.ins
        ld a,(ed_m+1)
        or a
        jr nz,.ins
        ld hl,ed_c
        ld (hl),'/'
        inc hl
        ld (hl),'/'
        inc hl
        ld (hl),' '             ; "// " - text starts after a space
        inc hl
        ld (hl),0
        xor a
        ld (ed_m),a
        ld (ed_o),a
        ld a,F_COMM
        ld (ed_field),a
        ld a,3
        ld (ed_pos),a
        jr .redraw
.ins:   ld a,(ed_field)         ; first letter of a comment after "// ":
        cp F_COMM               ; typed as with CAPS LOCK
        jr nz,.ins1
        ld a,(ed_pos)
        cp 3
        jr nz,.ins1
        ld a,(ed_c+3)
        or a
        jr nz,.ins1
        ld a,(il_ch)
        call case_swap
        ld (il_ch),a
.ins1:  ld a,(il_ch)
        call ed_insert
        call c,beep
.redraw:                        ; text part only (no flicker of the line number)
        call il_draw_cur_text
        jp .loop
.redrawf:                       ; whole row incl. inverted line number
        call il_draw_cur
        jp .loop

        ; ---- SPACE in the mnemonic field: recognise and indent
.space: ld a,(ed_m)
        or a
        jp z,.loop
        ld hl,ed_m
        call il_mnem_find
        jr nc,.known
        call beep
        jp .loop
.known: ld hl,il_mtmp
        ld de,ed_m
        call put_str
        ld a,(il_mclass)
        bit 7,a
        jr z,.knp
        ld a,'('
        ld (de),a
        inc de
.knp:   xor a
        ld (de),a
        ld a,(il_mclass)
        and 0x7F
        cp IC_NONE
        jr z,.stay
        ld a,F_OPER
        ld (ed_field),a
        ld hl,ed_o
        call strlen
        ld (ed_pos),a
        jr .redraw
.stay:  ld hl,ed_m
        call strlen
        ld (ed_pos),a
        jr .redraw

        ; ---- cursor left / right
.left:  ld a,(ed_pos)
        or a
        jr z,.l0
        dec a
        ld (ed_pos),a
        jp .loop                ; only the cursor moves
.l0:    ld a,(ed_field)
        cp F_OPER
        jp nz,.loop
.tomnem:
        ld a,F_MNEM
        ld (ed_field),a
        ld hl,ed_m
        call strlen
        ld (ed_pos),a
        jr .redraw
.right: call ed_field_info
        call strlen
        ld b,a
        ld a,(ed_pos)
        cp b
        jp nc,.loop
        inc a
        ld (ed_pos),a
        jp .loop

        ; ---- SS+LEFT / SS+RIGHT: start / end of the line
.home:  ld a,(ed_field)
        cp F_OPER
        jr nz,.h1
        ld a,F_MNEM
        ld (ed_field),a
.h1:    xor a
        ld (ed_pos),a
        jp .redraw
.end:   ld a,(ed_field)         ; instruction with an operand: end of it
        cp F_MNEM
        jp nz,.en1
        ld a,(ed_o)
        or a
        jp z,.en1
        ld a,F_OPER
        ld (ed_field),a
.en1:   call ed_field_info
        call strlen
        ld (ed_pos),a
        jp .redraw

        ; ---- SS+UP / SS+DOWN: one screen up / down
.pgup:  call il_commit
        jp c,.loop
        ld hl,(il_cur)
        ld de,IL_ROWS-1
        or a
        sbc hl,de
        jp nc,.move
        ld hl,0
        jp .move
.pgdn:  call il_commit
        jp c,.loop
        ld hl,(il_cur)
        ld de,IL_ROWS-1
        add hl,de
        ld de,(il_n)            ; max. the last line
        or a
        sbc hl,de
        add hl,de
        jp c,.move
        ex de,hl
        dec hl
        jp .move

        ; ---- DELETE (backspace)
.del:   ld a,(ed_pos)
        or a
        jr z,.del0
        dec a
        ld (ed_pos),a
        call ed_del_char
        ld a,(ed_field)
        cp F_COMM
        jp nz,.redraw
        ld a,(ed_c+1)           ; comment shorter than "//" -> back to mnemonic
        or a
        jp nz,.redraw
        ld hl,ed_c
        ld de,ed_m
        call put_str
        xor a
        ld (de),a
        ld (ed_c),a
        jp .tomnem
.del0:  ld a,(ed_field)
        cp F_OPER
        jp z,.tomnem
        cp F_MNEM
        jp nz,.loop
        ld a,(ed_m)
        or a
        jp nz,.loop
        ld a,(ed_o)
        or a
        jp nz,.loop
        ; empty line: remove it (at least one line stays)
        ld hl,(il_n)
        dec hl
        ld a,h
        or l
        jp z,.loop
        ld de,(il_cur)
        call il_del_line
        ld hl,(il_cur)
        ld a,h
        or l
        jr z,.d2
        dec hl
        ld (il_cur),hl
.d2:    call il_load
        call il_fix_top
        jp nz,.full
        call il_row_cur
        call il_redraw_from
        jp .loop

        ; ---- ENTER: store the line, open a new one below
.enter: ; cursor at the very start of a non-empty line -> the line moves down
        xor a
        ld (il_atstart),a
        ld a,(ed_pos)
        or a
        jr nz,.e0
        ld a,(ed_field)
        cp F_OPER
        jr z,.e0
        call ed_kind
        cp K_EMPTY
        jr z,.e0
        ld a,1
        ld (il_atstart),a
        jr .e0
.ssent: xor a                   ; SS+ENTER: new line below wherever the cursor is
        ld (il_atstart),a
.e0:    call il_commit
        jp c,.loop
        ld hl,(il_n)
        ld de,IL_MAXLN
        or a
        sbc hl,de
        jp c,.e1
        ld hl,err_il_lines
        call ui_error
        jp .loop
.e1:    ld de,(il_cur)
        ld a,(il_atstart)
        or a
        jr z,.e2
        call il_ins_empty       ; empty line above, cursor stays with the text
        jp c,.loop
        ld hl,(il_cur)
        inc hl
        ld (il_cur),hl
        call il_load
        ld a,(ed_field)
        cp F_COMM
        jr z,.e3
        ld a,F_MNEM
        ld (ed_field),a
.e3:    xor a
        ld (ed_pos),a
        call il_fix_top
        jp nz,.full
        call il_row_cur
        dec a
        call il_redraw_from
        jp .loop
.e2:    inc de
        call il_ins_empty
        jp c,.loop
        ld hl,(il_cur)
        inc hl
        ld (il_cur),hl
        call il_load
        call il_fix_top
        jp nz,.full
        call il_row_cur
        dec a
        call il_redraw_from
        jp .loop

        ; ---- UP / DOWN
.up:    call il_commit
        jp c,.loop
        ld hl,(il_cur)
        ld a,h
        or l
        jp z,.redraw
        dec hl
        jr .move
.down:  call il_commit
        jp c,.loop
        ld hl,(il_cur)
        inc hl
        ld de,(il_n)
        or a
        sbc hl,de
        add hl,de
        jp nc,.redraw           ; already on the last line
.move:  push hl
        call il_row_cur
        ld (il_oldrow),a
        ld hl,(il_cur)
        ld (il_oldln),hl
        pop hl
        ld (il_cur),hl
        call il_load
        call il_fix_top
        jp nz,.full
        ld a,(il_oldrow)
        ld b,a
        ld de,(il_oldln)
        call il_draw_row
        jp .redrawf

        ; ---- menu
.menu:  call il_commit
        jp c,.loop
        call il_draw_cur
        call menu_handle
        jp z,.loop
        cp CMD_REDRAW
        jr nz,.m1
        call il_load
        jp .full
.m1:    cp CMD_IL_INS
        jr z,.mins
        cp CMD_IL_DEL
        jr z,.mdel
        ld hl,0
        ld (st_left),hl
        ret
.mins:  ld de,(il_cur)
        call il_ins_empty
        jp c,.loop
        call il_load
        call il_row_cur
        call il_redraw_from
        jp .loop
.mdel:  ld hl,(il_n)
        dec hl
        ld a,h
        or l
        jr z,.mclr
        ld de,(il_cur)
        call il_del_line
        ld hl,(il_cur)
        ld de,(il_n)
        or a
        sbc hl,de
        jr c,.md2
        ld hl,(il_n)
        dec hl
        ld (il_cur),hl
.md2:   call il_load
        call il_fix_top
        jp nz,.full
        call il_row_cur
        call il_redraw_from
        jp .loop
.mclr:  xor a                   ; the only line -> make it empty
        ld (ed_m),a
        ld (ed_o),a
        ld (ed_c),a
        ld (ed_pos),a
        ld (ed_field),a
        call il_commit
        jp .redrawf

; ============================================================
; line storage
; ============================================================

; ---- il_body_start: HL = body start of the current POU (keeps DE)
il_body_start:
        push de
        ld a,(cur_pou)
        call pou_body
        pop de
        ret

; ---- il_count: il_n = number of line records
il_count:
        ld a,(cur_pou)
        call pou_body
        ld de,0
.l:     ld a,b
        or c
        jr z,.e
        ld a,(hl)
        ld (ilt_len),a
        add a,l
        ld l,a
        jr nc,.n1
        inc h
.n1:    ld a,(ilt_len)
        push hl
        ld l,a
        ld h,0
        push bc
        ex (sp),hl              ; HL = remaining, (sp) = len
        pop bc                  ; BC = len
        or a
        sbc hl,bc
        ld b,h
        ld c,l
        pop hl
        inc de
        jr .l
.e:     ld (il_n),de
        ret

; ---- il_line_addr: DE = line -> HL = record address; C = DE >= il_n (HL = body end)
il_line_addr:
        push de
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (il_end),hl
        pop hl
        pop de
        push de
.l:     ld a,d
        or e
        jr z,.chk
        push de
        ld e,(hl)
        ld d,0
        add hl,de
        pop de
        dec de
        jr .l
.chk:   pop de
        push hl
        ld bc,(il_end)
        or a
        sbc hl,bc
        pop hl
        ccf
        ret

; ---- il_offset: HL = address in the body -> DE = offset
il_offset:
        push hl
        call il_body_start
        ex de,hl
        pop hl
        push hl
        or a
        sbc hl,de
        ex de,hl
        pop hl
        ret

; ---- il_ins_empty: DE = line index -> inserts an empty line; C = out of memory
il_ins_empty:
        call il_line_addr
        call il_offset
        ld bc,2
        ld a,(cur_pou)
        call pou_insert
        jr c,.mem
        ld (hl),2
        inc hl
        ld (hl),K_EMPTY
        ld hl,(il_n)
        inc hl
        ld (il_n),hl
        call status_right
        or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret

; ---- il_del_line: DE = line index
il_del_line:
        call il_line_addr
        call il_offset
        ld c,(hl)
        ld b,0
        ld a,(cur_pou)
        call pou_delete
        ld hl,(il_n)
        dec hl
        ld (il_n),hl
        jp status_right

; ---- il_commit: validates the edit buffer and stores it as line il_cur
;      C = error (message shown)
il_commit:
        call ed_kind
        ld (cm_kind),a
        cp K_COMM
        jp z,.comm
        cp K_EMPTY
        jr z,.empty
        cp K_LABEL
        jr z,.label
        ld hl,ed_m
        ld de,ed_o
        call il_check
        jp c,.err
        ld a,(il_outlen)        ; binary instruction
        ld c,a
        ld b,0
        ld hl,il_out
        ld de,rec_buf+2
        ldir
        jr .blen
.label: ld hl,ed_m
        call il_check_label
        jp c,.err
        ld hl,il_out
        jr .build
.comm:  ld hl,ed_c
        jr .build
.empty: ld hl,il_nothing
.build: ld de,rec_buf+2
        call put_str
.blen:  ex de,hl
        ld de,rec_buf
        or a
        sbc hl,de
        ld a,l
        ld (rec_buf),a
        ld a,(cm_kind)
        ld (rec_buf+1),a
        ; unchanged? -> nothing to store
        ld de,(il_cur)
        call il_line_addr
        ld (cm_addr),hl
        ld a,(rec_buf)
        ld b,a
        ld de,rec_buf
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.store
        inc hl
        inc de
        djnz .cmp
        jp .done
.store: ld hl,(cm_addr)
        call il_offset
        ld (cm_off),de
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ld a,(cur_pou)
        call pou_insert         ; new record in front of the old one
        jr c,.mem
        ex de,hl
        ld hl,rec_buf
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ldir
        ld hl,(cm_off)
        ld a,(rec_buf)
        ld e,a
        ld d,0
        add hl,de
        ex de,hl                ; DE = offset of the old record
        call il_body_start
        add hl,de
        ld c,(hl)
        ld b,0
        ld a,(cur_pou)
        call pou_delete
        call status_right
.done:  call il_load            ; show the normalised form
        or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret
.err:   ld hl,(il_err)
        call ui_error
        scf
        ret

; ---- il_split: HL = record, sp_m/sp_o/sp_c = buffers -> A = kind
;      (instructions are decoded from the binary form)
il_split:
        ld de,(sp_m)
        xor a
        ld (de),a
        ld de,(sp_o)
        ld (de),a
        ld de,(sp_c)
        ld (de),a
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (sp_end),hl          ; end of the record
        pop hl
        ld a,(hl)
        sub 2
        ld b,a
        inc hl
        ld a,(hl)
        ld (sp_kind),a
        inc hl
        cp K_COMM
        jp z,.comm
        cp K_EMPTY
        jr z,.done
        cp K_INSTR
        jr z,.instr
        ld de,(sp_m)            ; label text
.o:     ld a,b
        or a
        jr z,.end
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        dec b
        jr .o
.comm:  ld de,(sp_c)
        jr .o
.end:   xor a
        ld (de),a
.done:  ld a,(sp_kind)
        ret
.instr: ; binary instruction -> mnemonic text + operand text
        ld a,(hl)
        inc hl
        push hl
        push af
        and 0x3F
        ld l,a
        add a,a
        add a,a
        add a,a
        sub l                   ; *7
        ld l,a
        ld h,0
        ld de,il_mnems
        add hl,de
        ld de,(sp_m)
        ld b,6
.mn:    ld a,(hl)
        or a
        jr z,.mne
        ld (de),a
        inc hl
        inc de
        djnz .mn
.mne:   pop af
        bit 7,a
        jr z,.mnp
        ld a,'('
        ld (de),a
        inc de
.mnp:   xor a
        ld (de),a
        pop hl
        ld de,(sp_o)
        call il_fmt_opnd
        xor a
        ld (de),a
        ld a,K_INSTR
        ret

; ---- il_fmt_opnd: HL = binary operand (up to sp_end), DE = dest
;      writes the operand text (symbols if View > Symbols), FB parameters
il_fmt_opnd:
        call sp_more
        ret nc
        ld a,(hl)
        cp AR_LBL
        jr nz,.op
        inc hl                  ; label name
.lb:    call sp_more
        ret nc
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .lb
.op:    and AR_MASK
        cp AR_FBI
        push af
        ld a,(hl)
        inc hl
        ld c,(hl)               ; instance (for FB calls)
        dec hl
        ld (fo_inst),bc
        call il_fmt_one
        pop af
        ret nz                  ; not an FB call
        call sp_more
        ret nc
        ld a,'('
.par:   ld (de),a
        inc de
        ; member name: fb_members[type*20 + member*4]
        ld a,(fo_inst)
        rrca
        rrca
        and 0x3F
        ld c,a
        add a,a
        add a,a
        ld b,a
        add a,a
        add a,a
        add a,b                 ; type*20
        ld b,a
        ld a,(hl)
        inc hl
        add a,a
        add a,a
        add a,b
        push hl
        ld l,a
        ld h,0
        ld bc,fb_members
        add hl,bc
        call put_str
        pop hl
        ld a,':'
        ld (de),a
        inc de
        ld a,'='
        ld (de),a
        inc de
        call il_fmt_one
        call sp_more
        ld a,')'
        jr nc,.pe
        ld a,','
        ld (de),a
        inc de
        ld a,' '
        jr .par
.pe:    ld (de),a
        inc de
        ret

; il_fmt_one: HL = [area][index] or [area][value] -> text at DE, HL advanced
il_fmt_one:
        ld a,(hl)
        inc hl
        ld b,a
        and AR_MASK
        cp AR_K16
        jr z,.val
        cp AR_KT
        jr z,.val
        ld c,(hl)
        inc hl
        ld (fo_src),hl
        ld a,(view_sym)         ; symbol instead of an I/Q/M address
        or a
        jr z,.fmt
        ld a,b
        cp AR_I
        jr z,.sym
        cp AR_Q
        jr z,.sym
        cp AR_M
        jr z,.sym
        cp AR_SX
        jr z,.sym
        cp AR_FBI
        jr z,.sym
        and AR_MASK
        cp AR_FBM
        jr nz,.fmt
        ; FB member: instance symbol + "." + member name
        push de
        push bc
        ld a,AR_FBI
        call sym_name_of
        pop bc
        pop de
        jr c,.fmt
        call put_str
        ld a,'.'
        ld (de),a
        inc de
        ld a,c                  ; fb_members[type*20 + member*4]
        rrca
        rrca
        and 0x3F
        ld c,a
        add a,a
        add a,a
        ld l,a
        add a,a
        add a,a
        add a,l
        ld l,a
        ld a,b
        rrca
        rrca
        and 0x1C
        add a,l
        ld l,a
        ld h,0
        ld bc,fb_members
        add hl,bc
        call put_str
        jr .ret
.sym:   push de
        push bc
        call sym_name_of
        pop bc
        pop de
        jr c,.fmt
        call put_str
        jr .ret
.fmt:   ld hl,0
        jr .go
.val:   ld c,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld (fo_src),hl
        ld h,a
        ld l,c                  ; HL = value
.go:    ld a,b                  ; A = area
        ex af,af'
        ld a,(fo_style)         ; B = style: 0 IEC, 1 short form (LD labels)
        ld b,a
        ex af,af'
        call op_format
.ret:   ld hl,(fo_src)
        ret

; sp_more: C if HL < sp_end (more bytes in the record)
sp_more:
        push hl
        push de
        ld de,(sp_end)
        or a
        sbc hl,de
        pop de
        pop hl
        ret

fo_inst: dw 0
fo_src:  dw 0
fo_style: db 0
sp_end:  dw 0

; ---- il_load: loads line il_cur into the edit buffer, cursor at the end,
;      and shows the comment of its operand in the status bar
il_load:
        call il_load_buf
        jp il_show_comment

; ---- il_show_comment: comment of the edited operand (I/Q/M symbol) -> status bar
il_show_comment:
        ld hl,0
        ld (st_left),hl
        ld a,(ed_field)
        cp F_COMM
        jr z,.show
        ld hl,ed_o
        ld a,(hl)
        or a
        jr z,.show
        call op_parse
        jr c,.show
        ld b,a
        and AR_MASK
        cp AR_FBI               ; FB call with parameters may follow
        jr z,.ok
        ld b,AR_FBI
        cp AR_FBM
        jr z,.ok
        ld b,a
        ld a,(hl)
        or a
        jr nz,.show
        ld a,b
        cp AR_I
        jr z,.ok
        cp AR_Q
        jr z,.ok
        cp AR_SX
        jr z,.ok
        cp AR_M
        jr nz,.show
.ok:    ld a,b
        call sym_find_addr
        jr c,.show
        ; comment = record text after the name
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (sy_end),hl
        pop hl
        inc hl
        inc hl
        inc hl
        ld de,il_cmt            ; symbol name (inverted, below the operand
        ld a,ST_TAB             ; column of the editor), then the comment
        ld (de),a
        inc de
        ld a,IL_X_OPER-2
        ld (de),a
        inc de
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
.c:     push hl
        ld bc,(sy_end)
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
        ld hl,il_cmt
        ld (st_left),hl
.show:  jp status_left

il_cmt: ds SYM_NMAX+SYM_CMAX+5

il_load_buf:
        ld hl,ed_m
        ld (sp_m),hl
        ld hl,ed_o
        ld (sp_o),hl
        ld hl,ed_c
        ld (sp_c),hl
        xor a
        ld (ed_m),a
        ld (ed_o),a
        ld (ed_c),a
        ld de,(il_cur)
        call il_line_addr
        ld a,K_EMPTY
        call nc,il_split
        ld b,F_COMM
        ld hl,ed_c
        cp K_COMM
        jr z,.set
        ld b,F_OPER
        ld hl,ed_o
        ld a,(hl)
        or a
        jr nz,.set
        ld b,F_MNEM
        ld hl,ed_m
.set:   ld a,b
        ld (ed_field),a
        call strlen
        ld (ed_pos),a
        ret

; ============================================================
; edit buffer
; ============================================================

; ---- ed_kind: A = kind of the edited line
ed_kind:
        ld a,(ed_field)
        cp F_COMM
        ld a,K_COMM
        ret z
        ld a,(ed_m)
        or a
        ld a,K_EMPTY
        ret z
        ld hl,ed_m
        call strlen
        dec a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        cp ':'
        ld a,K_LABEL
        ret z
        ld a,K_INSTR
        ret

; ---- ed_field_info: HL = active buffer, B = max length, C = x of the field,
;      D = max x of the text
ed_field_info:
        ld a,(ed_mode)
        or a
        jr nz,.sym
        ld a,(ed_field)
        cp F_OPER
        jr z,.o
        cp F_COMM
        jr z,.c
        ld hl,ed_m
        ld bc,ED_MLEN*256+IL_X_MNEM
        ld d,IL_X_OPER-2
        ret
.o:     ld hl,ed_o
        ld bc,ED_OLEN*256+IL_X_OPER
        ld d,IL_X_MAX
        ret
.c:     ld hl,ed_c
        ld bc,ED_CLEN*256+IL_X_MNEM
        ld d,IL_X_MAX
        ret
.sym:   ld a,(ed_field)         ; symbol editor: address / name / comment
        cp F_COMM
        jr z,.sc
        cp F_OPER
        jr z,.sa
        ld hl,ed_m
        ld bc,SYM_NMAX*256+SY_X_NAME
        ld d,SY_X_ADDR-2
        ret
.sc:    ld hl,ed_c
        ld bc,SYM_CMAX*256+SY_X_COMM
        ld d,IL_X_MAX
        ret
.sa:    ld hl,ed_o
        ld bc,8*256+SY_X_ADDR
        ld d,SY_X_COMM-2
        ret

; ---- ed_insert: A = char -> inserted at ed_pos; C = full / too wide
ed_insert:
        ld (ei_ch),a
        call ed_field_info
        ld a,c
        ld (ei_x),a
        ld a,d
        ld (ei_xmax),a
        ld a,b
        ld (ei_max),a
        call strlen             ; (destroys B)
        ld b,a
        ld a,(ei_max)
        dec a
        cp b
        ret c                   ; len >= max
        ld a,b
        ld (ei_len),a
        push hl
        ld e,a
        ld d,0
        add hl,de               ; &buf[len]
        ld d,h
        ld e,l
        inc de
        ld a,(ed_pos)
        ld c,a
        ld a,(ei_len)
        sub c
        inc a
        ld c,a
        ld b,0
        lddr
        inc hl
        ld a,(ei_ch)
        ld (hl),a
        pop hl
        call pt_width
        ld c,a
        ld a,(ei_x)
        add a,c
        jr c,.wide
        ld c,a
        ld a,(ei_xmax)          ; text must end before the next column
        cp c
        jr c,.wide
        ld hl,ed_pos
        inc (hl)
        or a
        ret
.wide:  call ed_del_char
        scf
        ret

; ---- ed_del_char: deletes the char at ed_pos in the active buffer
ed_del_char:
        call ed_field_info
        ld a,(ed_pos)
        ld e,a
        ld d,0
        add hl,de
        ld d,h
        ld e,l
        inc hl
.l:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.l
        ret

; ============================================================
; drawing
; ============================================================

; ---- il_row_cur: A = screen row of the current line
il_row_cur:
        ld hl,(il_cur)
        ld de,(il_top)
        or a
        sbc hl,de
        ld a,l
        add a,IL_ROW0
        ret

; ---- il_fix_top: keeps il_cur visible; NZ = il_top changed (full redraw needed)
il_fix_top:
        ld hl,(il_cur)
        ld de,(il_top)
        or a
        sbc hl,de
        jr c,.up
        ld de,IL_ROWS
        or a
        sbc hl,de
        jr nc,.down
        xor a
        ret
.up:    ld hl,(il_cur)
        ld (il_top),hl
        or 1
        ret
.down:  ld hl,(il_cur)
        ld de,IL_ROWS-1
        or a
        sbc hl,de
        ld (il_top),hl
        or 1
        ret

; ---- il_redraw_all / il_redraw_from: A = first screen row
il_redraw_all:
        ld a,IL_ROW0
il_redraw_from:
        cp IL_ROW0
        jr nc,.ok
        ld a,IL_ROW0
.ok:    ld (rf_row),a
.l:     ld a,(rf_row)
        cp IL_ROW0+IL_ROWS
        ret nc
        sub IL_ROW0
        ld e,a
        ld d,0
        ld hl,(il_top)
        add hl,de
        ex de,hl
        ld a,(rf_row)
        ld b,a
        call il_draw_row
        ld hl,rf_row
        inc (hl)
        jr .l

; ---- il_draw_cur: redraws the current line
il_draw_cur_text:
        ld a,1
        ld (dr_text),a
il_draw_cur:
        call il_row_cur
        ld b,a
        ld de,(il_cur)
        ; fall through

; ---- il_draw_row: B = screen row, DE = line index
il_draw_row:
        ld a,b
        ld (dr_row),a
        ld (dr_line),de
        ld hl,(il_cur)
        or a
        sbc hl,de
        jr nz,.notcur
        ld hl,ed_m
        ld (dr_m),hl
        ld hl,ed_o
        ld (dr_o),hl
        ld hl,ed_c
        ld (dr_c),hl
        call ed_kind
        jr .kind
.notcur:
        ld hl,rd_m
        ld (dr_m),hl
        ld (sp_m),hl
        ld hl,rd_o
        ld (dr_o),hl
        ld (sp_o),hl
        ld hl,rd_c
        ld (dr_c),hl
        ld (sp_c),hl
        ld de,(dr_line)
        call il_line_addr
        ld a,K_NONE
        call nc,il_split
.kind:  ld (dr_kind),a
        ; attributes
        ld a,(dr_row)
        ld b,a
        ld c,0
        ld de,0x0300+ATTR_LNUM
        call scr_fill_attr
        ld d,5
        ld a,(dr_kind)
        ld e,ATTR_MNEM
        cp K_INSTR
        jr nz,.a0
        ld hl,(dr_m)            ; cell 7 stays black unless the instruction
        call pt_width           ; reaches it (operand cursor sits at x = 63)
        cp 8*7-IL_X_MNEM+1
        jr nc,.a1
        dec d
        jr .a1
.a0:    ld e,ATTR_COMMENT
        cp K_COMM
        jr z,.a1
        ld e,ATTR_NORMAL
.a1:    ld a,(dr_row)
        ld b,a
        ld c,3
        push de
        call scr_fill_attr
        pop de
        ld a,(dr_row)           ; the rest of cells 3-7 (black)
        ld b,a
        ld a,3
        add a,d
        ld c,a
        ld a,8
        sub c
        jr z,.a1b
        ld d,a
        ld e,ATTR_NORMAL
        call scr_fill_attr
.a1b:
        ld a,(dr_kind)
        ld e,ATTR_COMMENT
        cp K_COMM
        jr z,.a2
        ld e,ATTR_NORMAL
.a2:    ld a,(dr_row)
        ld b,a
        ld c,8
        ld d,24
        call scr_fill_attr
        ; pixels
        ld a,(dr_text)
        or a
        jp nz,.tclr
        ld a,(dr_row)
        ld b,a
        call pt_clear_row
        ld a,(dr_row)
        ld b,a
        ld c,IL_X_SEP
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        call px_span
        ld a,(dr_kind)
        cp K_NONE
        ret z
        ld a,(dr_row)
        ld (pt_row),a
        ld hl,(dr_line)
        inc hl
        ld de,dr_num
        call dec3
        ld hl,dr_num            ; fixed pitch: each digit in its own slot
        ld a,IL_X_NUM-3*IL_NUM_PITCH
        ld (dr_dx),a
        ld b,3
.dg:    ld a,(dr_dx)
        ld (pt_x),a
        ld a,(hl)
        call pt_putc
        inc hl
        ld a,(dr_dx)
        add a,IL_NUM_PITCH
        ld (dr_dx),a
        djnz .dg
.text:  ld a,IL_X_MNEM
        ld (pt_x),a
        ld a,(dr_kind)
        cp K_COMM
        jr nz,.nc
        ld hl,(dr_c)
        call pt_puts
        jr .cur
.nc:    ld hl,(dr_m)
        call pt_puts
        ld a,IL_X_OPER
        ld (pt_x),a
        ld hl,(dr_o)
        call pt_puts
.cur:   ld a,(dr_text)
        or a
        jr z,.cur2
        xor a                   ; text-only redraw: line number untouched
        ld (dr_text),a
        ld (il_cur_on),a
        ret
.cur2:  ld hl,(il_cur)
        ld de,(dr_line)
        or a
        sbc hl,de
        ret nz
        ld a,(dr_row)           ; current line: inverted line number
        ld b,a
        ld c,0
        ld d,IL_X_SEP
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        xor a
        ld (il_cur_on),a
        ret

; clears the text cells 3-31 of row dr_row and draws the text (current line)
il_draw_row.tclr:
        ld a,(dr_row)
        ld b,a
        ld c,3
        call pix_addr
        ld e,8
.l:     push hl
        ld b,29
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.l
        ld a,(dr_row)
        ld (pt_row),a
        jp il_draw_row.text

; ---- dec3: HL = 0..999 -> 3 digits with leading zeros + 0 at (DE)
dec3:
        ld bc,100
        call .dig
        ld bc,10
        call .dig
        ld a,l
        add a,'0'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret
.dig:   ld a,'0'-1
.l:     inc a
        or a
        sbc hl,bc
        jr nc,.l
        add hl,bc
        ld (de),a
        inc de
        ret

; ---- il_cursor_toggle: XORs the 1 px text cursor
il_cursor_toggle:
        call ed_field_info
        ld a,(ed_pos)
        call pt_width_n
        add a,c
        dec a
        ld c,a
        call il_row_cur
        ld b,a
        ld d,1
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        ld a,(il_cur_on)
        xor 1
        ld (il_cur_on),a
        ret

; ---- il_key: waits for a key with a blinking cursor, A = key
il_key:
        ld a,(il_cur_on)
        or a
        call z,il_cursor_toggle
        ld a,(frames)
        and 16
        ld (il_blink),a
.w:     call kb_get
        or a
        jr nz,.got
        halt
        ld a,(frames)
        and 16
        ld b,a
        ld a,(il_blink)
        cp b
        jr z,.w
        ld a,b
        ld (il_blink),a
        call il_cursor_toggle
        jr .w
.got:   push af
        ld a,(il_cur_on)
        or a
        call nz,il_cursor_toggle
        pop af
        ret

; ---- il_load_text: HL = text lines (0-terminated, list ends with 0xFF),
;      A = slot -> replaces the POU body. "//..." comment, "" empty line,
;      "NAME:" label, else instruction "MNEM<TAB>operand" (stored binary).
il_load_text:
        ld (lt_slot),a
        ld (lt_ptr),hl
        call pou_body
        ld de,0
        ld a,(lt_slot)
        call pou_delete
.l:     ld hl,(lt_ptr)
        ld a,(hl)
        cp 0xFF
        ret z
        ; record text -> rec_buf+2, kind
        ld de,rec_buf+2
        call put_str
        inc hl
        ld (lt_ptr),hl
        ex de,hl
        ld (hl),0
        ld de,rec_buf+2
        or a
        sbc hl,de
        ld a,l                  ; text length
        ld (lt_len),a
        ld b,K_EMPTY
        or a
        jr z,.k
        ld b,K_COMM
        ld a,(de)
        cp '/'
        jr z,.k
        ld b,K_LABEL
        dec hl
        add hl,de
        ld a,(hl)
        cp ':'
        jr z,.k
        ; instruction "MNEM<TAB>operand" -> binary
        ld hl,rec_buf+2
        ld de,cp_empty
.t:     ld a,(hl)
        or a
        jr z,.te
        inc hl
        cp IL_TAB
        jr nz,.t
        dec hl
        ld (hl),0
        inc hl
        ex de,hl
.te:    ld hl,rec_buf+2
        call il_check
        ret c
        ld a,(il_outlen)
        ld c,a
        ld b,0
        ld hl,il_out
        ld de,rec_buf+2
        ldir
        ld hl,rec_buf+2
        ex de,hl
        or a
        sbc hl,de
        ld a,l
        ld (lt_len),a
        ld b,K_INSTR
.k:     ld a,b
        ld (rec_buf+1),a
        ld a,(lt_len)
        add a,2
        ld (rec_buf),a
        ; append the record
        ld a,(lt_slot)
        call pou_body           ; BC = length = insert at the end
        ld d,b
        ld e,c
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ld a,(lt_slot)
        call pou_insert
        ret c
        ex de,hl
        ld hl,rec_buf
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ldir
        jp .l

lt_slot: db 0
lt_len:  db 0
lt_ptr:  dw 0

err_il_lines: db "Max. 999 lines",0
il_nothing:   db 0

il_pou:    db 0xFF
il_n:      dw 0
il_cur:    dw 0
il_top:    dw 0
il_end:    dw 0
il_oldrow: db 0
il_oldln:  dw 0
il_ch:     db 0
il_atstart: db 0
il_blink:  db 0
il_cur_on: db 0
ilt_len:   db 0
ed_field:  db 0
ed_pos:    db 0
ed_m:      ds ED_MLEN+1
ed_o:      ds ED_OLEN+1
ed_c:      ds ED_CLEN+1
ei_ch:     db 0
ei_x:      db 0
ei_len:    db 0
ei_max:    db 0
ei_xmax:   db 0
ed_mode:   db 0             ; 0 = IL editor, 1 = symbol editor
sp_kind:   db 0
dr_row:    db 0
dr_line:   dw 0
dr_kind:   db 0
dr_m:      dw 0
dr_o:      dw 0
dr_c:      dw 0
dr_num:    ds 6
dr_dx:     db 0
dr_text:   db 0
rf_row:    db 0
cm_kind:   db 0
cm_addr:   dw 0
cm_off:    dw 0
