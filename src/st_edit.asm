; ============================================================
; st_edit.asm - Structured Text editor (bank BANK_FBD)
; ============================================================
; Own line editor on the principles of the IL editor: rows 1-22, one
; line per row, line numbers in cells 0-2, separator at x=23.
; POU body = line records [len][K_STXT][indent][text...] (st_lex.asm
; tokenizes the text, module ste). The indent (block depth) is computed
; from the line above: +1 after a line ending with THEN / ELSE / DO / OF /
; REPEAT (or an UNTIL line), -1 for a line starting with END_* / ELSE /
; ELSIF / UNTIL. Keywords start on an 8 px cell (x = 8k+1) and the text
; after them on the next cell, so whole cells of a keyword are coloured
; dark blue; comments are dark green to the end of the row.
; Leaving a line checks it (characters, names) and stores it with the
; keywords in upper case and single spaces between tokens.
; ============================================================
ST_ROW0  EQU 1
ST_ROWS  EQU 22
ST_X_NUM EQU 21             ; right edge of the line number
ST_X_SEP EQU 23
ST_X0    EQU 25             ; text start (cell 3 + 1)
ST_BLEN  EQU 60             ; max. characters of a line
ST_IMAX  EQU 12             ; max. indent (cells)
ST_SIM_COL EQU 25           ; simulation: the values from this cell (SIM_VCOL)

; ---- st_editor: screen handler for an ST POU, returns a command in A
st_editor:
        call screen_begin
        ld hl,0xFFFF            ; no marked block
        ld (mk_a),hl
        xor a
        ld (sr_sim),a
        ld a,(xr_jf)            ; opened from the cross references / an error
        or a
        jr z,.nj
        xor a
        ld (xr_jf),a
        ld a,(cur_pou)
        ld (st_pou),a
        ld hl,(xr_jl)
        ld (st_cur),hl
        ld (st_top),hl
        jr .same
.nj:    ld a,(cur_pou)
        ld hl,st_pou
        cp (hl)
        jr z,.same
        ld (hl),a
        ld hl,0
        ld (st_cur),hl
        ld (st_top),hl
.same:  call st_count
        ld hl,(st_n)
        ld a,h
        or l
        jr nz,.has
        ld de,0
        ld hl,st_nothing
        xor a
        call st_ins_line        ; an ST POU always has at least one line
.has:   ld hl,(st_cur)
        ld de,(st_n)
        or a
        sbc hl,de
        jr c,.okc
        ld hl,(st_n)
        dec hl
        ld (st_cur),hl
.okc:   call st_load
        call st_fix_top
.full:  call st_redraw_all
        call xr_errmsg          ; (after a jump to a compile error)
.loop:  call .mkd
        call st_key
        cp K_ENTER
        jp z,.enter
        cp K_SSENTER
        jp z,.ssent
        cp K_UP
        jp z,.up
        cp K_DOWN
        jp z,.down
        cp K_LEFT
        jp z,.left
        cp K_RIGHT
        jp z,.right
        cp K_HOME
        jp z,.home
        cp K_END
        jp z,.end
        cp K_PGUP
        jp z,.pgup
        cp K_PGDN
        jp z,.pgdn
        cp K_DEL
        jp z,.del
        cp K_MOUSE
        jp z,.mouse
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        ld b,CMD_WADD
        cp K_WATCH
        jp z,.mkc
        ld b,CMD_XREF
        cp K_XREF
        jp z,.mkc
        ld b,CMD_UNDO
        cp K_UNDO
        jp z,.mkc
        ld b,CMD_REDO
        cp K_REDO
        jp z,.mkc
        cp K_MARK               ; SS+A / SS+D / SS+F: mark, copy, paste
        jr c,.kc
        cp K_PASTE+1
        jr nc,.kc
        add a,CMD_MARK-K_MARK
        ld b,a
        jp .mkc
.kc:    cp 32
        jr c,.loop
        cp 128
        jr nc,.loop
        cp ' '                  ; a space after a keyword: in upper case
        push af
        call z,st_kwup
        pop af
        call st_insert
        call c,beep
.redraw:                        ; text part only
        call st_draw_cur_text
        jp .loop
.redrawf:                       ; whole row incl. inverted line number
        call st_draw_cur
        jp .loop

        ; ---- cursor
.left:  ld a,(st_pos)
        or a
        jp z,.loop
        dec a
        ld (st_pos),a
        jp .loop
.right: call st_len
        ld b,a
        ld a,(st_pos)
        cp b
        jp nc,.loop
        inc a
        ld (st_pos),a
        jp .loop
.home:  xor a
        ld (st_pos),a
        jp .loop
.end:   call st_len
        ld (st_pos),a
        jp .loop

        ; ---- DELETE (backspace); on an empty line: the line is removed
.del:   ld a,(st_pos)
        or a
        jr z,.del0
        dec a
        ld (st_pos),a
        call st_del_char
        jr .redraw
.del0:  call st_len
        or a
        jp nz,.loop
        ld hl,(st_n)
        dec hl
        ld a,h
        or l
        jp z,.loop
        ld de,(st_cur)
        call st_del_line
        ld hl,(st_cur)
        ld a,h
        or l
        jr z,.d2
        dec hl
        ld (st_cur),hl
.d2:    ld de,(st_cur)
        call st_reind
        call st_load
        call st_fix_top
        jp nz,.full
        call st_row_cur
        call st_redraw_from
        jp .loop

        ; ---- ENTER: the line is split at the cursor, the rest goes to a
        ;      new line below (cursor at its start)
.enter: ld a,(st_pos)            ; (not in front of VAR on line 0)
        or a
        call z,.var0
        jp z,.loop
        ld hl,se_buf
        ld a,(st_pos)
        ld e,a
        ld d,0
        add hl,de
        ld de,st_tail
        call put_str
        xor a
        ld (de),a
        ld hl,se_buf
        ld a,(st_pos)
        ld e,a
        ld d,0
        add hl,de
        ld (hl),0
        call .comment           ; (auto-declaration allowed)
        jr nc,.en1
        ld hl,st_tail           ; error: the line as it was
        ld de,se_buf
        call strcat
        jp .loop
.en1:   call .tolast
        ld hl,st_tail           ; (leading spaces dropped)
.en2:   ld a,(hl)
        cp ' '
        jr nz,.en3
        inc hl
        jr .en2
.en3:   ld a,(hl)               ; at the end of IF c / WHILE c / ...:
        or a                    ; the construct is completed
        jr nz,.en4
        push hl
        call .auto
        pop hl
        jp c,.loop
.en4:   push hl
        call .newok
        pop hl
        jp c,.loop
        ld de,(st_cur)
        inc de
        ld a,(st_ind)
        call st_ins_line
        jp c,.loop
        xor a
        jr .newl
        ; ---- SS+ENTER: a new empty line below
.ssent: call .comment
        jp c,.loop
        call .tolast
        call .newok
        jp c,.loop
        ld de,(st_cur)
        inc de
        ld hl,st_nothing
        ld a,(st_ind)
        call st_ins_line
        jp c,.loop
        ld a,0xFF               ; cursor at the end
.newl:  ld (st_npos),a
        ld hl,(st_cur)
        inc hl
        ld (st_cur),hl
        ex de,hl
        call st_reind
        call st_load
        ld a,(st_npos)
        inc a
        jr z,.nl1
        dec a
        ld (st_pos),a
.nl1:   call st_fix_top
        jp nz,.full
        call st_row_cur
        dec a
        call st_redraw_from
        jp .loop
.comment:                       ; st_commit from ENTER: unknown names may
        ld a,1                  ; be declared (st_decl)
        ld (st_dcok),a
        call st_commit
        ld a,0
        ld (st_dcok),a
        ret
.var0:  ld hl,(st_cur)           ; Z = the cursor is on line 0 = VAR (beep)
        ld a,h
        or l
        jr nz,.v0n
        ld hl,se_buf
        ld (ste.lx_p),hl
        call ste.lx_next
        ld a,(ste.lx_type)
        cp T_KW
        jr nz,.v0n
        ld a,(ste.lx_kw)
        cp KW_VAR
        jr nz,.v0n
        call beep
        xor a
        ret
.v0n:   or 1
        ret
.tolast:                        ; a split line: the new line after its end
        ld a,(st_split)
        or a
        ret z
        call st_row_cur         ; the first part: drawn as not current
        ld (st_oldrow),a
        ld hl,(st_cur)
        ld (st_oldln),hl
        ld a,(st_split)
        ld e,a
        ld d,0
        add hl,de
        ld (st_cur),hl
        call st_load
        ld a,(st_oldrow)
        ld b,a
        ld de,(st_oldln)
        jp st_draw_row
        ; ---- .auto: ENTER at the end of "IF c" (ELSIF, WHILE, FOR, CASE,
        ;      REPEAT, VAR) whose construct is not complete yet (.acomp):
        ;      its lines are added below (THEN / empty / END_IF ...), the
        ;      cursor goes to the empty line. C = done
.auto:  ld hl,se_buf
        ld (ste.lx_p),hl
        call ste.lx_next
        ld a,(ste.lx_type)
        cp T_KW
        jr nz,.aun
        ld a,(ste.lx_kw)
        ld hl,au_tab
        ld b,AU_N
        ld de,AU_ESZ
.au1:   cp (hl)
        jr z,.au2
        add hl,de
        djnz .au1
.aun:   or a
        ret
.au2:   ld (au_p),hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)               ; a condition must follow the keyword
        or a
        jr z,.au4
.au3:   call ste.lx_next
        ld a,(ste.lx_type)
        or a
        jr z,.aun
        cp T_CMT
        jr z,.au3
.au4:   call .acomp
        jr c,.aun
        ld hl,(st_n)            ; room for 3 lines
        ld de,IL_MAXLN-3
        or a
        sbc hl,de
        jr nc,.aun
        ld hl,(au_p)            ; the lines in reverse order
        ld de,AU_ESZ-2
        add hl,de
        ld b,3
.ai:    push bc
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        or e
        jr z,.ai2
        ex de,hl
        call .auins
        jr nc,.ai2
        pop hl
        pop bc
        ret                     ; (C: out of memory, message shown)
.ai2:   pop hl
        pop bc
        dec hl
        dec hl
        djnz .ai
        call st_row_cur
        ld (st_oldrow),a
        ld hl,(au_p)
        ld de,4
        add hl,de
        ld e,(hl)               ; the cursor: the empty line
        ld d,0
        ld hl,(st_cur)
        push hl
        add hl,de
        ld (st_cur),hl
        pop de
        call st_reind_all
        call st_load
        call st_fix_top
        jr nz,.auf
        ld a,(st_oldrow)
        call st_redraw_from
        scf
        ret
.auf:   call st_redraw_all
        scf
        ret
        ; .acomp: C = the construct of line st_cur is complete already.
        ;      Next-line mode (au_chk: ELSIF): the next line starts with
        ;      THEN. Otherwise the lines below with the same indent are
        ;      THEN / ELSE / DO / ... until its END_x (deeper ones skipped)
.acomp: ld hl,(au_p)
        inc hl
        ld a,(hl)
        ld (au_chk),a
        inc hl
        ld a,(hl)
        ld (au_end),a
        ld de,(st_cur)
.ac1:   inc de
        call st_line_addr
        jr c,.acn
        push de
        ld de,st_tmp2
        call st_rec_text        ; A = its indent
        pop de
        ld b,a
        ld a,(st_ind)
        cp b
        jr c,.ac2               ; deeper
        jr nz,.acn              ; less deep: the construct ended
        push de
        ld hl,st_tmp2
        ld (ste.lx_p),hl
        call ste.lx_next
        pop de
        ld a,(ste.lx_type)
        cp T_KW
        jr nz,.acn
        ld a,(ste.lx_kw)
        ld c,a
        ld a,(au_chk)
        or a
        jr z,.ac3
        cp c
        jr z,.acy
        jr .acn
.ac3:   ld a,(au_end)
        cp c
        jr z,.acy
        push de
        ld a,c
        ld hl,au_mid
        call ii_in
        pop de
        jr nz,.acn
.ac2:   ld a,(au_chk)
        or a
        jr z,.ac1
.acn:   or a
        ret
.acy:   scf
        ret
.auins: ld de,(st_cur)          ; HL = text -> new line below st_cur
        inc de
        xor a
        jp st_ins_line
.newok: ld hl,(st_n)            ; C = too many lines (message shown)
        ld de,IL_MAXLN
        or a
        sbc hl,de
        ccf
        ret nc
        ld hl,err_st_lines
        call ui_error
        scf
        ret

        ; ---- UP / DOWN / PGUP / PGDN
.up:    call st_commit
        jp c,.loop
        ld hl,(st_cur)
        ld a,h
        or l
        jp z,.redrawf
        dec hl
        jr .move
.down:  call st_commit
        jp c,.loop
        ld hl,(st_cur)
        inc hl
        ld de,(st_n)
        or a
        sbc hl,de
        add hl,de
        jp nc,.redrawf          ; already on the last line
        jr .move
.pgup:  call st_commit
        jp c,.loop
        ld hl,(st_cur)
        ld de,ST_ROWS-1
        or a
        sbc hl,de
        jr nc,.move
        ld hl,0
        jr .move
.pgdn:  call st_commit
        jp c,.loop
        ld hl,(st_cur)
        ld de,ST_ROWS-1
        add hl,de
        ld de,(st_n)
        or a
        sbc hl,de
        add hl,de
        jr c,.move
        ex de,hl
        dec hl
.move:  push hl
        call st_row_cur
        ld (st_oldrow),a
        ld hl,(st_cur)
        ld (st_oldln),hl
        pop hl
        ld (st_cur),hl
        call st_load
        ld a,(st_mpend)         ; (a mouse click: the cursor under it)
        or a
        call nz,.mpos
        call st_fix_top
        jp nz,.full
        ld a,(st_oldrow)
        ld b,a
        ld de,(st_oldln)
        call st_draw_row
        jp .redrawf

        ; ---- mouse: a click puts the cursor on the line and character under
        ;      it; the right button is ENTER
.mouse: BCALL ms_crow
        cp ST_ROW0
        jp c,.loop
        cp ST_ROW0+ST_ROWS
        jp nc,.loop
        call st_rowline
        ex de,hl
        ld de,(st_n)            ; (below the last line: the last line)
        or a
        sbc hl,de
        add hl,de
        jr c,.ml
        ld hl,(st_n)
        dec hl
.ml:    ld a,(ms_btn)
        dec a
        jp nz,.enter
        ld de,(st_cur)
        or a
        sbc hl,de
        add hl,de
        jr z,.mf
        push hl
        call st_commit
        pop hl
        jp c,.loop
        ld de,(st_cur)          ; below a split line: lines were added
        or a
        sbc hl,de
        add hl,de
        jr c,.mup
        ld a,(st_split)
        ld e,a
        ld d,0
        add hl,de
.mup:   ld a,1
        ld (st_mpend),a
        jp .move
.mf:    call .mpos
        jp .loop
.mpos:  xor a
        ld (st_mpend),a
        ld a,(ms_cx)
        call st_pos_at
        ld (st_pos),a
        ret

        ; ---- shortcut keys through the menu path
.mkc:   ld a,b
        ld (mk_cmd),a
        ; ---- menu
.menu:  call st_commit
        jp c,.loop
        call st_draw_cur
        call menu_key
        jp z,.loop
        cp CMD_REDRAW
        jr nz,.m1
        call st_load
        jp .full
.m1:    cp CMD_WADD
        jr z,.x0
        cp CMD_XREF
        jr nz,.m2
.x0:    ld (tl_cmd),a
        call st_word_at         ; the operand under the cursor
        BCALL tl_run
        ld hl,0
        ld (st_left),hl
        ret
.m2:    cp CMD_IL_INS
        jr z,.mins
        cp CMD_IL_DEL
        jr z,.mdel
        cp CMD_MARK             ; mark / copy / paste / cut (clip.asm)
        jr c,.m3
        cp CMD_CUT+1
        jr nc,.m3
        ld de,(st_cur)
        BCALL cl_cmd
        jp z,.loop
        ld (st_cur),de
        call st_count
        ld de,0
        call st_reind_all
        jp .same
.m3:    ld hl,0
        ld (st_left),hl
        ret
.mkd:   ld hl,(st_top)          ; marker bars of the marked block
        ld a,h                  ; (folded, top 0: rows 1.. are st_fh+1..)
        or l
        jr nz,.mk1
        ld hl,(st_fh)
.mk1:
        ld de,(st_cur)
        ld bc,ST_ROWS*256+ST_ROW0
        ld a,2
        BCALL mk_draw
        ret
.mins:  call .var0              ; (not above VAR on line 0)
        jp z,.loop
        ld de,(st_cur)          ; Edit > Insert line: an empty line above
        ld hl,st_nothing
        ld a,(st_ind)
        call st_ins_line
        jp c,.loop
        ld de,(st_cur)
        call st_reind
        call st_load
        call st_row_cur
        call st_redraw_from
        jp .loop
.mdel:  ld hl,(st_n)            ; Edit > Delete line
        dec hl
        ld a,h
        or l
        jr z,.mclr
        ld de,(st_cur)
        call st_del_line
        ld hl,(st_cur)
        ld de,(st_n)
        or a
        sbc hl,de
        jr c,.md2
        ld hl,(st_n)
        dec hl
        ld (st_cur),hl
.md2:   ld de,(st_cur)
        call st_reind
        call st_load
        call st_fix_top
        jp nz,.full
        call st_row_cur
        call st_redraw_from
        jp .loop
.mclr:  xor a                   ; the only line -> make it empty
        ld (se_buf),a
        ld (st_pos),a
        call st_commit
        jp .redrawf

; .auto: [keyword][next-line keyword (0: scan to END)][its END_x]
;        [condition needed][cursor: line offset][dw 3 lines (0: none)]
AU_N    EQU 7
AU_ESZ  EQU 11
au_tab: db KW_IF,0,KW_END_IF,1,2
        dw au_then,st_nothing,au_endif
        db KW_ELSIF,KW_THEN,0,1,2
        dw au_then,st_nothing,0
        db KW_WHILE,0,KW_END_WHILE,1,2
        dw au_do,st_nothing,au_endwh
        db KW_FOR,0,KW_END_FOR,1,2
        dw au_do,st_nothing,au_endfor
        db KW_CASE,0,KW_END_CASE,1,2
        dw au_of,st_nothing,au_endcs
        db KW_REPEAT,0,KW_END_REPEAT,0,1
        dw st_nothing,au_until,au_endrp
        db KW_VAR,0,KW_END_VAR,0,1
        dw st_nothing,au_endvar,0
au_mid:   db KW_THEN,KW_ELSE,KW_ELSIF,KW_DO,KW_OF,KW_UNTIL,0
au_then:  db "THEN",0
au_do:    db "DO",0
au_of:    db "OF",0
au_until: db "UNTIL",0
au_endif: db "END_IF",0
au_endwh: db "END_WHILE",0
au_endfor: db "END_FOR",0
au_endcs: db "END_CASE",0
au_endrp: db "END_REPEAT",0
au_endvar: db "END_VAR",0
au_chk:   db 0
txt_var:  db "VAR",0
txt_sf_more: db " ..",0
SF_MAX  EQU 46                  ; summary: characters of declarations
au_end:   db 0
au_p:     dw 0

; ============================================================
; line storage
; ============================================================

; ---- st_count: st_n = number of line records
st_count:
        ld a,(cur_pou)
        call pou_body
        ld de,0
.l:     ld a,b
        or c
        jr z,.e
        push de
        ld e,(hl)
        ld d,0
        add hl,de
        push hl
        ld h,b
        ld l,c
        or a
        sbc hl,de
        ld b,h
        ld c,l
        pop hl
        pop de
        inc de
        jr .l
.e:     ld (st_n),de
        ret

; ---- st_line_addr: DE = line -> HL = record; C = DE >= st_n (HL = body
;      end). st_end = body end. Keeps DE
st_line_addr:
        push de
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (st_end),hl
        pop hl
        pop de
        push de
.l:     ld a,d
        or e
        jr z,.chk
        push de
        ld e,(hl)
        ld d,0
        add hl,de
        pop de
        dec de
        jr .l
.chk:   pop de
        push hl
        ld bc,(st_end)
        or a
        sbc hl,bc
        pop hl
        ccf
        ret

; ---- st_offset: HL = address in the body -> DE = offset
st_offset:
        push hl
        ld a,(cur_pou)
        call pou_body
        ex de,hl
        pop hl
        push hl
        or a
        sbc hl,de
        ex de,hl
        pop hl
        ret

; ---- st_rec_text: HL = record, DE = dest -> text + 0 at DE, A = indent
st_rec_text:
        ld a,(hl)
        sub 3
        ld b,a
        inc hl
        ld a,(hl)
        inc hl
        cp K_STXT
        ld a,(hl)
        inc hl
        jr z,.ok
        ld b,0                  ; (not an ST line: empty)
        xor a
.ok:    push af
        ld a,b
        or a
        jr z,.e
.c:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz .c
.e:     xor a
        ld (de),a
        pop af
        ret

; ---- st_ins_line: DE = line index, HL = text (0), A = indent
;      -> inserts the line; C = out of memory (message shown)
st_ins_line:
        ld (sl_ind),a
        push hl
        call st_line_addr
        call st_offset
        pop hl
        push hl
        call strlen
        add a,3
        ld (sl_len),a
        ld c,a
        ld b,0
        ld a,(cur_pou)
        call pou_insert
        pop de
        jr c,.mem
        ld a,(sl_len)
        ld (hl),a
        inc hl
        ld (hl),K_STXT
        inc hl
        ld a,(sl_ind)
        ld (hl),a
        inc hl
        ex de,hl
        call put_str
        ld hl,(st_n)
        inc hl
        ld (st_n),hl
        call status_right
        or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret

; ---- st_del_line: DE = line index
st_del_line:
        call st_line_addr
        call st_offset
        ld c,(hl)
        ld b,0
        ld a,(cur_pou)
        call pou_delete
        ld hl,(st_n)
        dec hl
        ld (st_n),hl
        jp status_right

; ---- st_load: line st_cur -> se_buf / st_ind, cursor at the end
st_load:
        xor a
        ld (se_buf),a
        ld de,(st_cur)
        call st_line_addr
        ld de,se_buf
        ld a,0
        call nc,st_rec_text
        ld (st_ind),a
        call st_len
        ld (st_pos),a
        ret

; ---- st_commit: checks and normalises se_buf and stores it as line
;      st_cur; the lines below get their indent. A line with a control
;      keyword not at its start (or text after THEN / ELSE / DO / OF /
;      REPEAT / END_x;) is split into more lines (st_brk); st_split = the
;      number of lines added below st_cur. C = error (message shown)
st_commit:
        xor a
        ld (st_split),a
.again: ld hl,se_buf
        call st_norm
        jr nc,.ok
        call ui_error
        scf
        ret
.ok:    call st_brk
        sbc a,a
        ld (st_brkf),a
        ld hl,st_tmp            ; record [len][K_STXT][indent][text]
        ld de,rec_buf+3
        call put_str
        ex de,hl
        ld de,rec_buf
        or a
        sbc hl,de
        ld a,l
        ld (rec_buf),a
        ld a,K_STXT
        ld (rec_buf+1),a
        ld a,(st_ind)
        ld (rec_buf+2),a
        ; unchanged? -> nothing to store
        ld de,(st_cur)
        call st_line_addr
        ld (se_cmaddr),hl
        ld a,(rec_buf)
        ld b,a
        ld de,rec_buf
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.store
        inc hl
        inc de
        djnz .cmp
        jr .stored
.store: ld hl,(se_cmaddr)
        call st_offset
        ld (se_cmoff),de
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ld a,(cur_pou)
        call pou_insert         ; new record in front of the old one
        jp c,.mem
        ex de,hl
        ld hl,rec_buf
        ld a,(rec_buf)
        ld c,a
        ld b,0
        ldir
        ld hl,(se_cmoff)
        ld a,(rec_buf)
        ld e,a
        ld d,0
        add hl,de
        ex de,hl                ; DE = offset of the old record
        push de
        ld a,(cur_pou)
        call pou_body
        pop de
        add hl,de
        ld c,(hl)
        ld b,0
        ld a,(cur_pou)
        call pou_delete
        call status_right
.stored:
        ld a,(st_brkf)          ; the rest of a split line: a new line below,
        or a                    ; split again if needed
        jr z,.fin
        ld de,(st_cur)
        inc de
        ld hl,st_spl
        ld a,(st_ind)
        call st_ins_line
        jr c,.fin
        ld hl,(st_cur)
        inc hl
        ld (st_cur),hl
        ld hl,st_spl
        ld de,se_buf
        call put_str
        xor a
        ld (de),a
        ld hl,st_split
        inc (hl)
        jp .again
.fin:   ld a,(st_split)         ; back to the first part
        ld e,a
        ld d,0
        ld hl,(st_cur)
        or a
        sbc hl,de
        ld (st_cur),hl
        ld a,(st_pos)           ; its normalised form, the cursor kept
        push af
        call st_load
        pop af
        ld hl,st_pos
        cp (hl)
        jr nc,.d1
        ld (hl),a
.d1:    ld de,(st_cur)
        ld a,(st_split)
        or a
        jr z,.ri
        call st_reind_all       ; (the added lines keep a wrong indent)
        jr .ri2
.ri:    call st_reind
.ri2:   ld a,(st_redr)          ; a declaration was added above
        or a
        jr z,.ri3
        xor a
        ld (st_redr),a
        call st_fix_top
        call st_redraw_all
        jr .done
.ri3:   call st_row_cur
        ld b,a
        ld a,(st_split)
        or a
        jr nz,.rd               ; split: this row and all below
        ld a,(ri_chg)           ; lines below changed: redraw them
        or a
        jr z,.done
        inc b
.rd:    ld a,b
        call st_redraw_from
.done:  or a
        ret
.mem:   ld hl,err_il_mem
        call ui_error
        scf
        ret

; ---- st_brk: st_tmp (normalised) -> C if it must be split: st_tmp is cut
;      before the split point, the rest goes to st_spl. Control keywords
;      (bk_start) start a line, nothing follows THEN / ELSE / DO / OF /
;      REPEAT or END_x [;] on their line (comments may). No split when the
;      POU has the maximum number of lines.
st_brk:
        ld hl,(st_n)
        ld de,IL_MAXLN
        or a
        sbc hl,de
        ret nc                  ; (NC: full)
        ld de,(st_cur)
        call st_inblk
        ld (bk_decl),a
        ld hl,st_tmp
        ld (ste.lx_p),hl
        xor a
        ld (bk_n),a
        ld (bk_aft),a
        ld (bk_end),a
.l:     call ste.lx_next
        ld a,(ste.lx_type)
        or a
        ret z                   ; (NC)
        cp T_CMT
        jr z,.l
        ld e,0
        cp T_KW
        jr nz,.nk
        ld a,(ste.lx_kw)
        ld e,a
.nk:    ld a,(bk_aft)
        or a
        jr nz,.cut
        ld a,(bk_end)           ; END_x: a ";" may follow
        or a
        jr z,.ne
        xor a
        ld (bk_end),a
        ld a,(ste.lx_type)
        cp T_SYM
        jr nz,.cut
        ld a,(ste.lx_sym)
        cp ';'
        jr nz,.cut
        ld a,1
        ld (bk_aft),a
        jr .l
.ne:    ld a,(bk_n)
        or a
        jr z,.first
        ld a,e
        ld hl,bk_start
        call ii_in
        jr z,.cut
.first: ld a,1
        ld (bk_n),a
        ld a,e
        ld hl,ii_open
        call ii_in
        jr nz,.nal
        ld a,1
        ld (bk_aft),a
.nal:   ld a,(bk_decl)          ; VAR block: one declaration per line
        or a
        jr z,.nd
        ld a,(ste.lx_type)
        cp T_SYM
        jr nz,.nd
        ld a,(ste.lx_sym)
        cp ';'
        jr nz,.nd
        ld a,1
        ld (bk_aft),a
.nd:    ld a,e
        ld hl,bk_ends
        call ii_in
        jr nz,.l
        ld a,1
        ld (bk_end),a
        jp .l
.cut:   ld hl,(ste.lx_start)
        ld de,st_spl
        call put_str
        xor a
        ld (de),a
        ld hl,(ste.lx_start)
        dec hl
        ld a,(hl)
        cp ' '
        jr z,.c1
        inc hl
.c1:    ld (hl),0
        scf
        ret

bk_start: db KW_IF,KW_THEN,KW_ELSIF,KW_ELSE,KW_CASE,KW_OF,KW_FOR,KW_DO
          db KW_WHILE,KW_REPEAT,KW_UNTIL,KW_VAR
bk_ends:  db KW_END_IF,KW_END_CASE,KW_END_FOR,KW_END_WHILE,KW_END_REPEAT
          db KW_END_VAR,0

; ---- st_norm: HL = line text -> st_tmp = normalised text (keywords in
;      upper case, one space between tokens, no spaces at the ends);
;      C + HL = error message (invalid character, open comment, unknown name)
st_norm:
        ld (ste.lx_p),hl
        ld hl,st_tmp
        ld (sn_out),hl
        ld de,(st_cur)          ; in the VAR block: the declared name (the
        call st_inblk           ; first token) is not checked
        ld (sn_decl),a
        ld (sn_inb),a
        xor a
        ld (sn_par),a
        ld (sn_lend),a
.l:     ld hl,(ste.lx_p)
        ld (sn_prev),hl
        call ste.lx_next
        ld a,(ste.lx_type)
        or a
        jp z,.end
        cp T_BAD
        ld hl,err_st_char
        scf
        ret z
        cp T_CMT
        jr nz,.nc
        ld a,(ste.lx_bad)
        or a
        ld hl,err_st_cmt
        scf
        ret nz
.nc:    call sn_semi            ; (no ";" after END_x)
        jp z,.l
        ld a,(ste.lx_type)      ; VAR ...: only on line 0
        cp T_KW
        jr nz,.nv
        ld a,(ste.lx_kw)
        sub KW_VAR
        cp 4
        jr nc,.nv
        ld hl,(st_cur)
        ld a,h
        or l
        jr z,.nv
        ld hl,err_st_var
        scf
        ret
.nv:
        ld hl,(sn_out)          ; a space in front (not at the start)
        ld de,st_tmp
        or a
        sbc hl,de
        jr z,.ns
        ld hl,(sn_prev)
        ld de,(ste.lx_start)
        or a
        sbc hl,de
        jr z,.ns
        ld hl,(sn_out)
        ld (hl),' '
        inc hl
        ld (sn_out),hl
.ns:    ld de,(sn_out)
        ld a,(ste.lx_type)
        cp T_KW
        jr nz,.raw
        ld hl,ste.lx_word
        call put_str
        jr .ce
.raw:   ld hl,(ste.lx_start)
.r:     push hl
        ld bc,(ste.lx_p)
        or a
        sbc hl,bc
        pop hl
        jr z,.ce
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .r
.ce:    ld (sn_out),de
        ld a,(ste.lx_type)
        cp T_WORD
        jr nz,.np
        ld a,(sn_decl)
        or a
        jr nz,.np0
        ld hl,ste.lx_word       ; a name / operand must be known
        call op_parse
        jr c,.unk
        ld a,(hl)
        or a
        jr z,.np0
.unk:   ld hl,(ste.lx_p)        ; the name as typed (auto-declaration)
        ld de,(ste.lx_start)
        or a
        sbc hl,de
        ld b,l
        ex de,hl
        ld de,sn_name
.u1:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz .u1
        xor a
        ld (de),a
        ld a,(cur_pou)          ; a local variable (lx_word changes)
        ld hl,ste.lx_word
        call ste.st_vfind
        jr nc,.np0
        ld a,(sn_par)           ; FB parameter: "(" / "," before, ":=" / "=>" after
        or a
        jr z,.bad
        ld hl,(ste.lx_p)
        push hl
        call ste.lx_next
        pop hl
        ld (ste.lx_p),hl
        ld a,(ste.lx_type)
        cp T_SYM
        jr nz,.bad
        ld a,(ste.lx_sym)
        cp S_ASG
        jr z,.np0
        cp S_OUT
        jr z,.np0
.bad:   call st_decl            ; declare it as a local?
        jr nc,.np0
        ld hl,err_st_name
        scf
        ret
.np0:   xor a
        ld (sn_par),a
        ld (sn_decl),a
        jp .l
.np:    ld b,0                  ; sn_par: the token is "(" or ","
        ld hl,sn_decl
        ld (hl),b
        cp T_SYM
        jr nz,.p
        ld a,(ste.lx_sym)
        cp '('
        jr z,.p1
        cp ','
        jr nz,.p
.p1:    inc b
.p:     ld a,b
        ld (sn_par),a
        jp .l
.end:   ld hl,(sn_out)
        ld (hl),0
        or a
        ret

; ---- st_decl: sn_name = an unknown name (not in the VAR block) -> popup
;      "Declare NAME as: BOOL / INT / TIME" (only after ENTER, st_dcok);
;      NC: the declaration was added
;      (a new VAR block at line 0, or before END_VAR), st_cur moved down,
;      st_redr = 1. C: cancelled / not a valid name / no room
st_decl:
        ld a,(st_dcok)          ; only when the line is left with ENTER
        sub 1
        ret c
        ld a,(sn_inb)
        or a
        scf
        ret nz
        ld hl,sn_name           ; a letter or _, then letters, digits, _
        ld a,(hl)
        call to_upper
        cp 'A'
        jr c,.f1
        cp 'Z'+1
        jr c,.f2
.f1:    cp '_'
        scf
        ret nz
.f2:    inc hl
        ld a,(hl)
        or a
        jr z,.ok
        cp '_'
        jr z,.f2
        call ste.lx_alnum
        jr c,.f2
        scf                     ; (an invalid character)
        ret
.ok:    ld a,(cur_pou)          ; where: a new block, or before END_VAR
        ld hl,st_nothing
        call ste.st_vfind
        ld a,(ste.vf_var)
        or a
        jr z,.q
        ld hl,(ste.vf_end)
        ld a,h
        or l
        scf
        ret z                   ; (VAR without END_VAR)
.q:     ld de,popup_buf         ; "Declare NAME as:" / B BOOL / I INT / T TIME
        ld hl,txt_dc1
        call put_str
        ld hl,sn_name
        call put_str
        ld hl,txt_dc2
        ld bc,txt_dc_end-txt_dc2
        ldir
        ld hl,popup_buf
        call popup_open
.k:     call kb_wait
        cp K_MOUSE
        jr nz,.nm
        ld a,3
        ld b,2
        BCALL ms_item
        jp c,.cancel
        jr .sel
.nm:    cp K_BREAK
        jp z,.cancel
        cp K_EDIT
        jp z,.cancel
        call to_upper
        ld b,0
        cp 'B'
        jr z,.typ
        inc b
        cp 'I'
        jr z,.typ
        inc b
        cp 'T'
        jr nz,.k
.typ:   ld a,b
.sel:   push af
        call win_close
        pop af
        add a,a                 ; "NAME : TYPE;"
        ld e,a
        ld d,0
        ld hl,dc_types
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        ld hl,sn_name
        ld de,sd_text
        call put_str
        ld hl,txt_dc3
        call put_str
        pop hl
        call put_str
        ld a,';'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld a,(ste.vf_var)
        or a
        jr z,.new
        ld de,(ste.vf_end)      ; before END_VAR
        ld hl,sd_text
        ld a,1
        call st_ins_line
        ret c
        ld de,1
        jr .moved
.new:   ld de,0                 ; VAR / NAME : TYPE; / END_VAR at line 0
        ld hl,txt_endvar
        xor a
        call st_ins_line
        ret c
        ld de,0
        ld hl,sd_text
        ld a,1
        call st_ins_line
        ret c
        ld de,0
        ld hl,txt_var
        xor a
        call st_ins_line
        ret c
        ld de,3
.moved: ld hl,(st_cur)
        add hl,de
        ld (st_cur),hl
        ld a,1
        ld (st_redr),a
        or a
        ret
.cancel:
        call win_close
        scf
        ret

dc_types:  dw txt_bool,txt_int,txt_time
txt_bool:  db "BOOL",0
txt_int:   db "INT",0
txt_time:  db "TIME",0
txt_endvar: db "END_VAR",0
txt_dc1:   db "Declare ",0
txt_dc2:   db " as:",0
           db " ",0
           db "B",PT_TAB,"BOOL",0
           db "I",PT_TAB,"INT",0
           db "T",PT_TAB,"TIME",0
           db 0
txt_dc_end:
txt_dc3:   db " : ",0

; st_inblk: DE = line -> A = 1 if it is a declaration line of the VAR
;      block of the POU (between VAR and END_VAR)
st_inblk:
        push de
        ld a,(cur_pou)
        ld hl,st_nothing
        call ste.st_vfind
        pop de
        ld a,(ste.vf_var)
        or a
        ret z
        ld a,d
        or e
        ret z                   ; (line 0: VAR)
        ld hl,(ste.vf_end)
        ld a,h
        or l
        ld a,1
        ret z                   ; (no END_VAR yet)
        ex de,hl
        or a
        sbc hl,de
        ld a,0
        ret nc
        inc a
        ret

; sn_semi: the token of st_norm -> Z if it is a ";" right after END_x (it
;      is left out: END_IF, not END_IF;). Comments in between are skipped
sn_semi:
        ld a,(ste.lx_type)
        cp T_CMT
        jr z,.keep
        ld b,a
        ld a,(sn_lend)
        ld c,a
        xor a
        ld (sn_lend),a
        ld a,b
        cp T_KW
        jr nz,.nk
        ld a,(ste.lx_kw)
        ld hl,bk_ends
        call ii_in
        jr nz,.keep
        ld a,1
        ld (sn_lend),a
        jr .keep
.nk:    cp T_SYM
        jr nz,.keep
        ld a,(ste.lx_sym)
        cp ';'
        jr nz,.keep
        ld a,c
        or a
        jr z,.keep
        xor a                   ; Z: drop it
        ret
.keep:  or 1
        ret

; ---- st_iinfo: HL = line text -> B = 1 if the next line is indented
;      deeper, C = 1 if this line is one level less deep than its block
st_iinfo:
        ld (ste.lx_p),hl
        ld bc,0
        ld a,1
        ld (ii_first),a
        xor a
        ld (ii_last),a
        ld (ii_until),a
.l:     push bc
        call ste.lx_next
        pop bc
        ld a,(ste.lx_type)
        or a
        jr z,.e
        cp T_CMT
        jr z,.l
        ld e,0
        cp T_KW
        jr nz,.nk
        ld a,(ste.lx_kw)
        ld e,a
.nk:    ld a,e
        ld (ii_last),a
        ld a,(ii_first)
        or a
        jr z,.nf
        xor a
        ld (ii_first),a
        ld a,e
        ld hl,ii_close
        call ii_in
        jr nz,.nf
        ld c,1
        ld a,e
        cp KW_UNTIL
        jr nz,.nf
        ld (ii_until),a
.nf:    ld a,e
        cp KW_END_REPEAT
        jr nz,.l
        xor a
        ld (ii_until),a
        jr .l
.e:     ld a,(ii_until)
        or a
        jr nz,.op
        ld a,(ii_last)
        ld hl,ii_open
        call ii_in
        ret nz
.op:    ld b,1
        ret

; ii_in: A = keyword, HL = list (0) -> Z if in it (keeps BC, E)
ii_in:  ld d,a
.l:     ld a,(hl)
        inc hl
        or a
        jr z,.no
        cp d
        ret z
        jr .l
.no:    or 1
        ret

ii_close: db KW_END_IF,KW_END_CASE,KW_END_FOR,KW_END_WHILE,KW_END_REPEAT
          db KW_END_VAR,KW_ELSE,KW_ELSIF,KW_UNTIL,0
ii_open:  db KW_THEN,KW_ELSE,KW_DO,KW_OF,KW_REPEAT
          db KW_VAR,KW_VAR+1,KW_VAR+2,KW_VAR+3,0

; ---- st_reind: DE = first line -> sets the indent of the lines from DE
;      on, stops at the first line after DE that keeps its indent.
;      ri_chg = 1 if a line after DE changed. st_reind_all: no stop
st_reind_all:
        ld a,1
        jr st_reind.go
st_reind:
        xor a
.go:    ld (ri_all),a
        ld (ri_line),de
        ld a,1
        ld (ri_first),a
        xor a
        ld (ri_chg),a
        call st_line_addr
        ret c
        ld (ri_rec),hl
        ld de,(ri_line)
        ld b,0                  ; base indent: the line above + its opening
        ld a,d
        or e
        jr z,.b0
        dec de
        call st_line_addr
        call ri_open
        ld b,a
.b0:    ld a,b
        ld (ri_base),a
.l:     ld hl,(ri_rec)
        ld de,(st_end)
        or a
        sbc hl,de
        ret nc
        ld hl,(ri_rec)
        ld de,st_tmp2
        call st_rec_text
        ld (ri_old),a
        ld hl,st_tmp2
        call st_iinfo
        ld a,(ri_base)
        sub c
        jr nc,.p
        xor a
.p:     cp ST_IMAX+1
        jr c,.p2
        ld a,ST_IMAX
.p2:    ld hl,ri_old
        cp (hl)
        jr z,.same
        ld hl,(ri_rec)
        inc hl
        ld b,a
        ld a,(hl)
        cp K_STXT
        jr nz,.next
        push hl
        push bc
        call undo_save
        pop bc
        pop hl
        inc hl
        ld (hl),b
        ld a,(ri_first)
        or a
        jr nz,.next
        ld a,1
        ld (ri_chg),a
        jr .next
.same:  ld a,(ri_first)
        ld hl,ri_all
        or (hl)
        ret z
.next:  xor a
        ld (ri_first),a
        ld hl,(ri_rec)
        call ri_open            ; base for the next line
        ld (ri_base),a
        ld hl,(ri_rec)
        ld e,(hl)
        ld d,0
        add hl,de
        ld (ri_rec),hl
        jr .l

; ri_open: HL = record -> A = its indent + 1 if it opens a block
ri_open:
        ld de,st_tmp2
        call st_rec_text
        push af
        ld hl,st_tmp2
        call st_iinfo
        pop af
        add a,b
        ret

; ============================================================
; edit buffer
; ============================================================

; ---- st_kwup: a keyword that ends at the cursor is written in upper case
;      in se_buf (not in a comment: the line is read by the tokenizer)
st_kwup:
        ld a,(st_pos)
        ld e,a
        ld d,0
        ld hl,se_buf
        add hl,de
        ld (ku_end),hl
        ld hl,se_buf
        ld (ste.lx_p),hl
.l:     call ste.lx_next
        ld a,(ste.lx_type)
        or a
        ret z
        ld hl,(ste.lx_p)
        ld de,(ku_end)
        or a
        sbc hl,de
        jr c,.l
        ret nz                  ; (the cursor is inside this token)
        ld a,(ste.lx_type)
        cp T_KW
        ret nz
        ld hl,(ste.lx_start)
        ld de,ste.lx_word
.u:     ld a,(de)
        or a
        ret z
        ld (hl),a
        inc hl
        inc de
        jr .u

; ---- st_len: A = length of se_buf (keeps BC, DE)
st_len:
        push bc
        push hl
        ld hl,se_buf
        call strlen
        pop hl
        pop bc
        ret

; ---- st_insert: A = char -> inserted at st_pos; C = full / too wide
st_insert:
        ld (ei_c),a
        call st_len
        cp ST_BLEN
        ccf
        ret c
        ld hl,se_buf            ; move the tail (with the 0) one up
        ld e,a
        ld d,0
        add hl,de
        ld d,h
        ld e,l
        inc de
        ld b,a
        ld a,(st_pos)
        ld c,a
        ld a,b
        sub c
        inc a
        ld c,a
        ld b,0
        lddr
        inc hl
        ld a,(ei_c)
        ld (hl),a
        ld hl,st_pos
        inc (hl)
        call st_measure         ; too wide?
        ld a,(rn_ovf)
        or a
        ret z
        ld hl,st_pos
        dec (hl)
        call st_del_char
        scf
        ret

; ---- st_del_char: deletes the char at st_pos
st_del_char:
        ld hl,se_buf
        ld a,(st_pos)
        ld e,a
        ld d,0
        add hl,de
        ld d,h
        ld e,l
        inc hl
.l:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.l
        ret

; ---- strcat: HL = text appended to the 0-terminated text at DE
strcat:
        ld a,(de)
        or a
        jr z,.c
        inc de
        jr strcat
.c:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.c
        ret

; ---- st_measure: lays se_buf out (no drawing): rn_qx = x of the cursor,
;      rn_ovf = 1 if the line is wider than the screen
st_measure:
        ld a,(st_pos)
        ld (rn_qpos),a
        xor a
        ld (rn_cx),a
        ld (rn_draw),a
        ld hl,se_buf
        ld a,(st_ind)
        jp st_render

; ---- st_pos_at: A = x -> A = position of the char nearest to it
st_pos_at:
        ld (rn_cx),a
        xor a
        ld (rn_draw),a
        dec a
        ld (rn_qpos),a
        ld hl,se_buf
        ld a,(st_ind)
        call st_render
        xor a
        ld (rn_cx),a
        ld a,(rn_cpos)
        cp 0xFF
        ret nz
        jp st_len

; ---- st_word_at: the word under (or before) the cursor -> A = area,
;      C = index, DE = value (op_parse); A = 0 if there is no operand
st_word_at:
        ld hl,se_buf
        ld (ste.lx_p),hl
        xor a
        ld (st_tail),a
.l:     call ste.lx_next
        ld a,(ste.lx_type)
        or a
        jr z,.e
        cp T_WORD
        jr nz,.l
        ld hl,(ste.lx_start)    ; starts after the cursor: done
        ld de,se_buf
        or a
        sbc hl,de
        ld a,(st_pos)
        cp l
        jr c,.e
        ld hl,ste.lx_word
        ld de,st_tail
        call put_str0
        jr .l
.e:     ld hl,st_tail
        ld a,(hl)
        or a
        ret z
        call op_parse
        ret nc
        xor a
        ret

; ============================================================
; drawing
; ============================================================

; ---- st_render: HL = text, A = indent -> lays the line out:
;      rn_draw = 1: draws it at pt_row (glyphs ending past rn_lim, if not
;        0, are left out) and fills rn_attr with the cell colours;
;      rn_qpos = char index -> rn_qx = its x;
;      rn_cx = x (not 0) -> rn_cpos = index of the char under it (0xFF: none);
;      rn_ovf = 1: wider than the screen
st_render:
        ld (rn_txt),hl
        ld (ste.lx_p),hl
        cp ST_IMAX+1
        jr c,.i
        ld a,ST_IMAX
.i:     add a,a
        add a,a
        add a,a
        add a,ST_X0
        ld (rn_x),a
        xor a
        ld (rn_ovf),a
        ld (rn_gap),a
        dec a
        ld (rn_cpos),a
        ld a,(rn_draw)
        or a
        jr z,.tok
        ld hl,rn_attr
        ld b,32
.fa:    ld (hl),ATTR_NORMAL
        inc hl
        djnz .fa
.tok:   ld hl,(ste.lx_p)
        ld (rn_prev),hl
        call ste.lx_next
        ld hl,(rn_prev)         ; the spaces in front of the token
.ws:    ld de,(ste.lx_start)
        or a
        sbc hl,de
        add hl,de
        jr z,.wse
        ld a,(rn_gap)           ; (the first one after a keyword: in its gap)
        or a
        ld a,0
        jr nz,.w0
        ld a,' '
        call pt_charw
.w0:    ld c,a
        call rn_char
        xor a
        ld (rn_gap),a
        inc hl
        jr .ws
.wse:   ld a,(ste.lx_type)
        or a
        jr nz,.wse2
        ld a,(rn_gap)           ; a keyword at the end (no space after it):
        or a                    ; the cursor right behind it, not in the gap
        jr z,.end
        ld a,(rn_ke)
        ld (rn_x),a
        jr .end
.wse2:  xor a
        ld (rn_gap),a
        ld a,(ste.lx_type)
        cp T_KW
        jr z,.snap
        cp T_CMT
        jr nz,.chars
.snap:  call rn_snap
        ld a,(rn_x)
        ld (rn_kx),a
.chars: ld hl,(ste.lx_start)
.cl:    ld de,(ste.lx_p)
        or a
        sbc hl,de
        add hl,de
        jr z,.ce
        ld a,(hl)
        call pt_charw
        ld c,a
        call rn_char
        inc hl
        jr .cl
.ce:    ld a,(ste.lx_type)
        cp T_CMT
        jr z,.cmt
        cp T_KW
        jr nz,.tok
        ld a,(rn_x)             ; keyword: its cells blue, next cell
        ld (rn_ke),a
        sub 2
        ld e,ATTR_MNEM
        call rn_mark
        call rn_snap
        ld a,(rn_ke)
        ld b,a
        ld a,(rn_x)
        sub b
        cp 2
        jp c,.tok
        ld a,1
        ld (rn_gap),a
        jp .tok
.cmt:   ld a,255
        ld e,ATTR_COMMENT
        call rn_mark
        jp .tok
.end:   ld hl,(ste.lx_start)    ; (the 0: the cursor at the end)
        ld c,0
        jp rn_q

; rn_char: HL = char, C = width -> drawn at rn_x, rn_x advanced (keeps HL, C)
rn_char:
        call rn_q
        ld a,(rn_ovf)
        or a
        ret nz
        ld a,(rn_x)
        ld b,a
        add a,c
        jr c,rn_ov
        ld (rn_x),a
        ld d,a
        ld a,(rn_draw)
        or a
        ret z
        ld a,(rn_lim)
        or a
        jr z,.d
        cp d
        ret c
.d:     ld a,b
        ld (pt_x),a
        ld a,(hl)
        jp pt_putc
rn_ov:  ld a,1
        ld (rn_ovf),a
        ld a,255
        ld (rn_x),a
        ret

; rn_snap: rn_x -> the next x = 8k+1
rn_snap:
        ld a,(rn_x)
        add a,6
        jr c,rn_ov
        and 0xF8
        inc a
        ld (rn_x),a
        ret

; rn_q: HL = char, C = width -> the cursor / click queries (keeps HL, C)
rn_q:   push hl
        ld de,(rn_txt)
        or a
        sbc hl,de
        ld b,l                  ; B = index
        pop hl
        ld a,(rn_qpos)
        cp b
        jr nz,.c
        ld a,(rn_x)
        ld (rn_qx),a
.c:     ld a,(rn_cpos)
        inc a
        ret nz                  ; already found
        ld a,(rn_cx)
        or a
        ret z
        ld d,a
        ld a,c
        srl a
        ld e,a
        ld a,(rn_x)
        add a,e                 ; the middle of the char
        jr c,.f
        cp d
        ret c
        ret z
.f:     ld a,b
        ld (rn_cpos),a
        ret

; rn_mark: cells rn_kx/8 .. A/8 of rn_attr = E
rn_mark:
        rrca
        rrca
        rrca
        and 31
        ld b,a
        ld a,(rn_kx)
        rrca
        rrca
        rrca
        and 31
        ld c,a
        ld a,b
        sub c
        ret c
        inc a
        ld b,a
        ld hl,rn_attr
        ld a,l
        add a,c
        ld l,a
        jr nc,.l
        inc h
.l:     ld (hl),e
        inc hl
        djnz .l
        ret

; ---- st_row_cur: A = screen row of the current line
st_row_cur:
        ld hl,(st_top)
        call st_d
        ex de,hl
        ld hl,(st_cur)
        call st_d
        or a
        sbc hl,de
        ld a,l
        add a,ST_ROW0
        ret

; ---- folding of the VAR block: while the cursor is below END_VAR, the
;      lines 1..END_VAR (st_fh of them) are hidden and line 0 shows a
;      summary of the declarations. Display index D: line 0 -> 0, a hidden
;      line -> 0, line l > st_fh -> l - st_fh

; st_d: HL = line -> HL = display index (keeps BC, DE)
st_d:   push de
        ld de,(st_fh)
        ld a,d
        or e
        jr z,.e
        ld a,h
        or l
        jr z,.e
        or a
        sbc hl,de
        jr z,.z
        jr nc,.e
.z:     ld hl,0
.e:     pop de
        ret

; st_l: HL = display index -> HL = line (keeps BC, DE)
st_l:   ld a,h
        or l
        ret z
        push de
        ld de,(st_fh)
        add hl,de
        pop de
        ret

; st_fcalc: st_fh for the current cursor; NZ = it changed
st_fcalc:
        ld a,(cur_pou)
        ld hl,st_nothing
        call ste.st_vfind
        ld a,(ste.vf_cnt)
        ld (st_fcnt),a
        ld hl,0
        ld a,(ste.vf_var)
        or a
        jr z,.s
        ld de,(ste.vf_end)
        ld a,d
        or e
        jr z,.s
        ld hl,(st_cur)          ; below END_VAR?
        or a
        sbc hl,de
        ld hl,0
        jr z,.s
        jr c,.s
        ex de,hl
.s:     ld de,(st_fh)
        ld (st_fh),hl
        or a
        sbc hl,de
        ld a,h
        or l
        ret

; ---- st_fix_top: keeps st_cur visible; NZ = st_top or the folding changed
st_fix_top:
        call st_fcalc
        push af
        ld hl,(st_top)          ; (never a hidden line)
        call st_d
        call st_l
        ld (st_top),hl
        call st_d
        ex de,hl
        ld hl,(st_cur)
        call st_d
        or a
        sbc hl,de
        jr c,.up
        ld de,ST_ROWS
        or a
        sbc hl,de
        jr nc,.down
        pop af
        ret
.up:    pop af
        ld hl,(st_cur)
        ld (st_top),hl
        or 1
        ret
.down:  pop af
        ld hl,(st_cur)
        call st_d
        ld de,ST_ROWS-1
        or a
        sbc hl,de
        call st_l
        ld (st_top),hl
        or 1
        ret

; st_rowline: A = screen row (from ST_ROW0) -> DE = its line
st_rowline:
        sub ST_ROW0
        ld e,a
        ld d,0
        ld hl,(st_top)
        call st_d
        add hl,de
        call st_l
        ex de,hl
        ret

; st_fsum: the summary of the folded VAR block -> st_tmp2:
;      "VAR Idx : INT; Sum : INT; .. (n)" (comments left out)
st_fsum:
        ld de,st_tmp2
        ld hl,txt_var
        call put_str
        ld (sf_out),de
        ld hl,1
        ld (sf_l),hl
.l:     ld de,(sf_l)
        ld hl,(st_fh)
        or a
        sbc hl,de
        jr z,.e
        jr c,.e
        call st_line_addr
        ld de,sf_buf
        call st_rec_text
        ld hl,sf_buf            ; cut at a comment
        ld (ste.lx_p),hl
.c:     call ste.lx_next
        ld a,(ste.lx_type)
        or a
        jr z,.c2
        cp T_CMT
        jr nz,.c
        ld hl,(ste.lx_start)
        ld (hl),0
        dec hl
        ld a,(hl)
        cp ' '
        jr nz,.c2
        ld (hl),0
.c2:    ld hl,sf_buf
        call strlen
        or a
        jr z,.n
        ld c,a
        ld hl,(sf_out)
        ld de,st_tmp2
        or a
        sbc hl,de
        ld a,l
        add a,c
        cp SF_MAX
        jr nc,.full
        ld de,(sf_out)
        ld a,' '
        ld (de),a
        inc de
        ld hl,sf_buf
        call put_str
        ld (sf_out),de
.n:     ld hl,(sf_l)
        inc hl
        ld (sf_l),hl
        jr .l
.full:  ld de,(sf_out)
        ld hl,txt_sf_more
        call put_str
        ld (sf_out),de
.e:     ld de,(sf_out)          ; " (n)"
        ld a,' '
        ld (de),a
        inc de
        ld a,'('
        ld (de),a
        inc de
        ld a,(st_fcnt)
        ld b,0
        cp 100
        jr c,.d1
        sub 100
        ld c,'1'
        call .put
        inc b
.d1:    ld c,'0'-1
.d2:    inc c
        sub 10
        jr nc,.d2
        add a,10
        push af
        ld a,c
        cp '0'
        jr nz,.d3
        ld a,b
        or a
        jr z,.d4
.d3:    call .put
.d4:    pop af
        add a,'0'
        ld c,a
        call .put
        ld a,')'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret
.put:   push af
        ld a,c
        ld (de),a
        inc de
        pop af
        ret

; ---- st_redraw_all / st_redraw_from: A = first screen row
st_redraw_all:
        ld a,ST_ROW0
st_redraw_from:
        cp ST_ROW0
        jr nc,.ok
        ld a,ST_ROW0
.ok:    ld (rf_r),a
.l:     ld a,(rf_r)
        cp ST_ROW0+ST_ROWS
        ret nc
        call st_rowline
        ld a,(rf_r)
        ld b,a
        call st_draw_row
        ld hl,rf_r
        inc (hl)
        jr .l

; ---- st_draw_cur: redraws the current line (_text: the text only)
st_draw_cur_text:
        ld a,1
        ld (sr_tonly),a
st_draw_cur:
        call st_row_cur
        ld b,a
        ld de,(st_cur)
        ; fall through

; ---- st_draw_row: B = screen row, DE = line index
;      (sr_sim = 1: the simulation listing, no edit buffer, cells 3-24)
st_draw_row:
        ld a,b
        ld (sr_row),a
        ld (sr_line),de
        ld a,(sr_sim)
        or a
        jr nz,.oth
        ld hl,(st_cur)
        or a
        sbc hl,de
        jr nz,.oth
        ld hl,se_buf
        ld a,(st_ind)
        jr .go
.oth:   ld a,d                  ; line 0 of a folded VAR block: summary
        or e
        jr nz,.oth2
        ld hl,(st_fh)
        ld a,h
        or l
        jr z,.oth2
        ld a,(sr_sim)
        or a
        jr nz,.oth2
        call st_fsum
        ld de,0
        ld hl,st_tmp2
        xor a
        jr .go
.oth2:  call st_line_addr
        jp c,.none
        ld de,st_tmp2
        call st_rec_text
        ld hl,st_tmp2
.go:    ld (sr_txt),hl
        ld (sr_ind),a
        ld a,(sr_tonly)
        or a
        jr nz,.tclr
        ld a,(sr_row)
        ld b,a
        call pt_clear_row
        call .sep
        ld a,(sr_row)           ; line number, fixed digit pitch
        ld (pt_row),a
        ld hl,(sr_line)
        inc hl
        ld de,sr_num
        call st_dec3
        ld hl,sr_num
        ld a,ST_X_NUM-3*IL_NUM_PITCH
        ld (sr_dx),a
        ld b,3
.dg:    ld a,(sr_dx)
        ld (pt_x),a
        ld a,(hl)
        call pt_putc
        inc hl
        ld a,(sr_dx)
        add a,IL_NUM_PITCH
        ld (sr_dx),a
        djnz .dg
        jr .txt
.tclr:  ld a,(sr_row)           ; text only: clear cells 3-31
        ld b,a
        ld c,3
        call pix_addr
        ld e,8
.z0:    push hl
        ld b,29
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.z0
.txt:   ld a,(sr_row)
        ld (pt_row),a
        ld a,1
        ld (rn_draw),a
        ld a,0xFF
        ld (rn_qpos),a
        xor a
        ld (rn_cx),a
        ld a,(sr_sim)           ; simulation: values from cell 25
        or a
        jr z,.lim
        ld a,ST_SIM_COL*8-1
.lim:   ld (rn_lim),a
        ld hl,(sr_txt)
        ld a,(sr_ind)
        call st_render
        xor a
        ld (rn_draw),a
        ld (rn_lim),a
        ld a,(sr_row)           ; attributes
        ld b,a
        ld c,0
        ld de,0x0300+ATTR_LNUM
        call scr_fill_attr
        call .aaddr
        ex de,hl
        ld hl,rn_attr+3
        ld bc,29
        ld a,(sr_sim)
        or a
        jr z,.ac
        ld c,ST_SIM_COL-3
.ac:    ldir
        ld a,(sr_tonly)
        or a
        jr z,.inv
        xor a                   ; text only: the line number stays
        ld (sr_tonly),a
        ld (st_con),a
        ret
.inv:   ld a,(sr_sim)
        or a
        ret nz
        ld hl,(st_cur)
        ld de,(sr_line)
        or a
        sbc hl,de
        ret nz
        ld a,(sr_row)           ; current line: inverted line number
        ld b,a
        ld c,0
        ld d,ST_X_SEP
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        xor a
        ld (st_con),a
        ret
.none:  xor a                   ; below the last line: empty row
        ld (sr_tonly),a
        ld a,(sr_row)
        ld b,a
        call pt_clear_row
        call .sep
        ld a,(sr_row)
        ld b,a
        ld c,0
        ld de,0x0300+ATTR_LNUM
        call scr_fill_attr
        ld a,(sr_row)
        ld b,a
        ld c,3
        ld d,29
        ld a,(sr_sim)
        or a
        jr z,.n1
        ld d,ST_SIM_COL-3
.n1:    ld e,ATTR_NORMAL
        jp scr_fill_attr
.sep:   ld a,(sr_row)
        ld b,a
        ld c,ST_X_SEP
        ld d,1
        ld hl,0x0008
        ld e,PX_SET
        jp px_span
.aaddr: ld a,(sr_row)           ; HL = attribute of cell 3
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,0x5800+3
        add hl,de
        ret

; ---- st_dec3: HL = 0..999 -> 3 digits with leading zeros + 0 at (DE)
st_dec3:
        ld bc,100
        call .dig
        ld bc,10
        call .dig
        ld a,l
        add a,'0'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret
.dig:   ld a,'0'-1
.l:     inc a
        or a
        sbc hl,bc
        jr nc,.l
        add hl,bc
        ld (de),a
        inc de
        ret

; ---- st_cursor: XORs the 1 px text cursor
st_cursor:
        call st_measure
        ld a,(rn_qx)
        dec a
        ld c,a
        call st_row_cur
        ld b,a
        ld d,1
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        ld a,(st_con)
        xor 1
        ld (st_con),a
        ret

; ---- st_key: waits for a key with a blinking cursor, A = key
st_key:
        ld a,(st_con)
        or a
        call z,st_cursor
        ld a,(frames)
        and 16
        ld (st_blink),a
.w:     call kb_get
        or a
        jr nz,.got
        halt
        ld a,(frames)
        and 16
        ld b,a
        ld a,(st_blink)
        cp b
        jr z,.w
        ld a,b
        ld (st_blink),a
        call st_cursor
        jr .w
.got:   push af
        ld a,(st_con)
        or a
        call nz,st_cursor
        pop af
        ret

; ---- st_sim_row: the simulation listing (sim.asm, BCALL): B = screen
;      row, DE = line of POU cur_pou -> drawn in cells 0-24; rd_o = the
;      operand to watch: the target of "x :=", the operand of
;      "IF x THEN" / "WHILE x DO" / "UNTIL x" / "CASE x OF" / "FOR x :=",
;      "INST(" -> "INST.ET" (as in IL); "" for none
st_sim_row:
        ld a,1
        ld (sr_sim),a
        xor a
        ld (rd_o),a
        ld (st_tmp2),a
        call st_draw_row
        xor a
        ld (sr_sim),a
        ld hl,st_tmp2
        ld (ste.lx_p),hl
        call ste.lx_next
        ld a,(ste.lx_type)
        cp T_KW
        jr nz,.w
        ld a,(ste.lx_kw)
        ld hl,ws_kw
        call ii_in
        ret nz
        call ste.lx_next
        ld a,(ste.lx_type)
        cp T_WORD
        ret nz
        call .copy
        call ste.lx_next        ; a single operand: THEN / DO / OF / := / end
        ld a,(ste.lx_type)
        or a
        ret z
        cp T_KW
        ret z
        cp T_SYM
        jr nz,.clr
        ld a,(ste.lx_sym)
        cp S_ASG
        ret z
.clr:   xor a
        ld (rd_o),a
        ret
.w:     cp T_WORD
        ret nz
        call .copy
        call ste.lx_next
        ld a,(ste.lx_type)
        cp T_SYM
        jr nz,.clr
        ld a,(ste.lx_sym)
        cp S_ASG
        ret z
        cp ':'                  ; a declaration "Name : TYPE"
        ret z
        cp '('
        jr nz,.clr
        ld hl,rd_o              ; "INST" + ".ET"
        xor a
        ld bc,40
        cpir
        dec hl
        ex de,hl
        ld hl,txt_ws_et
        jr put_str0
.copy:  ld hl,ste.lx_word
        ld de,rd_o
put_str0:                       ; HL -> DE with the 0 (DE -> the 0)
        call put_str
        xor a
        ld (de),a
        ret

ws_kw:     db KW_IF,KW_ELSIF,KW_WHILE,KW_UNTIL,KW_CASE,KW_FOR,0
txt_ws_et: db ".ET",0

; ---- st_xr_line: HL = ST line record (cross references, tools.asm, BCALL),
;      A = area, C = index of the operand searched (a member counts as its
;      FB instance) -> Z if the line uses it, B = 'W' written (x :=,
;      => x), 'C' FB call, 'R' read
st_xr_line:
        ld (xl_a),a
        ld a,c
        ld (xl_i),a
        ld de,st_tmp2
        call st_rec_text
        ld hl,st_tmp2
        ld (ste.lx_p),hl
        xor a
        ld (xl_prev),a
.l:     call ste.lx_next
        ld a,(ste.lx_type)
        or a
        jr z,.no
        cp T_WORD
        jr nz,.nx
        ld hl,ste.lx_word
        call op_parse
        jr c,.nx
        and AR_MASK
        cp AR_FBM
        jr nz,.a
        ld a,AR_FBI
.a:     ld hl,xl_a
        cp (hl)
        jr nz,.nx
        ld a,(xl_i)
        cp c
        jr nz,.nx
        ld b,'W'                ; found: how is it used?
        ld a,(xl_prev)
        cp S_OUT
        ret z
        ld hl,(ste.lx_p)
        push hl
        call ste.lx_next
        pop hl
        ld (ste.lx_p),hl
        ld b,'R'
        ld a,(ste.lx_type)
        cp T_SYM
        jr nz,.r
        ld a,(ste.lx_sym)
        ld b,'W'
        cp S_ASG
        ret z
        ld b,'C'
        cp '('
        ret z
        ld b,'R'
.r:     cp a
        ret
.nx:    ld a,(ste.lx_type)      ; xl_prev = the symbol (or 0)
        cp T_SYM
        ld a,0
        jr nz,.p
        ld a,(ste.lx_sym)
.p:     ld (xl_prev),a
        jr .l
.no:    or 1
        ret

xl_a:    db 0
xl_i:    db 0
xl_prev: db 0

; ---- st_add_line: A = slot, HL = line text (fixed memory) -> appended to
;      the POU, its indent computed (st_load_text in app.asm: demo, tests)
st_add_line:
        ld (lt_s),a
        ld (lt_p),hl
        ld a,(cur_pou)
        ld (lt_cur),a
        ld a,(lt_s)
        ld (cur_pou),a
        call st_count
        ld hl,(lt_p)
        ld de,st_tmp
        call put_str
        xor a
        ld (de),a
.l:     ld hl,(st_cur)          ; (st_brk: the VAR block test of line st_n)
        push hl
        ld hl,(st_n)
        ld (st_cur),hl
        call st_brk             ; control keywords on lines of their own
        pop hl
        ld (st_cur),hl
        sbc a,a
        ld (st_brkf),a
        ld de,(st_n)
        ld hl,st_tmp
        xor a
        call st_ins_line
        ld de,(st_n)
        dec de
        call st_reind
        ld a,(st_brkf)
        or a
        jr z,.e
        ld hl,st_spl
        ld de,st_tmp
        call put_str
        xor a
        ld (de),a
        jr .l
.e:
        ld a,0xFF               ; the editor starts at line 0
        ld (st_pou),a
        ld a,(lt_cur)
        ld (cur_pou),a
        ret

err_st_lines: db "Max. 999 lines",0
err_st_char: db "Invalid character",0
err_st_cmt:  db "Comment not closed",0
err_st_name: db "Unknown name",0
err_st_var:  db "VAR only at the start",0
st_nothing:  db 0

st_pou:    db 0xFF
st_n:      dw 0
st_cur:    dw 0
st_top:    dw 0
st_end:    dw 0
st_pos:    db 0
st_npos:   db 0
st_ind:    db 0
st_oldrow: db 0
st_oldln:  dw 0
st_mpend:  db 0
st_blink:  db 0
st_con:    db 0             ; 1: the cursor is drawn
se_buf:    ds ST_BLEN+2
st_tail:   ds ST_BLEN+2
st_tmp:    ds ST_BLEN+2
st_tmp2:   ds 256
st_spl:    ds ST_BLEN+2
st_split:  db 0
st_brkf:   db 0
ku_end:    dw 0
sn_lend:   db 0
sn_decl:   db 0
st_fh:     dw 0                 ; folded VAR block: hidden lines (0: none)
st_fcnt:   db 0
st_redr:   db 0
st_dcok:   db 0
sn_inb:    db 0
sn_name:   ds 32
sd_text:   ds 48
sf_l:      dw 0
sf_out:    dw 0
sf_buf:    ds 64
bk_decl:   db 0
bk_n:      db 0
bk_aft:    db 0
bk_end:    db 0
ei_c:      db 0
sl_ind:    db 0
sl_len:    db 0
se_cmaddr:   dw 0
se_cmoff:    dw 0
sn_out:    dw 0
sn_prev:   dw 0
sn_par:    db 0
ii_first:  db 0
ii_last:   db 0
ii_until:  db 0
ri_all:    db 0
ri_line:   dw 0
ri_first:  db 0
ri_chg:    db 0
ri_rec:    dw 0
ri_base:   db 0
ri_old:    db 0
rf_r:      db 0
sr_sim:    db 0
sr_tonly:  db 0
sr_row:    db 0
sr_line:   dw 0
sr_txt:    dw 0
sr_ind:    db 0
sr_dx:     db 0
sr_num:    ds 4
rn_draw:   db 0
rn_lim:    db 0
rn_txt:    dw 0
rn_prev:   dw 0
rn_x:      db 0
rn_kx:     db 0
rn_ke:     db 0
rn_gap:    db 0
rn_ovf:    db 0
rn_qpos:   db 0
rn_qx:     db 0
rn_cx:     db 0
rn_cpos:   db 0
rn_attr:   ds 32
lt_s:      db 0
lt_p:      dw 0
lt_cur:    db 0

        MODULE ste
        INCLUDE "st_lex.asm"
        ENDMODULE
