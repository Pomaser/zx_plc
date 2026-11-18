; ============================================================
; complete.asm - ST name completion (DEMO bank), SS+SPACE in the editor
; ============================================================
; ac_run gets the word part in front of the cursor in il_out and offers
; the names that start with it: the locals of the POU (its VAR block,
; declaration order), then the symbols (alphabetical); after "Inst." the
; members of that FB instance. One candidate is taken at once, more open
; a list window: letters / digits / _ filter it, DELETE shortens the
; filter, UP / DOWN select, ENTER / SS+SPACE / a click take the name,
; BREAK / EDIT close it (the filter typed so far is kept).
; ============================================================
AC_MAX   EQU 56                 ; candidates
AC_NLEN  EQU 20                 ; name buffer
AC_ROWS  EQU 8                  ; list rows of the window
AC_COLS  EQU 22                 ; window width (cells)
AC_X0    EQU 6*8                ; window x (px)
AC_XINF  EQU 104                ; right column, from the window x

; ---- ac_run: A = POU slot, B = screen row of the line, il_out = the
;      word part in front of the cursor -> il_out = the text that replaces
;      it: NC = a name was chosen, C = none (the prefix + typed filter)
ac_run:
        ld (ac_slot),a
        ld a,b
        ld (ac_crow),a
        ld hl,il_out            ; "Inst.mem": prefix "Inst.", filter "mem"
        ld de,0
.d:     ld a,(hl)
        or a
        jr z,.d2
        cp '.'
        jr nz,.d1
        ld d,h
        ld e,l
.d1:    inc hl
        jr .d
.d2:    ld a,d
        or e
        ld hl,il_out
        jr z,.nod
        inc de                  ; DE = after the dot
        push de
        ld b,d                  ; prefix (with the dot) -> ac_pre
        ld c,e
        ld de,ac_pre
.p:     ld a,h
        cp b
        jr nz,.p1
        ld a,l
        cp c
        jr z,.p2
.p1:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .p
.p2:    xor a
        ld (de),a
        pop hl
        jr .flt
.nod:   xor a
        ld (ac_pre),a
.flt:   ld de,ac_flt            ; the filter
        ld b,AC_NLEN-1
.f:     ld a,(hl)
        ld (de),a
        or a
        jr z,.f2
        inc hl
        inc de
        djnz .f
        xor a
        ld (de),a
.f2:    xor a
        ld (ac_sel),a
        call ac_collect
        call ac_filter
        ld a,(ac_n)
        or a
        jr nz,.some
        call beep
        jp ac_keep
.some:  dec a
        jp z,ac_take            ; one candidate: at once
        ; ---- the window
        ld a,(ac_n)
        cp AC_ROWS
        jr c,.r
        ld a,AC_ROWS
.r:     ld (ac_rows),a
        add a,2                 ; + the filter row + a margin
        ld d,a
        ld a,(ac_crow)          ; below the line, or above it
        inc a
        ld b,a
        add a,d
        cp 24
        jr c,.pos
        ld a,(ac_crow)
        sub d
        ld b,a
.pos:   ld c,AC_X0/8
        ld e,AC_COLS
        call win_open
        xor a
        ld (ac_sel),a
        ld (ac_top),a
        call ac_draw
.key:   call kb_wait
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jp z,.take
        cp K_COMPL
        jp z,.take
        cp K_BREAK
        jp z,.close
        cp K_EDIT
        jp z,.close
        cp K_DEL
        jr z,.del
        cp K_MOUSE
        jr z,.mouse
        call ac_wch             ; a letter / digit / _: the filter grows
        jr nc,.key
        ld hl,ac_flt
        call strlen
        cp AC_NLEN-1
        jr nc,.key
        ld e,a
        ld d,0
        add hl,de
        ld a,c
        ld (hl),a
        inc hl
        ld (hl),0
        call ac_filter
        ld a,(ac_n)
        or a
        jr z,.close             ; (no name fits: the text stays typed)
        jr .redo
.del:   ld hl,ac_flt
        call strlen
        or a
        jr z,.key
        dec a
        ld e,a
        ld d,0
        add hl,de
        ld (hl),0
        call ac_filter
.redo:  xor a
        ld (ac_sel),a
        ld (ac_top),a
        call ac_draw
        jr .key
.up:    ld a,(ac_sel)
        or a
        jr z,.key
        dec a
        jr .mv
.down:  ld a,(ac_sel)
        inc a
        ld hl,ac_n
        cp (hl)
        jr nc,.key
.mv:    ld (ac_sel),a
        ld hl,ac_top            ; keep it in the visible rows
        cp (hl)
        jr nc,.m1
        ld (hl),a
.m1:    ld a,(ac_rows)
        ld b,a
        ld a,(ac_sel)
        sub (hl)
        cp b
        jr c,.m2
        ld a,(ac_sel)
        sub b
        inc a
        ld (hl),a
.m2:    call ac_draw
        jp .key
.mouse: ld a,(ac_rows)
        ld b,1
        call ms_item
        jr c,.close
        ld hl,ac_top
        add a,(hl)
        ld hl,ac_n
        cp (hl)
        jr nc,.close
        ld (ac_sel),a
.take:  call win_close
        jr ac_take
.close: call win_close
        ; fall through
; ac_keep: no choice: il_out = prefix + the filter typed (C)
ac_keep:
        ld hl,ac_flt
        call ac_out
        scf
        ret
; ac_take: the selected candidate -> il_out = prefix + its name (NC)
ac_take:
        ld a,(ac_sel)
        call ac_vnam
        call ac_out
        or a
        ret

; ac_out: HL = name -> il_out = ac_pre + name
ac_out: push hl
        ld hl,ac_pre
        ld de,il_out
        call put_str
        pop hl
        call put_str
        xor a
        ld (de),a
        ret

; ac_wch: A = key -> C = a letter, digit or _ (C register = the char)
ac_wch: ld c,a
        cp '_'
        scf
        ret z
        cp '0'
        ccf
        ret nc
        cp '9'+1
        ret c
        call to_upper
        cp 'A'
        ccf
        ret nc
        cp 'Z'+1
        ret

; ac_vnam: A = index in the filtered list -> HL = its name (ac_nbuf)
ac_vnam:
        ld e,a
        ld d,0
        ld hl,ac_vis
        add hl,de
        ld a,(hl)
        ; fall through
; ac_name: A = entry number -> HL = ac_nbuf = its name (0); ac_e = entry
ac_name:
        call ac_eadr
        ld (ac_e),hl
        ld a,(hl)               ; kind
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                ; HL = the name in the project / a table
        dec a
        jr nz,.cp
        inc hl                  ; (a symbol record: the name at +3)
        inc hl
        inc hl
.cp:    ld de,ac_nbuf
        ld b,AC_NLEN-1
.l:     ld a,(hl)
        or a
        jr z,.e
        cp ' '                  ; (a local: "Name : TYPE")
        jr z,.e
        cp ':'
        jr z,.e
        ld (de),a
        inc hl
        inc de
        djnz .l
.e:     xor a
        ld (de),a
        ld hl,ac_nbuf
        ret

; ac_eadr: A = entry number -> HL = entry (keeps BC)
ac_eadr:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld de,ac_list
        add hl,de
        ret

; ---- ac_filter: ac_vis / ac_n = the entries starting with ac_flt
ac_filter:
        xor a
        ld (ac_n),a
        ld (ac_i),a
.l:     ld a,(ac_i)
        ld hl,ac_cnt
        cp (hl)
        ret nc
        call ac_name
        ld de,ac_flt
.c:     ld a,(de)
        or a
        jr z,.yes
        call to_upper
        ld b,a
        ld a,(hl)
        call to_upper
        cp b
        jr nz,.n
        inc hl
        inc de
        jr .c
.yes:   ld a,(ac_n)
        ld e,a
        ld d,0
        ld hl,ac_vis
        add hl,de
        ld a,(ac_i)
        ld (hl),a
        ld hl,ac_n
        inc (hl)
.n:     ld hl,ac_i
        inc (hl)
        jr .l

; ---- ac_draw: the filter row and the list rows of the window
ac_draw:
        ld a,(win_r)            ; filter row: "prefix" + filter + "_"
        push af                 ; (not its top line: the frame)
        ld b,a
        ld a,(win_bx)
        inc a
        ld c,a
        ld a,(win_bw)
        sub 2
        ld d,a
        ld hl,0x0107
        ld e,PX_CLR
        call px_span
        pop af
        ld (pt_row),a
        ld a,AC_X0+4
        ld (pt_x),a
        ld hl,ac_pre
        call pt_puts
        ld hl,ac_flt
        call pt_puts
        ld a,'_'
        call pt_putc
        xor a
        ld (ac_r),a
.l:     ld a,(ac_r)
        ld hl,ac_rows
        cp (hl)
        ret nc
        ld hl,win_r
        add a,(hl)
        inc a
        call ac_clr
        ld (pt_row),a
        ld a,(ac_r)
        ld hl,ac_top
        add a,(hl)
        ld hl,ac_n
        cp (hl)
        jr nc,.n
        push af
        call ac_vnam
        ld a,AC_X0+4
        ld (pt_x),a
        call pt_puts
        call ac_info
        ld a,AC_X0+AC_XINF
        ld (pt_x),a
        call pt_puts
        pop af
        ld hl,ac_sel
        cp (hl)
        jr nz,.n
        ld a,(pt_row)           ; the selected row: inverted
        ld e,PX_XOR
        call ac_span
.n:     ld hl,ac_r
        inc (hl)
        jr .l

; ac_info: the entry ac_e -> HL = its right column text (ac_nbuf)
ac_info:
        ld hl,(ac_e)
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        or a
        jr z,.loc
        dec a
        jr z,.sym
        ld a,(hl)               ; a member: 0 BOOL, 1 TIME, 2 INT
        ld hl,txt_ac_bool
        or a
        ret z
        ld hl,txt_ac_time
        dec a
        ret z
        ld hl,txt_ac_int
        ret
.sym:   ex de,hl                ; a symbol: its address, e.g. %MW0
        inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        ld hl,0
        ld b,0
        ld de,ac_nbuf
        call op_format
        ld hl,ac_nbuf
        ret
.loc:   ex de,hl                ; a local: the word after ":"
.l1:    ld a,(hl)
        or a
        jr z,.l3
        inc hl
        cp ':'
        jr nz,.l1
.l2:    ld a,(hl)
        cp ' '
        jr nz,.l3
        inc hl
        jr .l2
.l3:    ld de,ac_nbuf
        ld b,7
.l4:    ld a,(hl)
        call ac_wch
        jr nc,.l5
        ld (de),a
        inc hl
        inc de
        djnz .l4
.l5:    xor a
        ld (de),a
        ld hl,ac_nbuf
        ret

; ac_clr: A = row -> its inside cleared (keeps A)
ac_clr: ld e,PX_CLR
; ac_span: A = row, E = operation -> on the inside of the window row
ac_span:
        push af
        ld b,a
        ld a,(win_bx)
        inc a
        ld c,a
        ld a,(win_bw)
        sub 2
        ld d,a
        ld hl,0x0008
        call px_span
        pop af
        ret

; ---- ac_collect: ac_list / ac_cnt = the candidates (without a filter);
;      entry [kind 0 local / 1 symbol / 2 member][pointer][member type]
ac_collect:
        xor a
        ld (ac_cnt),a
        ld a,(ac_pre)
        or a
        jp nz,ac_members
        ; ---- the locals: the VAR block at the start of the body
        ld a,(ac_slot)
        call pou_body
        ld (ac_p),hl
        add hl,bc
        ld (ac_end),hl
        call ac_line            ; line 0 must be "VAR"
        jr c,.syms
        ld hl,txt_ac_var
        call ac_is
        jr nz,.syms
.loc:   call ac_line
        jr c,.syms
        push hl
        ld hl,txt_ac_endv
        call ac_is
        pop hl
        jr z,.syms
        ld a,(hl)
        call ac_wch
        jr nc,.loc              ; (empty or a comment line)
        xor a                   ; the text in the project: record + 3
        call ac_add
        jr .loc
        ; ---- the symbols, sorted by name
.syms:  ld a,(ac_cnt)
        ld (ac_nloc),a
        call sym_first
.s:     call sym_at_end
        ret nc
        push hl
        call .sym
        pop hl
        call sym_next
        jr .s
.sym:   ld (ac_sn),hl
        ld a,(ac_cnt)
        cp AC_MAX
        ret nc
        ld a,(ac_nloc)          ; its place: before the first greater name
        ld (ac_i),a
.sp:    ld a,(ac_i)
        ld hl,ac_cnt
        cp (hl)
        jr nc,.sput
        call ac_name
        ex de,hl
        ld hl,(ac_sn)
        inc hl
        inc hl
        inc hl
        call ac_cmp
        jr c,.sput
        ld hl,ac_i
        inc (hl)
        jr .sp
.sput:  ld a,(ac_cnt)           ; the entries from there one up
        call ac_eadr
        ld d,h
        ld e,l
        inc de
        inc de
        inc de
        dec hl                  ; HL = the last byte, DE = it + 4
        push hl
        ld a,(ac_i)
        call ac_eadr
        ex de,hl
        pop hl
        push hl
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l                  ; BC = the bytes to move
        pop hl
        ld d,h
        ld e,l
        inc de
        inc de
        inc de
        inc de
        ld a,b
        or c
        jr z,.sp2
        lddr
.sp2:   ld a,(ac_i)
        call ac_eadr
        ld (hl),1
        inc hl
        ld de,(ac_sn)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,ac_cnt
        inc (hl)
        ret

; ac_add: A = kind, HL = pointer, C = member type -> a new entry (if room)
ac_add: ld b,a
        ld a,(ac_cnt)
        cp AC_MAX
        ret nc
        push hl
        call ac_eadr
        pop de
        ld (hl),b
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),c
        ld hl,ac_cnt
        inc (hl)
        ret

; ac_members: the members of the FB instance in ac_pre ("Inst.")
ac_members:
        ld hl,ac_pre
        ld de,ac_lbuf
        call put_str
        dec de
        xor a
        ld (de),a               ; (without the dot)
        ld hl,ac_lbuf
        call op_parse
        ret c
        and AR_MASK
        cp AR_FBI
        ret nz
        ld a,(hl)
        or a
        ret nz
        ld a,c                  ; type = index / 4
        rrca
        rrca
        and 0x3F
        ld (ac_sa),a
        ld l,a                  ; fb_members + type * 20
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,fb_members
        add hl,de
        ld (ac_sn),hl
        ld a,(ac_sa)            ; fb_mdesc + type * 5
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,fb_mdesc
        add hl,de
        ld (ac_p),hl
        ld b,5
.m:     push bc
        ld hl,(ac_sn)
        ld a,(hl)
        or a
        jr z,.n
        ld hl,(ac_p)            ; the type: BOOL, TIME (timers) or INT
        ld c,0
        bit 7,(hl)
        jr z,.t
        inc c
        ld a,(ac_sa)
        cp FBT_CTU
        jr c,.t
        inc c
.t:     ld hl,(ac_sn)
        ld a,2
        call ac_add
.n:     ld hl,(ac_sn)
        ld de,4
        add hl,de
        ld (ac_sn),hl
        ld hl,(ac_p)
        inc hl
        ld (ac_p),hl
        pop bc
        djnz .m
        ret

; ac_cmp: HL, DE = names -> C if HL < DE (ignoring case)
ac_cmp: ld a,(de)
        call to_upper
        ld b,a
        ld a,(hl)
        call to_upper
        cp b
        ret nz                  ; (C: HL < DE)
        or a
        ret z
        inc hl
        inc de
        jr ac_cmp

; ac_line: the line record at ac_p -> its text in ac_lbuf, ac_p = next;
;      C = past the end of the body
ac_line:
        ld hl,(ac_p)
        ld de,(ac_end)
        or a
        sbc hl,de
        ccf
        ret c
        add hl,de
        ld c,(hl)
        ld b,0
        push hl
        add hl,bc
        ld (ac_p),hl
        pop hl
        inc hl
        inc hl
        inc hl
        push hl
        ld a,c
        sub 3
        ld de,ac_lbuf
        jr z,.e
        jr c,.e
        cp 63
        jr c,.ok
        ld a,63
.ok:    ld c,a
        ldir
.e:     xor a
        ld (de),a
        pop hl                  ; HL = the text in the project
        ret

; ac_is: HL = word -> Z if ac_lbuf starts with it as a whole word
ac_is:  ld de,ac_lbuf
.l:     ld a,(hl)
        or a
        jr z,.e
        ex de,hl
        cp (hl)
        ex de,hl
        ret nz
        inc hl
        inc de
        jr .l
.e:     ld a,(de)               ; the next char ends the word
        call ac_wch
        sbc a,a                 ; (a word char: A = 0xFF, NZ)
        or a
        ret

txt_ac_var:  db "VAR",0
txt_ac_endv: db "END_VAR",0
txt_ac_bool: db "BOOL",0
txt_ac_int:  db "INT",0
txt_ac_time: db "TIME",0
ac_slot: db 0
ac_crow: db 0
ac_rows: db 0
ac_sel:  db 0
ac_top:  db 0
ac_n:    db 0
ac_i:    db 0
ac_r:    db 0
ac_cnt:  db 0
ac_nloc: db 0
ac_sa:   db 0
ac_si:   db 0
ac_sn:   dw 0
ac_e:    dw 0
ac_p:    dw 0
ac_end:  dw 0
ac_pre:  ds 34
ac_flt:  ds AC_NLEN
ac_nbuf: ds AC_NLEN
ac_lbuf: ds 64
ac_vis:  ds AC_MAX
ac_list: ds AC_MAX*4
