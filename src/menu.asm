; ============================================================
; menu.asm - top menu bar with drop-down submenus, popup windows
; ============================================================
; The bar is char row 0 (8 px), black on white, proportional font.
; Selection is shown by pixel inversion, never by colour.
; A drop-down / popup window is a cell aligned box; the cells it
; covers are saved to win_save and restored when it closes.
; ============================================================
MENU_N      EQU 6           ; number of top items
MENU_X0     EQU 3           ; x of the first title (its inversion starts at x=0)
MENU_GAP    EQU 7           ; gap between titles
ATTR_MENU   EQU 0x38        ; black ink, white paper
WIN_MAXC    EQU 200         ; max cells of a saved window (largest popup: 175)

; ---- top items: title, hotkey, submenu
menu_top:
        dw mt_file, mi_file
        dw mt_pou,  mi_pou
        dw mt_edit, mi_edit
        dw mt_view, mi_view
        dw mt_run,  mi_run
        dw mt_help, mi_help
mt_file: db "File",0
mt_pou:  db "POU",0
mt_edit: db "Edit",0
mt_view: db "View",0
mt_run:  db "Run",0
mt_help: db "Help",0

; submenu items: command, hotkey (upper case, not shown; not a title's letter F P E V R H,
; which the open drop-down would take), label, 0 ; list ends with 0
; (the last label of a list must not use descenders - it touches the frame)
mi_file:
        db CMD_NEW,  'N',"New project",0
        db CMD_DEMO, 'O',"Open demo",0
        db CMD_LOAD, 'L',"Load tape...",0
        db CMD_SAVE, 'S',"Save tape...",0
        db CMD_LOAD_SD,'D',"Load SD...",0
        db CMD_SAVE_SD,'W',"Save SD...",0
        db 0
mi_pou:
        db CMD_POU_MANAGE,'M',"Manage",0
        db CMD_POU_NEW,   'N',"New...",0
        db CMD_POU_RENAME,'R',"Rename/Comment...",0
        db CMD_POU_LANG,  'L',"Language...",0
        db CMD_POU_DUP,   'U',"Duplicate...",0
        db CMD_POU_DELETE,'D',"Delete",0
        db 0
mi_edit:
        db CMD_EDIT,  'E',"Edit POU",0
        db CMD_UNDO,  'U',"Undo",0
        db CMD_REDO,  'Y',"Redo",0
        db CMD_WADD,  'W',"Add to watch",0
        db CMD_SYMBOLS,'S',"Symbols",0
        db CMD_IL_INS,'I',"Insert line",0
        db CMD_IL_DEL,'D',"Delete line",0
        db CMD_MARK,  'M',"Mark block",0
        db CMD_COPY,  'C',"Copy",0
        db CMD_CUT,   'X',"Cut",0
        db CMD_PASTE, 'P',"Paste",0
        db 0
mi_view:
        db CMD_VIEW_SYM, 'S',"Symbols",0
        db CMD_VIEW_ADDR,'A',"Addresses",0
        db CMD_XREF,     'X',"Cross references",0
        db CMD_SOUND,    'O',"Sound",0
        db CMD_MOUSE,    'M',"Mouse",0
        db CMD_UR4,      'U',"UR-4 I/O",0
        db 0
mi_run:
        db CMD_RUN,  'R',"Run",0
        db CMD_STOP, 'T',"Stop",0
        db CMD_STEP, 'S',"Step",0
        db CMD_RESET,'E',"Reset",0
        db CMD_WATCH,'W',"Watch",0
        db CMD_TREND,'G',"Trend",0
        db 0
mi_help:
        db CMD_KEYS, 'C',"Controls",0
        db CMD_ABOUT,'A',"About",0
        db 0

; ---- menu_init: computes title positions
menu_init:
        ld ix,menu_x
        ld hl,menu_top
        ld c,MENU_X0
        ld b,MENU_N
.l:     push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        inc hl
        inc hl
        push hl
        ex de,hl
        call pt_width
        pop hl
        pop bc
        ld (ix+0),c
        ld (ix+MENU_N),a        ; width
        add a,MENU_GAP
        add a,c
        ld c,a
        inc ix
        djnz .l
        ret

menu_x: ds MENU_N           ; title x
menu_w: ds MENU_N           ; title width (must follow menu_x)

; ---- menu_draw_bar: draws the bar on row 0
menu_draw_bar:
        ld bc,0x0000
        ld d,32
        ld e,ATTR_MENU
        call scr_fill_attr
        ld b,0
        ld c,0
        call pix_addr
        ld e,8
.cl:    push hl
        ld b,32
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.cl
        xor a
        ld (pt_row),a
        inc a
        ld (pt_skip),a          ; text 1 px up: glyph line 1 -> screen line 0
        ld b,0
.t:     push bc
        ld a,b
        call menu_title_xy      ; HL = title, A = x
        ld (pt_x),a
        call pt_puts
        pop bc
        inc b
        ld a,b
        cp MENU_N
        jr c,.t
        xor a
        ld (pt_skip),a
        ; separator line (line 6 stays empty as a 1 px gap)
        ld hl,0x4700
        ld b,32
.sep:   ld (hl),0xFF
        inc l
        djnz .sep
        xor a
        ld (mp_last),a          ; force the POU name
        ; fall through

; ---- menu_pou: "NAME (LANG)" of the current POU flush right in the menu
;      bar; redrawn only when it changes
MP_COL  EQU 22              ; first cell of the name area (behind the titles)
menu_pou:
        ld de,st_buf
        ld a,(mp_alt)           ; a screen title instead of the POU
        or a
        jr z,.pou
        ld hl,txt_mp_sym
        dec a
        jr z,.alt
        ld hl,txt_mp_wt
        dec a
        jr z,.alt
        ld hl,txt_mp_tr
.alt:   call put_str
        jr .end
.pou:   ld a,(cur_pou)
        call pou_entry
        call name_unpad
        ld hl,txt_st_open
        call put_str
        ld a,(cur_pou)
        call pou_lang
        call lang_copy
        ld a,')'
        ld (de),a
        inc de
.end:   xor a
        ld (de),a
        ld hl,st_buf
        ld de,mp_last
        call str_eq
        ret z
        ld hl,st_buf
        ld de,mp_last
        call put_str
        xor a
        ld (de),a
        ld bc,MP_COL            ; clear lines 0-6 (line 7 = separator)
        call pix_addr
        ld e,7
.cl:    push hl
        ld b,32-MP_COL
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.cl
        xor a
        ld (pt_row),a
        inc a
        ld (pt_skip),a          ; 1 px up, as the titles
        ld hl,st_buf
        xor a                   ; flush right
        call pt_puts_r
        xor a
        ld (pt_skip),a
        ret

mp_last: ds 16
mp_alt:  db 0               ; 1: "Symbols", 2: "Watch" instead of the POU name
txt_mp_sym: db "Symbols",0
txt_mp_wt:  db "Watch",0
txt_mp_tr:  db "Trend",0

; A = item -> HL = title string, A = x (preserves BC)
menu_title_xy:
        push bc
        ld c,a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,menu_top
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld b,0
        ld hl,menu_x
        add hl,bc
        ld a,(hl)
        ex de,hl
        pop bc
        ret

; ---- menu_inv_title: A = item -> inverts its title area
menu_inv_title:
        ld c,a
        ld b,0
        ld hl,menu_x
        add hl,bc
        ld a,(hl)
        sub 3
        ld c,a
        ld de,MENU_N
        add hl,de
        ld a,(hl)
        add a,5
        ld d,a
        ld b,0
        ld hl,0x0007
        ld e,PX_XOR
        jp px_span

; ---- menu_items: A = item -> HL = submenu list
menu_items:
        add a,a
        add a,a
        inc a
        inc a
        ld l,a
        ld h,0
        ld de,menu_top
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ret

; ---- item_next: HL = item record -> HL = next record
item_next:
        inc hl
        inc hl
.l:     ld a,(hl)
        inc hl
        or a
        jr nz,.l
        ret

; ---- menu_open_drop: opens drop-down of item (menu_sel)
menu_open_drop:
        ld a,(menu_sel)
        call menu_items
        ld (drop_list),hl
        ; count items and max label width
        ld bc,0                 ; B = count, C = max width
.cnt:   ld a,(hl)
        or a
        jr z,.cdone
        push hl
        call menu_checkable     ; room for the check mark
        ld d,0
        jr c,.nc
        ld d,MENU_CHK_W
.nc:    inc hl
        inc hl
        call pt_width
        add a,d
        pop hl
        cp c
        jr c,.nw
        ld c,a
.nw:    inc b
        call item_next
        jr .cnt
.cdone: ld a,b
        ld (drop_n),a
        ; width = max(maxw + 8, title highlight width)
        ld a,c
        add a,8
        ld e,a
        ld a,(menu_sel)
        ld c,a
        ld b,0
        ld hl,menu_w
        add hl,bc
        ld a,(hl)
        add a,5                 ; same width as the title inversion
        cp e
        jr c,.wok
        ld e,a                  ; E = width px
.wok:   ; x0 = left edge of the title inversion, clipped to the screen
        ld hl,menu_x
        add hl,bc
        ld a,(hl)
        sub 3
        ld c,a
        add a,e
        jr nc,.fit
        xor a
        sub e
        ld c,a                  ; x0 = 256 - width
.fit:   ld b,1                  ; row 1
        ld a,(drop_n)
        inc a
        ld d,a                  ; rows: items + 1 for the bottom gap and frame
        xor a
        ld (win_top),a          ; the bar separator is the top edge
        ld a,2
        ld (win_bot),a          ; extra row: line 0 = gap, line 1 = frame
        call win_open_px
        ; labels
        ld hl,(drop_list)
        ld a,1
        ld (pt_row),a
.lab:   ld a,(hl)
        or a
        ret z
        push hl
        inc hl
        inc hl
        ld a,(win_bx)
        add a,4
        ld (pt_x),a
        call pt_puts
        ex (sp),hl              ; HL = record, (sp) = next record
        call menu_active
        jr c,.nchk
        ld a,(pt_x)             ; active option: check mark after the label
        add a,2
        ld (pt_x),a
        ld a,CH_CHECK
        call pt_putc
.nchk:  pop hl
        ld a,(pt_row)
        inc a
        ld (pt_row),a
        jr .lab

; ---- menu_checkable: HL = item record -> NC if the item is an option
;      that can be marked as active (keeps HL)
MENU_CHK_W EQU 8
menu_checkable:
        ld a,(hl)
        cp CMD_VIEW_SYM
        ret z
        cp CMD_VIEW_ADDR
        ret z
        cp CMD_SOUND
        ret z
        cp CMD_MOUSE
        ret z
        scf
        ret

; ---- menu_active: HL = item record -> NC if the option is active now
menu_active:
        ld a,(hl)
        cp CMD_SOUND
        jr z,.snd
        cp CMD_MOUSE
        jr z,.ms
        cp CMD_UR4
        jr z,.ur
        cp CMD_VIEW_SYM
        jr z,.sym
        cp CMD_VIEW_ADDR
        scf
        ret nz
        ld a,(view_sym)         ; Addresses active when symbols are off
        cp 1                    ; C if 0
        ccf
        ret
.snd:   ld a,(snd_on)
        jr .is1
.ms:    ld a,(ms_on)
        jr .is1
.ur:    ld a,(ur_on)
        jr .is1
.sym:   ld a,(view_sym)
.is1:   cp 1                    ; NC if 1
        ret

; ---- menu_inv_item: inverts row of item drop_sel in the open drop-down
menu_inv_item:
        ld a,(drop_sel)
        ld b,a
        ld a,(win_r)
        add a,b
        ld b,a                  ; char row (whole cell: the drop-down has no
        ld a,(win_bx)           ; top frame line, the bar separator is above)
        inc a
        ld c,a
        ld a,(win_bw)
        sub 2
        ld d,a
        ld hl,0x0008
        ld e,PX_XOR
        push bc
        push de
        call px_span
        pop de
        pop bc
        ld a,(drop_n)           ; last item: also the gap line above the frame
        dec a
        ld hl,drop_sel
        cp (hl)
        ret nz
        inc b
        ld hl,0x0001
        jp px_span

; ---- menu_run: interactive menu. A = command or 0 (cancelled)
menu_run:
        BCALL ms_msel           ; (opened by a click on a title)
        jr c,.m0
        ld (menu_sel),a
.m0:    ld a,(menu_sel)
        cp MENU_N
        jr c,.ok
        xor a
        ld (menu_sel),a
.ok:
.open:  ld a,(menu_sel)
        call menu_inv_title
        call menu_open_drop
        xor a
        ld (drop_sel),a
        call menu_inv_item
.key:   call kb_wait
        cp K_LEFT
        jp z,.left
        cp K_RIGHT
        jp z,.right
        cp K_UP
        jp z,.up
        cp K_DOWN
        jp z,.down
        cp K_ENTER
        jp z,.enter
        cp K_BREAK
        jp z,.cancel
        cp K_EDIT
        jr z,.edk
        cp K_MOUSE
        jr z,.mouse
        call to_upper
        ld c,a
        ; hotkey of an item in the open drop-down
        ld hl,(drop_list)
        ld b,0
.hk:    ld a,(hl)
        or a
        jr z,.hktop
        inc hl
        ld a,(hl)
        dec hl
        cp c
        jr z,.hkgo
        call item_next
        inc b
        jr .hk
.hkgo:  push bc
        call menu_inv_item
        pop bc
        ld a,b
        ld (drop_sel),a
        call menu_inv_item
        jp .enter
        ; hotkey of a top title (first letter)
.hktop: ld b,0
.ht:    ld a,b
        push bc
        call menu_title_xy
        pop bc
        ld a,(hl)
        call to_upper
        cp c
        jr z,.htgo
        inc b
        ld a,b
        cp MENU_N
        jr c,.ht
        jr .key
.edk:   BCALL ms_msel           ; a click on another title, or EDIT
        jp c,.cancel
        ld b,a
        jr .htgo
.mouse: BCALL ms_mhit           ; a click on an item, or outside
        jp c,.cancel
        ld b,a
        jr .hkgo
.htgo:  push bc
        call .close
        pop bc
        ld a,b
        ld (menu_sel),a
        jp .open
.left:  call .close
        ld a,(menu_sel)
        or a
        jr nz,.l1
        ld a,MENU_N
.l1:    dec a
        ld (menu_sel),a
        jp .open
.right: call .close
        ld a,(menu_sel)
        inc a
        cp MENU_N
        jr c,.r1
        xor a
.r1:    ld (menu_sel),a
        jp .open
.up:    call menu_inv_item
        ld a,(drop_sel)
        or a
        jr nz,.u1
        ld a,(drop_n)
.u1:    dec a
        ld (drop_sel),a
        call menu_inv_item
        jp .key
.down:  call menu_inv_item
        ld a,(drop_sel)
        inc a
        ld hl,drop_n
        cp (hl)
        jr c,.d1
        xor a
.d1:    ld (drop_sel),a
        call menu_inv_item
        jp .key
.enter: ld hl,(drop_list)
        ld a,(drop_sel)
        or a
        jr z,.e2
        ld b,a
.e1:    call item_next
        djnz .e1
.e2:    ld a,(hl)
        push af
        call .close
        pop af
        ret
.cancel:
        call .close
        xor a
        ret
.close: call win_close
        ld a,(menu_sel)
        jp menu_inv_title

menu_sel:  db 0
view_sym:  db 0             ; 1 = show symbols, 0 = show addresses (default)
drop_list: dw 0
drop_n:    db 0
drop_sel:  db 0

; ---- win_open: B = row, C = col, D = rows, E = cols (cell aligned box)
win_open:
        ld a,c
        add a,a
        add a,a
        add a,a
        ld c,a
        ld a,e
        add a,a
        add a,a
        add a,a
        ld e,a
        ; fall through
; ---- win_open_px: B = row, D = rows, C = x0 (px), E = width (px)
;      saves the covered cells, sets them black on white, clears the box
;      pixels and draws a 1 px frame (top line only if win_top != 0)
win_open_px:
        call data_in            ; win_save is in the DATA bank
        call win_open_px0
        jp data_out
win_open_px0:
        ld a,b
        ld (win_r),a
        ld a,d
        ld (win_rows),a
        ld a,c
        ld (win_bx),a
        ld a,e
        ld (win_bw),a
        ; covered cells: c0 = x0/8, cols = (x0+w-1)/8 - c0 + 1
        ld a,c
        rrca
        rrca
        rrca
        and 31
        ld (win_c),a
        ld a,c
        add a,e
        dec a
        rrca
        rrca
        rrca
        and 31
        ld hl,win_c
        sub (hl)
        inc a
        ld (win_cols),a
        ; save cells, set attributes
        ld ix,win_save
        ld a,(win_rows)
        ld d,a
        ld a,(win_r)
        ld b,a
.row:   push bc
        push de
        ld a,(win_c)
        ld c,a
        ld a,(win_cols)
        ld e,a
.cell:  push bc
        call pix_addr
        ld d,8
.px:    ld a,(hl)
        ld (ix+0),a
        inc ix
        inc h
        dec d
        jr nz,.px
        pop bc
        push bc
        call win_inner          ; fully inside the box -> clear it now
        jr nc,.keep
        call pix_addr
        ld d,8
.cz:    ld (hl),0
        inc h
        dec d
        jr nz,.cz
.keep:  pop bc
        push bc
        call attr_addr
        ld a,(hl)
        ld (ix+0),a
        ld (hl),ATTR_MENU
        inc ix
        pop bc
        inc c
        dec e
        jr nz,.cell
        pop de
        pop bc
        push bc
        push de
        ; clear the box pixels in the partially covered edge cells
        ld a,(win_bx)
        ld c,a
        and 7
        jr z,.nle
        neg
        add a,8                 ; pixels up to the cell boundary
        ld d,a
        ld a,(win_bw)
        cp d
        jr nc,.lw
        ld d,a
.lw:    call win_lines
        ld e,PX_CLR
        push bc
        call px_span
        pop bc
.nle:   ld a,(win_bx)
        ld d,a
        ld a,(win_bw)
        add a,d                 ; x end (exclusive), 0 = 256
        ld d,a
        and 7
        jr z,.nre
        ld e,a                  ; pixels in the last cell
        ld a,d
        and 0xF8
        ld c,a
        ld d,e
        call win_lines
        ld e,PX_CLR
        call px_span
.nre:   pop de
        pop bc
        inc b
        dec d
        jp nz,.row
        ; frame
        call win_geom           ; B=row0 C=x0 D=width L=last row
        ld a,(win_top)
        or a
        jr z,.notop
        push bc
        push de
        push hl
        ld hl,0x0001            ; top line
        ld e,PX_SET
        call px_span
        pop hl
        pop de
        pop bc
.notop: ld a,1
        ld (win_top),a          ; default for the next window
        push bc
        push de
        push hl
        ld b,l
        ld a,(win_bot)
        dec a
        ld h,a                  ; last used line of the last row
        ld l,1
        ld e,PX_SET
        call px_span
        pop hl
        pop de
        pop bc
        ; vertical lines
        ld a,(win_rows)
.vl:    push af
        push bc
        push de
        ld d,1
        call win_lines
        ld e,PX_SET
        push bc
        call px_span
        pop bc
        pop de
        push de
        ld a,c
        add a,d
        dec a
        ld c,a
        ld d,1
        call win_lines
        ld e,PX_SET
        call px_span
        pop de
        pop bc
        inc b
        pop af
        dec a
        jr nz,.vl
        ld a,8
        ld (win_bot),a          ; default for the next window
        ret

; win_lines: B = char row -> H = 0, L = lines used (win_bot in the last row, else 8)
win_lines:
        ld a,(win_r)
        ld l,a
        ld a,(win_rows)
        add a,l
        dec a
        cp b
        ld hl,0x0008
        ret nz
        ld a,(win_bot)
        ld l,a
        ret

; win_inner: B = row, C = col -> carry if the cell lies fully inside the box
;            (all 8 lines used and both cell edges inside [bx, bx+bw)); keeps BC, DE
win_inner:
        push de
        push hl
        call win_lines
        ld a,l
        pop hl
        cp 8
        jr nz,.no
        ld a,c
        add a,a
        add a,a
        add a,a                 ; cell x
        ld e,a
        ld a,(win_bx)
        dec a
        cp e
        jr c,.l_ok              ; bx <= cell x  (bx-1 < x)
        ld a,(win_bx)
        or a
        jr nz,.no
.l_ok:  ld a,(win_bx)
        ld d,a
        ld a,(win_bw)
        add a,d                 ; end (0 = 256)
        jr z,.yes
        sub 8
        jr c,.no
        cp e
        jr c,.no                ; end-8 < x -> cell sticks out
.yes:   pop de
        scf
        ret
.no:    pop de
        or a
        ret

; win_geom: B = first row, C = x0, D = width px, L = last row
win_geom:
        ld a,(win_r)
        ld b,a
        ld a,(win_rows)
        add a,b
        dec a
        ld l,a
        ld a,(win_bx)
        ld c,a
        ld a,(win_bw)
        ld d,a
        ret

; ---- win_close: restores the saved cells
win_close:
        call data_in
        call win_close0
        jp data_out
win_close0:
        ld ix,win_save
        ld a,(win_rows)
        ld d,a
        ld a,(win_r)
        ld b,a
.row:   push bc
        push de
        ld a,(win_c)
        ld c,a
        ld a,(win_cols)
        ld e,a
.cell:  push bc
        call pix_addr
        ld d,8
.px:    ld a,(ix+0)
        ld (hl),a
        inc ix
        inc h
        dec d
        jr nz,.px
        pop bc
        push bc
        call attr_addr
        ld a,(ix+0)
        ld (hl),a
        inc ix
        pop bc
        inc c
        dec e
        jr nz,.cell
        pop de
        pop bc
        inc b
        dec d
        jr nz,.row
        ret

win_c:    db 0
win_r:    db 0
win_cols: db 0
win_rows: db 0
win_top:  db 1             ; 0 = window without top frame line
win_bot:  db 8             ; pixel lines used in the last row
win_bx:   db 0             ; box x (px)
win_bw:   db 0             ; box width (px)

; ---- msg_box: HL = lines (each 0-terminated, list ends with an empty line)
;      shows a centred popup and waits for a key
msg_box:
        call popup_open
        call kb_wait
        call win_close
        ret

; ---- popup_open: HL = lines -> opens a centred window and draws the lines
;      (one empty margin row above and below the text)
popup_open:
        ld (mb_text),hl
        ld bc,0                 ; B = lines, C = max width
.cnt:   ld a,(hl)
        or a
        jr z,.cd
        push bc
        call pt_width_full
        pop bc
        cp c
        jr c,.n
        ld c,a
.n:     inc b
.sk:    ld a,(hl)
        inc hl
        or a
        jr nz,.sk
        jr .cnt
.cd:    ; rows = lines + 2, cols = (maxw + 16 + 7) / 8
        ld a,b
        add a,2
        ld d,a
        ld a,c
        add a,16+7
        rrca
        rrca
        rrca
        and 31
        ld e,a
        ld a,32
        sub e
        srl a
        ld c,a
        ld a,24
        sub d
        srl a
        ld b,a
        call win_open
        ld a,(win_r)
        inc a
        ld (pt_row),a
        ld a,(win_bx)
        add a,8
        ld (mb_x),a
        add a,MB_TAB
        ld (pt_tab),a
        ld hl,(mb_text)
.ln:    ld a,(hl)
        or a
        jr z,.wait
        ld a,(mb_x)
        ld (pt_x),a
        call pt_puts
        ld a,(pt_row)
        inc a
        ld (pt_row),a
        jr .ln
.wait:  ret

MB_TAB  EQU 64

; pt_width_full: HL = line, A = width incl. TAB column (preserves HL)
pt_width_full:
        push hl
        ld b,0
.l:     ld a,(hl)
        or a
        jr z,.e
        cp PT_TAB
        jr nz,.c
        ld a,b
        cp MB_TAB
        jr nc,.n
        ld b,MB_TAB
        jr .n
.c:     call pt_charw
        add a,b
        ld b,a
.n:     inc hl
        jr .l
.e:     ld a,b
        pop hl
        ret

txt_no_undo: db "Nothing to undo",0
txt_no_redo: db "Nothing to redo",0
mb_text: dw 0
mb_x:    db 0

; ---- menu_handle: runs the menu and executes global commands in place.
;      Z = nothing left to do; NZ + A = command for the screen / main loop
; menu_key: the menu, or the command of a shortcut key set by the editor in
;      mk_cmd (SS+U -> CMD_UNDO); same results as menu_handle
menu_key:
        ld a,(mk_cmd)
        or a
        jr z,menu_handle
        push af
        xor a
        ld (mk_cmd),a
        pop af
        jr menu_cmd
mk_cmd: db 0

menu_handle:
        call menu_run
; menu_cmd: A = command (also for shortcut keys such as SS+U)
menu_cmd:
        or a
        ret z
        cp CMD_UNDO
        jr z,.undo
        cp CMD_REDO
        jr z,.redo
        cp CMD_ABOUT
        jp z,.about
        cp CMD_KEYS
        jp z,.keys
        cp CMD_LOAD
        jp z,.load
        cp CMD_LOAD_SD          ; (A tells tape / SD card)
        jp z,.load
        cp CMD_SAVE
        jp z,.save
        cp CMD_SAVE_SD
        jp z,.save
        cp CMD_NEW
        jp z,.new
        cp CMD_DEMO
        jp z,.demo
        cp CMD_VIEW_SYM
        jr z,.vsym
        cp CMD_VIEW_ADDR
        jr z,.vadr
        cp CMD_SOUND
        jr z,.snd
        cp CMD_UR4
        jr nz,.nur
        BCALL ur_toggle
        xor a
        ret
.nur:   cp CMD_MOUSE
        jr nz,.nms
        BCALL ms_toggle
        xor a
        ret
.nms:   or a
        ret
.snd:   ld a,(snd_on)
        xor 1
        ld (snd_on),a
        xor a                   ; nothing else to do
        ret
.redo:  call redo_do
        ld hl,txt_no_redo
        jr .ur
.undo:  call undo_do
        ld hl,txt_no_undo
.ur:    jr nc,.ud
        call ui_error
        xor a
        ret
.ud:    ld a,(cur_pou)          ; (the POU may be gone)
        call pou_used
        jr nz,.uk
        xor a
        ld (cur_pou),a
.uk:    ld a,CMD_REOPEN
        or a
        ret
.vsym:  ld a,1
        jr .view
.vadr:  xor a
.view:  ld (view_sym),a
        ld a,CMD_REDRAW         ; the screen redraws itself
        or a
        ret
.about: BCALL tl_about        ; (texts in the DEMO bank)
        xor a
        ret
.keys:  BCALL tl_keys
        xor a
        ret
.load:  BCALL tape_load         ; A = command (NZ) or 0 (EDIT bank)
        ret
.save:  BCALL tape_save         ; (EDIT bank)
        xor a
        ret
.demo:  ld hl,txt_new_q
        call ui_confirm
        jr nz,.no
        call proj_load_demo
        ld a,CMD_POU_MANAGE
        or a
        ret
.new:   ld hl,txt_new_q
        call ui_confirm
        jr nz,.no
        BCALL ui_choose_lang
        jr c,.no
        call proj_new
        ld a,CMD_POU_MANAGE
        or a
        ret
.no:    xor a
        ret

txt_new_q:     db "Discard current project?",0
