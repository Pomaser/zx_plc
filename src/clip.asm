; ============================================================
; clip.asm - mark / copy / cut / paste in the editors (DEMO bank)
; ============================================================
; A block is marked with SS+A (mk_a = start line / row, the cursor is the
; other end) and shown by a 2 px bar at the left screen edge. Copy (SS+D)
; and Cut put the records of the block into clip_buf (BANK_DATA); Paste
; (SS+F) inserts them in front of the cursor line (IL) or in front of the
; rung / network of the cursor (LD / FBD). Without a mark the current line /
; rung / network is taken. LD blocks grow to whole rungs (rows joined by
; vertical links), FBD blocks to whole networks (the FBD editor sets cl_a,
; cl_b and cl_p, it knows the blocks); the comment rows just above a rung /
; network go with it. FB instances are kept as they are.
; ============================================================

; ---- mk_draw: the marker bars of the visible lines / rows
;      HL = first visible line / row, DE = cursor line / row, B = visible
;      count, C = first screen row; A bit 0: 2 screen rows per item (LD,
;      FBD), bit 1: the cursor line is left alone (IL: inverted number)
mk_draw:
        ld (md_top),hl
        ld (md_cur),de
        ld (md_flags),a
        ld a,c
        ld (md_row),a
        ld a,b
        ld (md_cnt),a
        ld hl,(mk_a)
        ld a,h
        and l
        inc a
        ret z                   ; no mark
        call cl_range
.l:     ld a,(md_cnt)
        or a
        ret z
        dec a
        ld (md_cnt),a
        ld hl,(md_top)          ; inside md_a..md_b?
        ld de,(md_a)
        or a
        sbc hl,de
        jr c,.out
        ld hl,(md_b)
        ld de,(md_top)
        or a
        sbc hl,de
        jr c,.out
        ld a,PX_SET
        jr .op
.out:   ld a,PX_CLR
.op:    ld (md_op),a
        ld a,(md_flags)
        and 2
        jr z,.draw
        ld hl,(md_top)
        ld de,(md_cur)
        or a
        sbc hl,de
        jr z,.next
.draw:  ld a,(md_row)
        call .bar
        ld a,(md_flags)
        and 1
        jr z,.next
        ld a,(md_row)
        inc a
        call .bar
.next:  ld hl,(md_top)
        inc hl
        ld (md_top),hl
        ld a,(md_flags)
        and 1
        inc a
        ld hl,md_row
        add a,(hl)
        ld (hl),a
        jr .l
.bar:   ld b,a                  ; A = screen row
        ld c,0
        ld d,2
        ld hl,0x0008
        ld a,(md_op)
        ld e,a
        jp px_span

; ---- cl_range: md_a / md_b = mk_a and md_cur in order
cl_range:
        ld hl,(mk_a)
        ld de,(md_cur)
        or a
        sbc hl,de
        add hl,de
        jr c,.lt
        ld (md_b),hl
        ld (md_a),de
        ret
.lt:    ld (md_a),hl
        ld (md_b),de
        ret

; ---- cl_cmd: A = CMD_MARK / CMD_COPY / CMD_PASTE / CMD_CUT, DE = cursor
;      line (IL) or row (LD / FBD) -> Z: nothing to redraw; NZ: the editor
;      redraws, DE = the new cursor line / row
cl_cmd:
        ld (cl_op),a
        ld (md_cur),de
        ld a,(cur_pou)
        call pou_lang
        inc a
        ld (cl_lang),a
        ld a,(cl_op)
        cp CMD_MARK
        jr nz,.nm
        ld hl,(mk_a)            ; SS+A: set the mark, or remove it
        ld a,h
        and l
        inc a
        jr z,.set
        ld hl,0xFFFF
        ld (mk_a),hl
        jp cl_redraw
.set:   ld (mk_a),de
        xor a
        ret
.nm:    cp CMD_PASTE
        jp z,cl_paste
        ; ---- copy / cut: the block md_a..md_b
        ld hl,(mk_a)
        ld a,h
        and l
        inc a
        jr nz,.mk
        ld hl,(md_cur)          ; no mark: the cursor line / row
        ld (md_a),hl
        ld (md_b),hl
        jr .rg
.mk:    call cl_range
.rg:    ld hl,0xFFFF
        ld (mk_a),hl
        ld a,(cl_lang)
        cp 1
        jr z,.il
        cp 3
        jr z,.fbd
        call cl_rung_ext        ; LD: whole rungs
        jr .rows
.fbd:   ld h,0                  ; FBD: whole networks (from the editor)
        ld a,(cl_a)
        ld l,a
        ld (md_a),hl
        ld a,(cl_b)
        ld l,a
        ld (md_b),hl
        call cl_fbd_tail
.rows:  ld hl,md_a              ; with the comment rows above it
        call cl_cmt_up
        ld a,(md_a)
        ld d,a
        ld e,0
        call ld_find
        ld (cl_s),hl
        ld a,(md_b)
        inc a
        ld d,a
        ld e,0
        call ld_find
        ld (cl_e),hl
        jr .copy
.il:    ld de,(md_a)
        call cl_line_addr
        ld (cl_s),hl
        ld de,(md_b)
        inc de
        call cl_line_addr
        ld (cl_e),hl
.copy:  ld hl,(cl_e)
        ld de,(cl_s)
        or a
        sbc hl,de
        ld (clip_len),hl
        ld b,h
        ld c,l
        ld hl,(cl_s)
        ld de,clip_buf
        ld a,BANK_DATA
        call bank_copy
        ld a,(cl_lang)
        ld (clip_lang),a
        ld hl,(md_b)
        ld de,(md_a)
        or a
        sbc hl,de
        inc hl
        ld (clip_n),hl
        ld a,(md_a)
        ld (clip_r0),a
        ld a,(cl_op)
        cp CMD_CUT
        ld hl,txt_cl_copied
        jr nz,.msg
        ld a,(cl_lang)          ; ---- cut: the block removed
        cp 1
        jr nz,.cutr
        ld a,(cur_pou)
        call pou_body
        ex de,hl
        ld hl,(cl_s)
        or a
        sbc hl,de
        ex de,hl                ; DE = offset
        ld bc,(clip_len)
        ld a,(cur_pou)
        call pou_delete
        jr .cutm
.cutr:  ld a,(clip_n)
        ld b,a
.cr:    push bc
        ld a,(md_a)
        ld d,a
        BCALL ld_del_row
        pop bc
        djnz .cr
.cutm:  ld hl,(md_a)            ; the cursor at the gap
        ld (md_cur),hl
        ld hl,txt_cl_cut
.msg:   call cl_msg
        ; fall through

; ---- cl_redraw: NZ, DE = cursor
cl_redraw:
        call status_right       ; (free memory)
        ld de,(md_cur)
        or 1
        ret

; ---- cl_paste: the clipboard in front of the cursor line / rung / network
cl_paste:
        ld hl,0xFFFF
        ld (mk_a),hl
        ld a,(clip_lang)
        or a
        ld hl,txt_cl_empty
        jp z,cl_err
        ld b,a
        ld a,(cl_lang)
        cp b
        jr z,.lang
        ld hl,txt_cl_hil        ; "Clipboard holds IL / LD / FBD"
        ld a,b
        dec a
        jr z,.herr
        ld hl,txt_cl_hld
        dec a
        jr z,.herr
        ld hl,txt_cl_hfbd
.herr:  jp cl_err
.lang:  call proj_free          ; room for the records (+ an LD header)
        ld de,(clip_len)
        inc de
        or a
        sbc hl,de
        ld hl,err_il_mem
        jp c,cl_err
        ld a,(cl_lang)
        cp 1
        jr nz,.rows
        call cl_il_count        ; IL: at most IL_MAXLN lines
        ld de,(clip_n)
        add hl,de
        ld de,IL_MAXLN+1
        or a
        sbc hl,de
        ld hl,txt_cl_rows
        jp nc,cl_err
        ld de,(md_cur)
        call cl_line_addr
        jr .ins
.rows:  cp 3
        jr z,.fp
        call cl_rung_start      ; LD: in front of the rung of the cursor
        jr .pr
.fp:    ld h,0                  ; FBD: in front of the network (editor)
        ld a,(cl_p)
        ld l,a
        ld (md_cur),hl
.pr:    ld hl,md_cur            ; and in front of its comment rows
        call cl_cmt_up
        call ld_nrows
        ld b,a
        ld a,(clip_n)
        add a,b
        cp LD_MAXROWS+1
        ld hl,txt_cl_rows
        jp nc,cl_err
        call ld_hdr
        ld hl,err_il_mem
        jp c,cl_err
        ld a,(clip_n)           ; empty rows for the block
        ld b,a
.ir:    push bc
        ld a,(md_cur)
        ld d,a
        BCALL ld_ins_row
        pop bc
        djnz .ir
        ld a,(md_cur)
        ld d,a
        ld e,0
        call ld_find            ; HL = where the rows start
.ins:   push hl                 ; HL = insertion address -> DE = offset
        ld a,(cur_pou)
        call pou_body
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ex de,hl
        ld bc,(clip_len)
        ld a,(cur_pou)
        call pou_insert
        jr nc,.gap
        ld hl,err_il_mem
        jp cl_err
.gap:   ld (cl_s),hl
        ex de,hl                ; DE = gap
        ld hl,clip_buf
        ld bc,(clip_len)
        ld a,BANK_DATA
        call bank_copy
        ld a,(cl_lang)
        cp 1
        jr z,.done
        ld a,(clip_r0)          ; LD / FBD: the rows of the pasted records
        ld b,a
        ld a,(md_cur)
        sub b
        ld (cl_dr),a
        ld hl,(cl_s)
        ld de,(clip_len)
        add hl,de
        ld (cl_e),hl
        ld hl,(cl_s)
.fr:    push hl
        ld de,(cl_e)
        or a
        sbc hl,de
        pop hl
        jr nc,.done
        ld a,(cl_dr)
        add a,(hl)
        ld (hl),a
        call ld_skip
        jr .fr
.done:  ld hl,txt_cl_pasted
        call cl_msg
        jp cl_redraw

; ---- cl_err: HL = message -> popup, Z (the screen is restored)
cl_err: call ui_error
        xor a
        ret

; ---- cl_msg: HL = verb -> "Copied 3 lines" in the status bar (once)
cl_msg: ld de,popup_buf
        call put_str
        ld a,' '
        ld (de),a
        inc de
        ld hl,(clip_n)
        push hl
        call cl_dec
        ld hl,txt_cl_line
        ld a,(clip_lang)
        cp 1
        jr z,.u
        ld hl,txt_cl_row
.u:     call put_str
        pop hl
        dec hl
        ld a,h
        or l
        jr z,.one
        ld a,'s'
        ld (de),a
        inc de
.one:   xor a
        ld (de),a
        ld hl,popup_buf
        ld (il_err),hl
        ld a,1
        ld (xr_err),a
        ret

; ---- cl_dec: HL = 0-999 -> decimal digits at DE (no leading zeros)
cl_dec: ld (cl_out),de
        ld b,0                  ; B = 1 after the first digit
        ld de,100
        call .dig
        ld de,10
        call .dig
        ld b,1                  ; (the last digit always)
        ld de,1
        call .dig
        ld de,(cl_out)
        ret
.dig:   ld a,'0'-1
.s:     inc a
        or a
        sbc hl,de
        jr nc,.s
        add hl,de
        cp '0'
        jr nz,.w
        ld c,a
        ld a,b
        or a
        ret z
        ld a,c
.w:     ld de,(cl_out)
        ld (de),a
        inc de
        ld (cl_out),de
        ld b,1
        ret

; ---- cl_line_addr: DE = IL line -> HL = its record (or the body end)
cl_line_addr:
        push de
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (cl_bend),hl
        pop hl
        pop de
.l:     ld a,d
        or e
        ret z
        push de
        ld de,(cl_bend)
        push hl
        or a
        sbc hl,de
        pop hl
        pop de
        ret nc                  ; (past the last line)
        push de
        ld e,(hl)
        ld d,0
        add hl,de
        pop de
        dec de
        jr .l

; ---- cl_il_count: HL = number of IL lines of cur_pou
cl_il_count:
        ld de,0xFFFF
        call cl_line_addr       ; walks to the end, DE = lines left
        ld hl,0xFFFF
        or a
        sbc hl,de
        ret

; ---- cl_vl: A = row -> NZ: the row has a vertical link down (LD)
cl_vl:  ld (cl_vr),a
        ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        ret z
        push hl
        add hl,bc
        ld (cl_bend),hl
        pop hl
        inc hl                  ; header
.l:     push hl
        ld de,(cl_bend)
        or a
        sbc hl,de
        pop hl
        jr nc,.no
        ld a,(cl_vr)
        cp (hl)
        jr c,.no                ; (records are sorted by row)
        jr nz,.n
        inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        and LT_VL
        ret nz
.n:     call ld_skip
        jr .l
.no:    xor a
        ret

; ---- cl_rung_ext: md_a / md_b grow to whole LD rungs
cl_rung_ext:
.up:    ld a,(md_a)
        or a
        jr z,.dn
        dec a
        call cl_vl
        jr z,.dn
        ld hl,md_a
        dec (hl)
        jr .up
.dn:    call ld_nrows
        dec a
        ld hl,md_b
        cp (hl)
        ret z
        ret c
        ld a,(hl)
        call cl_vl
        ret z
        ld hl,md_b
        inc (hl)
        jr .dn

; ---- cl_rung_start: md_cur = the first row of its LD rung
cl_rung_start:
        ld a,(md_cur)
        or a
        ret z
        dec a
        call cl_vl
        ret z
        ld hl,md_cur
        dec (hl)
        jr cl_rung_start

; ---- cl_cmt_up: HL = row variable -> moves up over the comment rows just
;      above it (a comment belongs to the rung / network below it)
cl_cmt_up:
        ld a,(hl)
        or a
        ret z
        dec a
        push hl
        ld d,a
        ld e,0
        call ld_get
        pop hl
        and LT_MASK
        cp LT_CMT
        ret nz
        dec (hl)
        jr cl_cmt_up

; ---- cl_fbd_tail: an empty row after the FBD block goes with it (keeps
;      the pasted network apart from the next one)
cl_fbd_tail:
        call ld_nrows
        ld b,a
        ld a,(md_b)
        inc a
        cp b
        ret nc
        ld d,a
        ld e,0
        call ld_find
        jr nc,.used             ; an element at position 0
        push hl
        ld de,(lf_end)
        or a
        sbc hl,de
        pop hl
        jr nc,.empty
        ld a,(md_b)
        inc a
        cp (hl)
        ret z                   ; the row has elements
.empty: ld hl,md_b
        inc (hl)
.used:  ret

md_top:   dw 0
md_cur:   dw 0
md_a:     dw 0
md_b:     dw 0
md_flags: db 0
md_row:   db 0
md_cnt:   db 0
md_op:    db 0
cl_op:    db 0
cl_lang:  db 0
cl_s:     dw 0
cl_e:     dw 0
cl_bend:  dw 0
cl_vr:    db 0
cl_dr:    db 0
cl_out:   dw 0

txt_cl_copied: db "Copied",0
txt_cl_cut:    db "Cut",0
txt_cl_pasted: db "Pasted",0
txt_cl_line:   db " line",0
txt_cl_row:    db " row",0
txt_cl_empty:  db "The clipboard is empty",0
txt_cl_hil:    db "The clipboard holds IL",0
txt_cl_hld:    db "The clipboard holds LD",0
txt_cl_hfbd:   db "The clipboard holds FBD",0
txt_cl_rows:   db "Too many lines",0
