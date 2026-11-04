; ============================================================
; ld_edit.asm - Ladder Diagram editor
; ============================================================
; POU body: [number of rows] + records [row][pos][type][area][index],
; sorted by (row, pos). type bit 7 = vertical link down at the right
; edge of the position. Row = left rail, positions 0-8 (contacts,
; wires), position 9 (coil), right rail. One element = 3 cells:
; leads + symbol in the outer cells, the middle cell shows the state
; in the simulation. One LD row = label row + symbol row.
; ============================================================
LT_EMPTY  EQU 0
LT_WIRE   EQU 1
LT_NO     EQU 2
LT_NC     EQU 3
LT_P      EQU 4
LT_N      EQU 5
LT_COIL   EQU 8
LT_NCOIL  EQU 9
LT_SET    EQU 10
LT_RES    EQU 11
LT_VL     EQU 0x80          ; vertical link down
LT_MASK   EQU 0x0F
LD_CPOS   EQU 9             ; coil position
LD_MAXROWS EQU 99
ATTR_LD_ON EQU 0x60         ; black on bright green: active element

; ============================================================
; storage
; ============================================================

; ---- ld_nrows: A = number of rows (an empty body has one)
ld_nrows:
        ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        ld a,1
        ret z
        ld a,(hl)
        ret

; ---- ld_hdr: makes sure the body has its header byte; C = out of memory
ld_hdr: ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        ret nz
        ld de,0
        ld bc,1
        ld a,(cur_pou)
        call pou_insert
        ret c
        ld (hl),1
        or a
        ret

; ---- ld_find: D = row, E = pos -> NC: HL = record; C: HL = insertion point
ld_find:
        ld (lf_pos),de
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (lf_end),hl
        pop hl
        ld a,b
        or c
        scf
        ret z
        inc hl                  ; header
.l:     push hl
        ld de,(lf_end)
        or a
        sbc hl,de
        pop hl
        jr nc,.nf
        ld a,(lf_row)
        cp (hl)
        jr c,.nf
        jr nz,.n
        inc hl
        ld a,(lf_pos)
        cp (hl)
        dec hl
        jr c,.nf
        jr z,.f
.n:     ld de,5
        add hl,de
        jr .l
.f:     or a
        ret
.nf:    scf
        ret

; ---- ld_get: D = row, E = pos -> A = type (0 = nothing), B = area, C = index
;      (keeps DE)
ld_get: push de
        call ld_find
        pop de
        jr c,.none
        inc hl
        inc hl
        ld a,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        ret
.none:  xor a
        ld b,a
        ld c,a
        ret

; ---- ld_put: D = row, E = pos, A = type, B = area, C = index
;      type 0 without a link removes the record. C = out of memory (shown)
ld_put: ld (lp_rec+2),a
        ld a,b
        ld (lp_rec+3),a
        ld a,c
        ld (lp_rec+4),a
        ld a,d
        ld (lp_rec),a
        ld a,e
        ld (lp_rec+1),a
        call ld_hdr
        jr c,.mem
        ld a,(lp_rec)
        ld d,a
        ld a,(lp_rec+1)
        ld e,a
        call ld_find
        jr c,.new
        ld a,(lp_rec+2)
        or a
        jr z,.del
        ex de,hl                ; overwrite
        ld hl,lp_rec
        ld bc,5
        ldir
        jr .rows
.del:   call il_offset
        ld bc,5
        ld a,(cur_pou)
        call pou_delete
        or a
        ret
.new:   ld a,(lp_rec+2)
        or a
        ret z
        call il_offset
        ld bc,5
        ld a,(cur_pou)
        call pou_insert
        jr c,.mem
        ex de,hl
        ld hl,lp_rec
        ld bc,5
        ldir
.rows:  ld a,(cur_pou)          ; the row count covers this row
        call pou_body
        ld a,(lp_rec)
        inc a
        cp (hl)
        jr c,.ok
        ld (hl),a
.ok:    or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret

; ---- ld_ins_row: D = row -> empty row inserted (rows below move down)
ld_ins_row:
        ld a,d
        ld (lr_row),a
        call ld_nrows
        cp LD_MAXROWS
        ret nc
        call ld_hdr
        ret c
        call ld_rec_loop
.l:     jr nc,.e
        ld a,(lr_row)
        cp (hl)
        jr z,.inc
        jr nc,.n
.inc:   inc (hl)
.n:     call ld_rec_next
        jr .l
.e:     ld a,(cur_pou)
        call pou_body
        inc (hl)
        ret

; ---- ld_del_row: D = row -> row removed (rows below move up)
ld_del_row:
        ld a,d
        ld (lr_row),a
.again: call ld_rec_loop        ; remove the records of the row
.f:     jr nc,.shift
        ld a,(lr_row)
        cp (hl)
        jr z,.rm
        call ld_rec_next
        jr .f
.rm:    call il_offset
        ld bc,5
        ld a,(cur_pou)
        call pou_delete
        jr .again
.shift: call ld_rec_loop
.s:     jr nc,.hdr
        ld a,(lr_row)
        cp (hl)
        jr nc,.sn
        dec (hl)
.sn:    call ld_rec_next
        jr .s
.hdr:   call ld_nrows
        cp 2
        ret c                   ; keep at least one row
        ld a,(cur_pou)
        call pou_body
        dec (hl)
        ret

; ld_rec_loop: HL = first record, C if there is one (lf_end = end)
ld_rec_loop:
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (lf_end),hl
        pop hl
        ld a,b
        or c
        ret z                   ; NC: no body
        inc hl
        jr ld_rec_chk
; ld_rec_next: HL = next record, C if not at the end
ld_rec_next:
        ld de,5
        add hl,de
ld_rec_chk:
        push hl
        ld de,(lf_end)
        or a
        sbc hl,de
        pop hl
        ret

; ============================================================
; drawing
; ============================================================

; element glyphs (8x8): wire, contact left/right, blank, slash, P, N, coil left/right, S, R
G_WIRE  EQU 0
G_CL    EQU 1
G_CR    EQU 2
G_BL    EQU 3
G_SL    EQU 4
G_P     EQU 5
G_N     EQU 6
G_OL    EQU 7
G_OR    EQU 8
G_S     EQU 9
G_R     EQU 10
ld_gfx:
        db 0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x00      ; wire
        db 0x00,0x02,0x02,0x02,0xFE,0x02,0x02,0x02      ; --|
        db 0x00,0x40,0x40,0x40,0x7F,0x40,0x40,0x40      ; |--
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00      ; blank
        db 0x00,0x04,0x04,0x08,0x10,0x20,0x20,0x00      ; /
        db 0x00,0x00,0x38,0x24,0x38,0x20,0x20,0x00      ; P
        db 0x00,0x00,0x24,0x34,0x2C,0x24,0x24,0x00      ; N
        db 0x00,0x02,0x04,0x04,0xFC,0x04,0x04,0x02      ; --(
        db 0x00,0x40,0x20,0x20,0x3F,0x20,0x20,0x40      ; )--
        db 0x00,0x00,0x1C,0x20,0x18,0x04,0x38,0x00      ; S
        db 0x00,0x00,0x38,0x24,0x38,0x28,0x24,0x00      ; R
; glyphs (left, middle, right) per element type 0-11
ld_types:
        db G_BL,G_BL,G_BL, G_WIRE,G_WIRE,G_WIRE, G_CL,G_BL,G_CR, G_CL,G_SL,G_CR
        db G_CL,G_P,G_CR,  G_CL,G_N,G_CR,      G_BL,G_BL,G_BL, G_BL,G_BL,G_BL
        db G_OL,G_BL,G_OR, G_OL,G_SL,G_OR,     G_OL,G_S,G_OR,  G_OL,G_R,G_OR

; ---- ld_draw_view: rows ld_top.. on screen rows ld_vbase.. (ld_vn rows)
ld_draw_view:
        xor a
        ld (ld_i),a
.l:     ld a,(ld_i)
        ld b,a
        ld a,(ld_vn)
        cp b
        ret z
        ld a,b
        call ld_draw_row
        ld hl,ld_i
        inc (hl)
        jr .l

; ---- ld_draw_row: A = visible row index
ld_draw_row:
        ld b,a
        add a,a
        ld c,a
        ld a,(ld_vbase)
        add a,c
        ld (ld_lrow),a          ; label row
        inc a
        ld (ld_srow),a          ; symbol row
        ld a,(ld_top)
        add a,b
        ld (ld_r),a
        ; clear both char rows
        ld a,(ld_lrow)
        ld b,a
        ld c,0
        ld de,0x2000+ATTR_NORMAL
        call scr_fill_attr
        ld a,(ld_srow)
        ld b,a
        ld c,0
        ld de,0x2000+ATTR_NORMAL
        call scr_fill_attr
        ld a,(ld_lrow)
        ld b,a
        call pt_clear_row
        ld a,(ld_srow)
        ld b,a
        call pt_clear_row
        call ld_nrows
        ld b,a
        ld a,(ld_r)
        cp b
        ret nc                  ; below the last row
        ; rails
        ld c,7
        call .rail
        ld c,248
        call .rail
        xor a
        ld (ld_p),a
.pos:   ld a,(ld_r)
        ld d,a
        ld a,(ld_p)
        ld e,a
        call ld_get
        ld (ld_t),a
        call ld_set_ar
        call ld_draw_elem
        ; incoming link from the row above
        ld a,(ld_r)
        or a
        jr z,.nin
        dec a
        ld d,a
        ld a,(ld_p)
        ld e,a
        call ld_get
        bit 7,a
        jr z,.nin
        ld a,(ld_lrow)
        ld b,a
        ld hl,0x0008
        call .vl
        ld a,(ld_srow)
        ld b,a
        ld hl,0x0005
        call .vl
.nin:   ld a,(ld_t)             ; own link down
        bit 7,a
        jr z,.nown
        ld a,(ld_srow)
        ld b,a
        ld hl,0x0404
        call .vl
.nown:  ld hl,ld_p
        inc (hl)
        ld a,(hl)
        cp LD_CPOS+1
        jr c,.pos
        ret
; vertical rail line at x = C in both rows
.rail:  ld a,(ld_lrow)
        ld b,a
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        push bc
        call px_span
        pop bc
        ld a,(ld_srow)
        ld b,a
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        jp px_span
; vertical link line at the right edge of position ld_p: B = row, H/L = lines
.vl:    ld a,(ld_p)
        ld c,a
        add a,a
        add a,c                 ; 3p
        add a,4
        add a,a
        add a,a
        add a,a
        dec a                   ; (3p+4)*8-1
        ld c,a
        ld d,1
        ld e,PX_SET
        jp px_span

; ---- ld_draw_elem: ld_t / ld_ar at (ld_r, ld_p): symbol + label
ld_draw_elem:
        ld a,(ld_t)
        and LT_MASK
        cp 12
        ret nc
        ld c,a
        add a,a
        add a,c                 ; *3
        ld e,a
        ld d,0
        ld hl,ld_types
        add hl,de
        ld a,(ld_p)
        ld c,a
        add a,a
        add a,c
        inc a                   ; first cell 1+3p
        ld c,a
        ld b,3
.g:     push bc
        push hl
        ld a,(hl)               ; glyph -> 8 bytes
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,ld_gfx
        add hl,de
        ex de,hl
        ld a,(ld_srow)
        ld b,a
        call pix_addr
        ld b,8
.gl:    ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz .gl
        pop hl
        pop bc
        inc hl
        inc c
        djnz .g
        ; label
        ld a,(ld_t)
        and LT_MASK
        cp LT_NO
        ret c                   ; empty / wire
        ld de,ld_lbl
        ld a,1
        ld (fo_style),a
        ld hl,ld_ar
        call il_fmt_one
        xor a
        ld (fo_style),a
        ld (de),a
        ld a,(ld_p)             ; element x = (1+3p)*8
        ld c,a
        add a,a
        add a,c
        inc a
        add a,a
        add a,a
        add a,a
        ld c,a
        add a,23
        ld (pt_xmax),a
        ld hl,ld_lbl
        call pt_width
        cp 23
        jr c,.w
        ld a,22
.w:     neg
        add a,24
        srl a
        add a,c
        ld (pt_x),a
        ld a,(ld_lrow)
        ld (pt_row),a
        ld hl,ld_lbl
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ret

; ---- ld_cursor: XORs the symbol cells of the cursor position
ld_cursor:
        ld a,(ld_row)
        ld b,a
        ld a,(ld_top)
        ld c,a
        ld a,b
        sub c
        add a,a
        ld b,a
        ld a,(ld_vbase)
        add a,b
        inc a
        ld b,a
        ld a,(ld_pos)
        ld c,a
        add a,a
        add a,c
        inc a
        add a,a
        add a,a
        add a,a
        ld c,a
        ld d,24
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; ---- ld_fix_top: keeps ld_row visible; NZ = ld_top changed
ld_fix_top:
        ld a,(ld_top)
        ld b,a
        ld a,(ld_row)
        cp b
        jr c,.up
        sub b
        ld c,a
        ld a,(ld_vn)
        dec a
        cp c
        jr c,.down
        xor a
        ret
.up:    ld (ld_top),a
        or 1
        ret
.down:  ld a,(ld_vn)
        dec a
        ld b,a
        ld a,(ld_row)
        sub b
        ld (ld_top),a
        or 1
        ret

; ---- ld_set_state: middle cells coloured by the state (simulation);
;      walks the records once, only attribute writes
ld_set_state:
        call ld_rec_loop
.l:     ret nc
        ld a,(ld_top)           ; visible row?
        ld b,a
        ld a,(hl)
        sub b
        jr c,.n
        ld c,a
        ld a,(ld_vn)
        dec a
        cp c
        jr c,.n
        ld a,c
        add a,a
        ld b,a
        ld a,(ld_vbase)
        add a,b
        inc a
        ld (ld_srow),a
        inc hl
        ld a,(hl)
        ld (ld_p),a
        inc hl
        ld a,(hl)
        and LT_MASK
        ld (ld_t),a
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        dec hl
        dec hl
        dec hl
        dec hl
        cp LT_NO
        jr c,.n
        push hl
        ld a,b
        ld de,0
        call cp_operand_av
        ld e,ATTR_NORMAL
        ld a,(cp_mode)
        cp VM_MB
        jr nz,.set
        ld hl,(cp_arg)
        ld a,(cp_arg3)
        and (hl)
        ld a,(ld_t)
        jr z,.f
        cp LT_NC                ; operand TRUE: active except NC
        jr z,.set
        ld e,ATTR_LD_ON
        jr .set
.f:     cp LT_NC                ; operand FALSE: only NC is active
        jr nz,.set
        ld e,ATTR_LD_ON
.set:   ld a,(ld_p)
        ld c,a
        add a,a
        add a,c
        add a,2                 ; middle cell 2+3p
        ld c,a
        ld a,(ld_srow)
        ld b,a
        call attr_addr
        ld (hl),e
        pop hl
.n:     call ld_rec_next
        jr .l

; ============================================================
; editor
; ============================================================
ld_editor:
        call screen_begin
        ld a,(cur_pou)
        ld hl,ld_pou
        cp (hl)
        jr z,.same
        ld (hl),a
        xor a
        ld (ld_row),a
        ld (ld_pos),a
        ld (ld_top),a
.same:  ld a,1
        ld (ld_vbase),a
        ld a,11
        ld (ld_vn),a
        call ld_fix_top
.full:  call ld_draw_view
.cur:   call ld_cursor
        call ld_info
.loop:  call kb_wait
        push af
        call ld_cursor          ; cursor off
        pop af
        cp K_LEFT
        jr z,.left
        cp K_RIGHT
        jr z,.right
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jp z,.enter
        cp K_DEL
        jp z,.del
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        call to_upper
        cp 'V'
        jp z,.vlink
        ld b,a
        ld hl,ld_keys_c         ; element keys
        ld a,(ld_pos)
        cp LD_CPOS
        jr c,.kl
        ld hl,ld_keys_q
.kl:    ld a,(hl)
        or a
        jr z,.cur
        cp b
        jr z,.kf
        inc hl
        inc hl
        jr .kl
.kf:    inc hl
        ld a,(hl)
        jp .place
.left:  ld a,(ld_pos)
        or a
        jr z,.cur
        dec a
        ld (ld_pos),a
        jr .cur
.right: ld a,(ld_pos)
        cp LD_CPOS
        jr z,.cur
        inc a
        ld (ld_pos),a
        jr .cur
.up:    ld a,(ld_row)
        or a
        jr z,.cur
        dec a
        jr .mv
.down:  call ld_nrows           ; one row below the last may be used
        ld b,a
        ld a,(ld_row)
        cp b
        jp nc,.cur
        inc a
        cp LD_MAXROWS
        jp nc,.cur
.mv:    ld (ld_row),a
        call ld_fix_top
        jp nz,.full
        jp .cur

        ; ---- place an element (A = type)
.place: ld (ld_newt),a
        cp LT_NO
        jr c,.pl2               ; wire: no operand
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        call ld_set_ar
        ld a,(ld_newt)
        call ld_ask_operand
        jp c,.redraw
        call ld_set_ar
        jr .pl3
.pl2:   ld bc,0
        call ld_set_ar
.pl3:   ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        and LT_VL               ; keep the link
        ld b,a
        ld a,(ld_newt)
        or b
        ld bc,(ld_ar)           ; C = area, B = index
        push af
        ld a,c
        ld c,b
        ld b,a
        pop af
        push af
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        pop af
        call ld_put
        jp c,.redraw
        call ld_autowire
.redraw:
        call status_right
        jp .full

        ; ---- ENTER: operand of the current element
.enter: ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        and LT_MASK
        cp LT_NO
        jp c,.cur
        jp .place

        ; ---- DELETE: clear the position (the link stays)
.del:   ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        and LT_VL
        ld bc,0
        call ld_put
        jr .redraw

        ; ---- V: vertical link at the right edge
.vlink: ld a,(ld_pos)
        cp LD_CPOS
        jp nc,.cur
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        xor LT_VL
        call ld_put
        jr .redraw

.menu:  call menu_handle
        jp z,.cur
        cp CMD_REDRAW
        jp z,.full
        cp CMD_IL_INS
        jr z,.mins
        cp CMD_IL_DEL
        jr z,.mdel
        push af
        ld hl,0
        ld (st_left),hl
        pop af
        ret
.mins:  ld a,(ld_row)
        ld d,a
        call ld_ins_row
        jr .redraw
.mdel:  ld a,(ld_row)
        ld d,a
        call ld_del_row
        jr .redraw

; key -> element type: contacts (positions 0-8), coils (position 9)
ld_keys_c: db 'C',LT_NO, '/',LT_NC, 'P',LT_P, 'N',LT_N, '-',LT_WIRE, 0
ld_keys_q: db 'C',LT_COIL, '/',LT_NCOIL, 'S',LT_SET, 'R',LT_RES, 0

; ---- ld_autowire: fills empty positions left of the new element with wires
;      (up to the previous element, the left rail or an incoming link)
ld_autowire:
        ld a,(ld_pos)
.l:     or a
        ret z
        dec a
        ld (ld_aw),a
        ld a,(ld_row)
        ld d,a
        ld a,(ld_aw)
        ld e,a
        call ld_get
        and LT_MASK
        ret nz                  ; previous element reached
        ld a,(ld_row)           ; power coming in from the row above?
        or a
        jr z,.w
        dec a
        ld d,a
        ld a,(ld_aw)
        ld e,a
        call ld_get
        bit 7,a
        ret nz
.w:     ld a,(ld_row)
        ld d,a
        ld a,(ld_aw)
        ld e,a
        call ld_get
        and LT_VL
        or LT_WIRE
        ld bc,0
        call ld_put
        ret c
        ld a,(ld_aw)
        jr .l

; ---- ld_ask_operand: A = element type, ld_ar = current operand
;      NC: B = area, C = index; C = cancelled
ld_ask_operand:
        ld (ld_kind),a
        ; initial text = current operand
        ld de,ld_obuf
        xor a
        ld (de),a
        ld a,(ld_ar)
        or a
        jr z,.ask
        ld hl,ld_ar
        call il_fmt_one
        xor a
        ld (de),a
.ask:   ld hl,txt_ld_opq
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,ld_obuf
        ld de,0x0C00
        call ui_input
        push af
        call win_close
        pop af
        ret c
        ld hl,ld_obuf
        call op_parse
        jr c,.bad
        ld b,a
        ld a,(hl)
        or a
        jr nz,.bad
        ld a,b
        and AR_MASK
        cp AR_FBM
        jr z,.fbm
        cp AR_Q
        jr z,.ok
        cp AR_M
        jr z,.ok
        cp AR_I
        jr nz,.bad
        ld a,(ld_kind)          ; inputs only for contacts
        cp LT_COIL
        jr nc,.bad
.ok:    or a
        ret
.fbm:   push bc                 ; only BOOL members
        ld a,c
        rrca
        rrca
        and 0x3F
        ld e,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld a,b
        rrca
        rrca
        rrca
        rrca
        and 7
        add a,e
        ld e,a
        ld d,0
        ld hl,fb_mdesc
        add hl,de
        ld a,(hl)
        pop bc
        bit 7,a
        jr z,.ok
.bad:   ld hl,err_ld_op
        call ui_error
        jp .ask

; ld_set_ar: B = area, C = index -> ld_ar ([area][index] for il_fmt_one)
ld_set_ar:
        ld a,b
        ld (ld_ar),a
        ld a,c
        ld (ld_ar+1),a
        ret

; ---- ld_info: status bar: symbol name and comment of the current element
ld_info:
        ld hl,0
        ld (st_left),hl
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        and LT_MASK
        cp LT_NO
        jr c,.show
        ld a,b
        and AR_MASK
        cp AR_FBM
        jr nz,.a
        ld b,AR_FBI
.a:     ld a,b
        call sym_find_addr
        jr c,.show
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (sy_end),hl
        pop hl
        inc hl
        inc hl
        inc hl
        ld de,ld_infob
.n:     ld a,(hl)
        inc hl
        or a
        jr z,.ne
        ld (de),a
        inc de
        jr .n
.ne:    ld a,' '
        ld (de),a
        inc de
        ld (de),a
        inc de
.c:     push hl
        ld bc,(sy_end)
        or a
        sbc hl,bc
        pop hl
        jr nc,.e
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .c
.e:     xor a
        ld (de),a
        ld hl,ld_infob
        ld (st_left),hl
.show:  jp status_left

txt_ld_opq: db "Operand (address or symbol):",0," ",0," ",0,0
err_ld_op:  db "Invalid operand for this element",0

ld_pou:   db 0xFF
ld_row:   db 0
ld_pos:   db 0
ld_top:   db 0
ld_vbase: db 1
ld_vn:    db 11
ld_i:     db 0
ld_r:     db 0
ld_p:     db 0
ld_t:     db 0
ld_ar:    dw 0              ; area, index of the element operand
ld_newt:  db 0
ld_kind:  db 0
ld_aw:    db 0
ld_lrow:  db 0
ld_srow:  db 0
lf_pos:   db 0              ; ld_find key (must be followed by lf_row)
lf_row:   db 0
lf_end:   dw 0
lr_row:   db 0
lp_rec:   ds 5
ld_lbl:   ds 16
ld_obuf:  ds 14
ld_infob: ds 44
