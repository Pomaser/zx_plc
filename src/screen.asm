; ============================================================
; screen.asm - výstup na obrazovku (32x24 znaků, ROM font)
; ============================================================
; Řídicí kódy v řetězcích pro scr_puts:
;   0          konec
;   1,row,col  AT
;   2,attr     nastavit atribut
; Znaky 128+ = vlastní grafika (udg_gfx)
; ============================================================
SC_END  EQU 0
SC_AT   EQU 1
SC_ATTR EQU 2

; ---- scr_cls: smaže celou obrazovku atributem cur_attr
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

; ---- scr_at: B=řádek, C=sloupec
scr_at:
        ld (cur_col),bc
        ret

; ---- attr_addr: B=řádek, C=sloupec -> HL adresa atributu (ničí A)
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

; ---- pix_addr: B=řádek, C=sloupec -> HL adresa 1. mikrořádku (ničí A)
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

; ---- scr_putc: A=znak na pozici kurzoru, posune kurzor. Zachová BC,DE,HL
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
        ex de,hl            ; DE = glyf
        ld bc,(cur_col)     ; C=sloupec, B=řádek
        ld a,b
        cp 24
        jr nc,.done         ; mimo obrazovku - ignorovat
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

; ---- scr_puts: HL=řetězec s řídicími kódy, HL na konci za 0
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

; ---- scr_putsn: HL=text, B=počet znaků (bez řídicích kódů)
scr_putsn:
        ld a,b
        or a
        ret z
.l:     ld a,(hl)
        inc hl
        call scr_putc
        djnz .l
        ret

; ---- scr_spaces: B mezer
scr_spaces:
        ld a,b
        or a
        ret z
.l:     ld a,' '
        call scr_putc
        djnz .l
        ret

; ---- scr_fill_attr: B=řádek, C=sloupec, D=délka, E=atribut
scr_fill_attr:
        call attr_addr
.l:     ld (hl),e
        inc hl
        dec d
        jr nz,.l
        ret

; ---- scr_clear_rows: B=první řádek, C=počet; atribut cur_attr
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

; ---- scr_num: HL=číslo (signed) vytiskne
scr_num:
        ld de,num_buf
        call itoa16
        ld hl,num_buf
        jp scr_puts

; ---- scr_unum_r: HL=číslo (unsigned) zarovnané vpravo na šířku B
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

; ---- vlastní grafika (znaky 128+) - doplní se ve fázi LD/FBD
udg_gfx:
        ; 128: plný blok
        db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
        ; 129: LED vypnuto (kroužek)
        db 0x00,0x3C,0x42,0x42,0x42,0x42,0x3C,0x00
        ; 130: LED zapnuto (plný kruh)
        db 0x00,0x3C,0x7E,0x7E,0x7E,0x7E,0x3C,0x00

cur_col:  db 0
cur_row:  db 0
cur_attr: db ATTR_NORMAL
num_buf:  ds 8
