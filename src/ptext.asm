; ============================================================
; ptext.asm - proportional pixel text and pixel span operations
; ============================================================
; pt_x   = pixel x (0-255), pt_row = character row (0-23)
; Text is ORed into the screen (background must be cleared first).
; Char 9 (TAB) moves pt_x to pt_tab.
; pt_skip > 0 draws the glyph shifted up by that many lines,
; pt_down = 1 draws it one line lower.
; ============================================================
PT_TAB  EQU 9
FONT_N  EQU 98             ; glyphs 32..129
CH_LEDOFF EQU 127
CH_LEDON  EQU 128
CH_CHECK  EQU 129

; ---- pt_putc: A = char (32-126). Preserves BC, DE, HL
pt_putc:
        push hl
        push de
        push bc
        cp PT_TAB
        jr nz,.nt
        ld a,(pt_tab)
        ld (pt_x),a
        jp .done
.nt:    sub 32
        jp c,.done
        cp FONT_N
        jp nc,.done
        ld l,a
        ld h,0
        ld de,font6_w
        add hl,de
        ld c,(hl)               ; C = width
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,font6_g
        add hl,de
        ld a,(pt_skip)          ; skip top glyph lines (shift text up)
        ld e,a
        ld d,0
        add hl,de
        ld (pt_gp),hl
        ld a,(pt_x)
        ld e,a
        add a,c
        jr c,.done              ; past the screen edge
        ld b,a
        ld a,(pt_xmax)
        cp b
        jr c,.done              ; past the clipping limit
        ld a,b
        ld (pt_x),a             ; advance cursor
        ld a,e
        and 7
        ld (pt_sh),a
        ld a,e
        rrca
        rrca
        rrca
        and 31
        ld c,a
        ld a,(pt_row)
        ld b,a
        call pix_addr
        ld a,(pt_down)          ; shift down: start one line lower
        add a,h
        ld h,a
        ld a,(pt_down)
        ld b,a
        ld a,(pt_skip)
        add a,b
        neg
        add a,8
        ld b,a                  ; lines to draw = 8 - pt_skip - pt_down
.line:  push bc
        push hl
        ld hl,(pt_gp)
        ld c,(hl)
        inc hl
        ld (pt_gp),hl
        pop hl
        ld e,0
        ld a,(pt_sh)
        or a
        jr z,.ns
        ld b,a
.sh:    srl c
        rr e
        djnz .sh
.ns:    ld a,(hl)
        or c
        ld (hl),a
        ld a,l
        and 31
        cp 31
        jr z,.skip
        inc l
        ld a,(hl)
        or e
        ld (hl),a
        dec l
.skip:  inc h
        pop bc
        djnz .line
.done:  pop bc
        pop de
        pop hl
        ret

; ---- pt_puts: HL = 0-terminated string, HL ends past the 0
pt_puts:
        ld a,(hl)
        inc hl
        or a
        ret z
        call pt_putc
        jr pt_puts

; ---- pt_width_n: HL = string, A = max chars -> A = width of the first chars
;      preserves BC, DE, HL
pt_width_n:
        push hl
        push bc
        ld c,a
        ld b,0
.l:     ld a,c
        or a
        jr z,.e
        ld a,(hl)
        or a
        jr z,.e
        call pt_charw
        add a,b
        ld b,a
        inc hl
        dec c
        jr .l
.e:     ld a,b
        pop bc
        pop hl
        ret

; ---- pt_puts_r: HL = string, A = right edge x (exclusive) -> right aligned on pt_row
pt_puts_r:
        ld b,a
        call pt_width
        neg
        add a,b
        ld (pt_x),a
        jp pt_puts

; ---- pt_clear_row: B = char row -> clears its 8 pixel lines (attributes kept)
pt_clear_row:
        ld c,0
        call pix_addr
        ld e,8
.l:     push hl
        ld b,32
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.l
        ret

; ---- pt_charw: A = char -> A = width in pixels (TAB = 0)
pt_charw:
        sub 32
        jr c,.z
        cp FONT_N
        jr nc,.z
        push hl
        push de
        ld l,a
        ld h,0
        ld de,font6_w
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        ret
.z:     xor a
        ret

; ---- pt_width: HL = string (0) -> A = width in pixels (stops at 0 or TAB)
;      preserves BC, DE, HL
pt_width:
        push bc
        push hl
        ld b,0
.l:     ld a,(hl)
        or a
        jr z,.e
        cp PT_TAB
        jr z,.e
        call pt_charw
        add a,b
        ld b,a
        inc hl
        jr .l
.e:     ld a,b
        pop hl
        pop bc
        ret

; ---- px_span: pixel span operation on one character row
;   B = char row, C = x, D = width (px), H = first line (0-7), L = line count,
;   E = operation: PX_SET, PX_CLR, PX_XOR
PX_SET  EQU 0
PX_CLR  EQU 1
PX_XOR  EQU 2
px_span:
        ld a,d
        or a
        ret z
        ld (ps_line),hl
        ld a,e
        ld (ps_op),a
        ld a,b
        ld (ps_row),a
.seg:   ld a,c
        and 7
        ld e,a                  ; E = bit offset
        ld a,8
        sub e
        cp d
        jr c,.n1
        ld a,d
.n1:    ld (ps_n),a             ; n = min(8-off, remaining)
        ; mask = (0xFF >> off) xor (0xFF >> (off+n))
        push hl
        ld hl,shr_tab
        ld a,e
        add a,l
        ld l,a
        ld b,(hl)               ; 0xFF >> off
        ld a,(ps_n)
        add a,e
        ld hl,shr_tab
        add a,l
        ld l,a
        ld a,(hl)               ; 0xFF >> (off+n)
        xor b
        ld (ps_mask),a
        pop hl
        ; address
        push bc
        push de
        ld a,c
        rrca
        rrca
        rrca
        and 31
        ld c,a
        ld a,(ps_row)
        ld b,a
        call pix_addr
        ld a,(ps_first)
        add a,h
        ld h,a
        ld a,(ps_cnt)
        ld b,a
        ld a,(ps_mask)
        ld e,a
        ld a,(ps_op)
        ld d,a
.ln:    ld a,d
        cp PX_CLR
        jr z,.clr
        jr nc,.xor
        ld a,(hl)
        or e
        jr .st
.clr:   ld a,e
        cpl
        and (hl)
        jr .st
.xor:   ld a,(hl)
        xor e
.st:    ld (hl),a
        inc h
        djnz .ln
        pop de
        pop bc
        ; advance
        ld a,(ps_n)
        ld b,a
        add a,c
        ld c,a
        ld a,d
        sub b
        ld d,a
        jr nz,.seg
        ret

; 0xFF >> n for n = 0..8 (must not cross a 256 byte page)
        ALIGN 16
shr_tab:  db 0xFF,0x7F,0x3F,0x1F,0x0F,0x07,0x03,0x01,0x00
pt_x:     db 0
pt_row:   db 0
pt_tab:   db 0
pt_skip:  db 0             ; glyph lines skipped at the top
pt_down:  db 0             ; 1 = glyph drawn one line lower (last line dropped)
pt_xmax:  db 255           ; glyphs ending past this x are not drawn
pt_sh:    db 0
pt_gp:    dw 0
ps_line:                        ; L = count, H = first line (ld (ps_line),hl)
ps_cnt:   db 0
ps_first: db 0
ps_op:    db 0
ps_row:   db 0
ps_n:     db 0
ps_mask:  db 0
