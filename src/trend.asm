; ============================================================
; trend.asm - trend page of the simulation (DEMO bank)
; ============================================================
; The BOOL entries of the watch list and the ET / CV members of timers
; and counters (up to 8, in list order) are sampled every tr_rate frames,
; also while another page is shown. A sample is a level 0-9: FALSE / TRUE
; are 0 / 9, ET and CV are scaled by their PT / PV (9 = reached). Trace t
; has its own ring buffer, the 256 bytes at tr_buf + t*256. The trend page
; (sim page 2) draws them as time charts: a label on the left, then 200
; pixels of history, the newest sample on the right edge. A trace takes
; two text rows: level 9 is the line beside the label, level 0 (dotted)
; 9 pixels below. When the chart is full it scrolls left by 8 pixels.
; ============================================================
TR_ROW0   EQU 2             ; text row of the first trace
TR_MAX    EQU 8             ; traces
TR_X0     EQU 56            ; first pixel of the chart
TR_COL0   EQU TR_X0/8
TR_LX     EQU 2             ; x of the labels
TR_W      EQU 200           ; chart width (samples)
TR_ROWE   EQU 20            ; the row after the page (sim.asm ROW_SEP)

; ---- tr_reset: empty history (start of the simulation)
tr_reset:
        xor a
        ld (tr_head),a
        ld (tr_cnt),a
        ld hl,(frames)
        ld (tr_last),hl
        ret

; ---- tr_zoom: Z: the next time base; the history starts again
tr_zoom:
        ld a,(tr_base)
        inc a
        cp TR_NB
        jr c,.s
        xor a
.s:     ld (tr_base),a
        jr tr_reset

; tr_rate: HL -> rate of the time base (frames per sample), A = rate
tr_rate:
        ld a,(tr_base)
        ld e,a
        ld d,0
        ld hl,tr_rates
        add hl,de
        ld a,(hl)
        ret

; ---- tr_tick: A = simulation page; called once per loop of the
;      simulation (which can take several frames). Adds a sample for every
;      tr_rate frames passed (the current values; the PLC scans only once
;      per loop anyway), so the time axis stays true; draws them on page 2
tr_tick:
        ld (tr_page),a
        call tr_rate
        ld e,a
        ld d,0
        xor a
        ld (tr_k),a
.c:     ld hl,(tr_last)         ; the time of the next sample
        add hl,de
        push hl
        ld hl,(frames)
        pop bc
        or a
        sbc hl,bc
        ret c                   ; (with tr_k = 0: not yet)
        ld (tr_last),bc
        ld hl,tr_k
        inc (hl)
        ld a,(hl)
        cp 16
        jr c,.n
        ld hl,(frames)          ; far behind: from now on
        ld (tr_last),hl
        jr .go
.n:     ld hl,(frames)          ; another one due?
        ld bc,(tr_last)
        or a
        sbc hl,bc
        ld a,h
        or a
        jr nz,.c
        ld a,l
        cp e
        jr nc,.c
.go:    call tr_sample
.rep:   ld a,(tr_head)          ; the levels into the buffers
        ld l,a
        inc a
        ld (tr_head),a
        ld h,high tr_buf
        ld de,tr_lv
        ld a,(tr_n)
        or a
        jr z,.st
        ld b,a
.sv:    ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz .sv
.st:    ld a,(tr_cnt)
        cp TR_W
        jr nc,.full
        inc a
        ld (tr_cnt),a
.full:  call tr_vis
        jr nz,.nx
        ld a,(tr_gx)
        cp TR_W
        call nc,tr_scroll
        ld a,(tr_head)          ; the newest sample
        dec a
        ld e,a
        call tr_col
.nx:    ld hl,tr_k
        dec (hl)
        jr nz,.rep
        ld a,(tr_page)
        cp 2
        ret nz
        call tr_vis
        jp z,tr_lab
        jp tr_draw              ; the watch list has changed: all again

; tr_vis: Z = the trend page is shown with the traces drawn so far
tr_vis: ld a,(tr_page)
        cp 2
        ret nz
        ld a,(tr_dn)
        ld b,a
        ld a,(tr_n)
        cp b
        ret

; tr_sample: the levels of the traces -> tr_lv, tr_n = number of traces
tr_sample:
        call wt_count
        ld (tr_wn),a
        xor a
        ld (wt_i),a
        ld (tr_n),a
.l:     ld a,(tr_wn)
        ld e,a
        ld a,(wt_i)
        cp e
        ret nc
        ld a,(tr_n)
        cp TR_MAX
        ret nc
        call wt_value           ; A = kind, DE = value
        call tr_level
        jr c,.n
        ld c,a
        ld a,(tr_n)
        ld e,a
        inc a
        ld (tr_n),a
        ld d,0
        ld hl,tr_lv
        add hl,de
        ld (hl),c
.n:     ld hl,wt_i
        inc (hl)
        jr .l

; tr_level: watch entry wt_i, A = kind, DE = value (wt_value) -> NC: A = level
;      0-9; C: not drawn (words other than ET / CV of a timer or counter)
tr_level:
        ld (tr_kd),a
        cp 1
        jr nz,.w
        ld a,e                  ; BOOL: 0 / 9
        or a
        ret z
        ld a,9
        ret
.w:     cp 2
        ret c                   ; (kind 0: nothing)
        push de
        ld a,(wt_i)             ; an FB member whose word is at instance + 4
        call wt_entry           ; (ET / CV): PT / PV is the word before it
        ld a,(hl)
        and AR_MASK
        cp AR_FBM
        jr nz,.no
        inc hl
        ld l,(hl)
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,RT_FB+4
        add hl,de
        ld de,(cp_arg)
        or a
        sbc hl,de
        jr nz,.no
        ex de,hl
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)               ; DE = preset
        pop hl                  ; HL = value
        ld a,(tr_kd)            ; a negative CV: 0
        cp 3
        jr z,.u
        bit 7,h
        jr nz,.zero
.u:     ld a,d
        or e
        jr nz,.cmp
        ld a,h                  ; preset 0: 9 for any value
        or l
        jr z,.zero
        jr .full
.cmp:   or a
        sbc hl,de
        jr nc,.full             ; reached
        add hl,de
.sc:    ld a,d                  ; value * 9 must fit 16 bits
        cp 0x1C
        jr c,.m
        srl d
        rr e
        srl h
        rr l
        jr .sc
.m:     ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,bc
        xor a                   ; A = value * 9 / preset (0-8)
.dv:    or a
        sbc hl,de
        jr c,.dd
        inc a
        jr .dv
.dd:    or a
        ret
.full:  ld a,9
        or a
        ret
.zero:  xor a
        ret
.no:    pop de
        scf
        ret

; ---- tr_draw: the whole trend page
tr_draw:
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
        cp TR_ROWE
        jr c,.cl
        ld bc,1*256             ; header: "Signal", the time window
        ld de,0x2000+ATTR_TITLE
        call scr_fill_attr
        ld a,1
        ld (pt_row),a
        ld a,TR_LX              ; (aligned with the labels)
        ld (pt_x),a
        ld hl,txt_tr_sig
        call pt_puts
        ld a,(tr_base)
        add a,a
        ld e,a
        ld d,0
        ld hl,tr_wins
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,252
        call pt_puts_r
        call tr_sample
        ld a,(tr_n)
        ld (tr_dn),a
        xor a
        ld (tr_gx),a
        ld a,(tr_n)
        or a
        jr nz,.lab
        ld a,TR_ROW0+1          ; no BOOL entry: a hint
        ld (pt_row),a
        xor a
        ld (pt_x),a
        ld hl,txt_tr_none
        jp pt_puts
.lab:   xor a                   ; the labels
        ld (wt_i),a
        ld a,TR_ROW0
        ld (pt_row),a
.ll:    ld a,(tr_wn)
        ld e,a
        ld a,(wt_i)
        cp e
        jr nc,.hist
        ld a,(pt_row)
        cp TR_ROW0+TR_MAX*2
        jr nc,.hist
        call wt_value
        call tr_level
        call nc,tr_name
        ld hl,wt_i
        inc (hl)
        jr .ll
.hist:  call tr_vline              ; the frame: label separator, zero lines
        ld c,TR_COL0
        call tr_dots
        ld a,(tr_cnt)           ; the history: the last tr_cnt samples
        or a
        ret z
        ld b,a
        ld a,(tr_head)
        sub b
        ld e,a
.h:     push bc
        push de
        call tr_col
        pop de
        inc e
        pop bc
        djnz .h
        ; fall through: the label colours of the newest sample

; tr_lab: labels of the traces at level 9 (TRUE, ET / CV reached) black
;      on bright green
tr_lab:
        ld a,(tr_n)
        or a
        ret z
        ld b,a
        ld a,(tr_head)
        dec a
        ld l,a
        ld h,high tr_buf
        ld c,TR_ROW0
.l:     push bc
        push hl
        ld b,c
        ld c,0
        ld de,TR_COL0*256+ATTR_NORMAL
        ld a,(hl)
        cp 9
        jr nz,.a
        ld e,ATTR_ON
.a:     call scr_fill_attr
        pop hl
        inc h
        pop bc
        inc c
        inc c
        djnz .l
        ret

; tr_name: the label of the trace at pt_row (wt_i): with View > Symbols the
;      symbol (if any), else the operand (an FB member: the symbol of the instance; only ET / CV are
;      drawn, so the member is clear);
;      pt_row moves to the next trace
tr_name:
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
        ld a,TR_LX
        ld (pt_x),a
        ld a,TR_X0-3
        ld (pt_xmax),a
        pop bc
        pop af
        ld b,a                  ; View > Addresses: the operand
        ld a,(view_sym)
        or a
        ld a,b
        jr z,.op
        and AR_MASK
        cp AR_FBM
        jr nz,.s
        ld a,AR_FBI
.s:     call sym_name_of
        jr nc,.p
.op:    ld hl,rd_o
.p:     call pt_puts
        ld a,255
        ld (pt_xmax),a
        ld hl,pt_row
        inc (hl)
        inc (hl)
        ret

; tr_col: E = index of a sample -> draws it in column tr_gx (a vertical line
;      from the level of the sample before, none in column 0), tr_gx + 1
tr_col:
        ld a,(tr_n)
        or a
        ret z
        ld b,a
        ld d,high tr_buf        ; D = buffer of trace t
        ld a,TR_ROW0*8+9        ; the level-0 line of trace 0
        ld (tr_py),a
.t:     push bc
        ld h,d
        ld l,e
        ld c,(hl)               ; C = level
        ld a,(tr_gx)
        or a
        ld a,c
        jr z,.p
        dec l
        ld a,(hl)               ; A = level before
.p:     cp c
        jr nc,.o
        ld b,a                  ; A = higher, C = lower
        ld a,c
        ld c,b
.o:     sub c
        inc a
        ld b,a                  ; B = pixels
        ld a,(tr_py)
        sub c                   ; from the lower level up
.e:     push bc
        push af
        call tr_set
        pop af
        pop bc
        dec a
        djnz .e
        ld a,(tr_py)
        add a,16
        ld (tr_py),a
        inc d
        pop bc
        djnz .t
        ld hl,tr_gx
        inc (hl)
        ret

; tr_set: A = pixel line -> sets the pixel of column tr_gx in it
tr_set: ld b,a
        and 7
        or 0x40
        ld h,a
        ld a,b
        rrca
        rrca
        rrca
        and 0x18
        or h
        ld h,a
        ld a,b
        rlca
        rlca
        and 0xE0
        ld l,a
        ld a,(tr_gx)
        add a,TR_X0
        ld c,a
        rrca
        rrca
        rrca
        and 0x1F
        or l
        ld l,a
        ld a,c
        and 7
        ld b,a
        ld a,0x80
        jr z,.d
.s:     rrca
        djnz .s
.d:     or (hl)
        ld (hl),a
        ret

; tr_scroll: the chart 8 pixels to the left, tr_gx - 8
tr_scroll:
        ld a,(tr_n)
        add a,a
        add a,TR_ROW0
        ld (tr_py),a            ; (here: the row after the last trace)
        ld b,TR_ROW0
.r:     push bc
        ld c,TR_COL0
        call pix_addr
        ld a,8
.l:     push af
        push hl
        ld d,h
        ld e,l
        inc l
        ld bc,31-TR_COL0
        ldir
        xor a
        ld (de),a
        pop hl
        inc h
        pop af
        dec a
        jr nz,.l
        pop bc
        inc b
        ld a,(tr_py)
        cp b
        jr nz,.r
        ld a,(tr_gx)
        sub 8
        ld (tr_gx),a
        ld c,31                 ; the zero lines in the new column
        ; fall through

; tr_dots: C = first cell -> the dotted zero lines (the FALSE level) of the
;      traces from cell C to the right edge
tr_dots:
        ld a,(tr_n)
        or a
        ret z
        ld b,a
        ld a,TR_ROW0+1          ; (the FALSE level: line 1 of the second row)
.t:     push bc
        push af
        ld b,a
        call pix_addr
        inc h
        ld a,32
        sub c
        ld b,a
.d:     ld (hl),0x88
        inc l
        djnz .d
        pop af
        add a,2
        pop bc
        djnz .t
        ret

; tr_vline: the vertical line between the labels and the chart (x = 55)
tr_vline:
        ld a,(tr_n)
        add a,a
        ld b,a
        ld a,TR_ROW0
.r:     push bc
        push af
        ld b,a
        ld c,TR_X0/8-1
        call pix_addr
        ld b,8
.l:     ld a,(hl)
        or 0x01
        ld (hl),a
        inc h
        djnz .l
        pop af
        inc a
        pop bc
        djnz .r
        ret

TR_NB     EQU 3
tr_rates: db 1,5,25         ; frames per sample: windows 4 s, 20 s, 100 s
tr_wins:  dw txt_tr_w0,txt_tr_w1,txt_tr_w2
txt_tr_w0:   db "Z Zoom: 4 s",0
txt_tr_w1:   db "Z Zoom: 20 s",0
txt_tr_w2:   db "Z Zoom: 100 s",0
txt_tr_sig:  db "Signal",0
txt_tr_none: db "Add BOOL, ET or CV operands on the watch page (W)",0

tr_base:  db 1
tr_head:  db 0
tr_cnt:   db 0
tr_last:  dw 0
tr_page:  db 0
tr_n:     db 0
tr_dn:    db 0
tr_wn:    db 0
tr_gx:    db 0
tr_k:     db 0
tr_kd:    db 0
tr_lv:    ds TR_MAX
tr_py:    db 0
        ALIGN 256
tr_buf:   ds 256*TR_MAX
