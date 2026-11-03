; ============================================================
; ui.asm - menu, hints, error messages, line input
; ============================================================

; ---- ui_draw_bar: A = highlighted item (0-3 / 0xFF), E = highlight attribute
ui_draw_bar:
        ld (bar_hl),a
        push de
        ld bc,0
        ld (cur_col),bc
        ld a,ATTR_BAR
        ld (cur_attr),a
        ld hl,bar_text
        call scr_puts
        pop de
        ld a,(bar_hl)
        cp 4
        ret nc
        add a,a
        ld l,a
        ld h,0
        ld bc,bar_pos
        add hl,bc
        ld c,(hl)
        inc hl
        ld d,(hl)
        ld b,0
        jp scr_fill_attr

bar_text: db " POU  EDIT  RUN  FILE     ZX-PLC",0
bar_pos:  db 0,5, 5,6, 11,5, 16,6
bar_hl:   db 0

; ---- screen_begin: clears the screen and draws the bar with the current screen
screen_begin:
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        call scr_cls
        ld a,(cur_screen)
        ld e,ATTR_BAR_CUR
        jp ui_draw_bar

; ---- ui_menu: selection in the bar. A = chosen screen or 0xFF
ui_menu:
        ld a,(cur_screen)
        ld (menu_sel),a
        ld hl,hint_menu
        call ui_hints_tmp
.draw:  ld a,(menu_sel)
        ld e,ATTR_BAR_SEL
        call ui_draw_bar
.key:   call kb_wait
        cp K_LEFT
        jr z,.left
        cp K_RIGHT
        jr z,.right
        cp K_ENTER
        jr z,.ok
        cp K_BREAK
        jr z,.cancel
        cp K_EDIT
        jr z,.cancel
        call to_upper
        ld hl,menu_keys
        ld b,4
.hk:    cp (hl)
        jr z,.hot
        inc hl
        djnz .hk
        jr .key
.hot:   ld a,4
        sub b
        ld (menu_sel),a
        jr .ok
.left:  ld a,(menu_sel)
        dec a
        and 3
        ld (menu_sel),a
        jr .draw
.right: ld a,(menu_sel)
        inc a
        and 3
        ld (menu_sel),a
        jr .draw
.ok:    ld a,(menu_sel)
        jr .ret
.cancel:
        ld a,0xFF
.ret:   push af
        ld a,(cur_screen)
        ld e,ATTR_BAR_CUR
        call ui_draw_bar
        call ui_hints_restore
        pop af
        ret

menu_keys: db "PERF"
menu_sel:  db 0

; ---- menu_switch: opens the menu; NZ + A = new screen, Z = stay
menu_switch:
        call ui_menu
        cp 0xFF
        ret z
        ld b,a
        ld a,(cur_screen)
        cp b
        ld a,b
        ret

; ---- ui_hints: HL = hint text for rows 22-23 (stored for restore)
ui_hints:
        ld (hint_ptr),hl
ui_hints_tmp:
        push hl
        ld a,ATTR_HINT
        ld (cur_attr),a
        ld bc,0x1602        ; row 22, 2 rows
        call scr_clear_rows
        ld bc,0x1600
        ld (cur_col),bc
        pop hl
        call scr_puts
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        ret

ui_hints_restore:
        ld hl,(hint_ptr)
        jr ui_hints_tmp

hint_ptr: dw hint_none
hint_none: db 0
hint_menu: db " MENU  LEFT/RIGHT:select ENTER:ok",SC_AT,23,0," P/E/R/F hotkeys   BREAK cancel",0

; ---- ui_error: HL = error text, beeps, waits for a key, restores hints
ui_error:
        push hl
        ld a,ATTR_ERR
        ld (cur_attr),a
        ld bc,0x1602
        call scr_clear_rows
        ld bc,0x1601
        ld (cur_col),bc
        pop hl
        call scr_puts
        ld bc,0x1701
        ld (cur_col),bc
        ld hl,txt_press_key
        call scr_puts
        call beep
        call kb_release
        call kb_wait
        call ui_hints_restore
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        ret

txt_press_key: db "(press any key)",0

; ---- ui_confirm: HL = question; Z = yes (Y), NZ = no
ui_confirm:
        push hl
        ld a,ATTR_INPUT
        ld (cur_attr),a
        ld bc,0x1602
        call scr_clear_rows
        ld bc,0x1601
        ld (cur_col),bc
        pop hl
        call scr_puts
        ld hl,txt_yn
        call scr_puts
.k:     call kb_wait
        call to_upper
        cp 'Y'
        jr z,.done
        cp 'N'
        jr z,.done
        cp K_BREAK
        jr z,.done
        jr .k
.done:  push af
        call ui_hints_restore
        pop af
        cp 'Y'
        ret

txt_yn: db " (Y/N)",0

; ---- ui_choose_lang: A = language (0-2), carry = cancelled
ui_choose_lang:
        ld a,ATTR_INPUT
        ld (cur_attr),a
        ld bc,0x1602
        call scr_clear_rows
        ld bc,0x1601
        ld (cur_col),bc
        ld hl,txt_lang_q
        call scr_puts
.k:     call kb_wait
        cp K_BREAK
        jr z,.cancel
        cp K_EDIT
        jr z,.cancel
        call to_upper
        ld b,LANG_IL
        cp 'I'
        jr z,.ok
        ld b,LANG_LD
        cp 'L'
        jr z,.ok
        ld b,LANG_FBD
        cp 'F'
        jr z,.ok
        jr .k
.ok:    push bc
        call ui_hints_restore
        pop bc
        ld a,b
        or a
        ret
.cancel:
        call ui_hints_restore
        scf
        ret

txt_lang_q: db "Language?",SC_AT,23,1,"I=IL  L=LD  F=FBD  BREAK=cancel",0

; ---- lang_name: A = language -> HL = 3-char name
lang_name:
        ld l,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        ld bc,lang_names
        add hl,bc
        ret
lang_names: db "IL LD FBD"

; ---- ui_input: line editor
;   HL = buffer (holds initial 0-terminated text), B = row, C = column,
;   D = max length, E = flags (bit0 = convert to upper case)
;   output: NC = ENTER, C = cancelled
ui_input:
        ld (in_buf),hl
        ld (in_col),bc
        ld a,d
        ld (in_max),a
        ld a,e
        ld (in_flags),a
        call strlen
        ld (in_len),a
        ld (in_pos),a
.redraw:
        ld bc,(in_col)
        ld (cur_col),bc
        ld a,ATTR_INPUT
        ld (cur_attr),a
        ld hl,(in_buf)
        ld a,(in_len)
        ld b,a
        call scr_putsn
        ld a,(in_len)
        ld b,a
        ld a,(in_max)
        inc a
        sub b
        ld b,a
        call scr_spaces
        ld bc,(in_col)
        ld a,(in_pos)
        add a,c
        ld c,a
        call attr_addr
        ld (hl),ATTR_CURSOR
.key:   call kb_wait
        cp K_ENTER
        jp z,.ok
        cp K_BREAK
        jp z,.cancel
        cp K_EDIT
        jp z,.cancel
        cp K_LEFT
        jr z,.left
        cp K_RIGHT
        jr z,.right
        cp K_DEL
        jr z,.del
        cp 32
        jr c,.key
        cp 128
        jr nc,.key
        ld c,a
        ld a,(in_flags)
        bit 0,a
        ld a,c
        jr z,.noup
        call to_upper
.noup:  ld c,a
        ld a,(in_len)
        ld b,a
        ld a,(in_max)
        cp b
        jr z,.key
        ; shift buf[pos..len] right by 1
        ld hl,(in_buf)
        ld a,(in_len)
        ld e,a
        ld d,0
        add hl,de           ; HL = &buf[len]
        ld d,h
        ld e,l
        inc de              ; DE = &buf[len+1]
        ld a,(in_pos)
        neg
        add a,b             ; len-pos
        inc a
        push bc
        ld c,a
        ld b,0
        lddr
        pop bc
        inc hl              ; &buf[pos]
        ld (hl),c
        ld hl,in_len
        inc (hl)
        ld hl,in_pos
        inc (hl)
        jp .redraw
.left:  ld a,(in_pos)
        or a
        jr z,.key
        dec a
        ld (in_pos),a
        jp .redraw
.right: ld a,(in_pos)
        ld b,a
        ld a,(in_len)
        cp b
        jp z,.key
        ld a,b
        inc a
        ld (in_pos),a
        jp .redraw
.del:   ld a,(in_pos)
        or a
        jp z,.key
        dec a
        ld (in_pos),a
        ld hl,(in_buf)
        ld e,a
        ld d,0
        add hl,de
        ld d,h
        ld e,l              ; DE = &buf[pos]
        inc hl              ; HL = &buf[pos+1]
        ld b,a
        ld a,(in_len)
        sub b               ; len-pos (incl. terminating 0)
        ld c,a
        ld b,0
        ldir
        ld hl,in_len
        dec (hl)
        jp .redraw
.ok:    or a
        jr .end
.cancel:
        scf
.end:   push af
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        pop af
        ret

in_buf:   dw 0
in_col:   db 0
in_row:   db 0
in_max:   db 0
in_flags: db 0
in_len:   db 0
in_pos:   db 0
