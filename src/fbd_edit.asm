; ============================================================
; fbd_edit.asm - Function Block Diagram editor (bank BANK_FBD)
; ============================================================
; Same grid, keys and record format as the LD editor: positions 0-8
; hold inputs, wires and blocks, position 9 the outputs. A grid row is
; drawn as two character rows (label row, signal row). A block at
; (r, p) with h inputs covers the rows r..r+h-1 at position p: input k
; comes from the left on row r+k, the output leaves on row r.
; The storage, operand / PT popups and comment routines of the LD
; editor are used through BCALL (their variables are in shared.asm).
; ============================================================

ATTR_FBON EQU ATTR_ON        ; TRUE (as in LD / IL)

; ---- fb_editor: edits the FBD POU cur_pou, returns a menu command
fb_editor:
        call screen_begin
        ld a,(cur_pou)
        ld hl,fb_pou
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
        call fb_fix_top
.full:  call fb_draw_view
.cur:   call fb_cursor
        call fb_info
.loop:  call kb_wait
        push af
        call fb_cursor          ; cursor off
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
        call fb_cmt_text        ; NC: ld_cbuf = the comment
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
        call to_upper
        cp '/'                  ; "//" at the start of an empty row: comment
        jr z,.slash
        cp 'T'                  ; T on a timer block: only its PT
        jr nz,.hot
.tkey:  call fb_pt_cell         ; (on its PT input: the timer)
        call nc,fb_to_timer
        call fb_cur_get
        call ld_isbox
        jr nz,.hott
        ld a,b                  ; same instance
        ld (ld_ar),a
        ld a,c
        ld (ld_ar+1),a
        ld a,(fb_t)
        ld (fb_newt),a
        ld hl,(ld_gpt)
        ld (ld_ppt),hl
        BCALL ld_ask_pt
        jp c,.redraw
        jp .put
.hott:  ld a,'T'
.hot:   ld (fb_key),a           ; shortcut key of a picker item
        call fb_pt_cell         ; (not on the PT input of a timer)
        jp nc,.cur
        ld a,(fb_key)
        ld b,a
        call fb_list
.kl:    ld a,(hl)
        cp 0xFF
        jp z,.cur
        inc hl
        ld a,(hl)
        dec hl
        cp b
        jr z,.kf
        call fk_next
        jr .kl
.kf:    ld a,(hl)
        jp .place
.slash: ld a,(ld_pos)
        or a
        jp nz,.cur
        call fb_row_empty
        jp nz,.cur
        call kb_wait
        cp '/'
        jp nz,.cur
        xor a
        ld (ld_cbuf),a
.cedit: ld a,(ld_row)           ; edit the comment in place
        call fb_scr_row
        inc a                   ; signal row
        ld b,a
        push bc
        ld c,1
        ld de,0x1E00+ATTR_LDCMT
        call scr_fill_attr
        pop bc
        ld a,b
        ld (pt_row),a
        ld a,8                  ; comments start at the element column
        ld (pt_x),a
        ld hl,txt_fb_sl
        call pt_puts
        ld a,(pt_x)
        ld c,a
        ld hl,ld_cbuf
        ld de,0x2406            ; max 36 chars, no underline, first letter capital
        call ui_input
        jp c,.full
        BCALL ld_put_cmt
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
        call fb_fix_top
        jp .redraw
.left:  ld a,(ld_pos)           ; (cells inside / behind a block skipped)
.lf:    or a
        jp z,.cur
        dec a
        ld e,a
        push af
        call fb_skip_e
        pop bc
        ld a,b
        jr c,.lf
        ld (ld_pos),a
        jp .cur
.right: ld a,(ld_pos)
.rt:    cp LD_CPOS
        jp z,.cur
        inc a
        ld e,a
        push af
        call fb_skip_e
        pop bc
        ld a,b
        jr c,.rt
        ld (ld_pos),a
        jp .cur
.nrow:  call fb_nrows           ; SS+ENTER: start of the next row
        ld b,a
        ld a,(ld_row)
        cp b
        jr nc,.home
        inc a
        cp LD_MAXROWS
        jr nc,.home
        ld (ld_row),a
        xor a
        ld (ld_pos),a
        call fb_fix_top
        jp nz,.full
        jp .cur
.home:  xor a
        jr .setp
.end:   ld a,LD_CPOS
.setp:  ld (ld_pos),a
        call fb_snap
        jp .cur
.pgup:  ld a,(ld_vn)
        dec a
        ld b,a
        ld a,(ld_row)
        sub b
        jr nc,.mv
        xor a
        jr .mv
.pgdn:  ld a,(ld_vn)
        dec a
        ld b,a
        ld a,(ld_row)
        add a,b
        ld c,a
        call fb_nrows
        cp c
        jr c,.mv
        ld a,c
        jr .mv
.up:    ld a,(ld_row)
        or a
        jp z,.cur
        dec a
        jr .mv
.down:  call fb_nrows
        ld b,a
        ld a,(ld_row)
        cp b
        jp nc,.cur
        inc a
        cp LD_MAXROWS
        jp nc,.cur
.mv:    ld (ld_row),a
        call fb_snap
        call fb_fix_top
        jp nz,.full
        jp .cur

        ; ---- ENTER: picker for the current position
.enter: ld a,(ld_row)           ; comment row: edit it
        call fb_cmt_text
        jp nc,.cedit
        call fb_pt_cell         ; PT input of a timer: its PT
        jp nc,.tkey
        call fb_to_owner        ; inside a block: the block itself
        call fb_cur_get
        ld a,(fb_t)
        call fb_pick
        jp c,.cur

        ; ---- place an element (A = type incl. FT_NEG)
.place: ld (fb_newt),a
        call fb_to_owner
        ld a,(fb_newt)          ; output / wire: a signal must come from the left
        and FT_MASK
        cp FT_OUT
        jr z,.src
        cp FT_WIRE
        jr nz,.srcok
.src:   call fb_left_sig
        jr nc,.srcok
        ld hl,err_fb_src
        call ui_error
        jp .redraw
.srcok:
        call fb_cur_get         ; old element: fb_t, B/C operand, ld_gpt
        ld hl,50                ; default PT T#1s, kept from a timer block
        ld a,(fb_t)
        call ld_isbox
        jr nz,.dpt
        ld hl,(ld_gpt)
.dpt:   ld (ld_ppt),hl
        ld a,(fb_newt)
        call fb_kind            ; A = kind of operand, Z = none
        jr z,.noop
        ld (fb_kind_v),a
        ld a,(fb_t)             ; operand kept when the kind stays the same
        call fb_kind
        ld hl,fb_kind_v
        cp (hl)
        jr z,.keep
        ld bc,0
.keep:  ld a,b
        ld (ld_ar),a
        ld a,c
        ld (ld_ar+1),a
        ld a,(fb_kind_v)
        BCALL ld_ask_operand
        jp c,.redraw
        ld a,b
        ld (ld_ar),a
        ld a,c
        ld (ld_ar+1),a
        ld a,(fb_newt)
        call ld_isbox
        jr nz,.room
        BCALL ld_ask_pt         ; timer: preset time
        jp c,.redraw
        jr .room
.noop:  ld a,(fb_newt)          ; logic blocks: number of inputs
        and FT_MASK
        ld b,1
        cp FT_NOT
        jr z,.nin
        ld b,0
        cp FT_WIRE
        jr z,.nin
        call fb_ask_inputs
        jp c,.redraw
        ld b,a
.nin:   ld a,b
        ld (ld_ar),a
        xor a
        ld (ld_ar+1),a
.room:  ld a,(fb_newt)          ; a block needs free rows below it
        ld b,a
        ld a,(ld_ar)
        ld c,a
        ld a,b
        call fb_height_t
        or a
        jr z,.put
        ld (fb_hh),a
        xor a
        ld (fb_ins),a
        call fb_cur_get         ; block on an input: the input feeds its
        and FT_MASK             ; first input (the network moves right)
        cp FT_IN
        jr nz,.rows
        call fb_ins_col
        jr c,.noroom
        ld a,1
        ld (fb_ins),a
.rows:  ld a,(fb_hh)
        call fb_make_rows       ; free rows below (rows inserted if needed)
        jr c,.noroom
        ld a,(fb_newt)          ; timer: its PT input needs the cell on the
        call ld_isbox           ; left of the PT row
        jr nz,.put
        ld a,(ld_pos)
        or a
        jr z,.noroom
        ld a,(ld_row)
        inc a
        ld d,a
        ld a,(ld_pos)
        dec a
        ld e,a
        call ld_get
        and FT_MASK
        jr z,.put
.noroom:
        ld hl,err_fb_room
        call ui_error
        jp .redraw
.put:   call fb_cur_get         ; old element (cursor move, undo)
        ld a,(fb_t)
        ld (fb_oldt),a
        ld a,b
        ld (fb_olda),a
        ld a,c
        ld (fb_oldc),a
        ld hl,(ld_gpt)
        ld (fb_oldpt),hl
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        ld a,(ld_ar)
        ld b,a
        ld a,(ld_ar+1)
        ld c,a
        ld a,(fb_newt)
        BCALL ld_put
        jp c,.redraw
        call fb_rows_fit        ; the row count covers the whole block
        call fb_make_room       ; new inputs without a free cell: shift
        jp nc,.redraw           ; (NC: shifted, cursor on the new input)
        ld a,(fm_err)
        or a
        jr nz,.undo             ; no room: the old element comes back
        call fb_autowire
        ld a,(fb_ins)           ; inserted on an input: cursor on the
        or a                    ; free cell of the second input
        jr z,.nins
        call fb_cur_get
        ld c,b
        ld b,a
        call ld_isbox
        jr z,.nins
        ld a,b
        call fb_height_t
        cp 2
        jr c,.nins
        ld hl,ld_row
        inc (hl)
        ld hl,ld_pos
        dec (hl)
        jr .redraw
.undo:  ld hl,(fb_oldpt)
        ld (ld_ppt),hl
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        ld a,(fb_olda)
        ld b,a
        ld a,(fb_oldc)
        ld c,a
        ld a,(fb_oldt)
        BCALL ld_put
        jr .redraw
.nins:
        ld a,(fb_oldt)          ; new element on an empty position:
        and FT_MASK             ; the cursor moves on behind it
        jr nz,.redraw
        ld a,(ld_pos)
        cp LD_CPOS
        jr nc,.redraw
        inc a
        ld e,a                  ; (not into a block)
        push af
        call fb_skip_e
        pop bc
        jr c,.redraw
        ld a,b
        ld (ld_pos),a
.redraw:
        call status_right
        jp .full

        ; ---- DELETE: the element (inside a block: the block)
.del:   call fb_pt_cell         ; (the PT input stays)
        jp nc,.cur
        call fb_to_owner
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        xor a
        ld bc,0
        BCALL ld_put
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
        BCALL ld_ins_row
        jp .redraw
.mdel:  ld a,(ld_row)
        ld d,a
        BCALL ld_del_row
        jp .redraw

; ---- fb_pt_cell: NC if the cursor is on the PT input of a timer (the cell
;      left of its PT row): fpt_row / fpt_pos = the timer
fb_pt_cell:
        ld a,(ld_row)
        or a
        scf
        ret z
        ld a,(ld_pos)
        cp LD_CPOS-1
        ccf
        ret c
        ld a,(ld_row)
        dec a
        ld (fpt_row),a
        ld d,a
        ld a,(ld_pos)
        inc a
        ld (fpt_pos),a
        ld e,a
        call ld_get
        call ld_isbox
        scf
        ret nz
        or a
        ret

; fb_to_timer: cursor -> the timer of the PT input (fpt_row / fpt_pos)
fb_to_timer:
        ld a,(fpt_row)
        ld (ld_row),a
        ld a,(fpt_pos)
        ld (ld_pos),a
        ret

; ---- fb_skip_e: E = position in row ld_row -> C if the cursor must not
;      stand there: inside a block, or an empty cell behind a lower block row
;      (only empty cells between it and the block: no signal reaches it)
fb_skip_e:
        ld a,(ld_row)
        ld d,a
.l:     push de
        call fb_owner
        pop de
        ccf
        ret c                   ; inside a block
        ld a,e
        or a
        ret z                   ; left edge (NC)
        push de
        call ld_get
        pop de
        and FT_MASK
        ret nz                  ; an element (NC)
        dec e                   ; empty: look further left
        jr .l

; fb_snap: the cursor on a cell it must not stand on -> moved to the left
fb_snap:
        ld a,(ld_pos)
.l:     ld e,a
        push af
        call fb_skip_e
        pop bc
        ret nc
        ld a,b
        or a
        ret z
        dec a
        ld (ld_pos),a
        jr .l

; ---- fb_left_sig: NC if a signal reaches the cursor from the left: the next
;      element on the left (over empty cells, not through a block) exists
fb_left_sig:
        ld a,(ld_pos)
.l:     or a
        scf
        ret z                   ; left edge: no source
        dec a
        ld (fb_aw),a
        ld a,(ld_row)
        ld d,a
        ld a,(fb_aw)
        ld e,a
        call fb_owner
        ccf
        ret c                   ; inside a block: its lower rows have no output
        call ld_get
        and FT_MASK
        jr nz,.f
        ld a,(fb_aw)
        jr .l
.f:     cp FT_CMT
        scf
        ret z
        or a
        ret

; ---- fb_list: HL = picker list of the cursor column (keeps B)
fb_list:
        ld hl,fb_pick_l
        ld a,(ld_pos)
        cp LD_CPOS
        ret c
        ld hl,fb_pick_o
        ret

; ---- fb_cur_get: element at the cursor -> A = fb_t = type, B = area, C = index
fb_cur_get:
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        ld (fb_t),a
        ret

; ---- fb_kind: A = type -> A = operand kind for ld_ask_operand, Z = none
fb_kind:
        ld e,a
        and FT_MASK
        cp FT_IN
        ld a,LT_NO              ; any BOOL
        jr z,.k
        ld a,e
        and FT_MASK
        cp FT_OUT
        ld a,LT_COIL            ; writable BOOL
        jr z,.k
        ld a,e
        and FT_MASK
        ld d,LK_FB+FBT_TON
        cp FT_TON
        jr z,.fb
        ld d,LK_FB+FBT_TOF
        cp FT_TOF
        jr z,.fb
        ld d,LK_FB+FBT_TP
        cp FT_TP
        jr z,.fb
        ld d,LK_FB+FBT_SR
        cp FT_SR
        jr z,.fb
        ld d,LK_FB+FBT_RS
        cp FT_RS
        jr z,.fb
        ld d,LK_FB+FBT_RTRIG
        cp FT_RTRIG
        jr z,.fb
        ld d,LK_FB+FBT_FTRIG
        cp FT_FTRIG
        jr z,.fb
        xor a                   ; Z: no operand
        ret
.fb:    ld a,d
.k:     or a                    ; NZ
        ret

; ---- fb_height_t: A = type, C = area -> A = rows of the block (0 = none)
fb_height_t:
        and FT_MASK
        cp FT_AND
        jr z,.lg
        cp FT_OR
        jr z,.lg
        cp FT_XOR
        jr z,.lg
        cp FT_SR
        jr z,.two
        cp FT_RS
        jr z,.two
        cp FT_NOT
        jr z,.one
        cp FT_RTRIG
        jr z,.one
        cp FT_FTRIG
        jr z,.one
        call ld_isbox           ; timers: IN row + PT row
        jr z,.two
        xor a
        ret
.lg:    ld a,c
        ret
.two:   ld a,2
        ret
.one:   ld a,1
        ret

; ---- fb_owner: D = row, E = pos -> NC: A = row of the block covering this
;      cell from above; C: not covered (keeps DE)
fb_owner:
        ld b,1
.l:     ld a,d
        sub b
        jr c,.no
        push bc
        push de
        ld d,a
        call ld_get
        ld c,b                  ; C = area
        call fb_height_t
        pop de
        pop bc
        cp b
        jr z,.n
        jr c,.n
        ld a,d                  ; height > distance: covered
        sub b
        or a
        ret
.n:     inc b
        ld a,b
        cp FT_MAXIN
        jr c,.l
.no:    scf
        ret

; fb_to_owner: cursor inside a block -> moved to the block row
fb_to_owner:
        ld a,(ld_row)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call fb_owner
        ret c
        ld (ld_row),a
        ret

; ---- fb_make_room: after placing a logic block at the cursor: if one of its
;      new input rows has no free cell on the left (another block there, or
;      position 0), the block and everything right of it in its rows moves
;      one position to the right; the old inputs get a wire in the freed
;      column and the cursor goes to the free cell of the first new input.
;      NC = shifted, C = nothing to do (or not possible: message shown)
fb_make_room:
        xor a
        ld (fm_err),a
        call fb_cur_get
        and FT_MASK
        cp FT_AND
        jr z,.lg
        cp FT_OR
        jr z,.lg
        cp FT_XOR
        scf
        ret nz
.lg:    ld a,b                  ; new number of inputs
        ld (fm_h),a
        ld a,(fb_oldt)          ; inputs that already had a connection
        and FT_MASK
        ld c,1
        cp FT_AND
        jr z,.old
        cp FT_OR
        jr z,.old
        cp FT_XOR
        jr nz,.o1
.old:   ld a,(fb_olda)
        ld c,a
.o1:    ld a,c
        ld (fm_h0),a
        ld hl,fm_h              ; first new input row .. last
        cp (hl)
        ccf
        ret c                   ; no new inputs
        ld a,(ld_pos)
        or a
        jr z,.need              ; position 0: no cell on the left
        ld a,(fm_h0)
        ld b,a
.chk:   ld a,(ld_row)           ; new input row: covered cell on the left?
        add a,b
        ld d,a
        ld a,(ld_pos)
        dec a
        ld e,a
        push bc
        call fb_owner
        pop bc
        jr nc,.need
        inc b
        ld a,(fm_h)
        cp b
        jr nz,.chk
        scf                     ; every new input has a free cell
        ret
.need:  ld a,(ld_pos)            ; the network moves right from the block
        cp LD_CPOS-1
        jr nc,.err
        ld (fm_p),a
        call fb_net_shift
        jr nc,.ok
.err:   ld a,1
        ld (fm_err),a
        ld hl,err_fb_room
        call ui_error
        scf
        ret
.ok:    ld a,(ld_row)           ; cursor: first new input, free cell
        ld hl,fm_h0
        add a,(hl)
        ld (ld_row),a
        or a                    ; NC
        ret

; ---- fb_shift_cols: rows fm_r0..fm_r1: positions fm_p..7 move one to the
;      right (fm_p <= 7, position 8 must be free)
fb_shift_cols:
        ld a,LD_CPOS-2
.qcol:  ld (fm_q),a
        ld a,(fm_r0)
        ld (fm_rr),a
.qrow:  ld a,(fm_rr)
        ld d,a
        ld a,(fm_q)
        ld e,a
        call ld_get
        or a
        jr z,.qn
        ld (fm_t),a
        ld hl,(ld_gpt)
        ld (ld_ppt),hl
        ld a,(fm_rr)
        ld d,a
        ld a,(fm_q)
        inc a
        ld e,a
        ld a,(fm_t)
        BCALL ld_put            ; (B, C passed through)
        ld a,(fm_rr)
        ld d,a
        ld a,(fm_q)
        ld e,a
        xor a
        ld bc,0
        BCALL ld_put
.qn:    ld hl,fm_rr
        ld a,(fm_r1)
        cp (hl)
        jr z,.qe
        inc (hl)
        jr .qrow
.qe:    ld a,(fm_p)
        ld b,a
        ld a,(fm_q)
        cp b
        ret z
        dec a
        jr .qcol

; ---- fb_ins_col: a block is placed on an input at (ld_row, p): the network
;      of the row (rows up to empty / comment rows) moves one position to the
;      right from p+1, the freed column gets wires where a signal goes on,
;      and the cursor goes to p+1, so the input feeds the first input of the
;      block. C = no room (position 8 used, or p >= 7)
fb_ins_col:
        ld a,(ld_pos)
        cp LD_CPOS-2
        ccf
        ret c
        inc a
        ld (fm_p),a
        call fb_net_shift
        ret c
        ld a,(fm_p)
        ld (ld_pos),a
        ret

; fb_net_shift: the network of row ld_row moves one position to the right
;      from fm_p (<= 7); the freed column gets wires where an element on the
;      left feeds something on the right. C = position 8 used
fb_net_shift:
        ld a,(ld_row)           ; first row of the network
.up:    ld (fm_r0),a
        or a
        jr z,.dn0
        dec a
        push af
        call fb_net_row
        pop bc                  ; B = row (flags kept)
        ld a,b
        jr c,.up
.dn0:   ld a,(ld_row)           ; last row
.dn:    ld (fm_r1),a
        inc a
        cp LD_MAXROWS
        jr nc,.chk
        push af
        call fb_net_row
        pop bc
        ld a,b
        jr c,.dn
.chk:   ld a,(fm_r0)            ; position 8 must be free
.c8:    ld (fm_rr),a
        ld d,a
        ld e,LD_CPOS-1
        call ld_get
        and FT_MASK
        scf
        ret nz
        ld a,(fm_rr)
        ld hl,fm_r1
        cp (hl)
        jr z,.sh
        inc a
        jr .c8
.sh:    call fb_shift_cols
        ld a,(fm_p)
        or a
        ret z                   ; (position 0: nothing on the left)
        ld a,(fm_r0)            ; wires in the freed column: an element on
.w:     ld (fm_rr),a            ; the left and something on the right
        ld d,a
        ld a,(fm_p)
        dec a
        ld e,a
        call ld_get
        and FT_MASK
        jr z,.wn
        ld a,(fm_rr)
        ld d,a
        ld a,(fm_p)
        inc a
        ld e,a
        call ld_get
        or a
        jr nz,.wy
        call fb_owner           ; (a lower input of a block)
        jr c,.wn
.wy:    ld a,(fm_rr)
        ld d,a
        ld a,(fm_p)
        ld e,a
        ld a,FT_WIRE
        ld bc,0
        BCALL ld_put
.wn:    ld a,(fm_rr)
        ld hl,fm_r1
        cp (hl)
        jr z,.done
        inc a
        jr .w
.done:  or a
        ret

; fb_net_row: A = row -> C if it belongs to a network (an element that is
;      not a comment, or a cell covered by a block)
fb_net_row:
        ld (fi_x),a
        call fb_cmt_text
        ret nc                  ; comment row
        ld a,(fi_x)
        ld d,a
        ld e,0
.l:     call ld_get
        or a
        scf
        ret nz
        call fb_owner
        ccf
        ret c
        inc e
        ld a,e
        cp LD_CPOS+1
        jr c,.l
        or a
        ret

; ---- fb_make_rows: block of A rows at the cursor: every row below it must be
;      free at its position (no element, no comment row, not inside another
;      block); a row that is not gets an empty row inserted in front of it
;      (the rows below move down). C = not possible (grid full, or the new row
;      would split another block)
fb_make_rows:
        ld (fr_h),a
        ld a,1
        ld (fr_k),a
.l:     ld a,(fr_k)
        ld hl,fr_h
        cp (hl)
        jr nc,.ok
        ld a,(ld_row)
        ld hl,fr_k
        add a,(hl)
        ld (fr_x),a
        cp LD_MAXROWS
        ccf
        ret c
        call .free
        jr nc,.nx
        call .cross
        ret c
        ld a,(fr_x)
        ld d,a
        BCALL ld_ins_row
        call .free              ; (nothing inserted: grid full)
        ret c
.nx:    ld hl,fr_k
        inc (hl)
        jr .l
.ok:    or a
        ret
; NC if row fr_x is free at the cursor position
.free:  ld a,(fr_x)
        call fb_cmt_text
        ccf
        ret c                   ; comment row
        ld a,(fr_x)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call ld_get
        and FT_MASK
        scf
        ret nz
        ld a,(fr_x)
        ld d,a
        ld a,(ld_pos)
        ld e,a
        call fb_owner
        jr c,.f                 ; not covered
        ld hl,ld_row            ; covered by this block itself: free
        cp (hl)
        scf
        ret nz
.f:     or a
        ret
; C if another block spans across row fr_x (an inserted row would split it)
.cross: ld e,0
.cl:    ld a,(fr_x)
        ld d,a
        push de
        call fb_owner
        pop de
        jr c,.cn
        ld hl,ld_row            ; (this block itself)
        cp (hl)
        jr nz,.cy
        ld a,(ld_pos)
        cp e
        jr nz,.cy
.cn:    inc e
        ld a,e
        cp LD_CPOS
        jr c,.cl
        or a
        ret
.cy:    scf
        ret

; ---- fb_rows_fit: the row count covers the block at the cursor
fb_rows_fit:
        call fb_cur_get
        ld c,b
        call fb_height_t
        or a
        ret z
        ld b,a
        ld a,(ld_row)
        add a,b
        ld b,a                  ; rows needed
        ld a,(cur_pou)
        call pou_body
        ld a,(hl)
        cp b
        ret nc
        ld (hl),b
        ret

; ---- fb_autowire: empty positions left of a new block / output become
;      wires (up to the previous element, not into a block above)
fb_autowire:
        call fb_cur_get
        and FT_MASK
        cp FT_IN
        ret z
        cp FT_WIRE
        ret z
        ld a,(ld_pos)
.l:     or a
        ret z
        dec a
        ld (fb_aw),a
        ld a,(ld_row)
        ld d,a
        ld a,(fb_aw)
        ld e,a
        call ld_get
        and FT_MASK
        ret nz                  ; previous element reached
        ld a,(ld_row)
        ld d,a
        ld a,(fb_aw)
        ld e,a
        call fb_owner
        ret nc                  ; inside a block
        ld a,(ld_row)
        ld d,a
        ld a,(fb_aw)
        ld e,a
        ld a,FT_WIRE
        ld bc,0
        BCALL ld_put
        ret c
        ld a,(fb_aw)
        jr .l

; ---- fb_row_empty: Z if row ld_row has no records
fb_row_empty:
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
        ld a,(ld_row)           ; and is not inside a block
        ld d,a
        ld e,0
        call fb_owner
        ccf
        sbc a,a                 ; NC (not covered) -> 0 / Z
        ret

; ---- fb_cmt_text: A = row -> NC: ld_cbuf = its comment; C: no comment
fb_cmt_text:
        ld d,a
        ld e,0
        call ld_find
        ret c
        inc hl
        inc hl
        ld a,(hl)
        cp FT_CMT
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

; ---- fb_ask_inputs: popup "Inputs (2-4)" -> NC: A = 2..4, C = cancelled
fb_ask_inputs:
        ld hl,txt_fb_inq
        call popup_open
.k:     call kb_wait
        cp K_BREAK
        jr z,.c
        cp K_EDIT
        jr z,.c
        cp '2'
        jr c,.k
        cp '4'+1
        jr nc,.k
        sub '0'
        push af
        call win_close
        pop af
        or a
        ret
.c:     call win_close
        scf
        ret

; ---- fb_nrows: A = rows of the diagram incl. the rows that blocks of the
;      last rows reach into (they have no records of their own)
fb_nrows:
        call ld_nrows
        ld (fn_n),a
        sub FT_MAXIN-1          ; blocks can only start in the last 3 rows
        jr nc,.r
        xor a
.r:     ld (fn_r),a
.row:   ld a,(fn_r)
        ld hl,fn_n
        cp (hl)
        jr nc,.e
        ld d,a
        ld e,0
.pos:   push de
        call ld_get
        ld c,b
        call fb_height_t
        pop de
        add a,d                 ; row + height
        ld hl,fn_n
        cp (hl)
        jr c,.n
        ld (hl),a
.n:     inc e
        ld a,e
        cp LD_CPOS
        jr c,.pos
        ld hl,fn_r
        inc (hl)
        jr .row
.e:     ld a,(fn_n)
        ret

; ---- fb_fix_top: keeps ld_row visible; NZ = ld_top changed
fb_fix_top:
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

; ---- fb_scr_row: A = grid row -> A = its label row on the screen
fb_scr_row:
        ld b,a
        ld a,(ld_top)
        ld c,a
        ld a,b
        sub c
        add a,a
        ld b,a
        ld a,(ld_vbase)
        add a,b
        ret

; ---- fb_cursor: XORs the signal cells of the cursor position
;      (comment row: a 1 px text cursor behind the end of the comment)
fb_cursor:
        ld a,(ld_row)
        call fb_cmt_text
        push af
        ld a,(ld_row)
        call fb_scr_row
        inc a
        ld b,a
        pop af
        jr c,.elem
        ld hl,txt_fb_sl       ; behind the end of the comment text
        call pt_width           ; (where editing continues)
        ld c,a
        ld hl,ld_cbuf
        call pt_width
        add a,c
        add a,8-1
        ld c,a
        ld d,1
        jr .draw
.elem:  ld a,(ld_pos)
        call fb_pos_x
        ld c,a
        ld d,24
.draw:  ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; fb_pos_x: A = position -> A = x (px) of its first cell (1+3p)*8
fb_pos_x:
        ld c,a
        add a,a
        add a,c
        inc a
        add a,a
        add a,a
        add a,a
        ret

; ============================================================
; drawing
; ============================================================

; ---- fb_draw_view: rows ld_top.. on screen rows ld_vbase.. (ld_vn rows)
fb_draw_view:
        ld hl,fd_cov            ; blocks that start above the view
        ld b,LD_CPOS+1
.z:     ld (hl),0
        inc hl
        djnz .z
        ld a,(ld_top)
        sub FT_MAXIN-1
        jr nc,.r0
        xor a
.r0:    ld (fd_rr),a
.above: ld a,(ld_top)
        ld b,a
        ld a,(fd_rr)
        cp b
        jr nc,.rows
        call fb_row_load
        ld e,0
.ap:    ld d,0
        ld hl,fw_t
        add hl,de
        ld a,(hl)
        ld hl,fw_a
        add hl,de
        ld c,(hl)
        call fb_height_t        ; rows left at the top of the view:
        ld hl,fd_rr             ; rr + h - top
        add a,(hl)
        ld hl,ld_top
        sub (hl)
        jr c,.an
        jr z,.an
        ld hl,fd_cov
        add hl,de
        cp (hl)
        jr c,.an
        ld (hl),a
        call fd_setcb
.an:    inc e
        ld a,e
        cp LD_CPOS
        jr c,.ap
        ld hl,fd_rr
        inc (hl)
        jr .above
.rows:  xor a
        ld (fd_i),a
.l:     ld a,(fd_i)
        ld b,a
        ld a,(ld_vn)
        cp b
        ret z
        ld a,b
        call fb_draw_row
        ld hl,fd_i
        inc (hl)
        jr .l

; ---- fb_draw_row: A = visible row index
fb_draw_row:
        ld b,a
        ld a,(ld_top)
        add a,b
        ld (fd_r),a
        call fb_scr_row
        ld (fd_lrow),a
        inc a
        ld (fd_srow),a
        ld a,(fd_lrow)          ; clear both char rows
        ld b,a
        ld c,0
        ld de,0x2000+ATTR_NORMAL
        call scr_fill_attr
        ld a,(fd_srow)
        ld b,a
        ld c,0
        ld de,0x2000+ATTR_NORMAL
        call scr_fill_attr
        ld a,(fd_lrow)
        ld b,a
        call pt_clear_row
        ld a,(fd_srow)
        ld b,a
        call pt_clear_row
        call ld_nrows
        ld b,a
        ld a,(fd_r)
        cp b
        jr c,.in
        ld hl,fd_cov            ; below the last row: only the rest of the
        ld b,LD_CPOS+1          ; blocks from above (e.g. the PT row)
        xor a
.ac:    or (hl)
        inc hl
        djnz .ac
        or a
        ret z
        ld hl,fw_t
        ld b,3*(LD_CPOS+1)
        xor a
.zf:    ld (hl),a
        inc hl
        djnz .zf
        jr .elems
.in:    call fb_row_load
        ld a,(fw_t)
        and FT_MASK
        cp FT_CMT
        jr nz,.elems
        ld a,(fd_r)
        call fb_cmt_text
        jr c,.elems
        ld a,(fd_srow)          ; "// text" in dark green
        ld b,a
        ld c,1
        ld de,0x1E00+ATTR_LDCMT
        call scr_fill_attr
        ld a,(fd_srow)
        ld (pt_row),a
        ld a,8                  ; comments start at the element column
        ld (pt_x),a
        ld hl,txt_fb_sl
        call pt_puts
        ld hl,ld_cbuf
        jp pt_puts
.elems: xor a
        ld (fd_p),a
.pos:   ld a,(fd_p)
        call fb_pos_x
        ld (fd_x),a
        ld a,(fd_p)
        ld e,a
        ld d,0
        ld hl,fd_cov            ; inside a block from above?
        add hl,de
        ld a,(hl)
        or a
        jr z,.own
        dec (hl)
        ld a,(hl)
        call fb_draw_cov        ; A = rows left below this one (0 = last)
        jr .next
.own:   call fd_ptcell          ; PT input of a timer on the right?
        jr nz,.next
        ld a,(fd_p)
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld a,(hl)
        ld (fd_t),a
        ld hl,fw_a
        add hl,de
        ld a,(hl)
        ld (ld_ar),a
        ld hl,fw_i
        add hl,de
        ld a,(hl)
        ld (ld_ar+1),a
        call fb_draw_elem
.next:  ld hl,fd_p
        inc (hl)
        ld a,(hl)
        cp LD_CPOS+1
        jr c,.pos
        ret

; ---- fb_draw_elem: fd_t / ld_ar at fd_x of the current row
fb_draw_elem:
        ld a,(fd_t)
        and FT_MASK
        ret z
        cp FT_WIRE
        jr nz,.nw
        ld a,(fd_x)
        ld c,a
        ld d,24
        jp fd_hline
.nw:    cp FT_IN                ; input: "name--" on the signal row
        jr nz,.nin
        call fd_fmt
        ld a,(fd_t)             ; negated: "o" at the end of the line, or at
        rlca                    ; the block input when it leads into a block
        jr nc,.ip
        call fd_dst_block
        jr nz,.ip
        ld bc,15*256+19         ; text up to x+15, line up to x+18
        call fd_in_txt
        ld a,(fd_x)
        add a,19
        jp fd_circle
.ip:    ld bc,20*256+24
        jp fd_in_txt
.nin:   cp FT_OUT               ; output: "-name" right behind the block
        jr nz,.nout
        call fd_fmt
        ld a,(fd_t)             ; negated: "o" at the start, or at the output
        rlca                    ; of the block the signal comes from
        jr nc,.ol
        call fd_src_block
        jr nz,.ol
        ld a,(fd_x)
        call fd_circle
        ld a,(fd_x)
        add a,4
        ld c,a
        ld d,2
        call fd_hline
        ld a,(fd_x)
        add a,7
        jr .ot
.ol:    ld a,(fd_x)
        ld c,a
        ld d,3
        call fd_hline
        ld a,(fd_x)
        add a,4
.ot:    ld (pt_x),a
        ld a,(fd_srow)
        ld (pt_row),a
        call fd_out_lim
        ld (pt_xmax),a
        ld hl,FMT_BUF
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ret
.nout:  ld a,(ld_ar)            ; block: top part
        ld c,a
        ld a,(fd_t)
        call fb_height_t
        or a
        ret z
        ld (fd_h),a
        dec a                   ; the rows below are drawn with their row
        ld e,a
        ld a,(fd_p)
        ld c,a
        ld b,0
        ld hl,fd_cov
        add hl,bc
        ld (hl),e
        ld e,c
        ld d,b
        call fd_setcb
        ld a,(fd_srow)          ; top line in the signal row (the label row
        ld b,a                  ; above the block holds the instance)
        ld a,(fd_x)
        add a,2
        ld c,a
        ld d,20
        ld hl,0x0001
        ld e,PX_SET
        call px_span
        ld a,(fd_srow)
        call fd_sides
        call fd_in_stub
        call fd_out_neg         ; output: "o" at the edge when it goes to a
        jr z,.ostub             ; negated output, else a stub
        ld a,(fd_x)
        add a,21
        call fd_circle
        jr .ob
.ostub: ld a,(fd_x)
        add a,21
        ld c,a
        ld d,3
        call fd_hline
.ob:
        ld a,(fd_h)
        dec a
        call z,fd_bottom
        ; type name inside the block, instance above it
        ld a,(fd_t)
        and FT_MASK
        add a,a
        ld e,a
        ld d,0
        ld hl,fd_names
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,(fd_srow)          ; (small letters, centred at the top)
        ld b,a
        ld a,(fd_x)
        ld c,a
        call pt_tiny_c
        ld a,(fd_t)             ; FB blocks: instance label above the block
        call fb_kind
        ret z
        call fd_fmt
        ; fall through

; fd_label: FMT_BUF centred in the label row above the element (24 px)
fd_label:
        ld a,(fd_x)
        ld c,a
        add a,23
        ld (pt_xmax),a
        ld hl,FMT_BUF
        call pt_width
        cp 23
        jr c,.w
        ld a,22
.w:     neg
        add a,24
        srl a
        add a,c
        ld (pt_x),a
        ld a,(fd_lrow)
        ld (pt_row),a
        ld hl,FMT_BUF
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ret

; fd_text: HL = text in the block at pt_row (x+4, clipped inside)
fd_text:
        ld a,(fd_x)
        add a,4
        ld (pt_x),a
        add a,18                ; up to the right edge of the block
        ld (pt_xmax),a
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ret

; ---- fb_draw_cov: A = rows of the block left (0 = last row): sides,
;      input stub, bottom line in the last row
fb_draw_cov:
        push af
        ld a,(fd_lrow)
        call fd_sides
        ld a,(fd_srow)
        call fd_sides
        call fd_in_stub
        ld a,(fd_p)             ; timer: its PT pin
        ld e,a
        ld d,0
        ld hl,fd_cbt
        add hl,de
        ld a,(hl)
        call ld_isbox
        jr nz,.np
        ld a,(fd_srow)
        ld b,a
        ld a,(fd_x)
        add a,4
        ld c,a
        ld hl,txt_fb_ptl
        call pt_tiny
.np:    pop af
        or a
        ret nz
        ; fall through

; fd_bottom: bottom line of the block in the signal row
fd_bottom:
        ld a,(fd_srow)
        ld b,a
        ld a,(fd_x)
        add a,2
        ld c,a
        ld d,20
        ld hl,0x0701
        ld e,PX_SET
        jp px_span

; fd_sides: A = char row -> left and right edge of the block
fd_sides:
        ld b,a
        push bc
        ld a,(fd_x)
        add a,2
        ld c,a
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        call px_span
        pop bc
        ld a,(fd_x)
        add a,21
        ld c,a
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        jp px_span

; fd_setcb: E = position -> fd_cbt / fd_cpt = type / PT of the block of the
;      current row there (keeps DE)
fd_setcb:
        push de
        ld d,0
        ld hl,fw_t
        add hl,de
        ld a,(hl)
        ld hl,fd_cbt
        add hl,de
        ld (hl),a
        ld hl,fw_pt
        add hl,de
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld hl,fd_cpt
        add hl,de
        add hl,de
        ld (hl),c
        inc hl
        ld (hl),b
        pop de
        ret

; fd_ptcell: the cell left of the PT row of a timer: draws "T#..--" and
;      returns NZ; Z: an ordinary cell
fd_ptcell:
        ld a,(fd_p)
        cp LD_CPOS-1
        jr nc,.no
        inc a
        ld e,a
        ld d,0
        ld hl,fd_cov
        add hl,de
        ld a,(hl)
        or a
        ret z
        ld hl,fd_cbt
        add hl,de
        ld a,(hl)
        call ld_isbox
        jr nz,.no
        ld hl,fd_cpt
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld de,FMT_BUF
        ld a,AR_KT
        ld bc,0
        call op_format
        ld bc,20*256+24
        call fd_in_txt
        or 1
        ret
.no:    xor a
        ret

; fd_in_stub: input of the block on this row: "o" right in front of the
;      block edge when the signal comes from a negated input, else a stub
fd_in_stub:
        call fd_src_neg
        jp z,fd_stubs
        ld a,(fd_srow)          ; clear the line inside the circle
        ld b,a
        ld a,(fd_x)
        dec a
        ld c,a
        ld d,3
        ld hl,0x0401
        ld e,PX_CLR
        call px_span
        ld a,(fd_x)
        sub 2
        jp fd_circle

; fd_src_neg: NZ if the signal of this row at fd_p comes (through wires)
;      from a negated input
fd_src_neg:
        ld a,(fd_p)
.l:     or a
        jr z,.no
        dec a
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld a,(hl)
        ld b,a
        and FT_MASK
        cp FT_WIRE
        jr nz,.nw
        ld a,e
        jr .l
.nw:    cp FT_IN
        jr nz,.no
        ld a,b
        and FT_NEG
        ret
.no:    xor a
        ret

; fd_dst_block: NZ if the signal of this row at fd_p leads (through wires)
;      into a block (its first row or a row it covers)
fd_dst_block:
        ld a,(fd_p)
.l:     inc a
        cp LD_CPOS
        jr nc,.no
        ld e,a
        ld d,0
        ld hl,fd_cov
        add hl,de
        ld a,(hl)
        or a
        ret nz                  ; covered by a block from above
        ld hl,fw_t
        add hl,de
        ld b,(hl)
        ld hl,fw_a
        add hl,de
        ld c,(hl)
        ld a,b
        and FT_MASK
        cp FT_WIRE
        jr nz,.nw
        ld a,e
        jr .l
.nw:    ld a,b
        call fb_height_t
        or a
        ret
.no:    xor a
        ret

; fd_out_neg: NZ if the output of the block at fd_p leads (through wires)
;      to a negated output
fd_out_neg:
        ld a,(fd_p)
.l:     inc a
        cp LD_CPOS+1
        jr nc,.no
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld a,(hl)
        ld b,a
        and FT_MASK
        cp FT_WIRE
        jr nz,.nw
        ld a,e
        jr .l
.nw:    cp FT_OUT
        jr nz,.no
        ld a,b
        and FT_NEG
        ret
.no:    xor a
        ret

; fd_src_block: NZ if the signal of this row at fd_p comes (through wires)
;      from the output of a block
fd_src_block:
        ld a,(fd_p)
.l:     or a
        jr z,.no
        dec a
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld b,(hl)
        ld hl,fw_a
        add hl,de
        ld c,(hl)
        ld a,b
        and FT_MASK
        cp FT_WIRE
        jr nz,.nw
        ld a,e
        jr .l
.nw:    ld a,b
        call fb_height_t
        or a
        ret
.no:    xor a
        ret

; fd_stubs: input stub of this row (left of the block)
fd_stubs:
        ld a,(fd_x)
        ld c,a
        ld d,3
        ; fall through
; fd_hline: C = x, D = width -> line 4 of the signal row
fd_hline:
        ld a,(fd_srow)
        ld b,a
        ld hl,0x0401
        ld e,PX_SET
        jp px_span

; fd_circle: A = x -> "o" (negation) on the signal row
fd_circle:
        ld (pt_x),a
        ld a,(fd_srow)
        ld (pt_row),a
        ld a,'o'
        jp pt_putc

; fd_fmt: ld_ar -> FMT_BUF (address or symbol)
fd_fmt: BCALL ld_fmt_ar
        ret

; fd_in_txt: FMT_BUF right-aligned to x+B on the signal row (it may reach
;      into the empty cells on the left), then the line up to x+C-1
fd_in_txt:
        push bc
        call fd_in_left
        ld (fd_l),a
        ld a,(fd_srow)
        ld (pt_row),a
        pop bc
        push bc
        ld a,(fd_x)
        add a,b
        ld (pt_xmax),a
        ld c,a
        ld hl,FMT_BUF
        call pt_width
        ld b,a
        ld a,c                  ; start = right edge - width, not left of L
        sub b
        jr c,.lim
        ld hl,fd_l
        cp (hl)
        jr nc,.st
.lim:   ld a,(fd_l)
.st:    ld (pt_x),a
        ld hl,FMT_BUF
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        pop bc
        ld a,(fd_x)
        add a,c
        ld b,a                  ; end of the line
        ld a,(pt_x)
        ld c,a
        ld a,b
        sub c
        ret c
        ret z
        ld d,a
        jp fd_hline

; fd_in_left: A = leftmost x for an input label: its cell plus the empty
;      cells on its left (the left margin at position 0)
fd_in_left:
        ld a,(fd_x)
        ld c,a
        ld a,(fd_p)
.l:     or a
        jr z,.edge
        dec a
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld b,(hl)
        ld hl,fd_cov
        add hl,de
        ld a,(hl)
        or b
        jr nz,.e
        ld a,c
        sub 24
        ld c,a
        ld a,e
        jr .l
.edge:  ld c,0                  ; up to the screen edge
.e:     ld a,c
        ret

; fd_out_lim: A = clipping x of an output label: its cell plus the empty
;      cells behind it
fd_out_lim:
        ld a,(fd_x)
        add a,23
        ld c,a
        ld a,(fd_p)
.l:     inc a
        cp LD_CPOS+1
        jr nc,.e
        ld e,a
        ld d,0
        ld hl,fw_t
        add hl,de
        ld b,(hl)
        ld hl,fd_cov
        add hl,de
        ld a,(hl)
        or b
        jr nz,.e
        ld a,c
        add a,24
        jr c,.e
        ld c,a
        ld a,e
        jr .l
.e:     ld a,c
        ret

; block names by type
fd_names:
        dw 0, 0, 0, 0, fdn_and, fdn_or, fdn_ton, fdn_tof
        dw fdn_xor, fdn_not, fdn_sr, fdn_rs, fdn_tp, fdn_rt, 0, fdn_ft
fdn_and: db "AND",0
fdn_or:  db "OR",0
fdn_xor: db "XOR",0
fdn_not: db "NOT",0
fdn_sr:  db "SR",0
fdn_rs:  db "RS",0
fdn_rt:  db "RTRG",0
fdn_ft:  db "FTRG",0
fdn_ton: db "TON",0
fdn_tof: db "TOF",0
fdn_tp:  db "TP",0

; ---- fb_row_load: A = row -> fw_t / fw_a / fw_i [position] (0 = empty),
;      fw_pt [position] = PT of a timer block
fb_row_load:
        ld (fw_row),a
        ld hl,fw_t
        ld b,3*(LD_CPOS+1)
        xor a
.z:     ld (hl),a
        inc hl
        djnz .z
        ld a,(fw_row)
        ld d,a
        ld e,0
        call ld_find
.l:     push hl
        ld de,(lf_end)
        or a
        sbc hl,de
        pop hl
        ret nc
        ld a,(fw_row)
        cp (hl)
        ret nz
        push hl
        inc hl
        ld e,(hl)
        ld a,e
        cp LD_CPOS+1
        jr nc,.n
        ld d,0
        inc hl
        ld a,(hl)               ; type, area, index
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        push hl
        ld hl,fw_t
        add hl,de
        ld (hl),a
        ld hl,fw_a
        add hl,de
        ld (hl),b
        ld hl,fw_i
        add hl,de
        ld (hl),c
        pop hl
        call ld_isbox
        jr nz,.n
        inc hl                  ; timer: PT
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld hl,fw_pt
        add hl,de
        add hl,de
        ld (hl),c
        inc hl
        ld (hl),b
.n:     pop hl
        call ld_skip
        jr .l

; ---- fb_set_state: simulation colours of the visible inputs, outputs
;      and FB blocks (signal row: input line, output start, block middle):
;      TRUE = black on bright green
fb_set_state:
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (fs_end),hl
        pop hl
        ld a,b
        or c
        ret z
        inc hl
.l:     push hl
        ld de,(fs_end)
        or a
        sbc hl,de
        pop hl
        ret nc
        push hl
        call .rec
        pop hl
        call ld_skip
        jr .l
.rec:   ld a,(ld_top)           ; visible row?
        ld b,a
        ld a,(hl)
        sub b
        ret c
        ld c,a
        ld a,(ld_vn)
        dec a
        cp c
        ret c
        ld a,(hl)
        call fb_scr_row
        inc a
        ld (fs_row),a
        inc hl
        ld a,(hl)
        ld (fs_p),a
        inc hl
        ld a,(hl)
        ld (fs_t),a
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        and FT_MASK
        ld e,3                  ; colour cell: input = right (its line),
        cp FT_IN                ; output = left, block = middle
        jr z,.opc
        ld e,1
        cp FT_OUT
        jr z,.opc
        ld e,2
        ld a,e
        ld (fs_off),a
        ld a,(fs_t)             ; FB block: its Q
        call fb_kind
        ret z
        ld a,(fs_t)
        and FT_MASK
        ld b,AR_FBM+0x20        ; Q (TON/TOF/TP), Q1 (SR/RS)
        cp FT_RTRIG
        jr z,.q1
        cp FT_FTRIG
        jr nz,.op
.q1:    ld b,AR_FBM+0x10        ; R_TRIG/F_TRIG: Q
        xor a
        ld (fs_t),a             ; (no negation)
.opc:   ld a,e
        ld (fs_off),a
.op:    ld a,b
        ld de,0
        call cp_operand_av
        ret c
        ld a,(cp_mode)
        cp VM_MB
        ret nz
        ld hl,(cp_arg)
        ld a,(cp_arg3)
        and (hl)
        ld a,(fs_t)             ; negated input / output: inverted
        jr z,.f
        rlca
        jr c,.set0
        jr .set1
.f:     rlca
        jr c,.set1
.set0:  ld e,ATTR_NORMAL
        jr .set
.set1:  ld e,ATTR_FBON
.set:   ld a,(fs_p)
        ld c,a
        add a,a
        add a,c
        ld hl,fs_off
        add a,(hl)              ; cell 1+3p .. 3+3p
        ld c,a
        ld a,(fs_row)
        ld b,a
        call attr_addr
        ld (hl),e
        ret

; ---- fb_info: status bar: block / operand, symbol name and comment
fb_info:
        call fb_pt_cell         ; PT input: info of its timer
        jr c,fb_info0
        ld hl,(ld_row)          ; (ld_row, ld_pos)
        push hl
        call fb_to_timer
        call fb_info0
        pop hl
        ld (ld_row),hl
        ret
fb_info0:
        ld hl,0
        ld (st_left),hl
        call fb_cur_get
        ld a,b
        ld (ld_ar),a
        ld a,c
        ld (ld_ar+1),a
        ld de,FB_INFOB
        ld (fi_p),de
        ld a,(fb_t)
        call ld_isbox
        jr nz,.nbx
        call fd_fmt             ; "TON1 PT=T#4s " in front of the comment
        ld hl,FMT_BUF
        ld de,FB_INFOB
        call put_str
        ld hl,txt_fb_pt
        call put_str
        ld hl,(ld_gpt)
        ld a,AR_KT
        ld bc,0
        call op_format
        ld a,' '
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld (fi_p),de
        ld hl,FB_INFOB
        ld (st_left),hl
.nbx:   ld a,(fb_t)
        and FT_MASK
        cp FT_IN
        jr z,.sym
        cp FT_OUT
        jr z,.sym
        ld a,(fb_t)
        call fb_kind
        jr z,.show
.sym:   ld a,(ld_ar)
        and AR_MASK
        cp AR_FBM
        ld a,(ld_ar)
        jr nz,.a
        ld a,AR_FBI
.a:     ld b,a
        ld a,(ld_ar+1)
        ld c,a
        ld a,b
        call sym_find_addr
        jr c,.show
        ld e,(hl)
        ld d,0
        push hl
        add hl,de
        ld (fi_end),hl
        pop hl
        inc hl
        inc hl
        inc hl
        ld de,(fi_p)
        ld a,ST_SYM             ; symbol name inverted, then the comment
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
        ld bc,(fi_end)
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
        ld hl,FB_INFOB
        ld (st_left),hl
.show:  jp status_left

; ---- fb_pick: element picker. A = current type -> NC: A = chosen type
;      (incl. FT_NEG); C = cancelled
FP_COLS EQU 13
fb_pick:
        ld (fk_cur),a
        call fb_list
        ld (fk_list),hl
        ld bc,0                 ; B = count, C = selection
.cnt:   ld a,(hl)
        cp 0xFF
        jr z,.cd
        ld e,a
        ld a,(fk_cur)
        cp e
        jr nz,.cn
        ld c,b
.cn:    inc b
        call fk_next
        jr .cnt
.cd:    ld a,b
        ld (fk_n),a
        ld a,c
        ld (fk_sel),a
        ld a,b
        add a,2
        ld d,a
        ld a,24
        sub d
        srl a
        ld b,a
        ld c,(32-FP_COLS)/2
        ld e,FP_COLS
        call win_open
        ld hl,(fk_list)
        ld a,(win_r)
        inc a
        ld (fk_row),a
.it:    ld a,(hl)
        cp 0xFF
        jr z,.drawn
        push hl
        inc hl
        inc hl
        ld a,(fk_row)
        ld (pt_row),a
        ld a,(win_c)
        inc a
        add a,a
        add a,a
        add a,a
        ld (pt_x),a
        call pt_puts
        pop hl
        call fk_next
        ld hl,fk_row
        inc (hl)
        ld hl,(fk_ptr)
        jr .it
.drawn: call fk_inv
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
        call to_upper           ; shortcut key
        ld c,a
        ld hl,(fk_list)
        ld b,0
.hk:    ld a,(hl)
        cp 0xFF
        jr z,.key
        inc hl
        ld a,(hl)
        dec hl
        cp c
        jr z,.hkf
        call fk_next
        inc b
        jr .hk
.hkf:   ld a,b
        ld (fk_sel),a
        jr .ok
.up:    call fk_inv
        ld a,(fk_sel)
        or a
        jr nz,.u1
        ld a,(fk_n)
.u1:    dec a
        jr .mv
.down:  call fk_inv
        ld a,(fk_sel)
        inc a
        ld hl,fk_n
        cp (hl)
        jr c,.mv
        xor a
.mv:    ld (fk_sel),a
        call fk_inv
        jr .key
.ok:    ld hl,(fk_list)
        ld a,(fk_sel)
        or a
        jr z,.o2
        ld b,a
.o1:    call fk_next
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

; fk_next: HL = item -> next item ([type][key][label 0]); also in fk_ptr
fk_next:
        inc hl
        inc hl
.l:     ld a,(hl)
        inc hl
        or a
        jr nz,.l
        ld (fk_ptr),hl
        ret

; fk_inv: inverts the selected item row of the picker
fk_inv: ld a,(win_r)
        inc a
        ld b,a
        ld a,(fk_sel)
        add a,b
        ld b,a
        ld a,(win_c)
        add a,a
        add a,a
        add a,a
        add a,2
        ld c,a
        ld d,FP_COLS*8-4
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; picker items: type, shortcut key, label
fb_pick_l:
        db FT_IN,        'I',"Input",0
        db FT_IN|FT_NEG, 'N',"Negated input",0
        db FT_WIRE,      '-',"Wire",0
        db FT_AND,       'A',"AND",0
        db FT_OR,        'O',"OR",0
        db FT_XOR,       'X',"XOR",0
        db FT_NOT,       '!',"NOT",0
        db FT_SR,        'S',"SR flip-flop",0
        db FT_RS,        'R',"RS flip-flop",0
        db FT_RTRIG,     'P',"RT rising edge",0
        db FT_FTRIG,     'E',"RF falling edge",0
        db FT_TON,       'T',"TON timer",0
        db FT_TOF,       'F',"TOF timer",0
        db FT_TP,        'U',"TP pulse",0
        db FT_OUT,       'Q',"Output",0
        db FT_OUT|FT_NEG,'W',"Negated output",0
        db 0xFF
fb_pick_o:
        db FT_OUT,       'Q',"Output",0
        db FT_OUT|FT_NEG,'N',"Negated output",0
        db 0xFF

txt_fb_inq:  db "Number of inputs (2-4)?",0,0
txt_fb_sl:   db "// ",0
txt_fb_pt:   db " PT=",0
txt_fb_ptl:  db "PT",0
err_fb_room: db "No room for the block",0
err_fb_src:  db "No signal here (nothing on the left)",0

fb_pou:   db 0xFF
fb_t:     db 0
fb_newt:  db 0
fb_oldt:  db 0
fb_kind_v: db 0
fb_aw:    db 0
fr_h:     db 0
fr_k:     db 0
fr_x:     db 0
fb_olda:  db 0
fm_h:     db 0
fm_h0:    db 0
fm_r0:    db 0
fm_r1:    db 0
fm_rr:    db 0
fm_q:     db 0
fm_t:     db 0
fm_n:     db 0
fm_p:     db 0
fm_err:   db 0
fb_hh:    db 0
fb_ins:   db 0
fb_oldc:  db 0
fb_oldpt: dw 0
fi_x:     db 0
fn_n:     db 0
fn_r:     db 0
fb_key:   db 0
fpt_row:    db 0
fpt_pos:    db 0
fw_row:   db 0
fw_t:     ds LD_CPOS+1
fw_a:     ds LD_CPOS+1
fw_i:     ds LD_CPOS+1
fw_pt:    ds 2*(LD_CPOS+1)
fd_cbt:   ds LD_CPOS+1          ; type of the block covering the position
fd_cpt:   ds 2*(LD_CPOS+1)      ; its PT (timers)
fd_cov:   ds LD_CPOS+1          ; rows of a block still to draw (per position)
fd_rr:    db 0
fd_i:     db 0
fd_r:     db 0
fd_p:     db 0
fd_x:     db 0
fd_t:     db 0
fd_h:     db 0
fd_l:     db 0
fd_lrow:  db 0
fd_srow:  db 0
fs_end:   dw 0
fs_row:   db 0
fs_p:     db 0
fs_t:     db 0
fs_off:   db 0
fi_p:     dw 0
fi_end:   dw 0
fk_cur:   db 0
fk_list:  dw 0
fk_ptr:   dw 0
fk_n:     db 0
fk_sel:   db 0
fk_row:   db 0
