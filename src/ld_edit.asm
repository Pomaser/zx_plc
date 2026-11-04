; ============================================================
; ld_edit.asm - Ladder Diagram editor
; ============================================================
; POU body: [number of rows] + records [row][pos][type][area][index],
; timer boxes have 2 more bytes [PT lo][PT hi]; sorted by (row, pos). type bit 7 = vertical link down at the right
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
LT_TON    EQU 6             ; timer boxes (record + PT)
LT_TOF    EQU 7
LT_TP     EQU 12
LT_VLITEM EQU 13            ; picker item: toggle the vertical link
LT_CMT    EQU 14            ; network comment row: [row][0][14][n][text n]
ATTR_LDCMT EQU 0x3C         ; dark green: comments
LT_VL     EQU 0x80          ; vertical link down
LT_MASK   EQU 0x0F
LD_CPOS   EQU 9             ; coil position
LD_MAXROWS EQU 99
ATTR_LD_ON EQU 0x1F         ; white on dark magenta: active element (as TRUE in IL)

; ============================================================
; storage
; ============================================================

; ---- ld_put: D = row, E = pos, A = type, B = area, C = index
;      type 0 without a link removes the record. C = out of memory (shown)
ld_put: ld (lp_rec+2),a
        push hl
        ld hl,(ld_ppt)
        ld (lp_rec+5),hl
        pop hl
        ld a,b
        ld (lp_rec+3),a
        ld a,c
        ld (lp_rec+4),a
        ld a,d
        ld (lp_rec),a
        ld a,e
        ld (lp_rec+1),a
        call ld_hdr
        jp c,.mem
        ld a,(lp_rec)
        ld d,a
        ld a,(lp_rec+1)
        ld e,a
        call ld_find
        jr c,.new
        ld a,(lp_rec+2)
        or a
        jr z,.del
        call ld_rlen
        ld b,a
        ld a,(lp_rec+2)
        call ld_tlen
        cp b
        jr nz,.repl
        ex de,hl
        ld hl,lp_rec
        ld c,a
        ld b,0
        ldir
        jr .rows
.repl:  call .del               ; length changes: remove, then insert
        ld a,(lp_rec)
        ld d,a
        ld a,(lp_rec+1)
        ld e,a
        call ld_find
        jr .ins
.del:   call il_offset          ; (destroys BC)
        call ld_rlen
        ld c,a
        ld b,0
        ld a,(cur_pou)
        call pou_delete
        or a
        ret
.new:   ld a,(lp_rec+2)
        or a
        ret z
.ins:   call il_offset
        ld a,(lp_rec+2)
        call ld_tlen
        ld c,a
        ld b,0
        push bc
        ld a,(cur_pou)
        call pou_insert
        pop bc
        jr c,.mem
        ex de,hl
        ld hl,lp_rec
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
.rm:    call il_offset          ; (destroys BC)
        call ld_rlen
        ld c,a
        ld b,0
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
        call ld_skip
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
G_VL    EQU 11
G_BXL   EQU 12
G_TO    EQU 13
G_TPG   EQU 14
G_BRN   EQU 15
G_BRF   EQU 16
G_BR    EQU 17
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
        db 0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01      ; vertical link (right edge)
        db 0x00,0x30,0x20,0x20,0xE0,0x20,0x20,0x30      ; -[
        db 0x00,0x00,0xE4,0x4A,0x4A,0x4A,0x44,0x00      ; TO
        db 0x00,0x00,0xEC,0x4A,0x4C,0x48,0x48,0x00      ; TP
        db 0x00,0x0C,0xA4,0xE4,0xE7,0xA4,0xA4,0x0C      ; N]-
        db 0x00,0x0C,0xE4,0x84,0xC7,0x84,0x84,0x0C      ; F]-
        db 0x00,0x0C,0x04,0x04,0x07,0x04,0x04,0x0C      ; ]-
; glyphs (left, middle, right) per element type 0-13
ld_types:
        db G_BL,G_BL,G_BL, G_WIRE,G_WIRE,G_WIRE, G_CL,G_BL,G_CR, G_CL,G_SL,G_CR
        db G_CL,G_P,G_CR,  G_CL,G_N,G_CR,      G_BXL,G_TO,G_BRN, G_BXL,G_TO,G_BRF
        db G_OL,G_BL,G_OR, G_OL,G_SL,G_OR,     G_OL,G_S,G_OR,  G_OL,G_R,G_OR
        db G_BXL,G_TPG,G_BR                     ; TP
        db G_BL,G_BL,G_VL                       ; picker: vertical link

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
        call ld_cmt_text        ; comment row?
        jr c,.elems
        ld a,(ld_srow)          ; "// text" in dark green
        ld b,a
        ld c,1
        ld de,0x1E00+ATTR_LDCMT
        call scr_fill_attr
        ld a,(ld_srow)
        ld (pt_row),a
        ld a,12
        ld (pt_x),a
        ld hl,txt_ld_sl
        call pt_puts
        ld hl,ld_cbuf
        jp pt_puts
.elems: xor a
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
        ld a,(ld_p)
        ld c,a
        add a,a
        add a,c
        inc a                   ; first cell 1+3p
        ld c,a
        ld a,(ld_srow)
        ld b,a
        ld a,(ld_t)
        call ld_put_glyphs
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

; ---- ld_put_glyphs: A = element type, B = char row, C = first cell
;      draws the 3 cells of the element symbol
ld_put_glyphs:
        and LT_MASK
        cp LT_VLITEM+1
        ret nc
        ld (lg_row),bc          ; C = cell, B = row
        ld c,a
        add a,a
        add a,c                 ; *3
        ld e,a
        ld d,0
        ld hl,ld_types
        add hl,de
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
        ld bc,(lg_row)
        call pix_addr
        ld b,8
.gl:    ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz .gl
        ld hl,lg_row
        inc (hl)                ; next cell
        pop hl
        pop bc
        inc hl
        djnz .g
        ret

; ---- ld_pick: element picker. A = current type -> NC: A = chosen type;
;      C = cancelled. Items of the current column (contacts or coils).
LP_COLS EQU 14
ld_pick:
        and LT_MASK
        ld (lk_cur),a
        ld hl,ld_pick_c
        ld a,(ld_pos)
        cp LD_CPOS
        jr c,.l
        ld hl,ld_pick_q
.l:     ld (lk_list),hl
        ; number of items, preselected item
        ld bc,0                 ; B = count, C = selection
.cnt:   ld a,(hl)
        cp 0xFF
        jr z,.cd
        ld e,a
        ld a,(lk_cur)
        cp e
        jr nz,.cn
        ld c,b
.cn:    inc b
        call lk_next
        jr .cnt
.cd:    ld a,b
        ld (lk_n),a
        ld a,c
        ld (lk_sel),a
        ; window
        ld a,b
        add a,2
        ld d,a
        ld a,24
        sub d
        srl a
        ld b,a
        ld c,(32-LP_COLS)/2
        ld e,LP_COLS
        call win_open
        ; items: icon + label
        ld hl,(lk_list)
        ld a,(win_r)
        inc a
        ld (lk_row),a
.it:    ld a,(hl)
        cp 0xFF
        jr z,.drawn
        push hl
        ld e,a
        ld a,(lk_row)
        ld b,a
        ld a,(win_c)
        inc a
        ld c,a
        ld a,e
        call ld_put_glyphs
        pop hl
        push hl
        inc hl
        inc hl
        ld a,(lk_row)
        ld (pt_row),a
        ld a,(win_c)
        add a,5
        add a,a
        add a,a
        add a,a
        ld (pt_x),a
        call pt_puts
        pop hl
        call lk_next
        ld a,(lk_row)
        inc a
        ld (lk_row),a
        jr .it
.drawn: call lk_inv
.key:   call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jr z,.ok
        cp K_BREAK
        jr z,.cancel
        cp K_EDIT
        jr z,.cancel
        call to_upper           ; shortcut letter
        ld c,a
        ld hl,(lk_list)
        ld b,0
.hk:    ld a,(hl)
        cp 0xFF
        jr z,.key
        inc hl
        ld a,(hl)
        dec hl
        cp c
        jr z,.hkf
        call lk_next
        inc b
        jr .hk
.hkf:   ld a,b
        ld (lk_sel),a
        jr .ok
.up:    call lk_inv
        ld a,(lk_sel)
        or a
        jr nz,.u1
        ld a,(lk_n)
.u1:    dec a
        jr .mv
.down:  call lk_inv
        ld a,(lk_sel)
        inc a
        ld hl,lk_n
        cp (hl)
        jr c,.mv
        xor a
.mv:    ld (lk_sel),a
        call lk_inv
        jr .key
.ok:    ld hl,(lk_list)         ; type of the selected item
        ld a,(lk_sel)
        or a
        jr z,.o2
        ld b,a
.o1:    call lk_next
        djnz .o1
.o2:    ld a,(hl)
        push af
        call win_close
        pop af
        or a
        ret
.cancel:
        call win_close
        scf
        ret

; lk_next: HL = item -> next item ([type][hotkey][label 0])
lk_next:
        inc hl
        inc hl
.l:     ld a,(hl)
        inc hl
        or a
        jr nz,.l
        ret

; lk_inv: inverts the selected item row of the picker
lk_inv: ld a,(win_r)
        inc a
        ld b,a
        ld a,(lk_sel)
        add a,b
        ld b,a
        ld a,(win_c)
        add a,a
        add a,a
        add a,a
        add a,2
        ld c,a
        ld d,LP_COLS*8-4
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; picker items: type, shortcut key, label
ld_pick_c:
        db LT_NO,   'C',"NO contact",0
        db LT_NC,   '/',"NC contact",0
        db LT_P,    'P',"Rising edge",0
        db LT_N,    'N',"Falling edge",0
        db LT_WIRE, '-',"Wire",0
        db LT_VLITEM,'V',"Vertical link",0
        db LT_TON,  'T',"TON timer",0
        db LT_TOF,  'F',"TOF timer",0
        db LT_TP,   'U',"TP pulse",0
        db 0xFF
ld_pick_q:
        db LT_COIL, 'C',"Coil",0
        db LT_NCOIL,'/',"Negated coil",0
        db LT_SET,  'S',"Set coil",0
        db LT_RES,  'R',"Reset coil",0
        db 0xFF

; ---- ld_cmt_text: row ld_r -> NC: ld_cbuf = its comment text; C: no comment
ld_cmt_text:
        ld a,(ld_r)
        ld d,a
        ld e,0
        call ld_find
        ret c
        inc hl
        inc hl
        ld a,(hl)
        cp LT_CMT
        scf
        ret nz
        inc hl
        ld c,(hl)
        ld b,0
        inc hl
        ld de,ld_cbuf
        ld a,c
        or a
        jr z,.e
        ldir
.e:     xor a
        ld (de),a
        ret

; ---- ld_put_cmt: row ld_row <- comment text ld_cbuf (empty: removed)
;      C = out of memory
ld_put_cmt:
        ld a,(ld_row)           ; remove the old record of position 0
        ld d,a
        ld e,0
        xor a
        ld bc,0
        call ld_put
        ld hl,ld_cbuf
        call strlen
        or a
        ret z
        ld (lp_rec+3),a
        add a,4
        ld (lc_len),a
        call ld_hdr
        ret c
        ld a,(ld_row)
        ld d,a
        ld e,0
        call ld_find
        call il_offset
        ld a,(lc_len)
        ld c,a
        ld b,0
        ld a,(cur_pou)
        call pou_insert
        ret c
        ld a,(ld_row)
        ld (hl),a
        inc hl
        ld (hl),0
        inc hl
        ld (hl),LT_CMT
        inc hl
        ld a,(lp_rec+3)
        ld (hl),a
        inc hl
        ex de,hl
        ld hl,ld_cbuf
        ld c,a
        ld b,0
        ldir
        ld a,(cur_pou)          ; the row count covers this row
        call pou_body
        ld a,(ld_row)
        inc a
        cp (hl)
        jr c,.ok
        ld (hl),a
.ok:    or a                    ; NC: stored
        ret

; ---- ld_cursor: XORs the symbol cells of the cursor position
;      (comment row: a 1 px text cursor in front of "//")
ld_cursor:
        ld a,(ld_row)
        ld (ld_r),a
        call ld_cmt_text
        push af                 ; C = not a comment row
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
        pop af
        jr c,.elem
        ld c,10
        ld d,1
        jr .draw
.elem:  ld a,(ld_pos)
        ld c,a
        add a,a
        add a,c
        inc a
        add a,a
        add a,a
        add a,a
        ld c,a
        ld d,24
.draw:  ld hl,0x0008
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
        cp LT_CMT
        jr nz,.nc
        dec hl
        dec hl
        jr .n
.nc:    ld (ld_t),a
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
        call ld_isbox
        ld a,b
        jr nz,.op
        ld a,AR_FBM+0x20        ; timer box: state = Q
.op:    ld de,0
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
        jp .l

; ============================================================
; editor
; ============================================================
ld_editor:
        call screen_begin
        ld a,(cur_pou)
        ld hl,ld_pou
        cp (hl)
        jp z,.same
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
        cp K_LEFT               ; comment row: LEFT, RIGHT, DELETE and
        jr z,.ck                ; characters edit the comment in place
        cp K_RIGHT
        jr z,.ck
        cp K_DEL
        jr z,.ck
        cp 32
        jr c,.nck
        cp 128
        jr nc,.nck
.ck:    push af
        ld a,(ld_row)
        ld (ld_r),a
        call ld_cmt_text        ; NC: ld_cbuf = the comment
        jr c,.ckn
        pop af
        ld (in_pend),a
        jp .cedit
.ckn:   pop af
.nck:   cp K_LEFT
        jp z,.left
        cp K_RIGHT
        jp z,.right
        cp K_UP
        jp z,.up
        cp K_DOWN
        jp z,.down
        cp K_HOME
        jp z,.home
        cp K_END
        jp z,.end
        cp K_PGUP
        jp z,.pgup
        cp K_PGDN
        jp z,.pgdn
        cp K_SSENTER
        jp z,.nrow
        cp K_ENTER
        jp z,.enter
        cp K_DEL
        jp z,.del
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        call to_upper           ; shortcut keys of the picker items
        cp 'T'                  ; T on a timer box: only its PT
        jr nz,.nt
        push af
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        ld (ld_newt),a          ; same type (keeps the link bit, see .pl3)
        call ld_isbox
        jr nz,.ntb
        pop af
        ld a,(ld_newt)
        and LT_MASK
        ld (ld_newt),a
        call ld_set_ar          ; same instance
        ld hl,(ld_gpt)
        ld (ld_ppt),hl
        call ld_ask_pt
        jp c,.redraw
        jp .pl3
.ntb:   pop af
.nt:    ld b,a
        ld hl,ld_pick_c
        ld a,(ld_pos)
        cp LD_CPOS
        jr c,.kl
        ld hl,ld_pick_q
.kl:    ld a,(hl)
        cp 0xFF
        jp z,.cur
        inc hl
        ld a,(hl)
        dec hl
        cp b
        jr z,.kf
        call lk_next
        jr .kl
.kf:    ld a,(hl)
        cp LT_VLITEM
        jp z,.vlink
        cp LT_NC                ; "//" at the start of an empty row: comment
        jp nz,.place
        ld a,(ld_pos)
        or a
        ld a,LT_NC
        jp nz,.place
        call ld_row_empty
        ld a,LT_NC
        jp nz,.place
        call kb_wait
        cp '/'
        jr z,.cmt
        ld (ld_first),a         ; another key: NC contact, key starts the operand
        ld a,LT_NC
        jp .place
.cmt:   xor a
        ld (ld_cbuf),a
.cedit: ld a,(ld_row)           ; edit the comment in place
        ld b,a
        ld a,(ld_top)
        ld c,a
        ld a,b
        sub c
        add a,a
        inc a
        ld b,a
        ld a,(ld_vbase)
        add a,b
        ld b,a
        push bc
        ld c,1
        ld de,0x1E00+ATTR_LDCMT
        call scr_fill_attr
        pop bc
        ld a,b                  ; "// " drawn as in the row, text typed after it
        ld (pt_row),a
        ld a,12
        ld (pt_x),a
        ld hl,txt_ld_sl
        call pt_puts
        ld a,(pt_x)
        ld c,a
        ld hl,ld_cbuf
        ld de,0x2406            ; max 36 chars, no underline, first letter capital
        call ui_input
        jp c,.full
        call ld_put_cmt
        jp c,.redraw
        ld a,(ld_cbuf)          ; comment entered: start of the next row
        or a
        jp z,.redraw
        ld a,(ld_row)
        inc a
        cp LD_MAXROWS
        jp nc,.redraw
        ld (ld_row),a
        xor a
        ld (ld_pos),a
        call ld_fix_top
        jp .redraw
.left:  ld a,(ld_pos)
        or a
        jp z,.cur
        dec a
        ld (ld_pos),a
        jp .cur
.right: ld a,(ld_pos)
        cp LD_CPOS
        jp z,.cur
        inc a
        ld (ld_pos),a
        jp .cur
.nrow:  call ld_nrows           ; SS+ENTER: start of the next row
        ld b,a                  ; (max. the row after the last)
        ld a,(ld_row)
        cp b
        jr nc,.home
        inc a
        cp LD_MAXROWS
        jr nc,.home
        ld (ld_row),a
        call ld_fix_top
        jr nz,.nfull
        xor a
        ld (ld_pos),a
        jp .cur
.nfull: xor a
        ld (ld_pos),a
        jp .full
.home:  xor a                   ; first position
        jr .setp
.end:   ld a,LD_CPOS            ; coil position
.setp:  ld (ld_pos),a
        jp .cur
.pgup:  ld a,(ld_vn)            ; one screen up
        dec a
        ld b,a
        ld a,(ld_row)
        sub b
        jr nc,.mv
        xor a
        jr .mv
.pgdn:  ld a,(ld_vn)            ; one screen down (max. the row after the last)
        dec a
        ld b,a
        ld a,(ld_row)
        add a,b
        ld c,a
        call ld_nrows
        cp c
        jr c,.mv
        ld a,c
        jr .mv
.up:    ld a,(ld_row)
        or a
        jp z,.cur
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
        push af                 ; (ld_set_ar destroys A = old type)
        call ld_set_ar
        pop af
        ld hl,50                ; default PT T#1s, kept from an existing box
        ld e,0
        call ld_isbox
        jr nz,.dpt
        ld hl,(ld_gpt)
        inc e
.dpt:   ld (ld_ppt),hl
        ld a,(ld_newt)          ; box <-> contact/coil: no operand to keep
        call ld_isbox
        ld a,0
        jr nz,.nb
        inc a
.nb:    cp e
        jp z,.kept
        xor a
        ld (ld_ar),a
.kept:
        ld a,(ld_newt)
        call ld_ask_operand
        jp c,.redraw
        call ld_set_ar
        ld a,(ld_newt)
        call ld_isbox
        jr nz,.pl3
        call ld_ask_pt          ; timer box: preset time
        jp c,.redraw
        jr .pl3
.pl2:   ld bc,0
        call ld_set_ar
.pl3:   ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        ld (ld_oldt),a
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
        ld a,(ld_oldt)          ; new element on an empty position:
        and LT_MASK             ; the cursor moves on behind it
        jr nz,.redraw
        ld a,(ld_pos)
        cp LD_CPOS
        jr nc,.redraw
        inc a
        ld (ld_pos),a
.redraw:
        call status_right
        jp .full

        ; ---- ENTER: operand of the current element
.enter: ld a,(ld_row)              ; comment row: edit it
        ld (ld_r),a
        call ld_cmt_text
        jp nc,.cedit
        ld a,(ld_row)              ; element picker
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        call ld_pick
        jp c,.cur
        cp LT_VLITEM
        jp z,.vlink
        jp .place

        ; ---- DELETE: clear the position (the link stays)
.del:   ld a,(ld_row)           ; comment row: remove the comment
        ld (ld_r),a
        call ld_cmt_text
        jr c,.dl
        xor a
        ld (ld_cbuf),a
        call ld_put_cmt
        jp .redraw
.dl:    ld a,(ld_row)
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
        jp .redraw
.mdel:  ld a,(ld_row)
        ld d,a
        call ld_del_row
        jp .redraw


; ---- ld_row_empty: Z if row ld_row has no records
ld_row_empty:
        ld a,(ld_row)
        ld d,a
        ld e,0
.l:     call ld_get
        or a
        ret nz
        inc e
        ld a,e
        cp LD_CPOS+1
        jr c,.l
        xor a
        ret

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
        ; initial text = current operand (or the first key typed)
        ld de,ld_obuf
        xor a
        ld (de),a
        ld a,(ld_first)
        or a
        jr z,.nf
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld (ld_first),a
        jr .ask
.nf:    ld a,(ld_ar)
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
        ld a,(ld_kind)          ; timer box: an instance of the same FB type
        call ld_isbox
        jr nz,.nbox
        ld a,b
        cp AR_FBI
        jr nz,.bad
        ld a,(ld_kind)
        ld e,FBT_TON
        cp LT_TON
        jr z,.bt
        ld e,FBT_TOF
        cp LT_TOF
        jr z,.bt
        ld e,FBT_TP
.bt:    ld a,c
        rrca
        rrca
        and 0x3F
        cp e
        jr nz,.bad
        or a
        ret
.nbox:  ld a,b
        and AR_MASK
        cp AR_FBM
        jr z,.fbm
        cp AR_Q
        jr z,.ok
        cp AR_M
        jr z,.ok
        cp AR_SX
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

; ---- ld_ask_pt: popup for the preset time of a timer box (ld_ppt)
;      C = cancelled
ld_ask_pt:
        ld hl,(ld_ppt)          ; initial text: current PT
        ld de,ld_obuf
        ld a,AR_KT
        ld bc,0
        call op_format
.ask:   ld hl,txt_ld_ptq
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
        cp AR_KT
        jr z,.ok
        cp AR_K16
        jr nz,.bad
.ok:    ld (ld_ppt),de
        or a
        ret
.bad:   ld hl,err_ld_pt
        call ui_error
        jr .ask

; ---- ld_info: status bar: symbol name and comment of the current element
ld_info:
        ld hl,0
        ld (st_left),hl
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        ld de,ld_infob
        ld (ld_infop),de
        push af
        push bc
        call ld_isbox
        jr nz,.nbx
        call ld_set_ar          ; "TON1 PT=T#4s  " in front of the comment
        ld hl,ld_ar
        call il_fmt_one
        ld hl,txt_ld_pt
        call put_str
        ld hl,(ld_gpt)
        ld a,AR_KT
        ld bc,0
        call op_format
        ld a,' '
        ld (de),a
        inc de
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld (ld_infop),de
        ld hl,ld_infob
        ld (st_left),hl
.nbx:   pop bc
        pop af
        and LT_MASK
        cp LT_NO
        jr c,.show
        cp LT_CMT
        jr z,.show
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
        ld de,(ld_infop)
        ld a,ST_SYM             ; symbol name in dark blue
        ld (de),a
        inc de
.n:     ld a,(hl)
        inc hl
        or a
        jr z,.ne
        ld (de),a
        inc de
        jr .n
.ne:    ld a,ST_SYME
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
err_ld_pt:  db "Invalid time",0
txt_ld_ptq: db "PT (time, e.g. T#4s):",0," ",0," ",0,0
txt_ld_pt:  db " PT=",0
txt_ld_sl:  db "// ",0

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
ld_oldt:  db 0              ; element at the position before placing
ld_kind:  db 0
ld_aw:    db 0
ld_lrow:  db 0
ld_srow:  db 0
lr_row:   db 0
lp_rec:   ds 7
ld_infop: dw 0
ld_first: db 0              ; first key of an operand typed after '/'
lc_len:   db 0
ld_cbuf:  ds 40
ld_lbl:   ds 16
lg_row:   dw 0              ; ld_put_glyphs: cell, row
lk_cur:   db 0
lk_list:  dw 0
lk_n:     db 0
lk_sel:   db 0
lk_row:   db 0
ld_obuf:  ds 14
ld_infob: ds 44
