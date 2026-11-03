; ============================================================
; screen.asm - screen output (32x24 chars, ROM font)
; ============================================================
; Control codes in strings for scr_puts:
;   0          end
;   1,row,col  AT
;   2,attr     set attribute
; Chars 128+ = custom graphics (udg_gfx)
; ============================================================
SC_END  EQU 0
SC_AT   EQU 1
SC_ATTR EQU 2

; ---- scr_cls: clears the whole screen with attribute cur_attr
scr_cls:
        ld hl,0x4000
        ld de,0x4001
        ld bc,6143
        ld (hl),0
        ldir
        ld a,(cur_attr)
        ld hl,0x5800
        ld de,0x5801
        ld bc,767
        ld (hl),a
        ldir
        ld bc,0
        ld (cur_col),bc
        ret

; ---- scr_at: B=row, C=column
scr_at:
        ld (cur_col),bc
        ret

; ---- attr_addr: B=row, C=column -> HL attribute address (destroys A)
attr_addr:
        ld a,b
        rrca
        rrca
        rrca
        ld l,a
        and 3
        or 0x58
        ld h,a
        ld a,l
        and 0xE0
        or c
        ld l,a
        ret

; ---- pix_addr: B=row, C=column -> HL address of the 1st pixel line (destroys A)
pix_addr:
        ld a,b
        and 0x18
        or 0x40
        ld h,a
        ld a,b
        and 7
        rrca
        rrca
        rrca
        or c
        ld l,a
        ret

; ---- scr_putc: A=char at cursor position, advances cursor. Preserves BC,DE,HL
scr_putc:
        push hl
        push de
        push bc
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        cp 128
        jr nc,.udg
        ld de,0x3C00
        jr .go
.udg:   ld de,udg_gfx-128*8
.go:    add hl,de
        ex de,hl            ; DE = glyph
        ld bc,(cur_col)     ; C=column, B=row
        ld a,b
        cp 24
        jr nc,.done         ; off screen - ignore
        call pix_addr
        ld b,8
.lp:    ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz .lp
        ld bc,(cur_col)
        call attr_addr
        ld a,(cur_attr)
        ld (hl),a
        ld hl,cur_col
        inc (hl)
        ld a,(hl)
        cp 32
        jr c,.done
        ld (hl),0
        inc hl
        inc (hl)
        ld a,(hl)
        cp 24
        jr c,.done
        ld (hl),0
.done:  pop bc
        pop de
        pop hl
        ret

; ---- scr_puts: HL=string with control codes, on exit HL points past the 0
scr_puts:
        ld a,(hl)
        inc hl
        or a
        ret z
        cp SC_AT
        jr z,.at
        cp SC_ATTR
        jr z,.attr
        call scr_putc
        jr scr_puts
.at:    ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld (cur_col),bc
        jr scr_puts
.attr:  ld a,(hl)
        inc hl
        ld (cur_attr),a
        jr scr_puts

; ---- scr_putsn: HL=text, B=char count (no control codes)
scr_putsn:
        ld a,b
        or a
        ret z
.l:     ld a,(hl)
        inc hl
        call scr_putc
        djnz .l
        ret

; ---- scr_spaces: B spaces
scr_spaces:
        ld a,b
        or a
        ret z
.l:     ld a,' '
        call scr_putc
        djnz .l
        ret

; ---- scr_fill_attr: B=row, C=column, D=length, E=attribute
scr_fill_attr:
        call attr_addr
.l:     ld (hl),e
        inc hl
        dec d
        jr nz,.l
        ret

; ---- scr_clear_rows: B=first row, C=count; attribute cur_attr
scr_clear_rows:
.row:   push bc
        ld c,0
        call pix_addr
        ld e,8
.pl:    push hl
        ld b,32
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.pl
        pop bc
        push bc
        ld c,0
        call attr_addr
        ld a,(cur_attr)
        ld b,32
.a:     ld (hl),a
        inc hl
        djnz .a
        pop bc
        inc b
        dec c
        jr nz,.row
        ret

; ---- scr_num: prints HL (signed)
scr_num:
        ld de,num_buf
        call itoa16
        ld hl,num_buf
        jp scr_puts

; ---- scr_unum_r: HL (unsigned) right aligned to width B
scr_unum_r:
        push bc
        ld de,num_buf
        call utoa16
        ld hl,num_buf
        call strlen
        pop bc
        ld c,a
        ld a,b
        sub c
        jr c,.np
        jr z,.np
        ld b,a
        call scr_spaces
.np:    ld hl,num_buf
        jp scr_puts

; ---- custom graphics (chars 128+) - extended in the LD/FBD phases
udg_gfx:
        ; 128: full block
        db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
        ; 129: LED off (ring)
        db 0x00,0x3C,0x42,0x42,0x42,0x42,0x3C,0x00
        ; 130: LED on (filled circle)
        db 0x00,0x3C,0x7E,0x7E,0x7E,0x7E,0x3C,0x00

cur_col:  db 0
cur_row:  db 0
cur_attr: db ATTR_NORMAL
num_buf:  ds 8
