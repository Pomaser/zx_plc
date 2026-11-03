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
        ld a,ST_ROW
        ld (pt_row),a
        ld a,1
        ld (pt_down),a
        ; left: "POU: name (lang)"
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
        xor a
        ld (de),a
        ld a,4
        ld (pt_x),a
        ld hl,st_buf
        call pt_puts
        xor a
        ld (pt_down),a
        ld (st_last),a          ; force the right part to be drawn
        ; fall through

; ---- status_right: redraws only the right part of the status bar (free
;      memory, or st_right text if set) and only when the text changed
ST_RCOL EQU 18              ; first cell of the right part
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
        ld a,252
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
st_buf:      ds 24
st_last:     ds 24
st_right:    dw 0             ; text for the right part (0 = free memory)
