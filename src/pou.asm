; ============================================================
; pou.asm - POU management screen
; ============================================================
POU_LIST_ROW EQU 3            ; header on row 2

scr_pou:
        call screen_begin
        call pou_draw_header
        call pou_draw_list
        ld hl,pou_pending       ; command requested from another screen
        ld a,(hl)
        ld (hl),0
        or a
        jp .cmd
.redraw:
        call pou_draw_list
.key:   call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_PGUP               ; SS+UP / SS+DOWN: first / last POU
        jr z,.first
        cp K_PGDN
        jr z,.last
        cp K_ENTER
        jr z,.edit
        cp K_UNDO
        jr z,.undk
        cp K_XREF
        jr z,.xrk
        cp K_BREAK
        jr z,.menu
        cp K_EDIT
        jr z,.menu
        call to_upper
        cp 'E'
        jr z,.edit
        cp 'N'
        jp z,.new
        cp 'R'
        jp z,.rename
        cp 'D'
        jp z,.delete
        cp 'L'
        jp z,.lang
        cp 'C'
        jp z,.cmt
        jr .key
.first: xor a                   ; MAIN (NC)
        jr .move
.last:  ld a,(cur_pou)
.lst:   push af
        call pou_next
        jr c,.lend
        pop bc
        jr .lst
.lend:  pop af
        or a
        jr .move
.up:    ld a,(cur_pou)
        call pou_prev
        jr .move
.down:  ld a,(cur_pou)
        call pou_next
.move:  jp c,.key
        push af                 ; only the selection bar moves
        call pou_inv_sel
        pop af
        ld (cur_pou),a
        call pou_inv_sel
        call menu_pou           ; (redraws only if the text changed)
        jp .key
.edit:  ld a,CMD_EDIT
        ret
.xrk:   ld a,CMD_XREF           ; SS+X: calls of this POU
        ld (mk_cmd),a
        jr .menu
.undk:  ld a,CMD_UNDO           ; SS+U: undo through the menu path
        ld (mk_cmd),a
.menu:  call menu_key
.cmd:   jp z,.key
        cp CMD_XREF
        jr nz,.nx
        ld a,(cur_pou)
        ld c,a
        ld a,AR_POU
        BCALL xref_show
        ret
.nx:
        cp CMD_POU_NEW
        jp z,.new
        cp CMD_POU_RENAME
        jp z,.rename
        cp CMD_POU_DELETE
        jp z,.delete
        cp CMD_POU_LANG
        jp z,.lang
        ret

.new:   ld a,(PROJ+P_NPOU)
        cp MAX_POU
        jr c,.n1
        ld hl,err_pou_full
        call ui_error
        jp .key
.n1:    xor a
        ld (name_buf),a
        ld a,0xFF
        call input_pou_name
        jp c,.key
        call ui_choose_lang
        jp c,.key
        ld hl,name8
        call pou_add
        jp c,.key
        ld (cur_pou),a
        call input_pou_cmt
        jp .redraw

.cmt:   ld a,(cur_pou)
        call input_pou_cmt
        jp .redraw

.rename:                        ; name (not for MAIN) and comment
        ld a,(cur_pou)
        or a
        jr z,.rcmt
        call pou_entry
        ld de,name_buf
        call name_unpad
        ld a,(cur_pou)
        call input_pou_name
        jp c,.key
        call undo_save
        ld a,(cur_pou)
        call pou_entry
        ex de,hl
        ld hl,name8
        ld bc,8
        ldir
        call pou_draw_list      ; show the new name before the comment
.rcmt:  ld a,(cur_pou)
        call input_pou_cmt
        jp .redraw

.delete:
        ld a,(cur_pou)
        or a
        jr nz,.d1
        ld hl,err_main_del
        call ui_error
        jp .key
.d1:    ld hl,txt_del_q
        call ui_confirm
        jp nz,.key
        ld a,(cur_pou)
        call pou_remove
        ld a,(cur_pou)
        call pou_prev
        ld (cur_pou),a
        jp .redraw

.lang:  ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        jr z,.l1
        ld hl,err_not_empty
        call ui_error
        jp .key
.l1:    call ui_choose_lang
        jp c,.key
        ld b,a
        call undo_save
        ld a,(cur_pou)
        call pou_entry
        ld de,PE_LANG
        add hl,de
        ld (hl),b
        jp .redraw

; ---- input_pou_name: A = own slot (0xFF = new) ; name_buf = initial text
;      NC: name8 = valid name, C = cancelled
input_pou_name:
        ld (ipn_slot),a
.again: ld hl,txt_name_q
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8                 ; same x as the popup text
        ld c,a
        ld hl,name_buf
        ld de,0x0801
        call ui_input
        push af
        call win_close
        pop af
        ret c
        ; check characters
        ld hl,name_buf
        ld a,(hl)
        call is_alpha
        jr c,.bad
.chk:   inc hl
        ld a,(hl)
        or a
        jr z,.chkok
        cp '_'
        jr z,.chk
        call is_alpha
        jr nc,.chk
        call is_digit
        jr nc,.chk
.bad:   ld hl,err_bad_name
        call ui_error
        jr .again
.chkok: ; must not be an operand (address, FB, keyword)
        ld hl,name_buf
        call op_parse
        jr c,.notop
        and AR_MASK
        cp AR_POU
        jr z,.dup
        ld hl,name_buf          ; the name of a symbol?
        call sym_find_name
        ld hl,err_sym_used
        jr nc,.rerr
        ld hl,err_reserved
.rerr:  call ui_error
        jr .again
.dup:   ld a,(ipn_slot)
        cp c
        jr z,.notop2        ; own name (rename without change)
        ld hl,err_name_used
        call ui_error
        jr .again
.notop: ; IL instruction names are reserved too
        ld hl,name_buf
        call il_mnem_find
        jr c,.notop2
        ld hl,err_reserved
        call ui_error
        jp .again
.notop2:
        ld hl,name_buf
        call name_pad
        or a
        ret

ipn_slot: db 0
name_buf: ds 10

; ---- pou_draw_list: header and the used POUs in the proportional font,
;      selected row inverted, black on white
PL_X_NAME EQU 3               ; aligned with the File title
PL_X_LANG EQU 56
PL_X_SIZE EQU 124             ; right edge of the Size column
PL_X_CMT  EQU 130
pou_draw_header:
        ld bc,(POU_LIST_ROW-1)*256      ; column names in dark blue
        ld de,0x2000+ATTR_TITLE
        call scr_fill_attr
        ld b,POU_LIST_ROW-1
        call pt_clear_row
        ld a,POU_LIST_ROW-1
        ld (pt_row),a
        ld a,PL_X_NAME
        ld (pt_x),a
        ld hl,txt_h_name
        call pt_puts
        ld a,PL_X_LANG
        ld (pt_x),a
        ld hl,txt_h_lang
        call pt_puts
        ld hl,txt_h_size
        ld a,PL_X_SIZE
        call pt_puts_r
        ld a,PL_X_CMT
        ld (pt_x),a
        ld hl,txt_h_cmt
        jp pt_puts

pou_draw_list:
        ; clear the list rows
        ld b,POU_LIST_ROW
.clr:   push bc
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
        cp POU_LIST_ROW+MAX_POU
        jr c,.clr
        ; used slots one below the other
        ld a,POU_LIST_ROW
        ld (pt_row),a
        ld b,0
.slot:  push bc
        ld a,b
        call pou_used
        jr z,.next
        ld (pl_slot),a
        ; name
        ld a,PL_X_NAME
        ld (pt_x),a
        ld a,(pl_slot)
        call pou_entry
        ld de,pl_buf
        call name_unpad
        ld hl,pl_buf
        call pt_puts
        ; language
        ld a,PL_X_LANG
        ld (pt_x),a
        ld a,(pl_slot)
        call pou_lang
        ld de,pl_buf
        call lang_copy
        ld hl,pl_buf
        call pt_puts
        ; size
        ld a,(pl_slot)
        call pou_body
        ld h,b
        ld l,c
        ld de,pl_buf
        call utoa16
        ld hl,pl_buf
        ld a,PL_X_SIZE
        call pt_puts_r
        ; comment
        ld a,(pl_slot)
        call pou_cmt
        ld a,PL_X_CMT
        ld (pt_x),a
        ld hl,pl_cbuf
        call pt_puts
        ld hl,pt_row
        inc (hl)
.next:  pop bc
        inc b
        ld a,b
        cp MAX_POU
        jp c,.slot
        call pou_inv_sel
        call menu_pou           ; these parts redraw only when they change
        call status_left
        jp status_right

; ---- pou_inv_sel: XORs the selection bar of the current POU
pou_inv_sel:
        ld c,POU_LIST_ROW       ; row = list row + used slots before cur_pou
        ld b,0
.l:     ld a,(cur_pou)
        cp b
        jr z,.go
        ld a,b
        call pou_used
        jr z,.n
        inc c
.n:     inc b
        jr .l
.go:    ld b,c
        ld c,0
        ld d,255
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; ---- pou_cmt: A = slot -> pl_cbuf = its comment (0-terminated)
pou_cmt:
        call pou_entry
        ld de,PE_CMT
        add hl,de
        ld de,pl_cbuf
        ld bc,POU_CMAX
        ldir
        xor a
        ld (de),a
        ret

; ---- pou_set_cmt: A = slot, pl_cbuf = comment -> stored in the POU table
pou_set_cmt:
        call undo_save
        call pou_entry
        ld de,PE_CMT
        add hl,de
        ex de,hl
        ld hl,pl_cbuf
        ld bc,POU_CMAX
        ldir
        ret

; ---- input_pou_cmt: A = slot -> popup to edit the comment; C = cancelled
input_pou_cmt:
        ld (pl_slot),a
        call pou_cmt
        ld hl,txt_cmt_q
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,pl_cbuf
        ld de,POU_CMAX*256+4    ; case kept, first letter as with CAPS LOCK
        call ui_input
        push af
        call win_close
        pop af
        ret c
        ld a,(pl_slot)
        jp pou_set_cmt

pl_slot: db 0
pl_cbuf: ds POU_CMAX+1
pl_buf: ds 10

txt_h_name: db "POU Name",0
txt_h_lang: db "Language",0
txt_h_size: db "Size",0
txt_h_cmt:  db "Comment",0
txt_cmt_q:  db "Comment for the POU (optional):",0," ",0," ",0,0
txt_name_q:    db "POU name (A-Z, 0-9, _):",0," ",0," ",0,0
txt_del_q:     db "Delete selected POU?",0
err_sym_used:  db "Name used by a symbol",0
err_pou_full:  db "Max. 8 POUs",0
err_main_del:  db "MAIN cannot be deleted",0
err_not_empty: db "POU is not empty",0
