; ============================================================
; ui.asm - screen setup, popup dialogs, line input
; ============================================================

; ---- screen_begin: clears the screen and draws the menu bar
screen_begin:
        ld hl,0
        ld (st_left),hl
        ld a,ST_RCOL
        ld (st_rcol),a
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


; ---- ui_title: HL = title text -> row 2 in the proportional font, dark blue
UI_TITLE_ROW EQU 2
ui_title:
        push hl
        ld bc,UI_TITLE_ROW*256
        ld d,32
        ld e,ATTR_TITLE
        call scr_fill_attr
        ld b,UI_TITLE_ROW
        call pt_clear_row
        ld a,UI_TITLE_ROW
        ld (pt_row),a
        ld a,8
        ld (pt_x),a
        pop hl
        jp pt_puts

; ---- lang_copy: A = language, DE = dest -> name without padding, 0-terminated,
;      DE points to the terminating 0
lang_copy:
        call lang_name
        ld b,3
.l:     ld a,(hl)
        cp ' '
        jr z,.e
        ld (de),a
        inc hl
        inc de
        djnz .l
.e:     xor a
        ld (de),a
        ret

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

; ---- ui_input: line editor in the proportional font
;   HL = buffer (holds initial 0-terminated text), B = char row, C = x (px),
;   D = max length, E = flags (bit0 = convert to upper case, bit1 = no underline,
;   bit2 = first character typed as with CAPS LOCK: case swapped)
;   output: NC = ENTER, C = cancelled
ui_input:
        ld (in_buf),hl
        ld a,b
        ld (in_row),a
        ld a,c
        ld (in_x),a
        ld a,d
        ld (in_max),a
        ld a,e
        ld (in_flags),a
        call strlen
        ld (in_len),a
        ld (in_pos),a
.redraw:
        ; clear the field, underline it, draw the text
        ld a,(in_max)
        ld b,a
        add a,a
        add a,b
        add a,a                 ; max * 6
        add a,2
        ld d,a
        ld a,(in_x)
        dec a
        ld c,a
        ld a,(in_row)
        ld b,a
        push bc
        push de
        ld hl,0x0008
        ld e,PX_CLR
        call px_span
        pop de
        pop bc
        ld a,(in_flags)
        bit 1,a
        jr nz,.nul
        ld hl,0x0701
        ld e,PX_SET
        call px_span
.nul:   ld a,(in_row)
        ld (pt_row),a
        ld a,(in_x)
        ld (pt_x),a
        ld hl,(in_buf)
        call pt_puts
        xor a
        ld (in_con),a
.key:   call in_getkey
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
        jr nz,.up
        bit 2,a                 ; first character of an empty field
        jr z,.noup0
        ld a,(in_len)
        or a
        jr nz,.noup0
        ld a,c
        call case_swap
        ld c,a
        jr .noup0
.up:    ld a,c
        call to_upper
        ld c,a
.noup0: ld a,c
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
        add hl,de               ; HL = &buf[len]
        ld d,h
        ld e,l
        inc de                  ; DE = &buf[len+1]
        ld a,(in_pos)
        neg
        add a,b                 ; len-pos
        inc a
        push bc
        ld c,a
        ld b,0
        lddr
        pop bc
        inc hl                  ; &buf[pos]
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
        jp .key
.right: ld a,(in_pos)
        ld b,a
        ld a,(in_len)
        cp b
        jp z,.key
        ld a,b
        inc a
        ld (in_pos),a
        jp .key
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
        ld e,l                  ; DE = &buf[pos]
        inc hl                  ; HL = &buf[pos+1]
        ld b,a
        ld a,(in_len)
        sub b                   ; len-pos (incl. terminating 0)
        ld c,a
        ld b,0
        ldir
        ld hl,in_len
        dec (hl)
        jp .redraw
.ok:    or a
        ret
.cancel:
        scf
        ret

; in_getkey: waits for a key with a blinking 1 px cursor
in_getkey:
        ld a,(in_pend)          ; key passed by the caller (in_pend)
        or a
        jr z,.np
        push af
        xor a
        ld (in_pend),a
        pop af
        ret
.np:    ld a,(in_con)
        or a
        call z,in_cursor
        ld a,(frames)
        and 16
        ld (in_blink),a
.w:     call kb_get
        or a
        jr nz,.got
        halt
        ld a,(frames)
        and 16
        ld b,a
        ld a,(in_blink)
        cp b
        jr z,.w
        ld a,b
        ld (in_blink),a
        call in_cursor
        jr .w
.got:   push af
        ld a,(in_con)
        or a
        call nz,in_cursor
        pop af
        ret

; in_cursor: XORs the cursor bar
in_cursor:
        ld hl,(in_buf)
        ld a,(in_pos)
        call pt_width_n
        ld b,a
        ld a,(in_x)
        add a,b
        dec a
        ld c,a
        ld a,(in_row)
        ld b,a
        ld d,1
        ld hl,0x0007            ; keep the underline
        ld e,PX_XOR
        call px_span
        ld a,(in_con)
        xor 1
        ld (in_con),a
        ret

in_buf:   dw 0
in_x:     db 0
in_row:   db 0
in_con:   db 0
in_blink: db 0
in_max:   db 0
in_flags: db 0
in_pend:  db 0              ; first key for ui_input (0 = none)
in_len:   db 0
in_pos:   db 0
