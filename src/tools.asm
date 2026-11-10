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

; ---- tl_run: editor tool for the operand at the cursor (A = area,
;      C = index): tl_cmd = CMD_WADD adds it to the watch list, else the
;      cross references; A = command for the screen (CMD_REOPEN / CMD_EDIT)
tl_run: push af
        ld a,(tl_cmd)
        cp CMD_WADD
        jr z,.w
        pop af
        jp xref_show
.w:     pop af
        jp wt_add_op

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
        jp xr_add

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
        and LT_MASK             ; compare / arithmetic (LD and FBD)
        cp LT_CMP
        jr nc,.wd
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
        cp LT_CTU
        jr z,.m
        cp LT_CTD
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
        jr .add
.wd:    ld a,c                  ; D written (first), A and B read
        and LT_MASK
        cp LT_MATH
        jr nz,.wr
        push hl
        ld de,7
        add hl,de
        ld b,'W'
        call xr_match
        pop hl
        jr z,.add
.wr:    ld b,'R'
        call xr_match
        jr z,.add
        ld de,4
        add hl,de
        call xr_match
        ret nz
.add:   ld a,(xr_r)
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

; ============================================================
; watch / force table (simulation page, list in WATCH_SLOT)
; ============================================================
; Rows 1-19 of the simulation screen: row 1 column names, rows 2-17 the
; entries (> marks the selected one), the row after the last entry adds
; a new one. Values are redrawn when they change; forced values get an
; "F". Forcing: runtime table RT_FRC (applied by vm_force).
WT_ROW0   EQU 2
WT_X_SYM  EQU 64
WT_X_F    EQU 168
WT_VCOL   EQU 22            ; first cell of the value

; ---- wt_count: A = number of entries, HL = list start
wt_count:
        ld a,WATCH_SLOT
        call pou_body
        srl b
        rr c
        ld a,c
        ret

; ---- wt_draw: the whole page
wt_draw:
        ld b,1
.cl:    push bc
        ld c,0
        ld d,32
        ld e,ATTR_NORMAL
        call scr_fill_attr
        pop bc
        push bc
        call pt_clear_row
        pop bc
        inc b
        ld a,b
        cp WT_ROW0+WT_MAX+2
        jr c,.cl
        ld bc,1*256             ; column names
        ld de,0x2000+ATTR_TITLE
        call scr_fill_attr
        ld a,1
        ld (pt_row),a
        ld a,8
        ld (pt_x),a
        ld hl,txt_wt_op
        call pt_puts
        ld a,WT_X_SYM
        ld (pt_x),a
        ld hl,txt_wt_sym
        call pt_puts
        ld hl,txt_wt_val
        ld a,252
        call pt_puts_r
        call wt_count
        ld (wt_n),a
        ld b,a                  ; selection within 0 .. n (n = add row)
        ld a,(wt_sel)
        cp b
        jr c,.s1
        jr z,.s1
        ld a,b
        ld (wt_sel),a
.s1:    ld a,(wt_sel)
        cp WT_MAX
        jr c,.s2
        ld a,WT_MAX-1
        ld (wt_sel),a
.s2:    xor a
        ld (wt_i),a
.e:     ld a,(wt_n)
        ld b,a
        ld a,(wt_i)
        cp b
        jr nc,.add
        call wt_draw_entry
        ld hl,wt_i
        inc (hl)
        jr .e
.add:   ld a,(wt_n)
        cp WT_MAX
        jr nc,.mk
        add a,WT_ROW0
        ld (pt_row),a
        ld a,8
        ld (pt_x),a
        ld hl,txt_wt_add
        call pt_puts
.mk:    ld a,(wt_sel)           ; selection mark
        add a,WT_ROW0
        ld (pt_row),a
        xor a
        ld (pt_x),a
        ld a,'>'
        call pt_putc
        ld a,0xFF               ; values: draw all
        ld (wt_all),a
        ; fall through

; ---- wt_update: redraws the values that changed
wt_update:
        xor a
        ld (wt_i),a
.l:     ld a,(wt_n)
        ld b,a
        ld a,(wt_i)
        cp b
        jr nc,.e
        call wt_value           ; DE = value, A = kind (0 none, 1 BOOL, 2 INT, 3 TIME)
        ld (wt_k),a
        ld a,(wt_i)             ; forced?
        call wt_frc
        ld a,(hl)
        ld c,a
        ld a,(wt_i)             ; cache [value lo][value hi][forced]
        ld l,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        push de
        ld de,wt_cache
        add hl,de
        pop de
        ld a,(wt_all)
        or a
        jr nz,.dr
        ld a,(hl)
        cp e
        jr nz,.dr
        inc hl
        ld a,(hl)
        dec hl
        cp d
        jr nz,.dr
        inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        cp c
        jr z,.n
.dr:    ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),c
        ld a,c
        ld (wt_f),a
        call wt_draw_val
.n:     ld hl,wt_i
        inc (hl)
        jr .l
.e:     xor a
        ld (wt_all),a
        ret

; wt_entry: A = index -> HL = [area][index] in the list
wt_entry:
        push af
        ld a,WATCH_SLOT
        call pou_body
        pop af
        add a,a
        add a,l
        ld l,a
        ret nc
        inc h
        ret

; wt_frc: A = index -> HL = its RT_FRC entry
wt_frc: ld l,a
        add a,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        push de
        ld de,RT_FRC
        add hl,de
        pop de
        ret

; wt_value: entry wt_i -> A = kind (0 none, 1 BOOL, 2 INT, 3 TIME), DE = value;
;      cp_arg / cp_arg3 = address / bit mask
wt_value:
        ld a,(wt_i)
        call wt_entry
        ld a,(hl)
        inc hl
        ld c,(hl)
        ld de,0
        call cp_operand_av
        ld a,0
        ret c
        ld a,(cp_mode)
        cp VM_MB
        jr z,.b
        cp VM_MW
        ld a,0
        ret nz
        ld hl,(cp_arg)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,(cp_istime)
        or a
        ld a,2
        ret z
        inc a
        ret
.b:     ld hl,(cp_arg)
        ld a,(cp_arg3)
        and (hl)
        ld de,0
        jr z,.f
        inc e
.f:     ld a,1
        ret

; wt_draw_entry: operand and symbol of entry wt_i
wt_draw_entry:
        ld a,(wt_i)
        add a,WT_ROW0
        ld (pt_row),a
        ld a,(wt_i)
        call wt_entry
        ld a,(hl)
        inc hl
        ld c,(hl)
        push af
        push bc
        ld de,rd_o
        ld hl,0
        ld b,0
        call op_format
        xor a
        ld (de),a
        ld a,8
        ld (pt_x),a
        ld hl,rd_o
        call pt_puts
        pop bc
        pop af
        and AR_MASK             ; FB member: the instance symbol
        cp AR_FBM
        jr nz,.s
        ld a,AR_FBI
.s:     call sym_name_of
        ret c
        ld a,WT_X_SYM
        ld (pt_x),a
        ld a,WT_X_F-4
        ld (pt_xmax),a
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ret

; wt_draw_val: value DE of kind wt_k, forced flag wt_f, row of entry wt_i
wt_draw_val:
        ld a,(wt_i)
        add a,WT_ROW0
        ld (pt_row),a
        ld b,a                  ; clear the F cell and the value cells
        ld c,WT_X_F/8
        call pix_addr
        ld c,8
.cl:    push hl
        ld b,32-WT_X_F/8
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec c
        jr nz,.cl
        ld a,(pt_row)
        ld b,a
        ld c,WT_VCOL
        push de
        ld de,(32-WT_VCOL)*256+ATTR_NORMAL
        ld a,(wt_k)             ; TRUE: black on bright green
        cp 1
        jr nz,.at
        pop hl
        push hl
        ld a,l
        or a
        jr z,.at
        ld e,ATTR_ON
.at:    call scr_fill_attr
        pop de
        ld a,(wt_f)
        or a
        jr z,.nf
        ld a,WT_X_F
        ld (pt_x),a
        ld a,'F'
        push de
        call pt_putc
        pop de
.nf:    ld a,(wt_k)
        or a
        ret z
        ld hl,rd_c
        ex de,hl                ; HL = value, DE = text
        cp 1
        jr z,.bool
        cp 3
        jr z,.time
        call itoa16
        jr .pr
.time:  ld a,AR_KT
        ld b,0
        call op_format
        jr .pr
.bool:  ld a,l
        ld hl,kw_false
        or a
        jr z,.bs
        ld hl,kw_true
.bs:    call put_str
.pr:    xor a
        ld (de),a
        ld hl,rd_c
        ld a,252
        jp pt_puts_r

; ---- wt_key: A = key on the watch page (UP, DOWN, ENTER, DELETE, F)
wt_key:
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jp z,wt_edit
        cp K_DEL
        jp z,wt_del
        jp wt_force
.up:    ld a,(wt_sel)
        or a
        ret z
        dec a
        jr .mv
.down:  ld a,(wt_n)
        ld b,a
        ld a,(wt_sel)
        cp b
        ret nc                  ; (on the add row)
        inc a
        cp WT_MAX
        ret nc
.mv:    push af                 ; old mark off (cell 0 holds only the mark)
        ld a,(wt_sel)
        add a,WT_ROW0
        ld b,a
        ld c,0
        call pix_addr
        ld b,8
.c:     ld (hl),0
        inc h
        djnz .c
        pop af
        ld (wt_sel),a
        add a,WT_ROW0
        ld (pt_row),a
        xor a
        ld (pt_x),a
        ld a,'>'
        jp pt_putc

; wt_edit: ENTER: operand of the selected entry (new on the add row);
;      an empty text removes the entry
wt_edit:
        ld hl,rd_o
        ld (hl),0
        ld a,(wt_n)
        ld b,a
        ld a,(wt_sel)
        cp b
        jr nc,.ask
        call wt_entry           ; current operand as the initial text
        ld a,(hl)
        inc hl
        ld c,(hl)
        ld de,rd_o
        ld hl,0
        ld b,0
        call op_format
        xor a
        ld (de),a
.ask:   ld hl,txt_wt_q
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,rd_o
        ld de,0x0C01            ; 12 chars (fits the popup), upper case
        call ui_input
        push af
        call win_close
        pop af
        jp c,wt_draw
        ld a,(rd_o)
        or a
        jp z,wt_del
        ld hl,rd_o
        call op_parse
        jr c,.bad
        ld b,a
        ld a,(hl)
        or a
        jr nz,.bad
        ld a,b                  ; something with a value
        and AR_MASK
        cp AR_FBI
        jr z,.bad
        cp AR_POU
        jr z,.bad
        cp AR_KB
        jr z,.bad
        cp AR_K16
        jr z,.bad
        cp AR_KT
        jr z,.bad
        ld a,b
        ld (wt_na),a
        ld a,c
        ld (wt_ni),a
        ld a,(wt_sel)           ; not forced any more
        call wt_frc
        ld (hl),0
        ld a,(wt_n)
        ld b,a
        ld a,(wt_sel)
        cp b
        jr c,.repl
        add a,a                 ; new entry at the end
        ld e,a
        ld d,0
        ld bc,2
        ld a,WATCH_SLOT
        call pou_insert
        jr c,.mem
        jr .put
.repl:  call undo_save
        call wt_entry
.put:   ld a,(wt_na)
        ld (hl),a
        inc hl
        ld a,(wt_ni)
        ld (hl),a
        jp wt_draw
.bad:   ld hl,txt_wt_bad
        call ui_error
        jp wt_draw
.mem:   ld hl,err_il_mem
        call ui_error
        jp wt_draw

; wt_del: DELETE: removes the selected entry (its force too)
wt_del: ld a,(wt_n)
        ld b,a
        ld a,(wt_sel)
        cp b
        jp nc,wt_draw
        add a,a
        ld e,a
        ld d,0
        ld bc,2
        ld a,WATCH_SLOT
        call pou_delete
        ld a,(wt_sel)           ; forces of the following entries move up
        ld b,a
        ld a,WT_MAX-1
        sub b
        jr z,.last
        ld b,a                  ; (WT_MAX-1-sel) * 5 bytes
        add a,a
        add a,a
        add a,b
        ld c,a
        ld b,0
        push bc
        ld a,(wt_sel)
        call wt_frc
        pop bc
        push hl
        ld de,5
        add hl,de
        pop de
        ldir
.last:  ld hl,RT_FRC+(WT_MAX-1)*5   ; the last entry is free
        ld (hl),0
        jp wt_draw

; wt_force: F: BOOL cycles off -> TRUE -> FALSE -> off; INT asks a value
wt_force:
        call to_upper
        cp 'F'
        ret nz
        ld a,(wt_n)
        ld b,a
        ld a,(wt_sel)
        cp b
        ret nc
        ld (wt_i),a
        call wt_value
        or a
        jp z,.no
        cp 3
        jp z,.no
        ld (wt_k),a
        ld a,(wt_sel)
        call wt_frc
        push hl
        pop ix
        ld a,(wt_k)
        cp 2
        jr z,.int
        ld a,(ix+0)             ; BOOL
        or a
        jr z,.t
        ld a,(ix+4)
        or a
        jr z,.off
        ld (ix+4),0             ; TRUE -> FALSE
        jr .ap
.t:     ld (ix+0),1             ; off -> TRUE
        ld hl,(cp_arg)
        ld (ix+1),l
        ld (ix+2),h
        ld a,(cp_arg3)
        ld (ix+3),a
        ld (ix+4),1
        jr .ap
.off:   ld (ix+0),0             ; FALSE -> off
        jr .ap
.int:   ld a,(ix+0)             ; forced INT: off again
        or a
        jr z,.ask
        ld (ix+0),0
        jr .ap
.ask:   push ix
        ld hl,txt_wt_vq
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,rd_o
        ld (hl),0
        ld de,0x0701
        call ui_input
        push af
        call win_close
        pop af
        pop ix
        jr c,.ap
        ld hl,rd_o
        call op_parse
        jr c,.bad
        and AR_MASK
        cp AR_K16
        jr nz,.bad
        ld (ix+3),e
        ld (ix+4),d
        push de
        ld a,(wt_i)             ; (cp_arg again)
        call wt_value
        pop de
        ld hl,(cp_arg)
        ld (ix+1),l
        ld (ix+2),h
        ld (ix+0),2
.ap:    BCALL vm_force          ; shown at once
        jp wt_draw
.bad:   ld hl,txt_wt_bad
        call ui_error
        jp wt_draw
.no:    ld hl,txt_wt_nof
        call ui_error
        jp wt_draw

txt_wt_op:   db "Operand",0
txt_wt_sym:  db "Symbol",0
txt_wt_val:  db "Value",0
txt_wt_add:  db "+ ENTER: add an operand",0
txt_wt_q:    db "Operand to watch:",0," ",0," ",0,0
txt_wt_vq:   db "Forced value:",0," ",0," ",0,0
txt_wt_bad:  db "Invalid operand",0
txt_wt_nof:  db "Only BOOL and INT can be forced",0

wt_n:     db 0
wt_i:     db 0
wt_sel:   db 0
wt_k:     db 0
wt_f:     db 0
wt_all:   db 0
wt_na:    db 0
wt_ni:    db 0
wt_cache: ds WT_MAX*3

; ---- wt_add_op: A = area, C = index -> appended to the watch list (an FB
;      instance: its ET / CV / Q); message; A = CMD_REOPEN
wt_add_op:
        ld b,a
        and AR_MASK
        cp AR_FBI
        jr nz,.n
        ld a,c                  ; FB type -> member to watch
        rrca
        rrca
        and 0x3F
        cp FB_TYPES
        jr nc,.bad
        ld e,a
        ld d,0
        ld hl,wt_fbm
        add hl,de
        ld a,(hl)
        rlca
        rlca
        rlca
        rlca
        or AR_FBM
        ld b,a
.n:     ld a,b
        and AR_MASK
        cp AR_I
        jr z,.ok
        cp AR_Q
        jr z,.ok
        cp AR_M
        jr z,.ok
        cp AR_MW
        jr z,.ok
        cp AR_SX
        jr z,.ok
        cp AR_SM
        jr z,.ok
        cp AR_FBM
        jr z,.ok
.bad:   ld hl,txt_xr_noop
.err:   call ui_error
        ld a,CMD_REOPEN
        ret
.ok:    ld a,b
        ld (wt_na),a
        ld a,c
        ld (wt_ni),a
        call wt_count           ; already there?
        ld (wt_n),a
        or a
        jr z,.add
        ld b,a
.dup:   ld a,(wt_na)
        cp (hl)
        inc hl
        jr nz,.dn
        ld a,(wt_ni)
        cp (hl)
        jr nz,.dn
        ld hl,txt_wt_dup
        jr .err
.dn:    inc hl
        djnz .dup
        ld a,(wt_n)
        cp WT_MAX
        ld hl,txt_wt_full
        jr nc,.err
.add:   ld a,(wt_n)             ; at the end
        add a,a
        ld e,a
        ld d,0
        ld bc,2
        ld a,WATCH_SLOT
        call pou_insert         ; HL = the new 2 bytes
        jr c,.mem
        ld a,(wt_na)
        ld (hl),a
        inc hl
        ld a,(wt_ni)
        ld (hl),a
        ld de,rd_o              ; "Added to watch: %QX1.0"
        ld hl,txt_wt_added
        call put_str
        ld a,(wt_ni)
        ld c,a
        ld a,(wt_na)
        ld hl,0
        ld b,0
        call op_format
        xor a
        ld (de),a
        inc de
        ld (de),a
        ld hl,rd_o
        call msg_box
        ld a,CMD_REOPEN
        ret

.mem:   ld hl,err_il_mem
        jr .err

wt_fbm:       db 3,3,3,4,4,1,1,2,2      ; ET (timers), CV (counters), Q / Q1
txt_wt_added: db "Added to watch: ",0
txt_wt_dup:   db "Already in the watch list",0
txt_wt_full:  db "The watch list is full",0

; ---- tl_about / tl_keys: Help > About / Controls
tl_about:
        ld hl,txt_about
        jp msg_box
tl_keys:
        ld hl,txt_keys
        jp msg_box

txt_about:
        db "ZX-PLC  version "
        INCBIN "VERSION"        ; the release number (file VERSION, no newline)
        db 0
        db "PLC editor and simulator",0
        db "IEC 61131-3: IL, LD, FBD",0
        db "for ZX Spectrum 128K",0
        db " ",0
        db "J.Masopust 2026",0
        db "github.com/Pomaser/zx_plc",0
        db 0
txt_keys:
        db "BREAK, EDIT",PT_TAB,"menu",0
        db "Arrows",PT_TAB,"move (CS+5..8)",0
        db "SS+Arrows",PT_TAB,"line start/end, page",0
        db "SS+ENTER",PT_TAB,"new line / LD next row",0
        db "ENTER",PT_TAB,"confirm",0
        db "DELETE",PT_TAB,"delete (CS+0)",0
        db "Letters",PT_TAB,"hotkeys",0
        db "SS+U  SS+Y",PT_TAB,"undo  redo",0
        db "SS+X",PT_TAB,"cross references",0
        db "SS+W",PT_TAB,"add to watch",0
        db "SS+A D F",PT_TAB,"mark  copy  paste",0
        db "SS+I",PT_TAB,"LD: insert element",0
        db 0
