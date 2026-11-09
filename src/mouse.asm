; ============================================================
; mouse.asm - Kempston mouse (DEMO bank)
; ============================================================
; Ports: buttons 0xFADF (active low: bit 0 right, bit 1 left), X 0xFBDF,
; Y 0xFFDF (8-bit counters, Y grows upward). View > Mouse switches it on
; (ms_toggle; only when a mouse is detected). kb_get (core) calls ms_poll
; once per frame while it waits: the pointer follows the mouse (an 8x8
; arrow, XOR) and a button press returns K_MOUSE with the position in
; ms_cx / ms_cy and the button in ms_btn (1 left, 2 right). The pointer is
; hidden while the screens draw (kb_get hides it before it returns a key).
; The state is in the RT area (vm.asm), so all banks can read it.
; ============================================================

MS_PBTN EQU 0xFADF
MS_PX   EQU 0xFBDF
MS_PY   EQU 0xFFDF

; ---- ms_toggle: View > Mouse
ms_toggle:
        ld a,(ms_on)
        or a
        jr z,.on
        call ms_hide
        xor a
        ld (ms_on),a
        ret
.on:    call ms_detect
        ld hl,txt_ms_none
        jp c,ui_error
        ld bc,MS_PX             ; the counters as they are now
        in a,(c)
        ld (ms_lx),a
        ld b,MS_PY>>8
        in a,(c)
        ld (ms_ly),a
        ld b,MS_PBTN>>8
        in a,(c)
        ld (ms_b),a
        ld a,128                ; the pointer in the middle of the screen
        ld (ms_x),a
        ld a,96
        ld (ms_y),a
        xor a
        ld (ms_vis),a
        inc a
        ld (ms_on),a
        ret

; ---- ms_detect: NC = a Kempston mouse answers. Without one the ports read
;      0xFF in the top border (floating bus on 128K / +2, 0xFF on +2A / +3):
;      X and Y are read just after the interrupt, a few times
ms_detect:
        ld b,4
.l:     push bc
        halt
        ld bc,MS_PX
        in a,(c)
        inc a
        jr nz,.yes
        ld b,MS_PY>>8
        in a,(c)
        inc a
        jr nz,.yes
        pop bc
        djnz .l
        scf
        ret
.yes:   pop bc
        or a
        ret

; ---- ms_poll: follows the mouse -> A = K_MOUSE (a button pressed: the
;      pointer is hidden, ms_cx / ms_cy / ms_btn set) or 0
ms_poll:
        ld bc,MS_PX
        in a,(c)
        ld hl,ms_lx
        ld e,(hl)
        ld (hl),a
        sub e
        ld e,a                  ; E = X delta
        ld a,(ms_x)
        ld c,255
        call ms_cadd
        ld (ms_nx),a
        ld bc,MS_PY
        in a,(c)
        ld hl,ms_ly
        ld e,(hl)
        ld (hl),a
        ld d,a
        ld a,e
        sub d
        ld e,a                  ; E = -Y delta (the screen y grows down)
        ld a,(ms_y)
        ld c,191
        call ms_cadd
        ld (ms_ny),a
        ld hl,ms_x              ; moved: the pointer moves
        ld a,(ms_nx)
        cp (hl)
        jr nz,.mv
        ld hl,ms_y
        ld a,(ms_ny)
        cp (hl)
        jr z,.st
.mv:    call ms_hide
        ld a,(ms_nx)
        ld (ms_x),a
        ld a,(ms_ny)
        ld (ms_y),a
.st:    ld a,(ms_vis)
        or a
        call z,ms_draw
        ld bc,MS_PBTN           ; a button pressed now
        in a,(c)
        ld hl,ms_b
        ld e,(hl)               ; E = before
        ld (hl),a
        cpl
        and e                   ; pressed: 0 now, 1 before
        ld b,1
        bit 1,a
        jr nz,.cl
        inc b
        bit 0,a
        jr nz,.cl
        xor a
        ret
.cl:    ld a,b
        ld (ms_btn),a
        ld a,(ms_x)
        ld (ms_cx),a
        ld a,(ms_y)
        ld (ms_cy),a
        call ms_hide
        ld a,K_MOUSE
        ret

; ms_cadd: A = position, E = signed delta, C = maximum -> A clamped
ms_cadd:
        ld l,a
        ld h,0
        ld a,e
        rla
        sbc a,a
        ld d,a
        add hl,de
        bit 7,h
        jr nz,.z
        ld a,h
        or a
        jr nz,.m
        ld a,l
        cp c
        ret c
.m:     ld a,c
        ret
.z:     xor a
        ret

; ---- ms_draw / ms_hide: the pointer on / off (XOR)
ms_draw:
        ld a,(ms_x)
        ld (ms_dx),a
        ld a,(ms_y)
        ld (ms_dy),a
        ld a,1
        ld (ms_vis),a
        jr ms_xor
ms_hide:
        ld a,(ms_vis)
        or a
        ret z
        xor a
        ld (ms_vis),a
        ; fall through

; ms_xor: XORs the arrow at ms_dx / ms_dy
ms_xor: ld hl,ms_arrow
        ld a,(ms_dy)
        ld c,a
        ld b,8
.l:     ld a,c
        cp 192
        ret nc                  ; (below the screen)
        push bc
        push hl
        ld e,(hl)               ; E = the arrow line
        ld a,c                  ; HL = screen line y
        and 7
        or 0x40
        ld h,a
        ld a,c
        rra
        rra
        rra
        and 0x18
        or h
        ld h,a
        ld a,c
        rla
        rla
        and 0xE0
        ld l,a
        ld a,(ms_dx)
        ld c,a
        rrca
        rrca
        rrca
        and 31
        ld b,a                  ; B = column
        or l
        ld l,a
        ld a,c
        and 7
        ld d,e                  ; D:E = the line shifted right by x & 7
        ld e,0
        jr z,.x
.sh:    srl d
        rr e
        dec a
        jr nz,.sh
.x:     ld a,(hl)
        xor d
        ld (hl),a
        ld a,b
        cp 31
        jr z,.n                 ; (the right edge)
        inc l
        ld a,(hl)
        xor e
        ld (hl),a
.n:     pop hl
        pop bc
        inc hl
        inc c
        djnz .l
        ret

ms_arrow:
        db 0x80,0xC0,0xE0,0xF0,0xF8,0xE0,0xB0,0x18

txt_ms_none: db "No Kempston mouse",0
