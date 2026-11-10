; ============================================================
; trend.asm - trend page of the simulation (DEMO bank)
; ============================================================
; The BOOL entries of the watch list (up to 8, in list order) are
; sampled every tr_rate frames into a ring buffer (one byte per sample,
; bit t = trace t), also while another page is shown. The trend page
; (sim page 2) draws them as time charts: a label on the left, then
; 200 pixels of history, the newest sample on the right edge. A trace
; takes two text rows: TRUE is the high line (beside the label), FALSE
; the low one 9 pixels below. When
; the chart is full it scrolls left by 8 pixels.
; ============================================================
TR_ROW0   EQU 2             ; text row of the first trace
TR_MAX    EQU 8             ; traces
TR_X0     EQU 56            ; first pixel of the chart
TR_COL0   EQU TR_X0/8
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
        ld (tr_new),a
.rep:   ld a,(tr_new)
        ld c,a
        ld hl,tr_head
        ld e,(hl)
        inc (hl)
        ld d,0
        ld hl,tr_buf
        add hl,de
        ld (hl),c
        ld a,(tr_cnt)
        cp TR_W
        jr nc,.full
        inc a
        ld (tr_cnt),a
.full:  call tr_vis
        jr nz,.nx
        ld a,(tr_gx)
        cp TR_W
        call nc,tr_scroll
        ld a,(tr_head)          ; the newest sample and the one before
        dec a
        ld l,a
        ld h,high tr_buf
        ld a,(hl)
        ld (tr_cs),a
        ld b,a
        ld a,(tr_gx)            ; (the first column: no edge)
        or a
        ld a,b
        jr z,.p
        dec l
        ld a,(hl)
.p:     ld (tr_ps),a
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

; tr_sample: the BOOL watch entries -> A = bits, tr_n = number of traces
tr_sample:
        call wt_count
        ld (tr_wn),a
        xor a
        ld (wt_i),a
        ld (tr_n),a
        ld bc,0x0100            ; B = mask, C = bits
.l:     ld a,(tr_wn)
        ld e,a
        ld a,(wt_i)
        cp e
        jr nc,.e
        push bc
        call wt_value           ; A = kind, E = value
        pop bc
        cp 1
        jr nz,.n
        ld a,e
        or a
        jr z,.z
        ld a,c
        or b
        ld c,a
.z:     ld hl,tr_n
        inc (hl)
        rlc b
        jr c,.e                 ; 8 traces
.n:     ld hl,wt_i
        inc (hl)
        jr .l
.e:     ld a,c
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
        xor a
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
        cp 1
        call z,tr_name
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
        ld (tr_i),a
        ld a,(tr_cnt)
        ld b,a
.h:     push bc
        ld a,(tr_i)
        ld l,a
        ld h,0
        ld de,tr_buf
        add hl,de
        ld a,(hl)
        ld (tr_cs),a
        ld b,a
        ld a,(tr_gx)            ; the first column: no edge
        or a
        ld a,b
        jr z,.p
        dec l
        ld a,(hl)
.p:     ld (tr_ps),a
        call tr_col
        ld hl,tr_i
        inc (hl)
        pop bc
        djnz .h
        ; fall through: the label colours of the newest sample

; tr_lab: labels of the TRUE traces black on bright green
tr_lab:
        ld a,(tr_head)
        dec a
        ld l,a
        ld h,0
        ld de,tr_buf
        add hl,de
        ld a,(hl)
        ld (tr_cs),a
        ld a,(tr_n)
        or a
        ret z
        ld b,a
        ld c,TR_ROW0
.l:     push bc
        ld b,c
        ld c,0
        ld de,TR_COL0*256+ATTR_NORMAL
        ld hl,tr_cs
        srl (hl)
        jr nc,.a
        ld e,ATTR_ON
.a:     call scr_fill_attr
        pop bc
        inc c
        inc c
        djnz .l
        ret

; tr_name: the label of the trace at pt_row (wt_i): the symbol, else the
;      operand; pt_row moves to the next trace
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
        pop bc
        pop af
        ld hl,rd_o
        and AR_MASK             ; (an FB member: the operand, e.g. TON0.Q)
        cp AR_FBM
        jr z,.p
        call sym_name_of
        jr nc,.p
        ld hl,rd_o
.p:     xor a
        ld (pt_x),a
        ld a,TR_X0-3
        ld (pt_xmax),a
        call pt_puts
        ld a,255
        ld (pt_xmax),a
        ld hl,pt_row
        inc (hl)
        inc (hl)
        ret

; tr_col: draws column tr_gx (sample tr_cs, previous tr_ps), tr_gx + 1
tr_col:
        ld a,(tr_n)
        or a
        ret z
        ld b,a
        ld a,TR_ROW0*8          ; the high line of trace 0
        ld (tr_py),a
.t:     push bc
        ld a,(tr_cs)
        ld hl,tr_ps
        xor (hl)
        rra
        ld a,(tr_py)
        jr c,.edge
        ld a,(tr_cs)
        rra
        ld a,(tr_py)
        jr c,.hi
        add a,9                 ; the low line
.hi:    call tr_set
        jr .nx
.edge:  ld b,10                 ; a change: the vertical edge
.e:     push bc
        push af
        call tr_set
        pop af
        pop bc
        inc a
        djnz .e
.nx:    ld hl,tr_cs
        srl (hl)
        ld hl,tr_ps
        srl (hl)
        ld a,(tr_py)
        add a,16
        ld (tr_py),a
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

; tr_vline: the vertical line between the labels and the chart (x = 54)
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
        or 0x02
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
txt_tr_none: db "No BOOL operands: add them on the watch page (W)",0

tr_base:  db 1
tr_head:  db 0
tr_cnt:   db 0
tr_last:  dw 0
tr_page:  db 0
tr_n:     db 0
tr_dn:    db 0
tr_wn:    db 0
tr_gx:    db 0
tr_i:     db 0
tr_cs:    db 0
tr_k:     db 0
tr_new:   db 0
tr_ps:    db 0
tr_py:    db 0
        ALIGN 256
tr_buf:   ds 256
