; ============================================================
; sym_edit.asm - symbol editor (Edit > Symbols)
; ============================================================
; Free list: one row per symbol record (sorted by address) plus an
; empty row at the end for a new entry. Row: line number (cells 0-2,
; bright white, current row inverted), separator, name (dark blue,
; x=28), address (black, x=80), comment (dark green, x=120).
; SPACE moves name -> address -> comment.
; Uses the IL editor machinery (il_cur/il_top/il_n, cursor, fields):
;   F_OPER = address, F_MNEM = name, F_COMM = comment.
; ============================================================
SY_X_NAME EQU 28            ; cells 3-9
SY_X_ADDR EQU 80            ; cells 10-14
SY_X_COMM EQU 120           ; cells 15-31

scr_sym:
        call screen_begin
        ; the IL editor state is borrowed while the symbol editor runs
        ld hl,(il_cur)
        ld (sy_scur),hl
        ld hl,(il_top)
        ld (sy_stop),hl
        ld a,1
        ld (ed_mode),a
        call sy_count
        ld hl,(sy_cur)
        ld de,(il_n)
        or a
        sbc hl,de
        add hl,de
        jr c,.cok
        ld hl,(il_n)
        dec hl
.cok:   ld (il_cur),hl
        ld hl,(sy_top)
        ld (il_top),hl
        call sy_load
        call il_fix_top
.full:  call sy_redraw_all
.loop:  call il_key
        cp K_ENTER
        jp z,.enter
        cp K_DOWN
        jp z,.down
        cp K_UP
        jp z,.up
        cp K_LEFT
        jp z,.left
        cp K_RIGHT
        jp z,.right
        cp K_HOME
        jp z,.home
        cp K_END
        jp z,.end
        cp K_PGUP
        jp z,.pgup
        cp K_PGDN
        jp z,.pgdn
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
        cp ' '
        jr nz,.ins
        ld a,(ed_field)
        cp F_MNEM
        jp z,.toaddr
        cp F_OPER
        jp z,.tocomm
        ld a,' '
.ins:   ld (il_ch),a            ; first letter of the name / comment:
        ld a,(ed_field)         ; typed as with CAPS LOCK
        cp F_OPER
        jr z,.ins1
        call ed_field_info
        ld a,(hl)
        or a
        jr nz,.ins1
        ld a,(il_ch)
        call case_swap
        ld (il_ch),a
.ins1:  ld a,(il_ch)
        call ed_insert
        jr c,.beep
        ld a,1
        ld (sy_mod),a
.redraw:
        call sy_draw_edit
        jp .loop
.beep:  call beep
        jp .loop
.toname:
        ld a,F_MNEM
        ld hl,ed_m
        jr .tofield
.toaddr:
        ld a,F_OPER
        ld hl,ed_o
        jr .tofield
.tocomm:                        ; (only reached from the address field)
        call sy_norm_addr
        ld a,F_COMM
        ld hl,ed_c
.tofield:
        ld (ed_field),a
        call strlen
        ld (ed_pos),a
        jp .loop
.home:  ld a,(ed_field)         ; SS+LEFT: start of the name
        cp F_OPER
        call z,sy_norm_addr     ; (leaving the address field)
        ld a,F_MNEM
        ld (ed_field),a
        xor a
        ld (ed_pos),a
        jr .redraw
.end:   ld a,(ed_field)         ; SS+RIGHT: end of the comment
        cp F_COMM
        jr z,.tocomm2
        cp F_OPER
        jp z,.tocomm
        ld a,F_OPER             ; from the name: through the address field
        ld (ed_field),a
        jp .tocomm
.tocomm2:
        ld hl,ed_c
        ld a,F_COMM
        jr .tofield
.left:  ld a,(ed_pos)
        or a
        jr z,.back
        dec a
        ld (ed_pos),a
        jp .loop
.back:  ld a,(ed_field)         ; previous field
        cp F_COMM
        jp z,.toaddr
        cp F_OPER
        jp z,.toname
        jp .loop
.right: call ed_field_info
        call strlen
        ld b,a
        ld a,(ed_pos)
        cp b
        jr nc,.fwd
        inc a
        ld (ed_pos),a
        jp .loop
.fwd:   ld a,(ed_field)         ; next field
        cp F_MNEM
        jp z,.toaddr
        cp F_OPER
        jp z,.tocomm
        jp .loop
.del:   ld a,(ed_pos)
        or a
        jr z,.back
        dec a
        ld (ed_pos),a
        call ed_del_char
        ld a,1
        ld (sy_mod),a
        jp .redraw

.up:    call sy_commit
        jp c,.loop
        ld hl,(il_cur)
        ld a,h
        or l
        jp z,.stay
        dec hl
        jp .move
.pgup:  call sy_commit           ; SS+UP: one screen up
        jp c,.loop
        ld hl,(il_cur)
        ld de,IL_ROWS-1
        or a
        sbc hl,de
        jp nc,.move
        ld hl,0
        jr .move
.pgdn:  call sy_commit           ; SS+DOWN: one screen down
        jp c,.loop
        ld hl,(il_cur)
        ld de,IL_ROWS-1
        add hl,de
        ld de,(il_n)
        or a
        sbc hl,de
        add hl,de
        jr c,.move
        ex de,hl
        dec hl
        jr .move
.enter: ; cursor at the very start of a filled row -> empty row above it
        ld a,(ed_pos)
        or a
        jr nz,.down
        ld a,(ed_field)
        cp F_MNEM
        jr nz,.down
        ld de,(il_cur)
        call sy_rec
        jr c,.down              ; already the empty row
        call sy_commit
        jp c,.loop
        ld hl,(il_cur)
        ld (sy_newpos),hl       ; the empty row takes this place
        call sy_load
        call il_fix_top
        jp .full
.down:  call sy_commit
        jp c,.loop
        ld a,(sy_dirty)         ; a new symbol was added -> next new entry
        or a
        jr z,.dn
        ld a,(sy_old)
        or a
        jr nz,.dn
        ld hl,(il_n)
        dec hl
        jr .move
.dn:    ld hl,(il_cur)
        inc hl
        ld de,(il_n)
        or a
        sbc hl,de
        add hl,de
        jr c,.move
.stay:  ld a,(sy_dirty)
        or a
        jr z,.st2
        call sy_load            ; the row content changed
        jp .full
.st2:
        call sy_draw_cur
        jp .loop
.move:  push hl
        call il_row_cur
        ld (il_oldrow),a
        ld hl,(il_cur)
        ld (il_oldln),hl
        pop hl
        ld (il_cur),hl
        call sy_drop_empty      ; NZ: an inner empty row was removed
        jr z,.mv2
        ld a,1
        ld (sy_dirty),a
.mv2:
        ld a,(sy_dirty)         ; (sy_load clears it)
        push af
        call sy_load
        pop af
        or a
        jr nz,.mfull
        call il_fix_top
        jp nz,.full
        ld a,(il_oldrow)
        ld b,a
        ld de,(il_oldln)
        call sy_draw_row
        call sy_draw_cur
        jp .loop
.mfull: call il_fix_top
        jp .full

.menu:  call sy_commit
        jp c,.loop
        call sy_load
        ld a,(sy_dirty)
        or a
        call nz,sy_redraw_all
        call sy_draw_cur
        call menu_handle
        jp z,.loop
        cp CMD_REDRAW
        jp z,.full
        cp CMD_IL_DEL
        jr nz,.exit
        ; Edit > Delete line: remove the symbol of this row
        ld de,(il_cur)
        call sy_rec
        jp c,.loop
        inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        ld hl,cp_empty
        ld de,cp_empty
        call sym_store
        call sy_count
        call status_right
        call sy_load
        jp .full
.exit:  push af
        ld hl,(il_cur)
        ld (sy_cur),hl
        ld hl,(il_top)
        ld (sy_top),hl
        ld hl,(sy_scur)
        ld (il_cur),hl
        ld hl,(sy_stop)
        ld (il_top),hl
        xor a
        ld (ed_mode),a
        ld a,0xFF
        ld (il_pou),a           ; IL editor reloads its state
        pop af
        ret

; ---- sy_norm_addr: the typed address (e.g. "i0.0") -> IEC form "%IX0.0"
;      (left unchanged if it is not a valid I/Q/M address)
sy_norm_addr:
        ld hl,ed_o
        ld a,(hl)
        or a
        ret z
        call op_parse
        ret c
        ld b,a
        ld a,(hl)
        or a
        ret nz
        ld a,b
        cp AR_I
        jr z,.ok
        cp AR_Q
        jr z,.ok
        cp AR_M
        jr z,.ok
        cp AR_SX
        jr z,.ok
        cp AR_FBI
        ret nz
.ok:    ld (sy_narea),a
        ld a,c
        ld (sy_nidx),a
        ld hl,ed_o              ; a symbol name is not an address
        call sym_find_name
        ret nc
        ld a,(sy_nidx)
        ld c,a
        ld a,(sy_narea)
        ld de,ed_o
        ld hl,0
        ld b,0
        call op_format
        jp sy_draw_edit

; ---- sy_count: il_n = number of symbols + 1 (empty row for a new one)
sy_count:
        call sym_first
        ld bc,1
.l:     push bc
        call sym_at_end
        pop bc
        jr nc,.e
        inc bc
        call sym_next
        jr .l
.e:     ld (il_n),bc
        dec bc
        ld (sy_newpos),bc       ; the empty row is at the end
        ret

; ---- sy_drop_empty: after a move from row il_oldln to il_cur: if il_oldln
;      was an empty row in the middle of the list, it is removed (il_cur
;      corrected). NZ = removed
sy_drop_empty:
        ld hl,(il_n)
        dec hl
        ld de,(sy_newpos)
        or a
        sbc hl,de
        ret z                   ; the empty row is at the end
        ld hl,(il_oldln)
        or a
        sbc hl,de
        jr nz,.no               ; we did not leave the empty row
        ld hl,(il_cur)          ; rows below move up by one
        or a
        sbc hl,de
        jr c,.end
        jr z,.end
        ld hl,(il_cur)
        dec hl
        ld (il_cur),hl
.end:   ld hl,(il_n)
        dec hl
        ld (sy_newpos),hl
        or 1
        ret
.no:    xor a
        ret

; ---- sy_rec: DE = row -> NC: HL = record; C: the empty row (or beyond)
sy_rec: ld hl,(sy_newpos)
        or a
        sbc hl,de
        jr nz,.nz
        scf                     ; the empty row
        ret
.nz:    jr nc,.below            ; row < empty row
        dec de                  ; rows after the empty one
.below: ld b,d
        ld c,e
        push bc
        call sym_first
        pop bc
.l:     push bc
        call sym_at_end
        pop bc
        jr nc,.new
        ld a,b
        or c
        ret z
        dec bc
        call sym_next
        jr .l
.new:   scf
        ret

; ---- sy_split: HL = record -> name to (sp_m), comment to (sp_c)
sy_split:
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (sy_end),hl
        pop hl
        inc hl
        inc hl
        inc hl
        ld de,(sp_m)
.n:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.n
        ld de,(sp_c)
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
        ret

; ---- sy_rec_text: HL = record -> address to (sp_o), name/comment via sy_split
sy_rec_text:
        push hl
        inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        ld de,(sp_o)
        ld hl,0
        ld b,0
        call op_format
        pop hl
        jr sy_split

; ---- sy_load: row il_cur -> edit buffers (cursor at the end of the last field)
sy_load:
        xor a
        ld (ed_m),a
        ld (ed_o),a
        ld (ed_c),a
        ld (ed_pos),a
        ld (sy_mod),a
        ld (sy_dirty),a
        ld a,F_MNEM
        ld (ed_field),a
        ld hl,ed_m
        ld (sp_m),hl
        ld hl,ed_o
        ld (sp_o),hl
        ld hl,ed_c
        ld (sp_c),hl
        ld de,(il_cur)
        call sy_rec
        ret c
        call sy_rec_text
        ld a,F_COMM
        ld hl,ed_c
        ld b,(hl)
        inc b
        dec b
        jr nz,.set
        ld a,F_OPER
        ld hl,ed_o
.set:   ld (ed_field),a
        call strlen
        ld (ed_pos),a
        ret

; ---- sy_commit: validates and stores the edited row
;      C = error shown; sy_dirty = 1 if the list changed (il_cur = its new row)
sy_commit:
        xor a
        ld (sy_dirty),a
        ld a,(sy_mod)
        or a
        ret z                   ; nothing edited
        ; old address of this row
        xor a
        ld (sy_old),a
        ld de,(il_cur)
        call sy_rec
        jr c,.nold
        inc hl
        ld a,(hl)
        ld (sy_oarea),a
        inc hl
        ld a,(hl)
        ld (sy_oidx),a
        ld a,1
        ld (sy_old),a
.nold:  ; everything empty -> delete the row
        ld a,(ed_o)
        ld hl,ed_m
        or (hl)
        ld hl,ed_c
        or (hl)
        jr nz,.addr
        ld a,(sy_old)
        or a
        jp z,.done
        call .delold
        jp .stored
.addr:  ld a,(ed_o)
        or a
        ld hl,err_sy_noaddr
        jp z,.err
        ld hl,ed_o
        call op_parse
        jp c,.badaddr
        ld b,a
        ld a,(hl)
        or a
        jp nz,.badaddr
        ld a,b
        cp AR_I
        jr z,.aok
        cp AR_Q
        jr z,.aok
        cp AR_M
        jr z,.aok
        cp AR_SX
        jr z,.aok
        cp AR_FBI
        jp nz,.badaddr
.aok:   ld (sy_narea),a
        ld a,c
        ld (sy_nidx),a
        ld hl,ed_o              ; a symbol name is not an address
        call sym_find_name
        jp nc,.badaddr
        ; address used by another row?
        call .same
        jr z,.free
        ld a,(sy_nidx)
        ld c,a
        ld a,(sy_narea)
        call sym_find_addr
        ld hl,err_sy_used
        jp nc,.err
.free:  ; name check: a name of this row's old address counts as its own
        ld a,(sy_nidx)
        ld c,a
        ld a,(sy_narea)
        ld b,a
        ld hl,ed_m
        push bc
        call sym_find_name
        pop de                  ; D = new area, E = new index
        jr c,.vnew
        ld b,a
        ld a,(sy_old)
        or a
        jr z,.vnew
        ld a,(sy_oarea)
        cp b
        jr nz,.vnew
        ld a,(sy_oidx)
        cp c
        jr nz,.vnew
        ld a,b                  ; validate against the old address
        jr .val
.vnew:  ld a,d
        ld c,e
.val:   ld hl,ed_m
        call sym_validate
        jr c,.verr
        ; store
        ld a,(sy_old)
        or a
        call nz,.delold
        ld a,(sy_nidx)
        ld c,a
        ld a,(sy_narea)
        ld hl,ed_m
        ld de,ed_c
        call sym_store
        ret c
        ; the row of the stored record
        ld a,(sy_nidx)
        ld c,a
        ld a,(sy_narea)
        call sym_find_addr
        ex de,hl
        call sym_first
        ld bc,0
.pos:   or a
        sbc hl,de
        add hl,de
        jr z,.posok
        inc bc
        push de
        call sym_next
        pop de
        jr .pos
.posok: ld (il_cur),bc
.stored:
        call sy_count
        call status_right
        ld a,1
        ld (sy_dirty),a
.done:  xor a
        ld (sy_mod),a
        ret
.badaddr:
        ld hl,err_sy_addr
        jr .err
.verr:  ld hl,(il_err)
.err:   call ui_error
        scf
        ret
.delold:
        ld a,(sy_oidx)
        ld c,a
        ld a,(sy_oarea)
        ld hl,cp_empty
        ld de,cp_empty
        jp sym_store
; Z if the new address equals the old one of this row
.same:  ld a,(sy_old)
        or a
        jr z,.nz
        ld a,(sy_narea)
        ld b,a
        ld a,(sy_oarea)
        cp b
        ret nz
        ld a,(sy_nidx)
        ld b,a
        ld a,(sy_oidx)
        cp b
        ret
.nz:    or 1
        ret

; ---- drawing
sy_redraw_all:
        ld a,IL_ROW0
        ld (rf_row),a
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
        call sy_draw_row
        ld hl,rf_row
        inc (hl)
        jr .l

; sy_draw_edit: after editing a field (address field -> whole row)
sy_draw_edit:
        ld a,1
        ld (dr_text),a
sy_draw_cur:
        call il_row_cur
        ld b,a
        ld de,(il_cur)
; ---- sy_draw_row: B = screen row, DE = row index
sy_draw_row:
        ld a,b
        ld (dr_row),a
        ld (dr_line),de
        xor a
        ld (dr_kind),a
        ld hl,(il_cur)
        or a
        sbc hl,de
        jr nz,.rec
        ld hl,ed_o
        ld (dr_o),hl
        ld hl,ed_m
        ld (dr_m),hl
        ld hl,ed_c
        ld (dr_c),hl
        jr .attr
.rec:   ld hl,rd_o
        ld (dr_o),hl
        ld (sp_o),hl
        ld (hl),0
        ld hl,rd_m
        ld (dr_m),hl
        ld (sp_m),hl
        ld (hl),0
        ld hl,rd_c
        ld (dr_c),hl
        ld (sp_c),hl
        ld (hl),0
        ld de,(dr_line)
        call sy_rec
        call nc,sy_rec_text
        ld hl,(dr_line)         ; beyond the empty row: no address column
        ld de,(il_n)
        or a
        sbc hl,de
        jr c,.attr
        ld a,K_NONE
        ld (dr_kind),a
.attr:  ld a,(dr_row)
        ld b,a
        ld c,0
        ld de,0x0300+ATTR_LNUM
        call scr_fill_attr
        ld a,(dr_row)
        ld b,a
        ld c,3
        ld de,0x0700+ATTR_MNEM
        call scr_fill_attr
        ld a,(dr_row)
        ld b,a
        ld c,10
        ld de,0x0500+ATTR_NORMAL
        call scr_fill_attr
        ld a,(dr_row)
        ld b,a
        ld c,15
        ld de,0x1100+ATTR_COMMENT
        call scr_fill_attr
        ld a,(dr_row)
        ld (pt_row),a
        ld b,a
        ld a,(dr_text)
        or a
        jr z,.full
        ; text-only: clear cells 3-31
        ld c,3
        call pix_addr
        ld e,8
.cl:    push hl
        ld b,29
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.cl
        jr .text
.full:  call pt_clear_row
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
        ld hl,(dr_line)         ; line number, fixed pitch
        inc hl
        ld de,dr_num
        call dec3
        ld hl,dr_num
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
.text:  ld a,SY_X_NAME
        ld (pt_x),a
        ld hl,(dr_m)
        call pt_puts
        ld a,SY_X_ADDR
        ld (pt_x),a
        ld hl,(dr_o)
        call pt_puts
        ld a,SY_X_COMM
        ld (pt_x),a
        ld hl,(dr_c)
        call pt_puts
        ld a,(dr_text)
        or a
        jr z,.inv
        xor a
        ld (dr_text),a
        ld (il_cur_on),a
        ret
.inv:   ld hl,(il_cur)
        ld de,(dr_line)
        or a
        sbc hl,de
        ret nz
        ld a,(dr_row)
        ld b,a
        ld c,0
        ld d,IL_X_SEP
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        xor a
        ld (il_cur_on),a
        ret

err_sy_noaddr: db "Address required",0
err_sy_addr:   db "Invalid address (I, Q, M, S, FB)",0
err_sy_used:   db "Address already defined",0

sy_cur:   dw 0
sy_top:   dw 0
sy_scur:  dw 0
sy_stop:  dw 0
sy_end:   dw 0
sy_mod:   db 0
sy_newpos: dw 0          ; row index of the empty row
sy_dirty: db 0
sy_old:   db 0
sy_oarea: db 0
sy_oidx:  db 0
sy_narea: db 0
sy_nidx:  db 0
