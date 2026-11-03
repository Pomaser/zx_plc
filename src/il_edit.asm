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
        ld (hl),0
        xor a
        ld (ed_m),a
        ld (ed_o),a
        ld a,F_COMM
        ld (ed_field),a
        ld a,2
        ld (ed_pos),a
        jr .redraw
.ins:   ld a,(il_ch)
        call ed_insert
        call c,beep
.redraw:
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
        jr .redraw
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
        jp .redraw

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
        jr .tomnem
.del0:  ld a,(ed_field)
        cp F_OPER
        jr z,.tomnem
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
.enter: call il_commit
        jp c,.loop
        ld hl,(il_n)
        ld de,IL_MAXLN
        or a
        sbc hl,de
        jr c,.e1
        ld hl,err_il_lines
        call ui_error
        jp .loop
.e1:    ld de,(il_cur)
        inc de
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
        jp .redraw

        ; ---- menu
.menu:  call il_commit
        jp c,.loop
        call il_draw_cur
        call menu_handle
        jp z,.loop
        cp CMD_IL_INS
        jr z,.mins
        cp CMD_IL_DEL
        jr z,.mdel
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
        jp .redraw

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
        call status_draw
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
        jp status_draw

; ---- il_commit: validates the edit buffer and stores it as line il_cur
;      C = error (message shown)
il_commit:
        call ed_kind
        ld (cm_kind),a
        cp K_COMM
        jr z,.comm
        cp K_EMPTY
        jr z,.empty
        cp K_LABEL
        jr z,.label
        ld hl,ed_m
        ld de,ed_o
        call il_check
        jp c,.err
        ld hl,il_out
        jr .build
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
        ex de,hl
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
        jr .done
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
        call status_draw
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
il_split:
        ld de,(sp_m)
        xor a
        ld (de),a
        ld de,(sp_o)
        ld (de),a
        ld de,(sp_c)
        ld (de),a
        ld a,(hl)
        sub 2
        ld b,a
        inc hl
        ld a,(hl)
        ld (sp_kind),a
        inc hl
        cp K_COMM
        jr z,.comm
        cp K_EMPTY
        jr z,.done
        ld de,(sp_m)
.m:     ld a,b
        or a
        jr z,.end
        ld a,(hl)
        inc hl
        dec b
        cp IL_TAB
        jr z,.tab
        ld (de),a
        inc de
        jr .m
.tab:   xor a
        ld (de),a
        ld de,(sp_o)
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

; ---- il_load: loads line il_cur into the edit buffer, cursor at the end
il_load:
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

; ---- ed_field_info: HL = active buffer, B = max length, C = x of the field
ed_field_info:
        ld a,(ed_field)
        cp F_OPER
        jr z,.o
        cp F_COMM
        jr z,.c
        ld hl,ed_m
        ld bc,ED_MLEN*256+IL_X_MNEM
        ret
.o:     ld hl,ed_o
        ld bc,ED_OLEN*256+IL_X_OPER
        ret
.c:     ld hl,ed_c
        ld bc,ED_CLEN*256+IL_X_MNEM
        ret

; ---- ed_insert: A = char -> inserted at ed_pos; C = full / too wide
ed_insert:
        ld (ei_ch),a
        call ed_field_info
        ld a,c
        ld (ei_x),a
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
        cp IL_X_MAX
        jr nc,.wide
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
        ld a,(dr_kind)
        ld e,ATTR_MNEM
        cp K_INSTR
        jr z,.a1
        ld e,ATTR_COMMENT
        cp K_COMM
        jr z,.a1
        ld e,ATTR_NORMAL
.a1:    ld a,(dr_row)
        ld b,a
        ld c,3
        ld d,5
        call scr_fill_attr
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
        ld hl,dr_num
        ld a,IL_X_NUM
        call pt_puts_r
        ld a,IL_X_MNEM
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
.cur:   ld hl,(il_cur)
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

err_il_mem:   db "Out of memory",0
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
rd_m:      ds ED_MLEN+1
rd_o:      ds 64
rd_c:      ds 64
sp_m:      dw 0
sp_o:      dw 0
sp_c:      dw 0
sp_kind:   db 0
dr_row:    db 0
dr_line:   dw 0
dr_kind:   db 0
dr_m:      dw 0
dr_o:      dw 0
dr_c:      dw 0
dr_num:    ds 6
rf_row:    db 0
cm_kind:   db 0
cm_addr:   dw 0
cm_off:    dw 0
rec_buf:   ds 72
