; ============================================================
; il_comp.asm - compiles all POUs to bytecode (BCODE)
; ============================================================
; Every used POU slot gets its start address in RT_POU. IL POUs are
; compiled in two passes (1: label addresses, 2: code); LD and FBD POUs
; in one pass (ld_comp.asm, fbd_comp.asm).
; Error: C, il_err = message, cp_slot / cp_line = location.
; ============================================================
CP_MAXLBL EQU 32

il_compile:
        xor a
        ld (lc_edges),a
        ld hl,BCODE
        ld (cp_pc),hl
        xor a
        ld (cp_slot),a
.slot:  ld a,(cp_slot)
        call pou_used
        jr z,.next
        add a,a
        ld l,a
        ld h,0
        ld de,RT_POU
        add hl,de
        ld de,(cp_pc)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,0
        ld (cp_line),hl
        ld a,(cp_slot)
        call pou_lang
        cp LANG_IL
        jr nz,.stub
        call cp_pou
        ret c
        jr .next
.stub:  push af
        ld a,2
        ld (cp_pass),a
        pop af
        cp LANG_LD
        jr nz,.fbd
        call ld_compile
        ret c
        jr .ret
.fbd:   cp LANG_FBD
        jr nz,.ret
        call fb_compile
        ret c
.ret:   ld a,OP_RET
        call cp_emit0
        ret c
.next:  ld hl,cp_slot
        inc (hl)
        ld a,(hl)
        cp MAX_POU
        jr c,.slot
        or a
        ret

cp_pou: ld hl,(cp_pc)
        ld (cp_start),hl
        xor a
        ld (cp_nlbl),a
        inc a
        ld (cp_pass),a
        call cp_lines
        ret c
        ld hl,(cp_start)
        ld (cp_pc),hl
        ld a,2
        ld (cp_pass),a
        call cp_lines
        ret c
        ld a,OP_RET
        jp cp_emit0

; ---- cp_lines: one pass over the lines of POU cp_slot
cp_lines:
        ld a,(cp_slot)
        call pou_body
        ld (cp_rec),hl
        add hl,bc
        ld (cp_end),hl
        ld hl,0
        ld (cp_line),hl
.l:     ld hl,(cp_rec)
        ld de,(cp_end)
        or a
        sbc hl,de
        ret nc
        ld hl,(cp_line)
        inc hl
        ld (cp_line),hl
        ; copy the text, 0-terminated
        ld hl,(cp_rec)
        ld a,(hl)
        ld e,a
        ld d,0
        push hl
        add hl,de
        ld (cp_rec),hl
        pop hl
        sub 2
        ld b,a
        ld (cp_tlen),a
        inc hl
        ld a,(hl)
        ld (cp_kind),a
        inc hl
        ld de,cp_text
        ld a,b
        or a
        jr z,.ce
.cp:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz .cp
.ce:    xor a
        ld (de),a
        ld a,(cp_kind)
        cp K_INSTR
        jr nz,.nins
        call cp_instr
        ret c
        jr .l
.nins:  cp K_LABEL
        jr nz,.l
        ld a,(cp_pass)
        cp 1
        jr nz,.l
        call cp_label
        ret c
        jr .l

; ---- cp_label: pass 1, cp_text = "NAME:" -> label table
cp_label:
        ld hl,cp_text
.c:     ld a,(hl)
        cp ':'
        jr z,.e
        inc hl
        jr .c
.e:     ld (hl),0
        ld hl,cp_text
        call cp_find_label
        ld hl,err_cp_dup
        jp nc,cp_fail
        ld a,(cp_nlbl)
        cp CP_MAXLBL
        ld hl,err_cp_lbls
        jp nc,cp_fail
        inc a
        ld (cp_nlbl),a
        dec a
        call cp_lbl_entry
        ex de,hl
        ld hl,cp_name8
        ld bc,8
        ldir
        ld hl,(cp_pc)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        or a
        ret

; A = label index -> HL = entry
cp_lbl_entry:
        ld l,a
        ld h,0
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de               ; *10
        ld de,RT_LBL
        add hl,de
        ret

; ---- cp_find_label: HL = name (0) -> NC: DE = address; C: not found
;      (also leaves the 0-padded name in cp_name8)
cp_find_label:
        ld de,cp_name8
        ld b,8
.p:     ld a,(hl)
        or a
        jr z,.z
        inc hl
.z:     ld (de),a
        inc de
        djnz .p
        ld a,(cp_nlbl)
        or a
        scf
        ret z
        ld c,a
        ld a,0
.s:     push af
        call cp_lbl_entry
        ld de,cp_name8
        ld b,8
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.ne
        inc hl
        inc de
        djnz .cmp
        pop af
        ld e,(hl)
        inc hl
        ld d,(hl)
        or a
        ret
.ne:    pop af
        inc a
        cp c
        jr c,.s
        scf
        ret

; ---- cp_instr: compiles the binary instruction in cp_text ([op][operand...])
cp_instr:
        ld hl,cp_text
        ld e,0                  ; end of the instruction (for parameters)
        ld a,(cp_tlen)
        ld e,a
        ld d,0
        add hl,de
        ld (cp_tend),hl
        ld a,(cp_text)
        ld (cp_opb),a
        and 0x3F
        ld (il_mid),a
        ld e,a
        ld d,0
        ld hl,cp_optab
        add hl,de
        ld a,(hl)
        ld (cp_op),a
        ld a,e                  ; class: il_mnems[id*7 + 6]
        add a,a
        add a,a
        add a,a
        sub e
        add a,6
        ld e,a
        ld hl,il_mnems
        add hl,de
        ld a,(hl)
        and 0x7F
        ld (cp_class),a
        ld a,(cp_opb)
        bit 7,a
        jr z,.np
        ; "OP(" [operand]: push the operation, the operand starts a new CR
        xor a
        ld (cp_arg3),a
        ld hl,0
        ld (cp_arg),hl
        ld a,(cp_op)
        ld (cp_mode),a
        ld a,OP_PUSH
        call cp_emit
        ret c
        ld a,(cp_tlen)
        cp 2
        ret c                   ; no operand
        ld hl,cp_text+1
        call cp_operand_rec
        ret c
        ld a,OP_LD
        jp cp_emit
.np:    ld a,(cp_class)
        cp IC_NONE
        jr z,.none
        cp IC_LABEL
        jr z,.label
        cp IC_CALL
        jp z,cp_call
        ld hl,cp_text+1
        call cp_operand_rec
        ret c
        ld a,(cp_op)
        jp cp_emit
.none:  ld a,(cp_op)
        jp cp_emit0
.label: ld hl,0
        ld (cp_arg),hl
        ld a,(cp_pass)
        cp 2
        jr nz,.lemit
        ld hl,cp_text+2         ; [AR_LBL][name...0]
        call cp_find_label
        ld hl,err_cp_nolbl
        jp c,cp_fail
        ld (cp_arg),de
.lemit: xor a
        ld (cp_mode),a
        ld (cp_arg3),a
        ld a,(cp_op)
        jp cp_emit

; ---- cp_call: CAL / CALC / CALCN, binary [area][index][member][operand]...
cp_call:
        ld a,(cp_text+1)
        ld (cp_carea),a
        ld a,(cp_text+2)
        ld (cp_cidx),a
        ; number of parameters
        ld hl,cp_text+3
        ld b,0
.cnt:   call cp_more
        jr nc,.sz
        inc b
        inc hl                  ; member
        call cp_opsize
        add a,l
        ld l,a
        jr nc,.cnt
        inc h
        jr .cnt
.sz:    ld a,b
        ld (cp_npar),a
        add a,a
        ld c,a
        add a,a
        add a,a
        add a,c                 ; *10
        add a,5
        ld (cp_csize),a
        ; conditional call: jump over the sequence
        ld a,(il_mid)
        cp IL_ID_CAL
        jr z,.uncond
        ld b,OP_JMPCN
        cp IL_ID_CALC
        jr z,.cj
        ld b,OP_JMPC
.cj:    push bc
        ld hl,(cp_pc)
        ld de,5
        add hl,de
        ld a,(cp_csize)
        ld e,a
        add hl,de
        ld (cp_arg),hl
        xor a
        ld (cp_mode),a
        ld (cp_arg3),a
        pop af
        call cp_emit
        ret c
.uncond:
        ld a,(cp_carea)
        cp AR_POU
        jr nz,.fb
        ld a,(cp_cidx)
        ld (cp_mode),a
        ld a,OP_CALL
        jp cp_emit0m
.fb:    cp AR_FBI
        jp nz,cp_badcall
        ld hl,cp_text+3
.par:   call cp_more
        jr nc,.callfb
        ld a,(hl)               ; member -> destination operand
        inc hl
        push hl
        rlca
        rlca
        rlca
        rlca
        or AR_FBM
        ld b,a
        ld a,(cp_cidx)
        ld c,a
        ld a,b
        ld de,0
        call cp_operand_av
        pop hl
        ret c
        ld de,(cp_arg)
        ld (cp_darg),de
        ld a,(cp_arg3)
        ld (cp_darg3),a
        ld a,(cp_mode)
        ld (cp_dmode),a
        call cp_operand_rec     ; source value
        ret c
        ld (cp_after),hl
        ld a,OP_LDT
        call cp_emit
        ret c
        ld hl,(cp_darg)
        ld (cp_arg),hl
        ld a,(cp_darg3)
        ld (cp_arg3),a
        ld a,(cp_dmode)
        ld (cp_mode),a
        ld a,OP_STT
        call cp_emit
        ret c
        ld hl,(cp_after)
        jr .par
.callfb:
        ld a,(cp_cidx)
        ld l,a
        rrca
        rrca
        and 0x3F
        ld (cp_mode),a          ; FB type
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
        jp cp_emit

; cp_more: C if HL < cp_tend
cp_more:
        push hl
        push de
        ld de,(cp_tend)
        or a
        sbc hl,de
        pop de
        pop hl
        ret

; cp_opsize: HL = binary operand -> A = its size (2 or 3)
cp_opsize:
        ld a,(hl)
        and AR_MASK
        cp AR_K16
        jr z,.three
        cp AR_KT
        jr z,.three
        ld a,2
        ret
.three: ld a,3
        ret

; ---- cp_is_called: A = POU slot -> Z if the bytecode contains CALL <slot>
cp_is_called:
        ld b,a
        ld hl,BCODE
.l:     push hl
        ld de,(cp_pc)
        or a
        sbc hl,de
        pop hl
        jr nc,.no
        ld a,(hl)
        and 0x3F
        cp OP_CALL
        jr nz,.n
        inc hl
        ld a,(hl)
        dec hl
        cp b
        ret z
.n:     ld de,5
        add hl,de
        jr .l
.no:    or 1                    ; NZ
        ret

; ---- cp_emit0: A = op without operand; cp_emit0m keeps cp_mode
cp_emit0:
        push af
        xor a
        ld (cp_mode),a
        pop af
cp_emit0m:
        push af
        xor a
        ld (cp_arg3),a
        ld hl,0
        ld (cp_arg),hl
        pop af
; ---- cp_emit: A = op, operand from cp_mode/cp_arg/cp_arg3
cp_emit:
        ld b,a
        ld hl,(cp_pc)
        push hl
        ld de,BCODE_END-4
        or a
        sbc hl,de
        pop hl
        jr c,.ok
        ld hl,err_cp_big
        jp cp_fail
.ok:    ld a,(cp_pass)
        cp 2
        jr nz,.skip
        ld (hl),b
        inc hl
        ld a,(cp_mode)
        ld (hl),a
        inc hl
        ld de,(cp_arg)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(cp_arg3)
        ld (hl),a
.skip:  ld hl,(cp_pc)
        ld de,5
        add hl,de
        ld (cp_pc),hl
        or a
        ret

; operation per il_mnems index
IL_ID_CAL  EQU 27
IL_ID_CALC EQU 28
cp_optab:
        db OP_LD, OP_LD|VM_N, OP_ST, OP_ST|VM_N, OP_S, OP_R
        db OP_AND, OP_AND|VM_N, OP_OR, OP_OR|VM_N, OP_XOR, OP_XOR|VM_N
        db OP_NOT, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD
        db OP_GT, OP_GE, OP_EQ, OP_NE, OP_LE, OP_LT
        db OP_JMP, OP_JMPC, OP_JMPCN, 0, 0, 0
        db OP_RET, OP_RETC, OP_RETCN, OP_POP


