; ============================================================
; vm.asm - bytecode interpreter and standard function blocks
; ============================================================
; Instruction = 5 bytes: [op][mode][arg lo][arg hi][arg3]
;   op bit 7 = N modifier (negated operand), bits 0-5 = operation
;   mode: operand kind (VM_MB bit: arg = address, arg3 = mask;
;         VM_MW word: arg = address; VM_MIB / VM_MII immediate BOOL / INT)
;   PUSH: mode = operation applied by the matching POP (")")
;   CALFB: mode = FB type, arg = instance address
;   CALL: mode = POU slot
; CR = current result (16 bit) + type (0 BOOL, 1 INT).
; ============================================================

; ---- runtime data (RT area) --------------------------------
RT_I      EQU RT            ; inputs  %IX0.0-1.7 (2 bytes)
RT_Q      EQU RT+2          ; outputs %QX0.0-1.7 (2 bytes)
RT_M      EQU RT+4          ; %MX0.0-7.7 (8 bytes)
RT_MW     EQU RT+12         ; %MW0-15 (32 bytes)
RT_FB     EQU RT+44         ; 36 FB instances x 8 bytes
RT_SCR    EQU RT_FB+36*8    ; LD: power of the rung rows (16 bits)
RT_EDGE   EQU RT_SCR+2      ; LD: memory of P/N contacts (32 bits)
RT_STEP   EQU RT_EDGE+4     ; step flags S0-S7 (one active bit per byte)
RT_LGC    EQU RT_STEP+N_SB  ; FBD: results of logic blocks (64 bits, sim)
RT_SM     EQU RT_LGC+8      ; system flags %SM0-7 (written before each scan)
RT_DATA_LEN EQU 44+36*8+6+N_SB+8+1  ; cleared by Reset
RT_POU    EQU RT+RT_DATA_LEN        ; code address of each POU slot (8 words)
RT_LBL    EQU RT_POU+16             ; compiler label table (32 x 10 bytes)
RT_PSTK   EQU RT_LBL+320            ; "(" stack: 8 x 4 bytes
RT_CSTK   EQU RT_PSTK+32            ; call stack: 8 x 2 bytes
RT_MON    EQU RT_CSTK+16            ; monitor cache (sim.asm)
RT_FREE   EQU RT_MON+19*6
; work buffers (not part of the code image)
rec_buf   EQU RT_FREE           ; 72  line record being built
il_out    EQU rec_buf+72        ; 64  output of il_check
cp_text   EQU il_out+64         ; 64  compiler: current line
FMT_BUF   EQU cp_text           ;     (editors: formatted operand label)
FB_INFOB  EQU rec_buf           ;     (FBD editor: status bar text)
rd_m      EQU cp_text+64        ; 11  row drawing: mnemonic / name
rd_o      EQU rd_m+11           ; 64  row drawing: operand / address
rd_c      EQU rd_o+64           ; 64  row drawing: comment
popup_buf EQU rd_c+64           ; 80  popup text
st_buf    EQU popup_buf+80      ; 60  status bar text
st_last   EQU st_buf+60         ; 24  status bar: last right text
st_llast  EQU st_last+24        ; 60  status bar: last left text
RT_FRC    EQU st_llast+60       ; WT_MAX x 5 forced values of the watch list
WD_EXT    EQU RT_FRC+WT_MAX*5   ; 9  compare / arithmetic: operands from wexpr.asm
WD_TEXT   EQU il_out            ;     (its expression text)
RT_END    EQU WD_EXT+9
        ASSERT RT_END <= PROJ

VM_MB     EQU 1
VM_MW     EQU 2
VM_MIB    EQU 3
VM_MII    EQU 4
VM_N      EQU 0x80

OP_END    EQU 0
OP_LD     EQU 1
OP_ST     EQU 2
OP_S      EQU 3
OP_R      EQU 4
OP_AND    EQU 5
OP_OR     EQU 6
OP_XOR    EQU 7
OP_ADD    EQU 8
OP_SUB    EQU 9
OP_MUL    EQU 10
OP_DIV    EQU 11
OP_MOD    EQU 12
OP_GT     EQU 13
OP_GE     EQU 14
OP_EQ     EQU 15
OP_NE     EQU 16
OP_LE     EQU 17
OP_LT     EQU 18
OP_NOT    EQU 19
OP_PUSH   EQU 20
OP_POP    EQU 21
OP_JMP    EQU 22
OP_JMPC   EQU 23
OP_JMPCN  EQU 24
OP_CALFB  EQU 25
OP_CALL   EQU 26
OP_RET    EQU 27
OP_RETC   EQU 28
OP_RETCN  EQU 29
OP_LDT    EQU 30
OP_STT    EQU 31
VM_MAXOPS EQU 30000         ; watchdog: instructions per scan
VM_MODE_CR EQU 5            ; internal: operand = value saved by POP

; ---- vm_reset: clears all PLC data
vm_reset:
        ld a,1
        ld (vm_first),a
        xor a
        ld (vm_smc),a
        ld hl,RT
        ld bc,RT_DATA_LEN
        jp memset

; ---- vm_scan: runs MAIN once. NC = ok, C = error (vm_err = message)
;      The system flags are updated before the scan; SM0 is on in the
;      first scan after a reset only.
vm_scan:
        call vm_sm_upd
        call vm_force
        call vm_scan0
        push af
        call vm_force           ; (forced outputs stay)
        xor a
        ld (vm_first),a
        pop af
        ret

; vm_sm_upd: RT_SM = SM0 first scan, SM1 TRUE, SM2 FALSE, SM3 10 Hz, SM4 5 Hz,
;      SM5 2 Hz, SM6 1 Hz, SM7 0.5 Hz (from a 0-99 tick counter + vm_dt)
vm_sm_upd:
        ld a,(vm_dt)
        ld b,a
        ld a,(vm_smc)
        add a,b
.m:     cp 100
        jr c,.k
        sub 100
        jr .m
.k:     ld (vm_smc),a
        ld c,a
        ld b,0x02               ; SM1
        ld a,(vm_first)
        or a
        jr z,.f
        set 0,b
.f:     ld a,c                  ; 10 Hz
        ld d,5
        call .mod
        cp 3
        jr nc,.n3
        set 3,b
.n3:    ld a,c                  ; 5 Hz
        ld d,10
        call .mod
        cp 5
        jr nc,.n4
        set 4,b
.n4:    ld a,c                  ; 2 Hz
        ld d,25
        call .mod
        cp 13
        jr nc,.n5
        set 5,b
.n5:    ld a,c                  ; 1 Hz
        ld d,50
        call .mod
        cp 25
        jr nc,.n6
        set 6,b
.n6:    ld a,c                  ; 0.5 Hz
        cp 50
        jr nc,.n7
        set 7,b
.n7:    ld a,b
        ld (RT_SM),a
        ret
.mod:   sub d
        jr nc,.mod
        add a,d
        ret

; ---- vm_force: applies the forced values (RT_FRC): [kind][addr][x][y]
;      kind 1: bit, x = mask, y = 0 / 1; kind 2: word = x + 256*y
vm_force:
        ld hl,RT_FRC
        ld b,WT_MAX
.l:     ld a,(hl)
        or a
        jr z,.n
        push bc
        push hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        cp 2
        jr z,.w
        ld c,(hl)               ; mask
        inc hl
        ld a,(hl)
        ex de,hl
        or a
        ld a,c
        jr z,.clr
        or (hl)
        ld (hl),a
        jr .d
.clr:   cpl
        and (hl)
        ld (hl),a
        jr .d
.w:     ld a,(hl)
        inc hl
        ld c,(hl)
        ex de,hl
        ld (hl),a
        inc hl
        ld (hl),c
.d:     pop hl
        pop bc
.n:     ld de,5
        add hl,de
        djnz .l
        ret

vm_first: db 1
vm_smc:   db 0

vm_scan0:
        ld hl,(RT_POU)
        ld (vm_pc),hl
        xor a
        ld (vm_csp),a
        ld (vm_psp),a
        ld (vm_crt),a
        ld hl,0
        ld (vm_cr),hl
        ld (vm_ops),hl
vm_loop:
        ld hl,(vm_ops)
        inc hl
        ld (vm_ops),hl
        ld de,VM_MAXOPS
        or a
        sbc hl,de
        ld hl,err_vm_wd
        jp nc,vm_fail
        ld hl,(vm_pc)
        ld a,(hl)
        ld (vm_op),a
        inc hl
        ld a,(hl)
        ld (vm_mode),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (vm_arg),de
        ld a,(hl)
        ld (vm_arg3),a
        inc hl
        ld (vm_pc),hl
        ld a,(vm_op)
        and 0x3F
        cp OP_STT+1
        jr c,.ok
        xor a
.ok:    ld hl,vm_tab
        jp jump_table

vm_tab: dw vm_ret,vm_ld,vm_st,vm_s,vm_r,vm_and,vm_or,vm_xor
        dw vm_add,vm_sub,vm_mul,vm_div,vm_mod
        dw vm_gt,vm_ge,vm_eq,vm_ne,vm_le,vm_lt
        dw vm_not,vm_push,vm_pop,vm_jmp,vm_jmpc,vm_jmpcn
        dw vm_calfb,vm_call,vm_ret,vm_retc,vm_retcn,vm_ldt,vm_stt

vm_fail:
        ld (vm_err),hl
        scf
        ret

; ---- vm_val: operand value -> HL, A = type (0 BOOL, 1 INT); N modifier applied
vm_val: ld a,(vm_mode)
        cp VM_MB
        jr z,.mb
        cp VM_MW
        jr z,.mw
        cp VM_MIB
        jr z,.mib
        cp VM_MODE_CR
        jr z,.cr
        ld hl,(vm_arg)          ; immediate INT
        ld a,1
        jr .neg
.mb:    ld hl,(vm_arg)
        ld a,(vm_arg3)
        and (hl)
        ld hl,0
        jr z,.b0
        inc l
.b0:    xor a
        jr .neg
.mw:    ld hl,(vm_arg)
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,1
        jr .neg
.mib:   ld hl,(vm_arg)
        ld h,0
        xor a
        jr .neg
.cr:    ld hl,(vm_tval)
        ld a,(vm_ttype)
.neg:   ld (vm_vt),a
        ld b,a
        ld a,(vm_op)
        bit 7,a
        ld a,b
        ret z
        or a
        jr nz,.ni
        ld a,l                  ; BOOL: logical not
        xor 1
        ld l,a
        xor a
        ret
.ni:    ld a,h                  ; INT: bitwise not
        cpl
        ld h,a
        ld a,l
        cpl
        ld l,a
        ld a,1
        ret

; ---- vm_store: HL = value -> operand (bit: bit 0 of value)
vm_store:
        ld a,(vm_mode)
        cp VM_MB
        jr z,.mb
        cp VM_MW
        ret nz
        ex de,hl
        ld hl,(vm_arg)
        ld (hl),e
        inc hl
        ld (hl),d
        ret
.mb:    ld a,l
        ld hl,(vm_arg)
        rrca
        ld a,(vm_arg3)
        jr nc,.clr
        push de                 ; step flag byte: only this bit stays set
        ld de,RT_STEP
        or a
        sbc hl,de
        add hl,de
        jr c,.nstep
        ld de,RT_STEP+N_SB
        or a
        sbc hl,de
        add hl,de
        jr nc,.nstep
        pop de
        ld a,(vm_arg3)
        ld (hl),a
        ret
.nstep: pop de
        ld a,(vm_arg3)
        or (hl)
        ld (hl),a
        ret
.clr:   cpl
        and (hl)
        ld (hl),a
        ret

vm_ld:  call vm_val
        ld (vm_cr),hl
        ld (vm_crt),a
        jp vm_loop

vm_st:  ld hl,(vm_cr)
        ld a,(vm_op)
        bit 7,a
        jr z,.s
        ld a,(vm_crt)           ; STN
        or a
        jr nz,.si
        ld a,l
        xor 1
        ld l,a
        jr .s
.si:    ld a,h
        cpl
        ld h,a
        ld a,l
        cpl
        ld l,a
.s:     call vm_store
        jp vm_loop

vm_s:   call vm_cr_true
        jp z,vm_loop
        ld hl,1
        call vm_store
        jp vm_loop
vm_r:   call vm_cr_true
        jp z,vm_loop
        ld hl,0
        call vm_store
        jp vm_loop

; Z if CR is FALSE / 0
vm_cr_true:
        ld hl,(vm_cr)
        ld a,h
        or l
        ret

vm_and: call vm_val
        ld de,(vm_cr)
        ld a,l
        and e
        ld l,a
        ld a,h
        and d
        ld h,a
        jr vm_setcr
vm_or:  call vm_val
        ld de,(vm_cr)
        ld a,l
        or e
        ld l,a
        ld a,h
        or d
        ld h,a
        jr vm_setcr
vm_xor: call vm_val
        ld de,(vm_cr)
        ld a,l
        xor e
        ld l,a
        ld a,h
        xor d
        ld h,a
vm_setcr:
        ld (vm_cr),hl
        jp vm_loop
vm_setint:
        ld (vm_cr),hl
        ld a,1
        ld (vm_crt),a
        jp vm_loop

vm_add: call vm_val
        ld de,(vm_cr)
        add hl,de
        jr vm_setint
vm_sub: call vm_val
        ex de,hl
        ld hl,(vm_cr)
        or a
        sbc hl,de
        jr vm_setint
vm_mul: call vm_val
        ld de,(vm_cr)
        call mul16
        jr vm_setint
vm_div: call vm_val
        ex de,hl
        ld hl,(vm_cr)
        call div16s
        jr vm_setint
vm_mod: call vm_val
        ex de,hl
        ld hl,(vm_cr)
        call div16s
        ex de,hl                ; remainder
        jr vm_setint

; ---- div16s: HL / DE signed -> HL quotient, DE remainder (sign of dividend); /0 -> 0
div16s:
        ld a,d
        or e
        jr nz,.nz
        ld hl,0
        ld de,0
        ret
.nz:    ld a,h
        ld (ds_sr),a            ; sign of remainder
        xor d
        ld (ds_sq),a            ; sign of quotient
        bit 7,h
        call nz,neg_hl
        bit 7,d
        jr z,.dp
        ex de,hl
        call neg_hl
        ex de,hl
.dp:    call div16u
        ld a,(ds_sq)
        bit 7,a
        call nz,neg_hl
        ld a,(ds_sr)
        bit 7,a
        ret z
        ex de,hl
        call neg_hl
        ex de,hl
        ret

; ---- comparisons: CR <op> operand -> BOOL
; vm_cmp: A = 0 equal, 1 less, 2 greater (signed CR vs operand)
vm_cmp: call vm_val
        ex de,hl
        ld hl,(vm_cr)
        or a
        sbc hl,de
        jr z,.eq
        jp pe,.ovf
        jp m,.lt
.gt:    ld a,2
        ret
.ovf:   jp m,.gt
.lt:    ld a,1
        ret
.eq:    xor a
        ret

vm_gt:  call vm_cmp
        cp 2
        jr vm_setbool_z
vm_ge:  call vm_cmp
        cp 1
        jr vm_setbool_nz
vm_eq:  call vm_cmp
        or a
        jr vm_setbool_z
vm_ne:  call vm_cmp
        or a
        jr vm_setbool_nz
vm_le:  call vm_cmp
        cp 2
        jr vm_setbool_nz
vm_lt:  call vm_cmp
        cp 1
vm_setbool_z:                   ; CR = (Z) ? TRUE : FALSE
        ld hl,1
        jr z,vm_bool
        dec l
        jr vm_bool
vm_setbool_nz:
        ld hl,0
        jr z,vm_bool
        inc l
vm_bool:
        ld (vm_cr),hl
        xor a
        ld (vm_crt),a
        jp vm_loop

vm_not: ld hl,(vm_cr)
        ld a,(vm_crt)
        or a
        jr nz,.i
        ld a,l
        xor 1
        ld l,a
        jp vm_setcr
.i:     ld a,h
        cpl
        ld h,a
        ld a,l
        cpl
        ld l,a
        jp vm_setcr

; ---- "(" : push operation + CR
vm_push:
        ld a,(vm_psp)
        cp 8
        ld hl,err_vm_paren
        jp nc,vm_fail
        inc a
        ld (vm_psp),a
        dec a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,RT_PSTK
        add hl,de
        ld a,(vm_mode)          ; pending operation (with N)
        ld (hl),a
        inc hl
        ld a,(vm_crt)
        ld (hl),a
        inc hl
        ld de,(vm_cr)
        ld (hl),e
        inc hl
        ld (hl),d
        jp vm_loop

; ---- ")" : CR = saved CR <op> CR
vm_pop: ld a,(vm_psp)
        or a
        ld hl,err_vm_paren
        jp z,vm_fail
        dec a
        ld (vm_psp),a
        add a,a
        add a,a
        ld l,a
        ld h,0
        ld de,RT_PSTK
        add hl,de
        ld a,(hl)
        ld (vm_op),a            ; execute the saved operation
        inc hl
        ld b,(hl)               ; saved type
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)               ; saved CR
        ld hl,(vm_cr)
        ld (vm_tval),hl         ; operand = current CR
        ld a,(vm_crt)
        ld (vm_ttype),a
        ld (vm_cr),de
        ld a,b
        ld (vm_crt),a
        ld a,VM_MODE_CR
        ld (vm_mode),a
        ld a,(vm_op)
        and 0x3F
        ld hl,vm_tab
        jp jump_table

vm_jmp: ld hl,(vm_arg)
        ld (vm_pc),hl
        jp vm_loop
vm_jmpc:
        call vm_cr_true
        jp z,vm_loop
        jr vm_jmp
vm_jmpcn:
        call vm_cr_true
        jp nz,vm_loop
        jr vm_jmp

vm_call:
        ld a,(vm_csp)
        cp 8
        ld hl,err_vm_depth
        jp nc,vm_fail
        inc a
        ld (vm_csp),a
        dec a
        add a,a
        ld l,a
        ld h,0
        ld de,RT_CSTK
        add hl,de
        ld de,(vm_pc)
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,(vm_mode)          ; POU slot
        add a,a
        ld l,a
        ld h,0
        ld de,RT_POU
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (vm_pc),hl
        jp vm_loop

vm_retc:
        call vm_cr_true
        jp z,vm_loop
        jr vm_ret
vm_retcn:
        call vm_cr_true
        jp nz,vm_loop
vm_ret: ld a,(vm_csp)
        or a
        ret z                   ; end of MAIN: scan finished (NC)
        dec a
        ld (vm_csp),a
        add a,a
        ld l,a
        ld h,0
        ld de,RT_CSTK
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (vm_pc),hl
        jp vm_loop

vm_ldt: call vm_val
        ld (vm_tval),hl
        jp vm_loop
vm_stt: ld hl,(vm_tval)
        call vm_store
        jp vm_loop

vm_calfb:
        ld hl,(vm_arg)
        ld a,(vm_mode)
        call fb_exec
        jp vm_loop

; ============================================================
; standard function blocks. Instance = 8 bytes:
;   +0 flags, +2 PT/PV (word), +4 ET/CV (word)
; ============================================================
; ---- fb_exec: A = FB type, HL = instance
fb_exec:
        push hl
        pop ix
        ld hl,.tab
        jp jump_table
.tab:   dw fb_ton,fb_tof,fb_tp,fb_ctu,fb_ctd,fb_rtrig,fb_ftrig,fb_sr,fb_rs

; timers: flags bit0 IN, bit1 Q, bit2 previous IN, bit3 running
; ET += dt, limited to PT. Z flag on return: ET < PT
fb_et_inc:
        ld l,(ix+4)
        ld h,(ix+5)
        ld de,(vm_dt)
        add hl,de
        ld e,(ix+2)
        ld d,(ix+3)
        or a
        sbc hl,de
        jr nc,.lim
        add hl,de
        ld (ix+4),l
        ld (ix+5),h
        or 1                    ; NZ: still running
        ret
.lim:   ld (ix+4),e
        ld (ix+5),d
        xor a                   ; Z: elapsed
        ret

fb_ton: bit 0,(ix+0)
        jr z,.off
        call fb_et_inc
        jr nz,.q0
        set 1,(ix+0)
        ret
.off:   xor a
        ld (ix+4),a
        ld (ix+5),a
.q0:    res 1,(ix+0)
        ret

fb_tof: bit 0,(ix+0)
        jr z,.off
        set 1,(ix+0)
        xor a
        ld (ix+4),a
        ld (ix+5),a
        ret
.off:   bit 1,(ix+0)
        ret z
        call fb_et_inc
        ret nz
        res 1,(ix+0)
        ret

fb_tp:  bit 3,(ix+0)
        jr nz,.run
        bit 0,(ix+0)            ; rising edge starts the pulse
        jr z,.idle
        bit 2,(ix+0)
        jr nz,.idle
        set 3,(ix+0)
        xor a
        ld (ix+4),a
        ld (ix+5),a
.run:   call fb_et_inc
        jr nz,.on
        res 3,(ix+0)
        jr .idle
.on:    set 1,(ix+0)
        jr .prev
.idle:  res 1,(ix+0)
        bit 0,(ix+0)
        jr nz,.prev
        xor a
        ld (ix+4),a
        ld (ix+5),a
.prev:  res 2,(ix+0)
        bit 0,(ix+0)
        ret z
        set 2,(ix+0)
        ret

; counters: bit0 CU/CD, bit1 R/LD, bit2 Q, bit3 previous CU/CD
fb_ctu: bit 1,(ix+0)
        jr z,.nr
        xor a
        ld (ix+4),a
        ld (ix+5),a
        jr .q
.nr:    call fb_edge
        jr z,.q
        ld l,(ix+4)
        ld h,(ix+5)
        ld de,0x7FFF
        or a
        sbc hl,de
        jr z,.q
        add hl,de
        inc hl
        ld (ix+4),l
        ld (ix+5),h
.q:     call fb_prev
        ; Q = CV >= PV
        ld l,(ix+4)
        ld h,(ix+5)
        ld e,(ix+2)
        ld d,(ix+3)
        call cmp_s16            ; C = HL < DE
        res 2,(ix+0)
        ret c
        set 2,(ix+0)
        ret

fb_ctd: bit 1,(ix+0)
        jr z,.nl
        ld a,(ix+2)
        ld (ix+4),a
        ld a,(ix+3)
        ld (ix+5),a
        jr .q
.nl:    call fb_edge
        jr z,.q
        ld l,(ix+4)
        ld h,(ix+5)
        ld de,0x8000
        or a
        sbc hl,de
        jr z,.q
        add hl,de
        dec hl
        ld (ix+4),l
        ld (ix+5),h
.q:     call fb_prev
        ; Q = CV <= 0
        ld l,(ix+4)
        ld h,(ix+5)
        res 2,(ix+0)
        bit 7,h
        jr nz,.q1
        ld a,h
        or l
        ret nz
.q1:    set 2,(ix+0)
        ret

; NZ if bit0 rose (bit0 = 1, bit3 = 0)
fb_edge:
        bit 0,(ix+0)
        ret z
        bit 3,(ix+0)
        jr z,.r
        xor a
        ret
.r:     or 1
        ret
; bit3 = bit0
fb_prev:
        res 3,(ix+0)
        bit 0,(ix+0)
        ret z
        set 3,(ix+0)
        ret

; triggers: bit0 CLK, bit1 Q, bit2 previous CLK
fb_rtrig:
        res 1,(ix+0)
        bit 0,(ix+0)
        jr z,.m
        bit 2,(ix+0)
        jr nz,.m
        set 1,(ix+0)
.m:     jr fb_trig_mem
fb_ftrig:
        res 1,(ix+0)
        bit 0,(ix+0)
        jr nz,fb_trig_mem
        bit 2,(ix+0)
        jr z,fb_trig_mem
        set 1,(ix+0)
fb_trig_mem:
        res 2,(ix+0)
        bit 0,(ix+0)
        ret z
        set 2,(ix+0)
        ret

; bistables: bit0 S1/S, bit1 R/R1, bit2 Q1
fb_sr:  bit 0,(ix+0)            ; set dominant
        jr nz,.set
        bit 1,(ix+0)
        ret z
        res 2,(ix+0)
        ret
.set:   set 2,(ix+0)
        ret
fb_rs:  bit 1,(ix+0)            ; reset dominant
        jr nz,.res
        bit 0,(ix+0)
        ret z
        set 2,(ix+0)
        ret
.res:   res 2,(ix+0)
        ret

; ---- cmp_s16: HL, DE signed -> C if HL < DE
cmp_s16:
        ld a,h
        xor d
        jp m,.diff
        or a
        sbc hl,de
        ret
.diff:  bit 7,h                 ; different signs: negative one is smaller
        scf
        ret nz
        or a
        ret



vm_pc:    dw 0
vm_op:    db 0
vm_mode:  db 0
vm_arg:   dw 0
vm_arg3:  db 0
vm_cr:    dw 0
vm_crt:   db 0
vm_vt:    db 0
vm_tval:  dw 0
vm_ttype: db 0
vm_ops:   dw 0
vm_csp:   db 0
vm_psp:   db 0
ds_sq:    db 0
ds_sr:    db 0
