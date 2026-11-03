; ============================================================
; util.asm - general helper routines
; ============================================================

; ---- utoa16: HL (unsigned) -> text at (DE), DE points to the terminating 0
utoa16:
        xor a
        ld (u_flag),a
        ld bc,10000
        call .dig
        ld bc,1000
        call .dig
        ld bc,100
        call .dig
        ld bc,10
        call .dig
        ld a,l
        add a,'0'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret
.dig:
        ld a,'0'-1
.lp:    inc a
        or a
        sbc hl,bc
        jr nc,.lp
        add hl,bc
        cp '0'
        jr nz,.emit
        ld a,(u_flag)
        or a
        ret z
        ld a,'0'
.emit:  ld (de),a
        inc de
        ld a,1
        ld (u_flag),a
        ret

; ---- itoa16: HL (signed) -> text at (DE)
itoa16:
        bit 7,h
        jr z,utoa16
        ld a,'-'
        ld (de),a
        inc de
        call neg_hl
        jr utoa16

; ---- neg_hl: HL = -HL
neg_hl:
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; ---- mul16: HL = HL*DE (low 16 bits), destroys A,BC,DE
mul16:
        ld b,h
        ld c,l
        ld hl,0
        ld a,16
.l:     add hl,hl
        sla e
        rl d
        jr nc,.n
        add hl,bc
.n:     dec a
        jr nz,.l
        ret

; ---- div16u: HL = HL/DE, DE = remainder; DE=0 -> carry. destroys A,BC
div16u:
        ld a,d
        or e
        jr nz,.ok
        scf
        ret
.ok:    ld a,h
        ld c,l
        ld hl,0
        ld b,16
.l:     sla c
        rla
        adc hl,hl
        or a
        sbc hl,de
        jr c,.f
        inc c
        jr .n
.f:     add hl,de
.n:     djnz .l
        ex de,hl            ; DE = remainder
        ld h,a
        ld l,c              ; HL = quotient
        or a
        ret

; ---- memmove: HL=src, DE=dst, BC=length (overlap safe)
memmove:
        ld a,b
        or c
        ret z
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.back          ; src < dst -> copy from the end
        ldir
        ret
.back:  add hl,bc
        dec hl
        ex de,hl
        add hl,bc
        dec hl
        ex de,hl
        lddr
        ret

; ---- memset: HL=address, BC=length (>0), A=value
memset:
        ld (hl),a
        dec bc
        ld a,b
        or c
        ret z
        ld d,h
        ld e,l
        inc de
        ldir
        ret

; ---- strlen: HL -> A = length (max 255)
strlen:
        push hl
        ld b,0
.l:     ld a,(hl)
        or a
        jr z,.e
        inc hl
        inc b
        jr .l
.e:     ld a,b
        pop hl
        ret

; ---- to_upper: A
to_upper:
        cp 'a'
        ret c
        cp 'z'+1
        ret nc
        sub 32
        ret

; ---- is_digit: A -> NC if '0'..'9'
is_digit:
        cp '0'
        ret c
        cp '9'+1
        ccf
        ret

; ---- is_alpha: A -> NC if 'A'..'Z'
is_alpha:
        cp 'A'
        ret c
        cp 'Z'+1
        ccf
        ret

; ---- jp_hl: indirect call
jp_hl:  jp (hl)

; ---- jump_table: A=index, HL=address table -> jump
jump_table:
        add a,a
        add a,l
        ld l,a
        jr nc,.n
        inc h
.n:     ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

; ---- beep: short beep
beep:
        push bc
        ld c,60
.l:     ld a,0x10+BORDER
        out (0xFE),a
        ld b,90
.d1:    djnz .d1
        ld a,BORDER
        out (0xFE),a
        ld b,90
.d2:    djnz .d2
        dec c
        jr nz,.l
        pop bc
        ret

u_flag: db 0
