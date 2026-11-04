; ============================================================
; status.asm - bottom status bar (char row 23)
; ============================================================
; Separator line on pixel line 0, 1 px gap, text one line lower
; (descender line is dropped). Left: current POU, right: free memory.
; ============================================================
ST_ROW  EQU 23

status_draw:
        ld bc,ST_ROW*256
        ld d,32
        ld e,ATTR_MENU
        call scr_fill_attr
        ; clear pixels, separator on line 0
        ld bc,ST_ROW*256
        call pix_addr
        ld e,8
        ld a,0xFF
.cl:    push hl
        ld b,32
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        xor a
        dec e
        jr nz,.cl
        xor a
        ld (st_llast),a         ; force both parts to be drawn
        ld (st_last),a
        call status_left
        jp status_right

; ---- status_left: left part (cells 0-23): "POU: name (lang)" followed by the
;      st_left text if set (comment of the current element); redrawn only on change
status_left:
        ld de,st_buf
        ld hl,txt_st_pou
        call put_str
        ld a,(cur_pou)
        call pou_entry
        call name_unpad
        ld hl,txt_st_open
        call put_str
        ld a,(cur_pou)
        call pou_lang
        call lang_copy
        ld a,')'
        ld (de),a
        inc de
        ld hl,(st_left)         ; comment of the current element
        ld a,h
        or l
        jr z,.term
        ld a,' '
        ld (de),a
        inc de
        ld (de),a
        inc de
        call put_str
.term:  xor a
        ld (de),a
        ld hl,st_buf
        ld de,st_llast
        call str_eq
        ret z
        ld hl,st_buf
        ld de,st_llast
        call put_str
        xor a
        ld (de),a
        ld c,0
        ld b,ST_RCOL
        call st_clear
        ld bc,ST_ROW*256        ; left part black again (symbol cells were blue)
        ld d,ST_RCOL
        ld e,ATTR_MENU
        call scr_fill_attr
        ld a,ST_RCOL*8-4        ; clip before the right part
        ld (pt_xmax),a
        xor a                   ; flush left
        call st_print
        ld a,255
        ld (pt_xmax),a
        ret

; st_clear: C = first cell, B = cells -> clears pixel lines 1-7 of the bar
st_clear:
        push bc
        ld b,ST_ROW
        call pix_addr
        pop bc
        inc h
        ld e,7
.cl:    push hl
        push bc
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop bc
        pop hl
        inc h
        dec e
        jr nz,.cl
        ret

; st_print: A = x (left) -> prints st_buf one line lower
st_print:
        ld (pt_x),a
        ld a,ST_ROW
        ld (pt_row),a
        ld a,1
        ld (pt_down),a
        ld hl,st_buf
.l:     ld a,(hl)
        inc hl
        or a
        jr z,.e
        cp ST_SYM
        jr z,.on
        cp ST_SYME
        jr z,.off
        call pt_putc
        jr .l
.on:    call st_align           ; the name starts in a new cell
        ld a,(pt_x)
        rrca
        rrca
        rrca
        and 31
        ld (st_c0),a
        jr .l
.off:   push hl                 ; cells st_c0 .. (pt_x-1)/8 in dark blue
        ld a,(pt_x)
        dec a
        rrca
        rrca
        rrca
        and 31
        cp ST_RCOL
        jr c,.c1
        ld a,ST_RCOL-1
.c1:    ld hl,st_c0
        sub (hl)
        jr c,.nofill
        inc a
        ld d,a
        ld c,(hl)
        ld b,ST_ROW
        ld e,ATTR_TITLE
        call scr_fill_attr
.nofill:
        pop hl
        ld a,(pt_x)             ; gap, then the next cell
        add a,3
        jr c,.l
        ld (pt_x),a
        call st_align
        jr .l
.e:     xor a
        ld (pt_down),a
        ret

; st_align: pt_x up to the next cell boundary
st_align:
        ld a,(pt_x)
        add a,7
        jr nc,.a
        ld a,255
.a:     and 0xF8
        ld (pt_x),a
        ret

st_c0:  db 0

; ---- status_right: redraws only the right part of the status bar (free
;      memory, or st_right text if set) and only when the text changed
ST_RCOL EQU 24              ; first cell of the right part
status_right:
        ld de,st_buf
        ld hl,(st_right)
        ld a,h
        or l
        jr z,.free
        call put_str
        jr .term
.free:  ld hl,txt_st_free
        call put_str
        push de
        call proj_free
        pop de
        call utoa16
        ld hl,txt_st_b
        call put_str
.term:  xor a
        ld (de),a
        ; unchanged -> nothing to do (no flicker)
        ld hl,st_buf
        ld de,st_last
        call str_eq
        ret z
        ld hl,st_buf
        ld de,st_last
        call put_str
        xor a
        ld (de),a
        ; clear pixel lines 1-7 of the right part (line 0 = separator)
        ld bc,ST_ROW*256+ST_RCOL
        call pix_addr
        inc h
        ld e,7
.cl:    push hl
        ld b,32-ST_RCOL
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.cl
        ld a,ST_ROW
        ld (pt_row),a
        ld a,1
        ld (pt_down),a
        ld hl,st_buf
        xor a                   ; right edge = 256 (flush right)
        call pt_puts_r
        xor a
        ld (pt_down),a
        ret

; str_eq: HL, DE strings -> Z if equal
str_eq: ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr str_eq

txt_st_pou:  db "POU: ",0
txt_st_open: db " (",0
txt_st_free: db "Free ",0
txt_st_b:    db " B",0
st_left:     dw 0             ; text for the left part (0 = POU info)
st_right:    dw 0             ; text for the right part (0 = free memory)
