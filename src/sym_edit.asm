; ============================================================
; sym_edit.asm - symbol editor (Edit > Symbols)
; ============================================================
; Fixed list of 80 addresses: %IX0.0-0.7, %QX0.0-0.7, %MX0-63.
; Cells 0-4 address (bright white, current row inverted), separator
; at x=39, symbol name (dark blue) at x=44, comment (dark green) at x=96.
; Uses the IL editor machinery (il_cur/il_top/il_n, cursor, fields).
; ============================================================
SY_ROWS   EQU 80
SY_X_ADDR EQU 4
SY_X_SEP  EQU 39
SY_X_NAME EQU 44
SY_X_COMM EQU 96

scr_sym:
        call screen_begin
        ; the IL editor state is borrowed while the symbol editor runs
        ld hl,(il_cur)
        ld (sy_scur),hl
        ld hl,(il_top)
        ld (sy_stop),hl
        ld hl,(sy_cur)
        ld (il_cur),hl
        ld hl,(sy_top)
        ld (il_top),hl
        ld hl,SY_ROWS
        ld (il_n),hl
        ld a,1
        ld (ed_mode),a
        call sy_load
        call il_fix_top
.full:  call sy_redraw_all
.loop:  call il_key
        cp K_ENTER
        jp z,.down
        cp K_DOWN
        jp z,.down
        cp K_UP
        jp z,.up
        cp K_LEFT
        jr z,.left
        cp K_RIGHT
        jr z,.right
        cp K_DEL
        jr z,.del
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        cp 32
        jr c,.loop
        cp 128
        jr nc,.loop
        ld b,a
        ld a,(ed_field)
        cp F_COMM
        ld a,b
        jr z,.ins
        cp ' '                  ; SPACE in the name -> comment
        jr z,.tocomm
.ins:   call ed_insert
        call c,beep
.redraw:
        call sy_draw_cur_text
        jr .loop
.tocomm:
        ld a,F_COMM
        ld (ed_field),a
        ld hl,ed_c
        call strlen
        ld (ed_pos),a
        jr .loop
.toname:
        ld a,F_MNEM
        ld (ed_field),a
        ld hl,ed_m
        call strlen
        ld (ed_pos),a
        jr .loop
.left:  ld a,(ed_pos)
        or a
        jr z,.l0
        dec a
        ld (ed_pos),a
        jr .loop
.l0:    ld a,(ed_field)
        cp F_COMM
        jr z,.toname
        jr .loop
.right: call ed_field_info
        call strlen
        ld b,a
        ld a,(ed_pos)
        cp b
        jr nc,.r0
        inc a
        ld (ed_pos),a
        jp .loop
.r0:    ld a,(ed_field)
        cp F_COMM
        jr nz,.tocomm
        jp .loop
.del:   ld a,(ed_pos)
        or a
        jr z,.l0
        dec a
        ld (ed_pos),a
        call ed_del_char
        jr .redraw

.up:    call sy_commit
        jp c,.loop
        ld hl,(il_cur)
        ld a,h
        or l
        jr z,.same
        dec hl
        jr .move
.down:  call sy_commit
        jp c,.loop
        ld hl,(il_cur)
        inc hl
        ld a,l
        cp SY_ROWS
        jr c,.move
.same:  call sy_draw_cur        ; stays: show the stored form
        jp .loop
.move:  push hl
        call il_row_cur
        ld (il_oldrow),a
        ld hl,(il_cur)
        ld (il_oldln),hl
        pop hl
        ld (il_cur),hl
        call sy_load
        call il_fix_top
        jp nz,.full
        ld a,(il_oldrow)
        ld b,a
        ld de,(il_oldln)
        call sy_draw_row
        call sy_draw_cur
        jp .loop

.menu:  call sy_commit
        jp c,.loop
        call sy_draw_cur
        call menu_handle
        jp z,.loop
        push af
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

; ---- sy_addr: E = row -> A = area, C = index
sy_addr:
        ld a,e
        cp 8
        jr nc,.q
        ld c,a
        ld a,AR_I
        ret
.q:     cp 16
        jr nc,.m
        sub 8
        ld c,a
        ld a,AR_Q
        ret
.m:     sub 16
        ld c,a
        ld a,AR_M
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

; ---- sy_load: row il_cur -> edit buffers
sy_load:
        xor a
        ld (ed_m),a
        ld (ed_c),a
        ld (ed_field),a         ; F_MNEM
        ld hl,ed_m
        ld (sp_m),hl
        ld hl,ed_c
        ld (sp_c),hl
        ld de,(il_cur)
        call sy_addr
        call sym_find_addr
        call nc,sy_split
        ld hl,ed_m
        call strlen
        ld (ed_pos),a
        ret

; ---- sy_commit: validates and stores the edited row; C = error shown
sy_commit:
        ld de,(il_cur)
        call sy_addr
        ld (sy_area),a
        ld hl,ed_m
        call sym_validate
        jr c,.err
        ld de,(il_cur)
        call sy_addr
        ld hl,ed_m
        ld de,ed_c
        call sym_store
        ret c
        call status_right
        or a
        ret
.err:   ld hl,(il_err)
        call ui_error
        scf
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

sy_draw_cur_text:
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
        ld hl,(il_cur)
        or a
        sbc hl,de
        jr nz,.rec
        ld hl,ed_m
        ld (dr_m),hl
        ld hl,ed_c
        ld (dr_c),hl
        jr .attr
.rec:   ld hl,rd_m
        ld (dr_m),hl
        ld (sp_m),hl
        ld (hl),0
        ld hl,rd_c
        ld (dr_c),hl
        ld (sp_c),hl
        ld (hl),0
        ld de,(dr_line)
        call sy_addr
        call sym_find_addr
        call nc,sy_split
.attr:  ld a,(dr_row)
        ld b,a
        ld c,0
        ld de,0x0500+ATTR_LNUM
        call scr_fill_attr
        ld a,(dr_row)
        ld b,a
        ld c,5
        ld de,0x0700+ATTR_MNEM
        call scr_fill_attr
        ld a,(dr_row)
        ld b,a
        ld c,12
        ld de,0x1400+ATTR_COMMENT
        call scr_fill_attr
        ld a,(dr_row)
        ld (pt_row),a
        ld b,a
        ld a,(dr_text)
        or a
        jr z,.full
        ; text-only: clear cells 5-31
        ld c,5
        call pix_addr
        ld e,8
.cl:    push hl
        ld b,27
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
        ld c,SY_X_SEP
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        call px_span
        ld de,(dr_line)
        call sy_addr
        ld de,sy_abuf
        ld hl,0
        ld b,0
        call op_format
        ld a,SY_X_ADDR
        ld (pt_x),a
        ld hl,sy_abuf
        call pt_puts
.text:  ld a,SY_X_NAME
        ld (pt_x),a
        ld hl,(dr_m)
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
        ld d,SY_X_SEP
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        xor a
        ld (il_cur_on),a
        ret

sy_cur:  dw 0
sy_top:  dw 0
sy_scur: dw 0
sy_stop: dw 0
sy_end:  dw 0
sy_area: db 0
sy_abuf: ds 8
