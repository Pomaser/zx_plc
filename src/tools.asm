; ============================================================
; tools.asm - cross references (DEMO bank, called with BCALL)
; ============================================================
; xref_show lists every use of one operand in all POUs: POU name,
; line (IL) or row / position (LD, FBD) and Read / Write / Call.
; ENTER on an entry opens that POU at that place (xr_jf / xr_jl /
; xr_jp in shared.asm are read by the editors when they start).
; ============================================================
XR_MAX    EQU 17            ; entries on the screen (rows 3-19)
XR_ROW0   EQU 3
XR_X_LOC  EQU 56
XR_X_KIND EQU 132

; ---- xref_show: A = area, C = index -> A = CMD_EDIT (go to the chosen use)
;      or CMD_REOPEN (back to the screen it was called from)
xref_show:
        and AR_MASK
        cp AR_FBM               ; FB member -> its instance
        jr nz,.n1
        ld a,AR_FBI
.n1:    ld (xr_area),a
        ld a,c
        ld (xr_idx),a
        ld a,(xr_area)
        call xr_valid
        jr nc,.ok
        ld hl,txt_xr_noop
        call ui_error
        ld a,CMD_REOPEN
        ret
.ok:    call xr_scan
        jp xr_screen

; xr_valid: A = area -> NC if it can be cross-referenced
xr_valid:
        cp AR_I
        ret z
        cp AR_Q
        ret z
        cp AR_M
        ret z
        cp AR_MW
        ret z
        cp AR_SX
        ret z
        cp AR_FBI
        ret z
        cp AR_POU
        ret z
        cp AR_SM
        ret z
        scf
        ret

; ---- xr_scan: fills xr_list (xr_n entries, xr_more = list full)
xr_scan:
        xor a
        ld (xr_n),a
        ld (xr_more),a
        ld (xr_slot),a
.slot:  ld a,(xr_slot)
        call pou_used
        jr z,.next
        call pou_lang
        ld (xr_lang),a
        ld a,(xr_slot)
        call pou_body           ; HL = body, BC = length
        push hl
        add hl,bc
        ld (xr_end),hl
        pop hl
        ld a,b
        or c
        jr z,.next
        ld a,(xr_lang)
        cp LANG_IL
        jr nz,.grid
        call xr_il
        jr .next
.grid:  inc hl                  ; (row count)
        call xr_grid
.next:  ld hl,xr_slot
        inc (hl)
        ld a,(hl)
        cp MAX_POU
        jr c,.slot
        ret

; xr_il: HL = first line record of an IL body
xr_il:  ld de,0
        ld (xr_line),de
.l:     call xr_at_end
        ret nc
        ld (xr_rec),hl
        inc hl
        ld a,(hl)               ; kind
        cp K_INSTR
        jr nz,.nx
        ld hl,(xr_rec)
        ld a,(hl)               ; len: [len][kind][op] + operand?
        cp 5
        jr c,.nx
        inc hl
        inc hl
        ld a,(hl)               ; op: mnemonic index -> class
        and 0x3F
        ld e,a
        add a,a
        add a,a
        add a,a
        sub e                   ; *7
        ld e,a
        ld d,0
        push hl
        ld hl,il_mnems+6
        add hl,de
        ld a,(hl)
        and 0x0F
        ld (xr_cls),a
        pop hl
        inc hl                  ; operand
        ld a,(hl)
        and AR_MASK
        cp AR_LBL
        jr z,.nx
        ld b,'W'
        ld a,(xr_cls)
        cp IC_WRITE
        jr z,.k
        cp IC_SETRES
        jr z,.k
        ld b,'C'
        cp IC_CALL
        jr z,.k
        ld b,'R'
.k:     call xr_match           ; HL = operand -> Z if it is the one
        jr nz,.par
        call xr_add_il
        jr .nx
.par:   ld a,(xr_cls)           ; FB call: the parameters are read
        cp IC_CALL
        jr nz,.nx
        call xr_opnd_len
        add a,l
        ld l,a
        jr nc,.p
        inc h
.p:     push hl                 ; [member][operand] ...
        ld hl,(xr_rec)
        ld e,(hl)
        ld d,0
        add hl,de
        ex de,hl                ; DE = record end
        pop hl
        or a
        sbc hl,de
        add hl,de
        jr nc,.nx
        inc hl                  ; member
        ld b,'R'
        call xr_match
        jr nz,.pn
        call xr_add_il
        jr .nx
.pn:    call xr_opnd_len
        add a,l
        ld l,a
        jr nc,.p
        inc h
        jr .p
.nx:    ld hl,(xr_line)
        inc hl
        ld (xr_line),hl
        ld hl,(xr_rec)
        ld e,(hl)
        ld d,0
        add hl,de
        jp .l

; xr_opnd_len: HL = operand -> A = its length (K16 / KT: 3, else 2)
xr_opnd_len:
        ld a,(hl)
        and AR_MASK
        cp AR_K16
        jr z,.l3
        cp AR_KT
        jr z,.l3
        ld a,2
        ret
.l3:    ld a,3
        ret

; xr_match: HL = [area][index] -> Z if it is the operand searched for
;      (keeps BC, HL)
xr_match:
        ld a,(hl)
        and AR_MASK
        cp AR_FBM
        jr nz,.a
        ld a,AR_FBI
.a:     push hl
        ld hl,xr_area
        cp (hl)
        pop hl
        ret nz
        inc hl
        ld a,(hl)
        dec hl
        push hl
        ld hl,xr_idx
        cp (hl)
        pop hl
        ret

xr_add_il:
        ld de,(xr_line)
        xor a
        jr xr_add

; xr_grid: HL = first record of an LD / FBD body
xr_grid:
.l:     call xr_at_end
        ret nc
        push hl
        call xr_grid_rec
        pop hl
        call ld_skip
        jr .l

; xr_grid_rec: HL = record [row][pos][type][area][index]
xr_grid_rec:
        ld a,(hl)
        ld (xr_r),a
        inc hl
        ld a,(hl)
        ld (xr_p),a
        inc hl
        ld a,(hl)               ; type
        inc hl                  ; HL = [area][index]
        ld c,a
        ld a,(xr_lang)
        cp LANG_LD
        ld a,c
        jr nz,.fbd
        and LT_MASK
        ld b,'W'
        cp LT_COIL
        jr z,.m
        cp LT_NCOIL
        jr z,.m
        cp LT_SET
        jr z,.m
        cp LT_RES
        jr z,.m
        ld b,'C'
        cp LT_TON
        jr z,.m
        cp LT_TOF
        jr z,.m
        cp LT_TP
        jr z,.m
        ld b,'R'
        cp LT_NO
        ret c
        cp LT_N+1
        ret nc
        jr .m
.fbd:   and FT_MASK
        ld b,'R'
        cp FT_IN
        jr z,.m
        ld b,'W'
        cp FT_OUT
        jr z,.m
        ld b,'C'                ; FB boxes (logic boxes hold no operand)
        ld a,(hl)
        cp AR_FBI
        ret nz
.m:     call xr_match
        ret nz
        ld a,(xr_r)
        ld e,a
        ld d,0
        ld a,(xr_p)
        ; fall through

; xr_add: DE = line / row, A = pos, B = kind letter -> one more entry
xr_add: push af
        ld a,(xr_n)
        cp XR_MAX
        jr c,.ok
        ld a,1
        ld (xr_more),a
        pop af
        ret
.ok:    ld l,a
        add a,a
        add a,a
        add a,l                 ; *5
        ld l,a
        ld h,0
        push de
        ld de,xr_list
        add hl,de
        pop de
        ld a,(xr_slot)
        ld (hl),a
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        pop af
        ld (hl),a
        inc hl
        ld (hl),b
        ld hl,xr_n
        inc (hl)
        ret

; xr_at_end: HL -> NC if HL >= xr_end, C while there is more (keeps HL)
xr_at_end:
        push de
        ld de,(xr_end)
        or a
        sbc hl,de
        add hl,de
        pop de
        ret

; ---- xr_screen: the list; A = CMD_EDIT / CMD_REOPEN
xr_screen:
        call screen_begin
        ld hl,txt_xr_hint       ; key hints (text in fixed memory)
        ld de,rd_c
        call put_str
        xor a
        ld (de),a
        ld hl,rd_c
        ld (st_left),hl
        call status_left
        ; title: "Cross references: %IX0.0 (Name)"
        ld de,rd_o
        ld hl,txt_xr_title
        call put_str
        ld a,(xr_idx)
        ld c,a
        ld a,(xr_area)
        ld hl,0
        ld b,0
        call op_format
        push de
        ld a,(xr_idx)
        ld c,a
        ld a,(xr_area)
        call sym_name_of
        pop de
        jr c,.nt
        ld a,' '
        ld (de),a
        inc de
        ld a,'('
        ld (de),a
        inc de
        call put_str
        ld a,')'
        ld (de),a
        inc de
.nt:    xor a
        ld (de),a
        ld bc,1*256
        ld de,0x2000+ATTR_TITLE
        call scr_fill_attr
        ld a,1
        ld (pt_row),a
        ld a,3
        ld (pt_x),a
        ld hl,rd_o
        call pt_puts
        ; entries
        ld a,(xr_n)
        or a
        jr nz,.has
        ld a,XR_ROW0
        ld (pt_row),a
        ld a,3
        ld (pt_x),a
        ld hl,txt_xr_none
        call pt_puts
        jp .wait
.has:   xor a
        ld (xr_i),a
.row:   call xr_draw_entry
        ld hl,xr_i
        inc (hl)
        ld a,(xr_n)
        cp (hl)
        jr nz,.row
        ld a,(xr_more)
        or a
        jr z,.sel
        ld a,XR_ROW0+XR_MAX
        ld (pt_row),a
        ld a,3
        ld (pt_x),a
        ld hl,txt_xr_more
        call pt_puts
.sel:   xor a
        ld (xr_sel),a
        call xr_inv
.key:   call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jr z,.go
        cp K_BREAK
        jr z,.back
        cp K_EDIT
        jr z,.back
        cp K_XREF
        jr z,.back
        jr .key
.up:    ld a,(xr_sel)
        or a
        jr z,.key
        call xr_inv
        ld hl,xr_sel
        dec (hl)
        call xr_inv
        jr .key
.down:  ld a,(xr_n)
        ld b,a
        ld a,(xr_sel)
        inc a
        cp b
        jr nc,.key
        call xr_inv
        ld hl,xr_sel
        inc (hl)
        call xr_inv
        jr .key
.go:    ld a,(xr_sel)           ; open the POU at that place
        call xr_entry
        ld a,(hl)
        ld (cur_pou),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (xr_jl),de
        ld a,(hl)
        ld (xr_jp),a
        ld a,1
        ld (xr_jf),a
        ld hl,0
        ld (st_left),hl
        ld a,CMD_EDIT
        ret
.wait:  call kb_wait
        cp K_ENTER
        jr z,.back
        cp K_BREAK
        jr z,.back
        cp K_EDIT
        jr z,.back
        cp K_XREF
        jr nz,.wait
.back:  ld hl,0
        ld (st_left),hl
        ld a,CMD_REOPEN
        ret

; xr_entry: A = index -> HL = its entry
xr_entry:
        ld l,a
        add a,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        ld de,xr_list
        add hl,de
        ret

; xr_inv: inverts the row of the selected entry
xr_inv: ld a,(xr_sel)
        add a,XR_ROW0
        ld b,a
        ld c,0
        ld d,255
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; xr_draw_entry: entry xr_i on its row
xr_draw_entry:
        ld a,(xr_i)
        add a,XR_ROW0
        ld (pt_row),a
        ld a,(xr_i)
        call xr_entry
        ld (xr_ep),hl
        ld a,(hl)               ; POU name
        push af
        call pou_entry
        ld de,rd_o
        call name_unpad
        ld a,3
        ld (pt_x),a
        ld hl,rd_o
        call pt_puts
        pop af
        call pou_lang
        ld de,rd_o              ; place
        cp LANG_IL
        jr nz,.rc
        ld hl,txt_xr_line
        call put_str
        ld hl,(xr_ep)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        inc hl                  ; (1-based)
        call utoa16
        jr .pl
.rc:    ld hl,txt_xr_row
        call put_str
        ld hl,(xr_ep)
        inc hl
        ld l,(hl)
        ld h,0
        inc hl
        call utoa16
        ld hl,txt_xr_pos
        call put_str
        ld hl,(xr_ep)
        inc hl
        inc hl
        inc hl
        ld l,(hl)
        ld h,0
        inc hl
        call utoa16
.pl:    xor a
        ld (de),a
        ld a,XR_X_LOC
        ld (pt_x),a
        ld hl,rd_o
        call pt_puts
        ld hl,(xr_ep)           ; kind
        ld de,4
        add hl,de
        ld a,(hl)
        ld hl,txt_xr_r
        cp 'R'
        jr z,.k
        ld hl,txt_xr_w
        cp 'W'
        jr z,.k
        ld hl,txt_xr_c
.k:     ld a,XR_X_KIND
        ld (pt_x),a
        jp pt_puts

txt_xr_title: db "Cross references: ",0
txt_xr_hint:  db "UP/DOWN  ENTER Go to  BREAK Back",0
txt_xr_none:  db "No references",0
txt_xr_more:  db "... (more)",0
txt_xr_noop:  db "No operand here",0
txt_xr_line:  db "Line ",0
txt_xr_row:   db "Row ",0
txt_xr_pos:   db ", pos ",0
txt_xr_r:     db "Read",0
txt_xr_w:     db "Write",0
txt_xr_c:     db "Call",0

xr_area:  db 0
xr_idx:   db 0
xr_slot:  db 0
xr_lang:  db 0
xr_end:   dw 0
xr_rec:   dw 0
xr_line:  dw 0
xr_cls:   db 0
xr_r:     db 0
xr_p:     db 0
xr_n:     db 0
xr_more:  db 0
xr_i:     db 0
xr_sel:   db 0
xr_ep:    dw 0
xr_list:  ds XR_MAX*5           ; [slot][line lo][line hi][pos][kind]
