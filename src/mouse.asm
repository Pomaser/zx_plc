; ============================================================
; mouse.asm - Kempston mouse (DEMO bank)
; ============================================================
; Ports: buttons 0xFADF (active low: bit 0 right, bit 1 left), X 0xFBDF,
; Y 0xFFDF (8-bit counters, Y grows upward). Options > Mouse switches it on
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

; ---- ms_toggle: Options > Mouse
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
        call ms_bar             ; on the menu bar: it opens (K_EDIT)
        ld a,K_EDIT
        ret nc
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

ms_arrow:                       ; the pointer, 8x8 (1 = pixel)
        db %10000000
        db %11000000
        db %11100000
        db %11110000
        db %11111000
        db %11100000
        db %10110000
        db %00011000

txt_ms_none: db "No Kempston mouse",0

; ---- ui_choose_lang: A = language (0-2), carry = cancelled (DEMO bank: BCALL)
ui_choose_lang:
        ld hl,txt_lang_q
        call popup_open
.k:     call kb_wait
        cp K_MOUSE              ; a click on a language line
        jr nz,.nm
        ld a,3
        ld b,3
        call ms_item
        jr c,.cancel
        ld b,a
        jr .ok
.nm:    cp K_BREAK
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

; ---- ms_item: a click in a list window: A = items, B = row of item 0
;      relative to win_r -> NC: A = the item clicked; C: right button or
;      outside the items (cancel)
ms_item:
        ld c,a
        ld a,(ms_btn)
        dec a
        scf
        ret nz                  ; right button
        ld a,(ms_cy)
        rrca
        rrca
        rrca
        and 31
        ld hl,win_r
        sub (hl)
        sub b
        ret c
        cp c
        ccf
        ret c
        ld e,a
        ld a,(ms_cx)
        ld hl,win_bx
        sub (hl)
        ret c
        ld hl,win_bw
        cp (hl)
        ccf
        ret c
        ld a,e
        ret

; ---- ms_msel: NC: A = the menu title clicked on the menu bar (then
;      forgotten); C: none
ms_msel:
        ld a,(ms_menu)
        cp 0xFF
        scf
        ret z
        ld b,a
        ld a,0xFF
        ld (ms_menu),a
        ld a,b
        or a
        ret

; ---- ms_mhit: a click in the open drop-down -> NC: A = item; C: cancel
ms_mhit:
        ld a,(drop_n)
        ld b,0
        jr ms_item

; ---- ms_yn: a click in a yes / no question -> A = 'Y' (left part of the
;      last line), 'N' (its right part, or the right button) or 0
ms_yn:  ld a,(ms_btn)
        dec a
        ld a,'N'
        ret nz
        ld a,(ms_cy)
        rrca
        rrca
        rrca
        and 31
        ld b,a
        ld a,(win_rows)
        ld hl,win_r
        add a,(hl)
        sub 2
        cp b
        ld a,0
        ret nz                  ; not on the "Y = yes  N = no" line
        ld a,(win_bx)
        add a,8+MB_TAB
        ld b,a
        ld a,(ms_cx)
        cp b
        ld a,'Y'
        ret c
        ld a,'N'
        ret

; ---- ms_bar: a click on the menu bar -> NC: A = title (ms_menu set); C: no
ms_bar: ld a,(ms_cy)
        cp 8
        ccf
        ret c
        ld b,0
.l:     ld hl,menu_x
        ld e,b
        ld d,0
        add hl,de
        ld a,(hl)
        sub 3
        ld c,a                  ; C = left edge
        ld hl,menu_w
        add hl,de
        ld a,(hl)
        add a,5
        add a,c
        ld d,a                  ; D = right edge
        ld a,(ms_cx)
        cp c
        jr c,.n
        cp d
        jr nc,.n
        ld a,b
        ld (ms_menu),a
        or a
        ret
.n:     inc b
        ld a,b
        cp MENU_N
        jr c,.l
        scf
        ret

; ---- ms_crow: A = the char row of the last click
ms_crow:
        ld a,(ms_cy)
        rrca
        rrca
        rrca
        and 31
        ret

; ---- ms_grid: the last click in an LD / FBD view -> NC: D = row
;      (ld_top + (char row - ld_vbase) / 2), E = position 0-9; C: outside
ms_grid:
        call ms_crow
        ld hl,ld_vbase
        sub (hl)
        ret c
        srl a
        ld hl,ld_vn
        cp (hl)
        ccf
        ret c
        ld hl,ld_top
        add a,(hl)
        ld d,a
        ld a,(ms_cx)            ; cell 1+3p .. 3+3p
        rrca
        rrca
        rrca
        and 31
        or a
        jr z,.p
        dec a
.p:     ld e,0
.dv:    sub 3
        jr c,.dd
        inc e
        jr .dv
.dd:    ld a,e
        cp LD_CPOS+1
        jr c,.ok
        ld e,LD_CPOS
.ok:    or a
        ret

; ---- ms_pou: the last click in the POU list -> NC: A = the slot of its row
;      (rows from POU_LIST_ROW, used slots only); C: no POU there
ms_pou: call ms_crow
        sub POU_LIST_ROW
        ret c
        ld c,a                  ; C = used slots to skip
        ld b,0
.l:     ld a,b
        call pou_used
        jr z,.n
        ld a,c
        or a
        ld a,b
        ret z                   ; (NC)
        dec c
.n:     inc b
        ld a,b
        cp MAX_POU
        jr c,.l
        scf
        ret
