; ============================================================
; app.asm - EDIT and RUN screens (phase 1: placeholders)
; ============================================================

; ---- EDIT screen: opens the editor for the current POU language
scr_edit:
        call screen_begin
        ld bc,0x0201
        ld (cur_col),bc
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld hl,txt_edit
        call scr_puts
        ld a,(cur_pou)
        call pou_entry
        ld b,8
        call scr_putsn
        ld a,' '
        call scr_putc
        ld a,(cur_pou)
        call pou_lang
        call lang_name
        ld b,3
        call scr_putsn
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        ld hl,txt_todo_edit
        call scr_puts
        ld hl,hint_back
        call ui_hints
        jr placeholder_loop

scr_run:
        call screen_begin
        ld hl,txt_todo_run
        call scr_puts
        ld hl,hint_back
        call ui_hints
placeholder_loop:
.key:   call kb_wait
        cp K_BREAK
        jr z,.menu
        cp K_EDIT
        jr z,.menu
        jr .key
.menu:  call menu_handle
        jr z,.key
        ret

txt_edit:      db "EDIT: ",0
txt_todo_edit: db SC_AT,5,1,"Editor for this language",SC_AT,6,1,"is not implemented yet.",0
txt_todo_run:  db SC_AT,2,1,SC_ATTR,ATTR_TITLE,"SIMULATION",SC_ATTR,ATTR_NORMAL
               db SC_AT,5,1,"Not implemented yet.",0
hint_back:     db " BREAK: menu",0
