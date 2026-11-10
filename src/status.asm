; ============================================================
; status.asm - bottom status bar (char row 23)
; ============================================================
; Separator line on pixel line 0, 1 px gap, text one line lower
; (descender line is dropped: g j p q y use glyphs with short descenders). Left: st_left text (element info, key hints),
; right: free memory or st_right. The POU name is in the menu bar (menu_pou).
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

; ---- status_left: left part (cells 0 .. st_rcol-1): the st_left text (info
;      of the current element, key hints); redrawn only on change
status_left:
        ld de,st_buf
        ld hl,(st_left)
        ld a,h
        or l
        call nz,put_str
        xor a
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
        ld a,(st_rcol)
        ld b,a
        call st_clear
        call st_lim             ; clip before the right part
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
        cp ST_TAB
        jr z,.tab
        call st_desc
        call pt_putc
        jr .l
.tab:   ld a,(pt_x)             ; move on to column x
        cp (hl)
        jr nc,.tab1
        ld a,(hl)
        ld (pt_x),a
.tab1:  inc hl
        jr .l
.on:    ld a,(pt_x)             ; inverted box: 2 px margin around the name
        ld (st_x0),a
        add a,2
        ld (pt_x),a
        jr .l
.off:   push hl
        call st_lim             ; not into the right part
        ld b,a
        ld a,(pt_x)
        add a,2
        cp b
        jr c,.w
        ld a,b
.w:     ld (pt_x),a
        ld hl,st_x0
        sub (hl)
        jr c,.nofill
        jr z,.nofill
        ld d,a
        ld c,(hl)
        ld b,ST_ROW
        ld hl,0x0107            ; lines 1-7, below the separator line
        ld e,PX_XOR
        call px_span
.nofill:
        pop hl
        ld a,(pt_x)             ; gap before the comment
        add a,3
        jr c,.l
        ld (pt_x),a
        jr .l
.e:     xor a
        ld (pt_down),a
        ret

st_x0:  db 0

; st_desc: A = char -> A = its short-descender glyph for g j p q y (the
;          status bar drops the glyph's last line); keeps BC, DE, HL
st_desc:
        push hl
        push bc
        ld hl,st_dtab
        ld bc,5
        cpir
        jr nz,.n
        ld a,CH_SDESC+4         ; BC = 4 - index
        sub c
.n:     pop bc
        pop hl
        ret
st_dtab: db "gjpqy"

; st_lim: A = last x of the left part (4 px before the right part)
st_lim: ld a,(st_rcol)
        add a,a
        add a,a
        add a,a
        sub 4
        ret

; ---- status_right: redraws only the right part of the status bar (free
;      memory, or st_right text if set) and only when the text changed
ST_RCOL EQU 25              ; first cell of the right part ("Mem 12288B" fits)
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
        ld a,(st_rcol)
        ld c,a
        ld b,ST_ROW
        call pix_addr
        inc h
        ld e,7
.cl:    push hl
        ld a,(st_rcol)
        neg
        add a,32
        ld b,a
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

txt_st_open: db " (",0
txt_st_free: db "Free ",0
txt_st_b:    db "B",0
st_left:     dw 0             ; text for the left part (0 = POU info)
st_right:    dw 0             ; text for the right part (0 = free memory)
st_rcol:     db ST_RCOL       ; first cell of the right part
