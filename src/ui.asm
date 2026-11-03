; ============================================================
; ui.asm - screen setup, popup dialogs, line input
; ============================================================

; ---- screen_begin: clears the screen and draws the menu bar
screen_begin:
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        call scr_cls
        call menu_draw_bar
        jp status_draw

; ---- ui_error: HL = error text; popup + beep, any key closes it
ui_error:
        ld de,popup_buf
        call put_str
        xor a
        ld (de),a
        inc de
        ld (de),a
        call beep
        ld hl,popup_buf
        jp msg_box

; ---- ui_confirm: HL = question; Z = yes (Y), NZ = no
ui_confirm:
        ld de,popup_buf
        call put_str
        xor a
        ld (de),a
        inc de
        ld hl,txt_yn
        ld bc,txt_yn_end-txt_yn
        ldir
        ld hl,popup_buf
        call popup_open
.k:     call kb_wait
        call to_upper
        cp 'Y'
        jr z,.done
        cp 'N'
        jr z,.done
        cp K_BREAK
        jr z,.done
        cp K_EDIT
        jr z,.done
        jr .k
.done:  push af
        call win_close
        pop af
        cp 'Y'
        ret

txt_yn: db " ",0,"Y = yes",PT_TAB,"N = no",0,0
txt_yn_end:

; ---- ui_choose_lang: A = language (0-2), carry = cancelled
ui_choose_lang:
        ld hl,txt_lang_q
        call popup_open
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
        call win_close
        pop bc
        ld a,b
        or a
        ret
.cancel:
        call win_close
        scf
        ret

txt_lang_q:
        db "Choose language:",0
        db " ",0
        db "I",PT_TAB,"IL - Instruction List",0
        db "L",PT_TAB,"LD - Ladder Diagram",0
        db "F",PT_TAB,"FBD - Function Block Diagram",0
        db 0

popup_buf: ds 80

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
        ld a,ATTR_MENU
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
