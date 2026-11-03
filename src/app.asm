; ============================================================
; app.asm - EDIT and RUN screens (phase 1: placeholders)
; ============================================================

; ---- EDIT screen: opens the editor for the current POU language
scr_edit:
        ld a,(cur_pou)
        call pou_lang
        cp LANG_IL
        jp z,il_editor
        call screen_begin
        ld de,app_buf
        ld hl,txt_edit
        call put_str
        ld a,(cur_pou)
        call pou_entry
        call name_unpad
        ld hl,txt_open
        call put_str
        ld a,(cur_pou)
        call pou_lang
        call lang_copy
        ld a,')'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld hl,app_buf
        call ui_title
        ld hl,txt_todo_edit
        call app_text
        jr placeholder_loop

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

; app_text: HL = text -> row 5 at x = 8 in the proportional font
app_text:
        ld a,5
        ld (pt_row),a
        ld a,8
        ld (pt_x),a
        jp pt_puts

txt_edit:      db "Edit: ",0
txt_open:      db " (",0
txt_todo_edit: db "The editor for this language is not implemented yet.",0
txt_todo:      db "Not implemented yet.",0
app_buf:       ds 24
