; ============================================================
; pou.asm - obrazovka správy POU
; ============================================================
POU_LIST_ROW EQU 5

scr_pou:
        call screen_begin
        ld hl,txt_pou_title
        call scr_puts
        ld hl,hint_pou
        call ui_hints
.redraw:
        call pou_draw_list
.key:   call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jr z,.edit
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
        jr .key
.up:    ld a,(cur_pou)
        call pou_prev
        jr c,.key
        ld (cur_pou),a
        jr .redraw
.down:  ld a,(cur_pou)
        call pou_next
        jr c,.key
        ld (cur_pou),a
        jr .redraw
.edit:  ld a,SCR_EDIT
        ret
.menu:  call menu_switch
        ret nz
        jr .key

.new:   ld a,(PROJ+P_NPOU)
        cp MAX_POU
        jr c,.n1
        ld hl,err_pou_full
        call ui_error
        jr .key
.n1:    xor a
        ld (name_buf),a
        ld a,0xFF
        call input_pou_name
        jr c,.key
        call ui_choose_lang
        jr c,.key
        ld hl,name8
        call pou_add
        jr c,.key
        ld (cur_pou),a
        jp .redraw

.rename:
        ld a,(cur_pou)
        or a
        jr nz,.r1
        ld hl,err_main_ren
        call ui_error
        jp .key
.r1:    call pou_entry
        ld de,name_buf
        call name_unpad
        ld a,(cur_pou)
        call input_pou_name
        jp c,.key
        ld a,(cur_pou)
        call pou_entry
        ex de,hl
        ld hl,name8
        ld bc,8
        ldir
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
        ld a,(cur_pou)
        call pou_entry
        ld de,PE_LANG
        add hl,de
        ld (hl),b
        jp .redraw

; ---- input_pou_name: A = vlastní slot (0xFF = nová) ; name_buf = počáteční text
;      NC: name8 = platné jméno, C = zrušeno
input_pou_name:
        ld (ipn_slot),a
.again: ld a,ATTR_INPUT
        ld (cur_attr),a
        ld bc,0x1602
        call scr_clear_rows
        ld bc,0x1601
        ld (cur_col),bc
        ld hl,txt_name_q
        call scr_puts
        ld hl,name_buf
        ld bc,0x1707
        ld de,0x0801
        call ui_input
        push af
        call ui_hints_restore
        pop af
        ret c
        ; kontrola znaků
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
.chkok: ; nesmí být operand (adresa, FB, klíčové slovo)
        ld hl,name_buf
        call op_parse
        jr c,.notop
        and AR_MASK
        cp AR_POU
        jr z,.dup
        ld hl,err_reserved
        call ui_error
        jr .again
.dup:   ld a,(ipn_slot)
        cp c
        jr z,.notop2        ; vlastní jméno (přejmenování beze změny)
        ld hl,err_name_used
        call ui_error
        jr .again
.notop: ; jméno IL instrukce je také rezervované - doplní se ve fázi 2
.notop2:
        ld hl,name_buf
        call name_pad
        or a
        ret

ipn_slot: db 0
name_buf: ds 10

; ---- pou_draw_list
pou_draw_list:
        ld a,ATTR_TITLE
        ld (cur_attr),a
        ld bc,(POU_LIST_ROW-1)*256+1
        ld (cur_col),bc
        ld hl,txt_pou_hdr
        call scr_puts
        ld b,0
.row:   push bc
        ld a,b
        add a,POU_LIST_ROW
        ld b,a
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        ld c,1
        call scr_clear_rows
        pop bc
        push bc
        ld a,b
        call pou_used
        jr z,.next
        ld a,(cur_pou)
        cp b
        jr nz,.nsel
        ld a,ATTR_SEL
        ld (cur_attr),a
.nsel:  ld a,b
        add a,POU_LIST_ROW
        ld b,a
        ld c,1
        ld (cur_col),bc
        pop bc
        push bc
        ld a,b
        add a,'0'
        call scr_putc
        ld b,3
        call scr_spaces
        pop bc
        push bc
        ld a,b
        call pou_entry
        ld b,8
        call scr_putsn
        ld b,3
        call scr_spaces
        pop bc
        push bc
        ld a,b
        call pou_lang
        call lang_name
        ld b,3
        call scr_putsn
        ld b,3
        call scr_spaces
        pop bc
        push bc
        ld a,b
        call pou_body
        ld h,b
        ld l,c
        ld b,6
        call scr_unum_r
        ld b,3
        call scr_spaces
.next:  pop bc
        inc b
        ld a,b
        cp MAX_POU
        jr c,.row
        ; volná paměť
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        ld bc,(POU_LIST_ROW+MAX_POU+1)*256+1
        ld (cur_col),bc
        ld hl,txt_free
        call scr_puts
        call proj_free
        ld b,6
        call scr_unum_r
        ld hl,txt_bytes
        jp scr_puts

txt_pou_title:
        db SC_AT,2,1,SC_ATTR,ATTR_TITLE,"PROGRAM ORGANIZATION UNITS",SC_ATTR,ATTR_NORMAL,0
txt_pou_hdr:
        db "#   NAME       LANG    SIZE",0
txt_free:  db "Free memory:",0
txt_bytes: db " bytes",0
hint_pou:
        db " ENTER:edit  N:new  R:rename",SC_AT,23,0," D:delete L:language BREAK:menu",0
txt_name_q:    db "POU name (A-Z,0-9,_):",0
txt_del_q:     db "Delete selected POU?",0
err_pou_full:  db "Max. 8 POUs",0
err_main_ren:  db "MAIN cannot be renamed",0
err_main_del:  db "MAIN cannot be deleted",0
err_not_empty: db "POU is not empty",0
err_bad_name:  db "Invalid name",0
err_reserved:  db "Reserved name",0
err_name_used: db "Name already used",0
