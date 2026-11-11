; ============================================================
; tests.asm - automated tests (build with -DTEST -DTPART=1 and -DTPART=2; each build
; runs one half of the tests so that it fits next to the whole editor)
; Result: TEST_RES+0 = passed, +1 = failed, +2 = 0xA5 done
; Green border = all OK, red = failure. Failing cases are printed.
; ============================================================
run_tests:
        ld a,1                  ; the tests expect View > Symbols
        ld (view_sym),a
        ld a,LANG_IL
        call proj_new
    IF TPART==1
        ld hl,t_motor           ; POU name for the operand tests
        ld a,LANG_FBD
        call pou_add
    ENDIF
        xor a
        ld (TEST_RES),a
        ld (TEST_RES+1),a
        ld (TEST_RES+2),a
        ld bc,0x0200
        ld (cur_col),bc
        ; ---- operand tests
    IF TPART==1
        ld hl,op_cases
.lp:    ld a,(hl)
        cp 0xFF
        jp z,.proj
        ld (t_in),hl
        call skipstr
        ld (t_exp),hl
        call skipstr
        ld (t_next),hl
        xor a
        ld (t_buf),a
        ld hl,(t_in)
        call op_parse
        jr c,.perr
        ld (t_area),a
        ld a,(hl)
        or a
        jr nz,.fail
        ld (t_val),de
        ld a,c
        ld (t_idx),a
        ld b,0
        ld hl,(t_exp)
        ld a,(hl)
        cp '~'
        jr nz,.st
        ld b,1
        inc hl
        ld (t_exp),hl
.st:    ld hl,(t_val)
        ld de,t_buf
        ld a,(t_idx)
        ld c,a
        ld a,(t_area)
        call op_format
        ld hl,t_buf
        ld de,(t_exp)
        call strcmp
        jr nz,.fail
        jr .pass
.perr:  ld hl,(t_exp)
        ld a,(hl)
        or a
        jr nz,.fail
.pass:  ld hl,TEST_RES
        inc (hl)
        jr .next
.fail:  ld hl,TEST_RES+1
        inc (hl)
        ld hl,(t_in)
        call scr_puts
        ld a,' '
        call scr_putc
        ld hl,t_buf
        call scr_puts
        ld a,'/'
        call scr_putc
        ld hl,(t_exp)
        call scr_puts
        ld a,(cur_row)
        inc a
        cp 22
        jr c,.rowok
        ld a,21
.rowok: ld b,a
        ld c,0
        ld (cur_col),bc
.next:  ld hl,(t_next)
        jp .lp

        ; ---- project tests
    ENDIF
.proj:
    IF TPART==1
        call proj_tests
        call ptext_tests
        call il_tests
    ELSE
        call vm_tests
        call sym_tests
        call ld_tests
        call fbd_tests
        call clip_tests
        call undo_tests
    ENDIF
        ; ---- result
        ld bc,0x0000
        ld (cur_col),bc
        ld hl,t_pass
        call scr_puts
        ld a,(TEST_RES)
        ld l,a
        ld h,0
        call scr_num
        ld hl,t_failtxt
        call scr_puts
        ld a,(TEST_RES+1)
        ld l,a
        ld h,0
        call scr_num
        ld a,0xA5
        ld (TEST_RES+2),a
        ld a,(TEST_RES+1)
        or a
        ld a,4
        jr z,.b
        ld a,2
.b:     out (0xFE),a
.halt:  halt
        jr .halt

; check one condition: Z = OK
t_check:
        ld hl,TEST_RES
        jr z,.ok
        inc hl
.ok:    inc (hl)
        ret

    IF TPART==1
proj_tests:
        ; MAIN = 0, MOTOR = 1 ; insert 10 B into MAIN, 5 B into MOTOR
        ld a,0
        ld de,0
        ld bc,10
        call pou_insert
        ld a,0x11
        ld bc,10
        call memset_hl_keep
        ld a,1
        ld de,0
        ld bc,5
        call pou_insert
        ld a,0x22
        ld bc,5
        call memset_hl_keep
        ; MOTOR body must start at POU_BODIES+10
        ld a,1
        call pou_body
        ld de,POU_BODIES+10
        or a
        sbc hl,de
        call t_check
        ld a,(POU_BODIES+10)
        cp 0x22
        call t_check
        ; insert 3 B into the middle of MAIN -> MOTOR moves
        xor a
        ld de,4
        ld bc,3
        call pou_insert
        ld a,1
        call pou_body
        ld de,POU_BODIES+13
        or a
        sbc hl,de
        call t_check
        ld a,(POU_BODIES+13)
        cp 0x22
        call t_check
        ld hl,(PROJ+P_LEN)
        ld de,HDR_LEN+18
        or a
        sbc hl,de
        call t_check
        ; delete 3 B from MAIN
        xor a
        ld de,4
        ld bc,3
        call pou_delete
        ld a,(POU_BODIES+10)
        cp 0x22
        call t_check
        ; delete MOTOR
        ld a,1
        call pou_remove
        ld hl,(PROJ+P_LEN)
        ld de,HDR_LEN+10
        or a
        sbc hl,de
        call t_check
        ld a,(PROJ+P_NPOU)
        cp 1
        call t_check
        ret

ptext_tests:
        ; width of "ii" = 2 * 2 px
        ld hl,t_ii
        call pt_width
        cp 4
        call t_check
        ; width of "File" = 5+2+3+5
        ld hl,mt_file
        call pt_width
        cp 15
        call t_check
        ; XOR span twice must restore the screen (row 0 checksum)
        call row0_sum
        ld (t_val),hl
        ld bc,0x0003            ; row 0, x = 3
        ld d,77
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        call row0_sum
        ld de,(t_val)
        or a
        sbc hl,de               ; must differ after one XOR
        ld a,h
        or l
        jr z,.eq
        xor a                   ; Z = pass
        jr .chk
.eq:    inc a                   ; NZ = fail
.chk:   call t_check
        ld bc,0x0003
        ld d,77
        ld hl,0x0008
        ld e,PX_XOR
        call px_span
        call row0_sum
        ld de,(t_val)
        or a
        sbc hl,de
        call t_check
        ret

; row0_sum: HL = sum of all pixel bytes of char row 0
row0_sum:
        ld hl,0
        ld de,0x4000
        ld c,8
.l1:    ld b,32
        push de
.l2:    ld a,(de)
        add a,l
        ld l,a
        jr nc,.n
        inc h
.n:     inc a                   ; weight by position to catch moved bits
        add a,l
        ld l,a
        jr nc,.n2
        inc h
.n2:    inc e
        djnz .l2
        pop de
        inc d
        dec c
        jr nz,.l1
        ret

t_ii:   db "ii",0

; ---- IL line check: mnemonic, operand, expected text ("" = error)
il_tests:
        ld hl,il_cases
.lp:    ld a,(hl)
        cp 0xFF
        ret z
        ld (t_in),hl            ; mnemonic
        call skipstr
        ld (t_val),hl           ; operand
        call skipstr
        ld (t_exp),hl
        call skipstr
        ld (t_next),hl
        xor a
        ld (il_out),a
        ld hl,(t_in)
        ld a,(hl)
        cp '/'
        jr z,.lab               ; "/" marks a label test
        ld de,(t_val)
        call il_check
        jr .chk
.lab:   ld hl,(t_val)
        call il_check_label
        jr c,.err
        ld hl,il_out
        jr .cmp
.chk:   jr c,.err
        call t_detok            ; binary -> "MNEM<TAB>OPERAND"
        ld hl,t_buf
.cmp:   ld de,(t_exp)
        call strcmp
        jr .res
.err:   ld hl,(t_exp)
        ld a,(hl)
        or a
.res:   push af
        call t_check
        pop af
        jr z,.next
        ld hl,(t_in)            ; print the failing case
        call scr_puts
        ld a,' '
        call scr_putc
        ld hl,(t_val)
        call scr_puts
        ld a,(cur_row)
        inc a
        cp 22
        jr c,.r
        ld a,21
.r:     ld b,a
        ld c,0
        ld (cur_col),bc
.next:  ld hl,(t_next)
        jr .lp

il_cases:
        db "ld",0,"i0.3",0,"LD",9,"%IX0.3",0
        db "LDN",0," %mx0.5 ",0,"LDN",9,"%MX0.5",0
        db "andn(",0,"m0.5",0,"ANDN(",9,"%MX0.5",0
        db "and(",0,0,"AND(",0
        db "st",0,"5",0,0
        db "st",0,"i0.0",0,0
        db "st",0,"sm1",0,0
        db "ld",0,"sm6",0,"LD",9,"%SM6",0
        db "st",0,"sw0",0,0
        db "st",0,"mw3",0,"ST",9,"%MW3",0
        db "s",0,"q0.7",0,"S",9,"%QX0.7",0
        db "r",0,"mw1",0,0
        db "not",0,0,"NOT",0
        db "not",0,"x",0,0
        db "ld",0,0,0
        db "add",0,"-5",0,"ADD",9,"-5",0
        db "gt",0,"t#1s",0,"GT",9,"T#1s",0
        db "jmpc",0,"loop",0,"JMPC",9,"LOOP",0
        db "jmp",0,"1x",0,0
        db "cal",0,"ton0(in:=i0.0, pt:=t#2s)",0,"CAL",9,"TON0(IN:=%IX0.0, PT:=T#2s)",0
        db "cal",0,"ctu1",0,"CAL",9,"CTU1",0
        db "cal",0,"ton0(cu:=m1)",0,0
        db "cal",0,"ton0(in:=m1",0,0
        db "cal",0,"main",0,"CAL",9,"MAIN",0
        db "cal",0,"xyz",0,0
        db "cal",0,"5",0,0
        db "ld",0,"ton0",0,0
        db "ld",0,"ton0.q",0,"LD",9,"TON0.Q",0
        db ")",0,0,")",0
        db "foo",0,"1",0,0
        db "ldx",0,"1",0,0
        db "ld(",0,"1",0,0
        db "/",0,"loop:",0,"LOOP:",0
        db "/",0,"Start_1 :",0,0
        db "/",0,"9x:",0,0
        db 0xFF

; ---- compiler + VM tests
    ENDIF
    IF TPART==2
vm_tests:
        ; program 1: latch with reset
        ld hl,t_prog1
        xor a
        BCALL il_load_text
        BCALL il_compile
        call t_nc
        BCALL vm_reset
        ld a,1
        call t_scan_i
        ld a,(RT_Q)
        and 1
        cp 1
        call t_check            ; set
        xor a
        call t_scan_i
        ld a,(RT_Q)
        and 1
        cp 1
        call t_check            ; holds
        ld a,2
        call t_scan_i
        ld a,(RT_Q)
        and 1
        call t_check            ; reset
        ; program 2: arithmetic, compare, "(", jump, CTU, POU call
        ld hl,t_motor
        ld a,LANG_IL
        call pou_add            ; slot 1 "MOTOR" (must exist before CAL MOTOR)
        ld hl,t_prog2
        xor a
        BCALL il_load_text
        call t_nc
        ld hl,t_prog3
        ld a,1
        BCALL il_load_text
        BCALL il_compile
        call t_nc
        BCALL vm_reset
        ld a,0x05               ; I0.0, I0.2
        call t_scan_i
        ld hl,RT_MW
        ld de,36
        call t_word
        ld hl,RT_MW+2
        ld de,-4
        call t_word
        ld hl,RT_MW+4
        ld de,-1
        call t_word
        ld hl,RT_MW+6
        ld de,1
        call t_word
        ld hl,RT_MW+8
        ld de,0
        call t_word             ; skipped by the jump
        ld hl,RT_MW+10
        ld de,5
        call t_word
        ld hl,RT_MW+12
        ld de,99
        call t_word             ; set by POU MOTOR
        ld a,(RT_Q)
        and 0x1C
        cp 0x1C                 ; Q0.2 GT, Q0.3 LT, Q0.4 AND(...)
        call t_check
        ; CTU0 PV=2: two rising edges of I0.3
        ld a,0x08
        call t_scan_i
        xor a
        call t_scan_i
        ld a,(RT_Q)
        and 0x20
        call t_check            ; not yet
        ld a,0x08
        call t_scan_i
        ld a,(RT_Q)
        and 0x20
        cp 0x20
        call t_check
        ; TON0 PT=T#100ms (5 ticks), dt = 3 per scan
        ld a,0x80
        call t_scan_i
        ld a,(RT_Q)
        and 0x40
        call t_check            ; ET = 3
        ld a,0x80
        call t_scan_i
        ld a,(RT_Q)
        and 0x40
        cp 0x40
        call t_check            ; ET = 5 -> Q
        ; compile error: unknown label
        ld hl,t_prog4
        xor a
        BCALL il_load_text
        BCALL il_compile
        ccf
        call t_nc
        ld hl,(il_err)
        ld de,err_cp_nolbl
        or a
        sbc hl,de
        call t_check
        ; step flags: one active bit per byte
        ld hl,t_prog5
        xor a
        BCALL il_load_text
        BCALL il_compile
        call t_nc
        BCALL vm_reset
        ld a,0x03               ; ST S0.2, then ST S0.5 -> only bit 5
        call t_scan_i
        ld a,(RT_STEP)
        cp 0x20
        call t_check
        ld a,(RT_STEP+1)        ; S S1.0 does not touch S0
        cp 0x01
        call t_check
        ld a,0x05               ; S0.2 on, ST S0.5 FALSE, R S0.5
        call t_scan_i
        ld a,(RT_STEP)
        cp 0x04
        call t_check
        ld a,0x06               ; S0.2 off, S0.5 on, then R S0.5
        call t_scan_i
        ld a,(RT_STEP)
        or a
        call t_check
        ret

; NC -> pass
    ENDIF
    IF TPART==2
; ---- undo / redo over several steps
undo_tests:
        BCALL um_reset
        call t_sum
        ld (t_us),hl            ; C0
        ld bc,10                ; step 1: 10 bytes in MAIN
        call t_ustep
        ld (t_us+2),hl
        ld bc,3                 ; step 2: 3 bytes
        call t_ustep
        ld (t_us+4),hl
        call t_arm              ; step 3: 5 bytes out
        xor a
        ld de,0
        ld bc,5
        call pou_delete
        call undo_do            ; back: C2, C1, C0, then nothing
        ld hl,(t_us+4)
        call t_usum
        call undo_do
        ld hl,(t_us+2)
        call t_usum
        call undo_do
        ld hl,(t_us)
        call t_usum
        call undo_do
        ccf
        call t_nc
        call redo_do            ; forward: C1, C2
        ld hl,(t_us+2)
        call t_usum
        call redo_do
        ld hl,(t_us+4)
        call t_usum
        ld bc,1                 ; a new change: no redo, undo -> C2
        call t_ustep
        call redo_do
        ccf
        call t_nc
        call undo_do
        ld hl,(t_us+4)
        call t_usum
        call t_sum              ; overflow: 2 x 10 steps of 1000 bytes
        ld (t_us),hl
        ld b,10
.ov:    push bc
        ld bc,1000
        call t_ustep
        ld (t_us+2),hl
        call t_arm
        xor a
        ld de,0
        ld bc,1000
        call pou_delete
        pop bc
        djnz .ov
        call undo_do            ; the newest steps are kept
        ld hl,(t_us+2)
        call t_usum
        call undo_do
        ld hl,(t_us)
        call t_usum
        ld b,0                  ; the oldest are gone: < 18 more steps
.uc:    push bc
        call undo_do
        pop bc
        jr c,.ue
        inc b
        jr .uc
.ue:    ld a,b
        cp 18
        ccf
        jp t_nc
; t_ustep: a new step, BC bytes (0x77) inserted at the start of MAIN -> HL = sum
t_ustep:
        call t_arm
        xor a
        ld de,0
        push bc
        call pou_insert
        pop bc
.f:     ld (hl),0x77
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.f
        jr t_sum
t_arm:  ld a,1
        ld (um_arm),a
        ret
; t_usum: the undo / redo went (NC) and the project sum is HL
t_usum: push hl
        call t_nc
        call t_sum
        pop de
        or a
        sbc hl,de
        jp t_check
; t_sum: HL = the sum of the project bytes (with its length)
t_sum:  ld de,PROJ
        ld bc,(PROJ+P_LEN)
        ld hl,0
.l:     ld a,(de)
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        add hl,hl               ; (order matters)
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.l
        ld de,(PROJ+P_LEN)
        add hl,de
        ret
t_us:   ds 6
    ENDIF
t_nc:   ld a,0
        jr nc,.ok
        inc a
.ok:    or a
        jp t_check

; A = inputs -> one scan with dt = 3
t_scan_i:
        ld (RT_I),a
        ld hl,3
        ld (vm_dt),hl
        BCALL vm_scan
        jr t_nc

; HL = address, DE = expected word
t_word: ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,de
        jp t_check


    IF TPART==2
; ---- clipboard: copy IL lines 1-2, paste them at line 0, cut them again
clip_tests:
        ld hl,t_clip
        xor a
        ld (cur_pou),a
        call il_load_text
        xor a
        call pou_body
        ld (t_val),bc
        ld de,rec_buf           ; the original body
        ldir
        ld hl,1                 ; mark line 1, cursor line 2: copy
        ld (mk_a),hl
        ld de,2
        ld a,CMD_COPY
        BCALL cl_cmd
        ld a,(clip_n)
        cp 2
        call t_check
        ld de,0                 ; paste in front of line 0
        ld a,CMD_PASTE
        BCALL cl_cmd
        xor a
        call pou_body
        ld hl,(t_val)
        ld de,(clip_len)
        add hl,de
        or a
        sbc hl,bc
        call t_check            ; longer by the clipboard
        ld hl,0                 ; cut lines 0-1
        ld (mk_a),hl
        ld de,1
        ld a,CMD_CUT
        BCALL cl_cmd
        xor a
        call pou_body
        ld de,rec_buf
.c:     ld a,(de)
        cp (hl)
        jr nz,.ne
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.c
.ne:    call t_check            ; the original body again
        ret
t_clip: db "LD",9,"%IX0.0",0
        db "ST",9,"%QX0.0",0
        db "ST",9,"%QX0.1",0
        db 0xFF

t_prog1:
        db "LD",9,"%IX0.0",0
        db "OR",9,"%QX0.0",0
        db "ANDN",9,"%IX0.1",0
        db "ST",9,"%QX0.0",0
        db 0xFF
t_prog2:
        db "LD",9,"7",0
        db "ADD",9,"5",0
        db "MUL",9,"3",0
        db "ST",9,"%MW0",0
        db "SUB",9,"40",0
        db "ST",9,"%MW1",0
        db "DIV",9,"3",0
        db "ST",9,"%MW2",0
        db "LD",9,"%MW0",0
        db "MOD",9,"5",0
        db "ST",9,"%MW3",0
        db "LD",9,"%MW0",0
        db "GT",9,"10",0
        db "ST",9,"%QX0.2",0
        db "LD",9,"%MW1",0
        db "LT",9,"0",0
        db "ST",9,"%QX0.3",0
        db "LD",9,"%IX0.0",0
        db "AND(",9,"%IX0.1",0
        db "OR",9,"%IX0.2",0
        db ")",0
        db "ST",9,"%QX0.4",0
        db "LD",9,"TRUE",0
        db "JMPC",9,"SKIP",0
        db "LD",9,"1",0
        db "ST",9,"%MW4",0
        db "SKIP:",0
        db "LD",9,"5",0
        db "ST",9,"%MW5",0
        db "CAL",9,"CTU0(CU:=%IX0.3, PV:=2)",0
        db "LD",9,"CTU0.Q",0
        db "ST",9,"%QX0.5",0
        db "CAL",9,"TON0(IN:=%IX0.7, PT:=T#100ms)",0
        db "LD",9,"TON0.Q",0
        db "ST",9,"%QX0.6",0
        db "CAL",9,"MOTOR",0
        db 0xFF
t_prog3:
        db "LD",9,"99",0
        db "ST",9,"%MW6",0
        db 0xFF
t_prog4:
        db "JMP",9,"NOWHERE",0
        db 0xFF
t_prog5:
        db "LD",9,"%IX0.0",0
        db "ST",9,"S0.2",0
        db "LD",9,"%IX0.1",0
        db "ST",9,"S0.5",0
        db "LD",9,"%IX0.2",0
        db "R",9,"S0.5",0
        db "LD",9,"TRUE",0
        db "S",9,"%SX1.0",0
        db 0xFF

; ---- symbol table
sym_tests:
        ld a,AR_Q
        ld c,0
        ld hl,t_sym_motor
        ld de,t_sym_mcomm
        call sym_store
        call t_nc
        ld a,AR_I
        ld c,0
        ld hl,t_sym_start
        ld de,cp_empty
        call sym_store
        call t_nc
        ; name lookup (any case)
        ld hl,t_sym_motl
        call op_parse
        ld (t_area),a
        ld a,c
        ld (t_idx),a
        call t_nc
        ld a,(t_area)
        cp AR_Q
        call t_check
        ld a,(t_idx)
        or a
        call t_check
        ; IL accepts the symbol, stores the address
        ld hl,t_ld
        ld de,t_sym_startl
        call il_check
        call t_nc
        call t_detok            ; shown as the symbol
        ld hl,t_buf
        ld de,t_sym_ldout
        call strcmp
        call t_check
        xor a                   ; View > Addresses
        ld (view_sym),a
        call t_detok
        ld a,1
        ld (view_sym),a
        ld hl,t_buf
        ld de,t_sym_ldadr
        call strcmp
        call t_check
        ; validation: own name ok, used / reserved / invalid rejected
        ld hl,t_sym_start
        ld a,AR_I
        ld c,0
        call sym_validate
        call t_nc
        ld hl,t_sym_start
        ld a,AR_I
        ld c,1
        call sym_validate
        ccf
        call t_nc
        ld hl,t_sym_ton
        ld a,AR_M
        ld c,0
        call sym_validate
        ccf
        call t_nc
        ld hl,t_sym_bad
        ld a,AR_M
        ld c,0
        call sym_validate
        ccf
        call t_nc
        ; FB instance symbol: "delay1.et" -> TON1.ET, shown as "Delay1.ET"
        ld a,AR_FBI
        ld c,1
        ld hl,t_sym_delay
        ld de,cp_empty
        call sym_store
        call t_nc
        ld hl,t_ld
        ld de,t_sym_dly_et
        call il_check
        call t_nc
        ld a,(il_out+1)
        cp AR_FBM+0x30          ; member 3 (ET)
        call t_check
        ld a,(il_out+2)
        cp 1
        call t_check
        call t_detok
        ld hl,t_buf
        ld de,t_sym_dly_out
        call strcmp
        call t_check
        ; delete: empty name and comment
        ld a,AR_I
        ld c,0
        ld hl,cp_empty
        ld de,cp_empty
        call sym_store
        ld a,AR_I
        ld c,0
        call sym_find_addr
        ccf
        jp t_nc

t_ld:         db "ld",0
t_sym_motor:  db "Motor1",0
t_sym_motl:   db "motor1",0
t_sym_mcomm:  db "Conveyor drive",0
t_sym_start:  db "Start",0
t_sym_startl: db "start",0
t_sym_ldout:  db "LD",9,"Start",0
t_sym_ldadr:  db "LD",9,"%IX0.0",0
t_sym_ton:    db "TON0",0
t_sym_bad:    db "1abc",0
t_sym_delay:  db "Delay1",0
t_sym_dly_et: db "delay1.et",0
t_sym_dly_out: db "LD",9,"Delay1.ET",0

; t_detok: il_out (binary instruction) -> t_buf = "MNEM" [TAB "OPERAND"]
    ENDIF
t_detok:
        ld a,(il_outlen)
        ld c,a
        add a,2
        ld (rec_buf),a
        ld a,K_INSTR
        ld (rec_buf+1),a
        ld b,0
        ld hl,il_out
        ld de,rec_buf+2
        ldir
        ld hl,rd_m
        ld (sp_m),hl
        ld hl,rd_o
        ld (sp_o),hl
        ld hl,rd_c
        ld (sp_c),hl
        ld hl,rec_buf
        BCALL il_split
        ld de,t_buf
        ld hl,rd_m
        call put_str
        ld a,(rd_o)
        or a
        jr z,.e
        ld a,9
        ld (de),a
        inc de
        ld hl,rd_o
        call put_str
.e:     xor a
        ld (de),a
        ret

; ---- LD compiler: latch with NC reset, P contact -> (S), NO -> (R)
    IF TPART==2
ld_tests:
        ld hl,t_ldname
        ld a,LANG_LD
        call pou_add
        ld (cur_pou),a
        ld hl,5                 ; PT of the timer box (5 ticks)
        ld (ld_ppt),hl
        ld hl,t_ld_cells
.cell:  ld a,(hl)
        cp 0xFF
        jr z,.prog
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        push hl
        BCALL ld_put
        pop hl
        jr .cell
.prog:  xor a
        ld (cur_pou),a
        ld hl,t_ld_main         ; MAIN: CAL LDT
        BCALL il_load_text
        call t_nc
        BCALL il_compile
        call t_nc
        BCALL vm_reset
        ld a,0x01               ; I0.0: Q0.0 on
        call t_scan_i
        xor a                   ; holds
        call t_scan_i
        ld a,(RT_Q)
        and 1
        cp 1
        call t_check
        ld a,0x02               ; I0.1 (NC): off
        call t_scan_i
        ld a,(RT_Q)
        and 1
        call t_check
        ld a,0x04               ; rising I0.2: set M0
        call t_scan_i
        ld a,(RT_M)
        and 1
        cp 1
        call t_check
        ld a,0x08               ; I0.3: reset M0
        call t_scan_i
        ld a,(RT_M)
        and 1
        call t_check
        ld a,0x10               ; I0.4 -> TON2 (PT 5, dt 3): not yet
        call t_scan_i
        ld a,(RT_Q)
        and 4
        call t_check
        ld a,0x10               ; ET 6 >= 5 -> Q0.2
        call t_scan_i
        ld a,(RT_Q)
        and 4
        cp 4
        call t_check
        ld a,0x20               ; I0.5: set coil S0.3 -> contact S0.3 -> Q0.3
        call t_scan_i
        ld a,(RT_STEP)
        cp 0x08
        call t_check
        ld a,(RT_Q)
        and 8
        cp 8
        call t_check
        ld a,0x40               ; I0.6: set coil S0.5 clears S0.3 -> Q0.3 off
        call t_scan_i
        ld a,(RT_STEP)
        cp 0x20
        call t_check
        ld a,(RT_Q)
        and 8
        jp t_check

; ---- FBD compiler: cells built with ld_put, MAIN = CAL FBT
fbd_tests:
        ld hl,t_fbname
        ld a,LANG_FBD
        call pou_add
        ld (cur_pou),a
        ld hl,5
        ld (ld_ppt),hl
        ld hl,t_fb_cells
.cell:  ld a,(hl)
        cp 0xFF
        jr z,.prog
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        push hl
        BCALL ld_put
        pop hl
        jr .cell
.prog:  xor a
        ld (cur_pou),a
        ld hl,t_fb_main
        BCALL il_load_text
        call t_nc
        BCALL il_compile
        call t_nc
        BCALL vm_reset
        ld hl,t_fb_cases
.case:  ld a,(hl)               ; inputs, Q mask, Q expected, M0 expected
        cp 0xEE
        ret z
        inc hl
        push hl
        call t_scan_i
        pop hl
        ld a,(RT_Q)
        and (hl)
        inc hl
        cp (hl)
        inc hl
        push hl
        call t_check
        pop hl
        ld a,(RT_M)
        and 1
        cp (hl)
        inc hl
        push hl
        call t_check
        pop hl
        jr .case

; inputs, mask of the checked outputs, expected outputs, expected M0
t_fb_cases:
        db 0x03, 0x07, 0x07, 0  ; AND: Q0.0; Q0.1 = NOT(0 XOR 0); TON starts: Q0.2 = NOT Q
        db 0x07, 0x01, 0x00, 0  ; I0.2 (negated input) blocks the AND
        db 0x08, 0x02, 0x00, 0  ; (I3 OR I4) XOR I5 = 1 -> negated output 0
        db 0x28, 0x02, 0x02, 0  ; 1 XOR 1 = 0 -> 1
        db 0x40, 0x00, 0x00, 1  ; SR set
        db 0x00, 0x00, 0x00, 1  ; holds
        db 0x80, 0x00, 0x00, 0  ; reset
        db 0x01, 0x04, 0x04, 0  ; TON3: ET 3 < 5, Q0.2 = NOT Q = 1
        db 0x01, 0x04, 0x00, 0  ; ET 6 >= 5: Q -> Q0.2 = 0
        db 0xEE

t_fbname: db "FBT     "
t_fb_main: db "CAL",9,"FBT",0
        db 0xFF
t_fb_cells:
        ; rows 0-2: Q0.0 = I0.0 AND I0.1 AND NOT I0.2
        db 0,0,FT_IN,AR_I,0
        db 0,1,FT_AND,3,0
        db 0,2,FT_WIRE,0,0
        db 0,3,FT_WIRE,0,0
        db 0,4,FT_WIRE,0,0
        db 0,5,FT_WIRE,0,0
        db 0,6,FT_WIRE,0,0
        db 0,7,FT_WIRE,0,0
        db 0,8,FT_WIRE,0,0
        db 0,9,FT_OUT,AR_Q,0
        db 1,0,FT_IN,AR_I,1
        db 2,0,FT_IN|FT_NEG,AR_I,2
        ; rows 4-5: Q0.1 = NOT ((I0.3 OR I0.4) XOR I0.5)
        db 4,0,FT_IN,AR_I,3
        db 4,1,FT_OR,2,0
        db 4,2,FT_WIRE,0,0
        db 4,3,FT_XOR,2,0
        db 4,4,FT_WIRE,0,0
        db 4,5,FT_WIRE,0,0
        db 4,6,FT_WIRE,0,0
        db 4,7,FT_WIRE,0,0
        db 4,8,FT_WIRE,0,0
        db 4,9,FT_OUT|FT_NEG,AR_Q,1
        db 5,0,FT_IN,AR_I,4
        db 5,2,FT_IN,AR_I,5
        ; rows 7-8: M0 = SR0(S1 := I0.6, R := I0.7)
        db 7,0,FT_IN,AR_I,6
        db 7,1,FT_SR,AR_FBI,FBT_SR*FB_PER_TYPE
        db 7,2,FT_WIRE,0,0
        db 7,3,FT_WIRE,0,0
        db 7,4,FT_WIRE,0,0
        db 7,5,FT_WIRE,0,0
        db 7,6,FT_WIRE,0,0
        db 7,7,FT_WIRE,0,0
        db 7,8,FT_WIRE,0,0
        db 7,9,FT_OUT,AR_M,0
        db 8,0,FT_IN,AR_I,7
        ; row 10: Q0.2 = NOT TON3(IN := I0.0, PT = 5 ticks).Q
        db 10,0,FT_IN,AR_I,0
        db 10,1,FT_TON,AR_FBI,3
        db 10,2,FT_NOT,1,0
        db 10,3,FT_WIRE,0,0
        db 10,4,FT_WIRE,0,0
        db 10,5,FT_WIRE,0,0
        db 10,6,FT_WIRE,0,0
        db 10,7,FT_WIRE,0,0
        db 10,8,FT_WIRE,0,0
        db 10,9,FT_OUT,AR_Q,2
        db 0xFF

t_ldname: db "LDT     "
t_ld_main: db "CAL",9,"LDT",0
        db 0xFF
; row, pos, type, area, index
t_ld_cells:
        db 0,0,LT_NO|LT_VL,AR_I,0
        db 0,1,LT_NC,AR_I,1
        db 0,2,LT_WIRE,0,0
        db 0,3,LT_WIRE,0,0
        db 0,4,LT_WIRE,0,0
        db 0,5,LT_WIRE,0,0
        db 0,6,LT_WIRE,0,0
        db 0,7,LT_WIRE,0,0
        db 0,8,LT_WIRE,0,0
        db 0,9,LT_COIL,AR_Q,0
        db 1,0,LT_NO,AR_Q,0
        db 2,0,LT_P,AR_I,2
        db 2,1,LT_WIRE,0,0
        db 2,2,LT_WIRE,0,0
        db 2,3,LT_WIRE,0,0
        db 2,4,LT_WIRE,0,0
        db 2,5,LT_WIRE,0,0
        db 2,6,LT_WIRE,0,0
        db 2,7,LT_WIRE,0,0
        db 2,8,LT_WIRE,0,0
        db 2,9,LT_SET,AR_M,0
        db 3,0,LT_NO,AR_I,3
        db 3,1,LT_WIRE,0,0
        db 3,2,LT_WIRE,0,0
        db 3,3,LT_WIRE,0,0
        db 3,4,LT_WIRE,0,0
        db 3,5,LT_WIRE,0,0
        db 3,6,LT_WIRE,0,0
        db 3,7,LT_WIRE,0,0
        db 3,8,LT_WIRE,0,0
        db 3,9,LT_RES,AR_M,0
        db 4,0,LT_NO,AR_I,4
        db 4,1,LT_TON,AR_FBI,2
        db 4,2,LT_WIRE,0,0
        db 4,3,LT_WIRE,0,0
        db 4,4,LT_WIRE,0,0
        db 4,5,LT_WIRE,0,0
        db 4,6,LT_WIRE,0,0
        db 4,7,LT_WIRE,0,0
        db 4,8,LT_WIRE,0,0
        db 4,9,LT_COIL,AR_Q,2
        db 5,0,LT_NO,AR_I,5
        db 5,1,LT_WIRE,0,0
        db 5,2,LT_WIRE,0,0
        db 5,3,LT_WIRE,0,0
        db 5,4,LT_WIRE,0,0
        db 5,5,LT_WIRE,0,0
        db 5,6,LT_WIRE,0,0
        db 5,7,LT_WIRE,0,0
        db 5,8,LT_WIRE,0,0
        db 5,9,LT_SET,AR_SX,3
        db 6,0,LT_NO,AR_I,6
        db 6,1,LT_WIRE,0,0
        db 6,2,LT_WIRE,0,0
        db 6,3,LT_WIRE,0,0
        db 6,4,LT_WIRE,0,0
        db 6,5,LT_WIRE,0,0
        db 6,6,LT_WIRE,0,0
        db 6,7,LT_WIRE,0,0
        db 6,8,LT_WIRE,0,0
        db 6,9,LT_SET,AR_SX,5
        db 7,0,LT_NO,AR_SX,3
        db 7,1,LT_WIRE,0,0
        db 7,2,LT_WIRE,0,0
        db 7,3,LT_WIRE,0,0
        db 7,4,LT_WIRE,0,0
        db 7,5,LT_WIRE,0,0
        db 7,6,LT_WIRE,0,0
        db 7,7,LT_WIRE,0,0
        db 7,8,LT_WIRE,0,0
        db 7,9,LT_COIL,AR_Q,3
        db 0xFF

    ENDIF
memset_hl_keep:
        push hl
        call memset
        pop hl
        ret

skipstr:
        ld a,(hl)
        inc hl
        or a
        jr nz,skipstr
        ret

; strcmp: HL, DE -> Z if equal
strcmp:
        ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr strcmp

t_motor:   db "MOTOR   "
t_pass:    db "PASS ",0
t_failtxt: db "  FAIL ",0
t_in:      dw 0
t_exp:     dw 0
t_next:    dw 0
t_area:    db 0
t_idx:     db 0
t_val:     dw 0
t_buf:     ds 32

; input, expected output ("" = error, "~" = short style)
    IF TPART==1
op_cases:
        db "%IX0.3",0,"%IX0.3",0
        db "%IX0.7",0,"~I0.7",0
        db "I0.5",0,"%IX0.5",0
        db "%I0.1",0,"%IX0.1",0
        db "q0.0",0,"%QX0.0",0
        db "%QX0.6",0,"~Q0.6",0
        db "S0.2",0,"%SX0.2",0
        db "%SX7.7",0,"~S7.7",0
        db "%S3.1",0,"%SX3.1",0
        db "s1.0",0,"%SX1.0",0
        db "S8.0",0,0
        db "S0.8",0,0
        db "%MX7.7",0,"%MX7.7",0
        db "M0.5",0,"%MX0.5",0
        db "%M1.4",0,"~M1.4",0
        db "MW15",0,"%MW15",0
        db "%MW3",0,"~MW3",0
        db "TRUE",0,"TRUE",0
        db "false",0,"FALSE",0
        db "0",0,"0",0
        db "123",0,"123",0
        db "-123",0,"-123",0
        db "32767",0,"32767",0
        db "-32768",0,"-32768",0
        db "T#2s",0,"T#2s",0
        db "T#1s500ms",0,"T#1s500ms",0
        db "t#1m",0,"T#60s",0
        db "TIME#100ms",0,"T#100ms",0
        db "T#0s",0,"T#0s",0
        db "TON0",0,"TON0",0
        db "TON0.Q",0,"TON0.Q",0
        db "tof3.et",0,"TOF3.ET",0
        db "TP1.PT",0,"TP1.PT",0
        db "CTU2.CV",0,"CTU2.CV",0
        db "CTD0.LD",0,"CTD0.LD",0
        db "RT3.CLK",0,"RT3.CLK",0
        db "RF0.Q",0,"RF0.Q",0
        db "SR1.S1",0,"SR1.S1",0
        db "RS2.R1",0,"RS2.R1",0
        db "i1.7",0,"%IX1.7",0
        db "sm3",0,"%SM3",0
        db "%SM0",0,"%SM0",0
        db "sw2",0,"%SW2",0
        db "%SW0",0,"%SW0",0
        db "%QX1.0",0,"%QX1.0",0
        db "MAIN",0,"MAIN",0
        db "MOTOR",0,"MOTOR",0
        ; errors
        db "%IX0.8",0,0
        db "%IX2.0",0,0
        db "%SM8",0,0
        db "%SW3",0,0
        db "Q2.1",0,0
        db "M8.0",0,0
        db "M5",0,0
        db "MW16",0,0
        db "TON4",0,0
        db "TON0.FOO",0,0
        db "CTU0.IN",0,0
        db "XYZ",0,0
        db "32768",0,0
        db "-32769",0,0
        db "99999",0,0
        db "T#",0,0
        db "T#5x",0,0
        db "%Z1",0,0
        db 0xFF
    ENDIF
