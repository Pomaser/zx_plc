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
FONT_N  EQU 103            ; glyphs 32..134
CH_LEDOFF EQU 127
CH_LEDON  EQU 128
CH_CHECK  EQU 129
CH_SDESC  EQU 130          ; 130-134: g j p q y with short descenders (status bar)

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
        jr nc,.in
        jr nz,.done             ; past the screen edge
        dec a                   ; ends exactly at x = 256
.in:    ld b,a
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
        ; shift: jump into the unrolled chain so that pt_sh pairs run
        ld a,(pt_sh)
        cpl
        add a,8                 ; 7 - sh
        add a,a
        add a,a                 ; *4 bytes per pair
        ld (.shj+1),a
        ld a,l                  ; last column: the spill byte is dropped
        and 31
        cp 31
        ld a,0x79               ; ld a,c
        jr nz,.ncol
        ld a,0xAF               ; xor a
.ncol:  ld (.spill),a
        ld de,(pt_gp)
.line:  ld a,(de)               ; glyph line
        inc de
        or a
        jr z,.next              ; empty line: nothing to draw
        ld c,0
.shj:   jr .sh0                 ; (offset patched)
.sh0:   srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        srl a
        rr c
        or (hl)
        ld (hl),a
        inc l
.spill: ld a,c                  ; (patched to xor a in the last column)
        or (hl)
        ld (hl),a
        dec l
.next:  inc h
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
        xor a
.l:     ld d,l
        ld b,4
.z:     ld (hl),a               ; 8 bytes per pass
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        ld (hl),a
        inc l
        djnz .z
        ld l,d
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

; ---- pt_tiny: HL = text, B = char row, C = x -> small letters (3-4 px wide,
;      pixel lines 2-6) for the type names of LD / FBD blocks
pt_tiny:
        ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        call ft_glyph           ; HL = [width][5 rows], Z = unknown
        jr z,.skip
        ld a,(hl)
        ld (ft_w),a
        inc hl
        ld e,2                  ; first pixel line
.row:   ld a,(hl)
        inc hl
        push hl
        push bc
        ld d,a                  ; bits, bit 7 = leftmost pixel
.px:    sla d
        jr nc,.n
        push de
        push bc
        ld h,e
        ld l,1
        ld d,1
        ld e,PX_SET
        call px_span
        pop bc
        pop de
.n:     inc c
        ld a,d
        or a
        jr nz,.px
        pop bc
        pop hl
        inc e
        ld a,e
        cp 7
        jr c,.row
        ld a,(ft_w)             ; next letter: width + 1 px gap
        inc a
        add a,c
        ld c,a
.skip:  pop hl
        jr pt_tiny

; ---- pt_tiny_c: HL = text, B = char row, C = x of a 3-cell block ->
;      small letters centred in the block (x+2 .. x+21)
pt_tiny_c:
        push bc
        call pt_tiny_w
        pop bc
        neg
        add a,20
        srl a
        add a,2
        add a,c
        ld c,a
        jp pt_tiny

; pt_tiny_w: HL = text -> A = its width in small letters (keeps HL)
pt_tiny_w:
        push hl
        ld c,0
.l:     ld a,(hl)
        or a
        jr z,.e
        inc hl
        push hl
        call ft_glyph
        jr z,.s
        ld a,(hl)
        inc a
        add a,c
        ld c,a
.s:     pop hl
        jr .l
.e:     ld a,c
        or a
        jr z,.z
        dec a                   ; (no gap after the last letter)
.z:     pop hl
        ret

; ft_glyph: A = char -> NZ: HL = its glyph [width][5 rows]; Z = no glyph
ft_glyph:
        ld e,a
        ld hl,ft_tab
.l:     ld a,(hl)
        or a
        ret z
        inc hl
        cp e
        jr z,.f
        push de
        ld de,6
        add hl,de
        pop de
        jr .l
.f:     or a                    ; NZ (a printable char)
        ret

; small letters: char, width, 5 rows (bit 7 = leftmost)
ft_tab:
        db 'A',3, 0x40,0xA0,0xE0,0xA0,0xA0
        db 'D',3, 0xC0,0xA0,0xA0,0xA0,0xC0
        db 'F',3, 0xE0,0x80,0xC0,0x80,0x80
        db 'G',3, 0x60,0x80,0xA0,0xA0,0x60
        db 'N',4, 0x90,0xD0,0xB0,0x90,0x90
        db 'O',3, 0x40,0xA0,0xA0,0xA0,0x40
        db 'P',3, 0xC0,0xA0,0xC0,0x80,0x80
        db 'R',3, 0xC0,0xA0,0xC0,0xA0,0xA0
        db 'S',3, 0x60,0x80,0x40,0x20,0xC0
        db 'T',3, 0xE0,0x40,0x40,0x40,0x40
        db 'X',3, 0xA0,0xA0,0x40,0xA0,0xA0
        db 'C',3, 0x60,0x80,0x80,0x80,0x60
        db 'L',3, 0x80,0x80,0x80,0x80,0xE0
        db 'U',3, 0xA0,0xA0,0xA0,0xA0,0xE0
        db 'V',3, 0xA0,0xA0,0xA0,0xA0,0x40
        db '_',3, 0x00,0x00,0x00,0x00,0xE0
        db 'E',3, 0xE0,0x80,0xC0,0x80,0xE0
        db 'Q',4, 0x60,0x90,0x90,0xB0,0x70
        db 'B',3, 0xC0,0xA0,0xC0,0xA0,0xC0
        db 'M',5, 0x88,0xD8,0xA8,0x88,0x88
        db 'I',3, 0xE0,0x40,0x40,0x40,0xE0
        db 0
ft_w:   db 0

