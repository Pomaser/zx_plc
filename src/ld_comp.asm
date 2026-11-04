; ============================================================
; ld_comp.asm - Ladder Diagram -> bytecode
; ============================================================
; A rung = consecutive rows joined by vertical links. Each rung is
; evaluated column by column; the power of each of its rows is kept
; in a scratch bit S[r] (RT_SCR). Elements:
;   empty     S = FALSE            wire      -
;   NO / NC   S = S AND op / S AND NOT op
;   P / N     S = S AND (op rising / falling), edge memory E (RT_EDGE)
;   timer box IN = S, PT = preset, CAL, S = Q
;   link      S of all linked rows = OR of them
;   coils     LD S / ST, STN, S, R op
; ============================================================
LC_MAXRR  EQU 16            ; rows per rung
LC_MAXEDG EQU 32            ; P/N contacts per project

; ---- ld_compile: compiles the LD POU cp_slot (pass 2 only); C = error
ld_compile:
        ld a,(cur_pou)
        ld (lc_pou),a
        ld a,(cp_slot)
        ld (cur_pou),a          ; the ld_* helpers work on cur_pou
        call .go
        push af
        ld a,(lc_pou)
        ld (cur_pou),a
        pop af
        ret
.go:    call ld_nrows
        ld (lc_nrows),a
        xor a
        ld (lc_r0),a
.rung:  ld a,(lc_nrows)
        ld b,a
        ld a,(lc_r0)
        cp b
        ret nc                  ; all rows done (NC = ok)
        ; rung end: follow the vertical links
        ld (lc_r1),a
.ext:   ld a,(lc_r1)
        inc a
        ld b,a
        ld a,(lc_nrows)
        cp b
        jr z,.endf              ; last row
        jr c,.endf
        ld a,(lc_r1)
        call lc_row_links
        jr z,.endf
        ld hl,lc_r1
        inc (hl)
        jr .ext
.endf:  ld a,(lc_r0)
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
        ; start: every row of the rung is powered by the left rail
        xor a
        ld (lc_i),a
.init:  call lc_row_used        ; rows without elements stay dead
        jr z,.idead
        ld a,OP_LD
        ld hl,1
        call lc_emit_k
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        jr .iset
.idead: ld a,1
.iset:  call lc_set_dead
        call lc_next_i
        jr c,.init
        ; contact columns
        xor a
        ld (lc_p),a
.col:   xor a
        ld (lc_i),a
.cell:  call lc_get
        and LT_MASK
        call lc_elem
        ret c
        call lc_next_i
        jr c,.cell
        call lc_links
        ret c
        ld hl,lc_p
        inc (hl)
        ld a,(hl)
        cp LD_CPOS
        jr c,.col
        ; coil column
        xor a
        ld (lc_i),a
.coil:  call lc_get
        and LT_MASK
        cp LT_COIL
        jr c,.cn
        call lc_coil
        ret c
.cn:    call lc_next_i
        jr c,.coil
        ld a,(lc_r1)
        inc a
        ld (lc_r0),a
        jp .rung

; lc_next_i: next row of the rung, C if there is one
lc_next_i:
        ld hl,lc_i
        inc (hl)
        ld a,(lc_n)
        ld b,a
        ld a,(hl)
        cp b
        ret

; lc_get: element at (lc_r0 + lc_i, lc_p) -> A type, B area, C index
lc_get: ld a,(lc_r0)
        ld b,a
        ld a,(lc_i)
        add a,b
        ld d,a
        ld a,(lc_p)
        ld e,a
        call ld_get
        push af
        ld a,b
        ld (lc_area),a
        ld a,c
        ld (lc_idx),a
        ld hl,(ld_gpt)
        ld (lc_pt),hl
        pop af
        ret

; lc_row_links: A = row -> NZ if the row has a vertical link
lc_row_links:
        ld d,a
        ld e,0
.l:     push de
        call ld_get
        pop de
        bit 7,a
        ret nz
        inc e
        ld a,e
        cp LD_CPOS
        jr c,.l
        xor a
        ret

; lc_row_used: row lc_r0+lc_i -> NZ if it has any element or link
lc_row_used:
        ld a,(lc_r0)
        ld b,a
        ld a,(lc_i)
        add a,b
        ld d,a
        ld e,0
.l:     push de
        call ld_get
        pop de
        cp LT_CMT               ; a comment row has no elements
        jr z,.cm
        or a
        ret nz
.cm:
        inc e
        ld a,e
        cp LD_CPOS+1
        jr c,.l
        xor a
        ret

; dead flags: a row whose power is known to be FALSE
lc_set_dead:
        push af
        ld a,(lc_i)
        ld e,a
        ld d,0
        ld hl,lc_dead
        add hl,de
        pop af
        ld (hl),a
        ret
lc_is_dead:
        ld a,(lc_i)
        ld e,a
        ld d,0
        ld hl,lc_dead
        add hl,de
        ld a,(hl)
        or a
        ret

; ---- lc_elem: A = type of a contact column element (lc_area = operand)
lc_elem:
        cp LT_CMT
        ret z
        cp LT_WIRE
        ret z
        or a
        jr nz,.cont
        call lc_is_dead         ; empty: no power from here
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
.cont:  ld (lc_t),a
        call ld_isbox
        jr z,.box
        ld a,(lc_t)
        cp LT_P
        jr nc,.edge
        call lc_is_dead
        ret nz
        ld a,OP_LD
        call lc_emit_s
        ret c
        ld a,(lc_t)
        cp LT_NC
        ld a,OP_AND
        jr nz,.no
        ld a,OP_AND|VM_N
.no:    call lc_emit_op
        ret c
        ld a,OP_ST
        jp lc_emit_s
.edge:  ld a,(lc_edges)
        cp LC_MAXEDG
        ld hl,err_lc_edges
        jp nc,cp_fail
        call lc_is_dead
        jr nz,.mem
        ld a,(lc_t)
        cp LT_N
        ld a,OP_LD              ; P: op AND NOT E
        ld b,OP_AND|VM_N
        jr nz,.p
        ld a,OP_LD|VM_N         ; N: NOT op AND E
        ld b,OP_AND
.p:     push bc
        call lc_emit_op
        pop bc
        ret c
        ld a,b
        call lc_emit_e
        ret c
        ld a,OP_AND
        call lc_emit_s
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
.mem:   ld a,OP_LD              ; edge memory = op
        call lc_emit_op
        ret c
        ld a,OP_ST
        call lc_emit_e
        ret c
        ld hl,lc_edges
        inc (hl)
        or a
        ret

.box:   call lc_is_dead         ; IN := power of the row
        jr z,.bpw
        ld a,OP_LD
        ld hl,0
        call lc_emit_k
        jr .bin
.bpw:   ld a,OP_LD
        call lc_emit_s
.bin:   ret c
        ld a,OP_ST
        ld b,0                  ; member IN
        call lc_emit_mem
        ret c
        ld hl,(lc_pt)           ; PT := preset time
        ld (cp_arg),hl
        xor a
        ld (cp_arg3),a
        ld a,VM_MII
        ld (cp_mode),a
        ld a,OP_LD
        call cp_emit
        ret c
        ld a,OP_ST
        ld b,1                  ; member PT
        call lc_emit_mem
        ret c
        ld a,(lc_idx)           ; CAL instance
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
        ld a,OP_LD
        ld b,2                  ; power := Q
        call lc_emit_mem
        ret c
        ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        jp lc_set_dead

; ---- lc_links: vertical links at the right edge of column lc_p
lc_links:
        xor a
        ld (lc_i),a
.l:     ld a,(lc_n)             ; the last row has no link down
        dec a
        ld b,a
        ld a,(lc_i)
        cp b
        ret nc
        call lc_get
        bit 7,a
        jr nz,.grp
        ld hl,lc_i
        inc (hl)
        jr .l
.grp:   ld a,(lc_i)             ; group lc_i .. lc_j
        ld (lc_g0),a
.ext:   ld hl,lc_i
        inc (hl)
        ld a,(lc_n)
        dec a
        ld b,a
        ld a,(lc_i)
        cp b
        jr nc,.gend
        call lc_get
        bit 7,a
        jr nz,.ext
.gend:  ld a,(lc_i)
        ld (lc_g1),a
        ; LD S[g0] / OR S[..] / ST S[g0..g1]
        ld a,(lc_g0)
        ld (lc_i),a
        ld a,OP_LD
        call lc_emit_s
        ret c
.or:    ld hl,lc_i
        inc (hl)
        ld a,(lc_g1)
        ld b,a
        ld a,(hl)
        cp b
        jr z,.or1
        jr nc,.st
.or1:   ld a,OP_OR
        call lc_emit_s
        ret c
        jr .or
.st:    ld a,(lc_g0)
        ld (lc_i),a
.st1:   ld a,OP_ST
        call lc_emit_s
        ret c
        xor a
        call lc_set_dead
        ld hl,lc_i
        ld a,(lc_g1)
        cp (hl)
        jr z,.next
        inc (hl)
        jr .st1
.next:  ld hl,lc_i
        inc (hl)
        jr .l

; ---- lc_coil: A = coil type (lc_area = operand)
lc_coil:
        ld (lc_t),a
        call lc_is_dead
        jr z,.pw
        ld a,(lc_t)             ; never powered: S/R do nothing
        cp LT_SET
        ret nc
        ld a,OP_LD
        ld hl,0
        call lc_emit_k
        jr .st
.pw:    ld a,OP_LD
        call lc_emit_s
.st:    ret c
        ld a,(lc_t)
        sub LT_COIL
        ld e,a
        ld d,0
        ld hl,.ops
        add hl,de
        ld a,(hl)
        jp lc_emit_op
.ops:   db OP_ST, OP_ST|VM_N, OP_S, OP_R

; ---- emit helpers
; lc_emit_mem: A = op, B = member of the FB instance lc_idx
lc_emit_mem:
        push af
        ld a,b
        rlca
        rlca
        rlca
        rlca
        or AR_FBM
        jr lc_emit_av
; lc_emit_s: A = op, operand S[lc_i]
lc_emit_s:
        push af
        ld a,(lc_i)
        ld hl,RT_SCR
        jr lc_emit_bit
; lc_emit_e: A = op, operand E[lc_edges]
lc_emit_e:
        push af
        ld a,(lc_edges)
        ld hl,RT_EDGE
lc_emit_bit:
        ld e,a
        rrca
        rrca
        rrca
        and 0x1F
        add a,l
        ld l,a
        jr nc,.n
        inc h
.n:     ld (cp_arg),hl
        ld a,e
        and 7
        ld e,a
        ld d,0
        ld hl,bit_masks
        add hl,de
        ld a,(hl)
        ld (cp_arg3),a
        ld a,VM_MB
        ld (cp_mode),a
        pop af
        jp cp_emit
; lc_emit_k: A = op, HL = BOOL constant
lc_emit_k:
        ld (cp_arg),hl
        push af
        xor a
        ld (cp_arg3),a
        ld a,VM_MIB
        ld (cp_mode),a
        pop af
        jp cp_emit
; lc_emit_op: A = op, operand lc_area/lc_idx
lc_emit_op:
        push af
        ld a,(lc_area)
lc_emit_av:
        push af
        ld a,(lc_idx)
        ld c,a
        pop af
        ld de,0
        call cp_operand_av
        pop bc
        ret c
        ld a,b
        jp cp_emit


lc_pou:   db 0
lc_nrows: db 0
lc_r0:    db 0
lc_r1:    db 0
lc_n:     db 0
lc_i:     db 0
lc_p:     db 0
lc_t:     db 0
lc_g0:    db 0
lc_g1:    db 0
lc_edges: db 0
lc_area:  db 0
lc_idx:   db 0
lc_pt:    dw 0
lc_dead:  ds LC_MAXRR
