; ============================================================
; fbd_comp.asm - Function Block Diagram -> bytecode (RUN bank)
; ============================================================
; Same grid and record format as LD (positions 0-8 logic, 9 output).
; A network = consecutive used rows (and the rows covered by boxes),
; separated by empty or comment rows. It is evaluated column by column;
; the signal of each row is kept in the scratch bit S[r] (RT_SCR) and a
; row without a signal is "dead" (FALSE, nothing emitted).
;   IN        S = op (LDN when negated)      wire  -
;   empty     S = FALSE
;   AND/OR/XOR box at row r with h inputs: S[r] = S[r] op .. S[r+h-1]
;   NOT       S = NOT S
;   FB boxes  inputs -> members, CAL, S[r] = Q (timers: 2 rows, IN and PT;
;             PT is the preset stored in the block)
;   OUT (any column) LD S / ST op (STN when negated)
; The LD compiler helpers are shared (lc_get, lc_emit_*, lc_dead ...).
; ============================================================

; ---- fb_compile: compiles the FBD POU cp_slot (pass 2); C = error
fb_compile:
        ld a,(cur_pou)
        ld (lc_pou),a
        ld a,(cp_slot)
        ld (cur_pou),a
        xor a
        ld (fc_ld),a
        call .go
        call c,lc_errpos
        push af
        ld a,(lc_pou)
        ld (cur_pou),a
        pop af
        ret
.go:    call ld_nrows
        ld (lc_nrows),a
        xor a
        ld (lc_r0),a
.net:   ld a,(lc_nrows)         ; skip empty / comment rows
        ld b,a
        ld a,(lc_r0)
        cp b
        ret nc                  ; done (NC)
        call fc_row_used
        jr nz,.start
        ld hl,lc_r0
        inc (hl)
        jr .net
.start: ld a,(lc_r0)            ; network end: used rows and box rows
        ld (lc_r1),a
        call fc_box_end         ; A = last row covered by boxes of this row
        ld (fc_cov),a
.ext:   ld a,(lc_r1)
        inc a
        ld b,a
        ld a,(lc_nrows)
        cp b
        jr z,.endn
        jr c,.endn
        ld a,b
        push af
        call fc_row_used
        pop bc
        jr nz,.take
        ld a,(fc_cov)           ; empty, but inside a box
        cp b
        jr c,.endn
.take:  ld a,b
        ld (lc_r1),a
        call fc_box_end
        ld hl,fc_cov
        cp (hl)
        jr c,.ext
        ld (hl),a
        jr .ext
.endn:  xor a                   ; (error position: the network start)
        ld (lc_i),a
        ld (lc_p),a
        ld a,(lc_r0)
        inc a
        ld l,a
        ld h,0
        ld (cp_line),hl
        ld a,(lc_r0)
        ld b,a
        ld a,(lc_r1)
        sub b
        inc a
        ld (lc_n),a
        cp LC_MAXRR+1
        ld hl,err_lc_rows
        jp nc,cp_fail
        ld b,a                  ; all rows start without a signal
        ld hl,lc_dead
.dd:    ld (hl),1
        inc hl
        djnz .dd
        ; logic columns
        xor a
        ld (lc_p),a
.col:   xor a
        ld (lc_i),a
        ld (fc_skip),a
.cell:  ld a,(fc_skip)          ; rows covered by a box of this column
        or a
        jr z,.c1
        dec a
        ld (fc_skip),a
        jr .cn
.c1:    call lc_get
        call fc_elem
        ret c
.cn:    call lc_next_i
        jr c,.cell
        ld hl,lc_p
        inc (hl)
        ld a,(hl)
        cp LD_CPOS
        jr c,.col
        ; output column
        xor a
        ld (lc_i),a
.out:   call lc_get
        ld b,a
        and FT_MASK
        cp FT_MATH              ; arithmetic in the output column
        jr nz,.o0
        ld a,OP_LD
        call fc_emit_row
        call nc,lc_wmath
        ret c
        jr .on
.o0:    cp FT_OUT
        jr nz,.on
        ld a,OP_LD
        call fc_emit_row
        ret c
        ld a,b
        rlca
        ld a,OP_ST
        jr nc,.st
        ld a,OP_ST|VM_N
.st:    call lc_emit_op
        ret c
.on:    call lc_next_i
        jr c,.out
        ld a,(lc_r1)
        inc a
        ld (lc_r0),a
        jp .net

; fc_row_used: row A -> NZ if it has an element (comment rows do not count)
fc_row_used:
        ld d,a
        ld e,0
.l:     push de
        call ld_get
        pop de
        and FT_MASK
        cp FT_CMT
        jr z,.n
        or a
        ret nz
.n:     inc e
        ld a,e
        cp LD_CPOS+1
        jr c,.l
        xor a
        ret

; fc_box_end: row A -> A = last row covered by the boxes in it (A if none)
fc_box_end:
        ld (fc_row),a
        ld (fc_end),a
        ld d,a
        ld e,0
.l:     push de
        call ld_get
        call fc_height          ; A = height
        pop de
        or a
        jr z,.n
        dec a
        ld hl,fc_row
        add a,(hl)
        ld hl,fc_end
        cp (hl)
        jr c,.n
        ld (hl),a
.n:     inc e
        ld a,e
        cp LD_CPOS
        jr c,.l
        ld a,(fc_end)
        ret

; ---- fc_height: A = type, B = area -> A = rows of the box (0 = no box)
;      (keeps BC, DE, HL)
fc_height:
        and FT_MASK
        cp FT_AND
        jr z,.lg
        cp FT_OR
        jr z,.lg
        cp FT_XOR
        jr z,.lg
        cp FT_SR
        jr z,.two
        cp FT_RS
        jr z,.two
        cp FT_NOT
        jr z,.one
        cp FT_RTRIG
        jr z,.one
        cp FT_FTRIG
        jr z,.one
        cp FT_CTU               ; counters: CU, R / CD, LD, PV
        jr z,.three
        cp FT_CTD
        jr z,.three
        call ld_isbox           ; timers: IN row + PT row
        jr z,.two
        xor a
        ret
.lg:    ld a,b
        ret
.two:   ld a,2
        ret
.one:   ld a,1
        ret
.three: ld a,3
        ret

; ---- fc_elem: element at (lc_r0+lc_i, lc_p): A = type, lc_area/lc_idx
fc_elem:
        ld (fc_t),a
        ld a,(lc_area)
        ld b,a
        ld a,(fc_t)
        call fc_height
        or a
        jr nz,.box
        ld a,(fc_t)
        and FT_MASK
        cp FT_WIRE
        ret z
        cp FT_CMT
        ret z
        cp FT_IN
        jr z,.in
        cp FT_OUT
        jr z,.out
        cp FT_CMP
        jr z,.cmp
        cp FT_MATH
        jr z,.math
        ; empty: no signal
        call lc_is_dead
        ret nz
        ld a,OP_LD
        ld hl,0
        call lc_emit_k
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        ld a,1
        jp lc_set_dead
.out:   ld a,OP_LD              ; output in a logic column (signal goes on)
        call fc_emit_row
        ret c
        ld a,(fc_t)
        rlca
        ld a,OP_ST
        jr nc,.o1
        ld a,OP_ST|VM_N
.o1:    jp lc_emit_op
.cmp:   call lc_wexpr           ; compare input: the signal = A op B
        ret c
        call fc_mon
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        jp lc_set_dead
.math:  ld a,OP_LD              ; arithmetic output: enabled by the signal,
        call fc_emit_row        ; which goes on unchanged
        ret c
        jp lc_wmath
.in:    ld a,(fc_t)
        rlca
        ld a,OP_LD
        jr nc,.in1
        ld a,OP_LD|VM_N
.in1:   call lc_emit_op
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        jp lc_set_dead
.box:   ld (fc_h),a
        dec a
        ld (fc_skip),a          ; the covered rows are handled here
        ld a,(fc_t)
        and FT_MASK
        cp FT_NOT
        jr z,.not
        cp FT_AND
        jr z,.lg
        cp FT_OR
        jr z,.lg
        cp FT_XOR
        jr z,.lg
        jp fc_fb
.not:   call lc_is_dead         ; NOT: dead row -> TRUE
        jr z,.nl
        ld a,OP_LD
        ld hl,1
        call lc_emit_k
        jr .nst
.nl:    ld a,OP_LD|VM_N
        call lc_emit_s
.nst:   ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        call fc_mon
        ret c
        xor a
        jp lc_set_dead
.lg:    ld b,OP_AND             ; logic op of the box
        cp FT_AND
        jr z,.lop
        ld b,OP_OR
        cp FT_OR
        jr z,.lop
        ld b,OP_XOR
.lop:   ld a,b
        ld (fc_op),a
        ld a,OP_LD
        call fc_emit_row
        ret c
        ld a,(lc_i)
        ld (fc_i0),a
.lin:   ld hl,lc_i              ; the other inputs
        inc (hl)
        ld a,(fc_i0)
        ld b,a
        ld a,(fc_h)
        add a,b
        cp (hl)
        jr z,.lend
        jr c,.lend
        ld a,(fc_op)
        call fc_emit_row
        ret c
        ld a,1                  ; consumed
        call lc_set_dead
        jr .lin
.lend:  ld a,(fc_i0)
        ld (lc_i),a
        ld a,OP_ST
        call lc_emit_s
        ret c
        call fc_mon
        ret c
        xor a
        jp lc_set_dead

; ---- fc_fb: FB box at row lc_i (fc_t, instance lc_idx, height fc_h)
;      inputs: member k <- S[lc_i+k]; timers: PT <- preset; then CAL and
;      S[lc_i] <- the BOOL output (member Q of the type)
fc_fb:  ld a,(lc_i)
        ld (fc_i0),a
        ld a,(fc_h)             ; BOOL inputs (timers: IN only, PT is preset)
        ld (fc_nin),a
        ld a,(fc_t)
        call ld_isbox           ; timers / counters: the last row is the preset
        jr nz,.nt
        ld hl,fc_nin
        dec (hl)
.nt:    xor a
        ld (fc_k),a
.inp:   ld a,OP_LD
        call fc_emit_row
        ret c
        ld a,(fc_k)             ; timers: IN = 0; SR/RS: 0, 1; trig: CLK 0
        ld b,a
        ld a,OP_ST
        call lc_emit_mem
        ret c
        ld a,1
        call lc_set_dead
        ld hl,lc_i
        inc (hl)
        ld hl,fc_k
        inc (hl)
        ld a,(fc_nin)
        cp (hl)
        jr nz,.inp
        ld a,(fc_i0)
        ld (lc_i),a
        ld a,(fc_t)
        call ld_isbox
        jr nz,.cal
        ld hl,(lc_pt)           ; timer: PT := preset time
        ld (cp_arg),hl
        xor a
        ld (cp_arg3),a
        ld a,VM_MII
        ld (cp_mode),a
        ld a,OP_LD
        call cp_emit
        ret c
        ld a,(fc_t)             ; member PT (timers) / PV (counters)
        call ld_iscnt
        ld b,1
        jr nz,.pm
        inc b
.pm:    ld a,OP_ST
        call lc_emit_mem
        ret c
.cal:   ld a,(lc_idx)           ; CAL instance
        ld l,a
        rrca
        rrca
        and 0x3F
        ld (cp_mode),a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,RT_FB
        add hl,de
        ld (cp_arg),hl
        xor a
        ld (cp_arg3),a
        ld a,OP_CALFB
        call cp_emit
        ret c
        ld a,(fc_t)             ; member of the BOOL output
        and FT_MASK
        ld b,2                  ; TON/TOF/TP: Q, SR/RS: Q1
        cp FT_CTU
        jr z,.q3
        cp FT_CTD
        jr z,.q3
        cp FT_RTRIG
        jr z,.q1
        cp FT_FTRIG
        jr nz,.q
.q1:    ld b,1                  ; R_TRIG/F_TRIG: Q
        jr .q
.q3:    ld b,3                  ; counters: Q
.q:     ld a,OP_LD
        call lc_emit_mem
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        jp lc_set_dead

; ---- fc_mon: logic block at (lc_r0+lc_i, lc_p), result in the accumulator
;      -> ST to its monitor bit RT_LGC[k], k = number of logic blocks stored
;      before it; only in the POU the simulation shows (lc_pou). C = error
fc_mon: ld a,(cp_slot)
        ld hl,lc_pou
        cp (hl)
        jr nz,.no
        ld a,(lc_r0)
        ld hl,lc_i
        add a,(hl)
        ld d,a
        ld a,(lc_p)
        ld e,a
        ld a,(cp_slot)
        call pou_body
        push hl
        add hl,bc
        ld (fc_bend),hl
        pop hl
        inc hl                  ; (row count)
        ld c,0
.l:     push hl
        push de
        ld de,(fc_bend)
        or a
        sbc hl,de
        pop de
        pop hl
        jr nc,.no
        ld a,(hl)
        cp d
        jr nz,.nx
        inc hl
        ld a,(hl)
        dec hl
        cp e
        jr z,.fnd
.nx:    inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        call fc_is_lg
        jr nz,.sk
        inc c
.sk:    push de
        call ld_skip            ; (keeps BC)
        pop de
        jr .l
.fnd:   ld a,c
        cp 64
        jr nc,.no
        ld a,OP_ST              ; (lc_emit_bit: op on the stack)
        push af
        ld a,c
        ld hl,RT_LGC
        jp lc_emit_bit
.no:    or a
        ret

; fc_is_lg: A = type -> Z if it has a monitor bit: FBD AND / OR / XOR / NOT
;   and compares, LD only compares (fc_ld = 1); keeps BC
fc_is_lg:
        and FT_MASK
        cp FT_CMP
        ret z
        push hl
        ld hl,fc_ld
        bit 0,(hl)
        pop hl
        ret nz
        cp FT_AND
        ret z
        cp FT_OR
        ret z
        cp FT_XOR
        ret z
        cp FT_NOT
        ret

; fc_emit_row: A = op with the signal of row lc_i (FALSE when dead)
fc_emit_row:
        push bc
        push af
        call lc_is_dead
        jr z,.s
        pop af
        ld hl,0
        call lc_emit_k
        pop bc
        ret
.s:     pop af
        call lc_emit_s
        pop bc
        ret

fc_cov:  db 0
fc_skip: db 0
fc_row:  db 0
fc_end:  db 0
fc_t:    db 0
fc_h:    db 0
fc_op:   db 0
fc_i0:   db 0
fc_k:    db 0
fc_nin:  db 0
fc_bend: dw 0
fc_ld:    db 0              ; 1: compiling LD (fc_is_lg: compares only)
