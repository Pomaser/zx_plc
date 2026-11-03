; ============================================================
; tests.asm - automated tests (build with -DTEST)
; Result: TEST_RES+0 = passed, +1 = failed, +2 = 0xA5 done
; Green border = all OK, red = failure. Failing cases are printed.
; ============================================================
run_tests:
        ld a,LANG_IL
        call proj_new
        ld hl,t_motor
        ld a,LANG_FBD
        call pou_add
        xor a
        ld (TEST_RES),a
        ld (TEST_RES+1),a
        ld (TEST_RES+2),a
        ld bc,0x0200
        ld (cur_col),bc
        ; ---- operand tests
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
.proj:  call proj_tests
        call ptext_tests
        call il_tests
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
.chk:   jr c,.err
        ld hl,il_out
        ld de,(t_exp)
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
        db "LDN",0," %mx5 ",0,"LDN",9,"%MX5",0
        db "andn(",0,"m5",0,"ANDN(",9,"%MX5",0
        db "and(",0,0,"AND(",0
        db "st",0,"5",0,0
        db "st",0,"i0.0",0,0
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
op_cases:
        db "%IX0.3",0,"%IX0.3",0
        db "%IX0.7",0,"~I0.7",0
        db "I0.5",0,"%IX0.5",0
        db "%I0.1",0,"%IX0.1",0
        db "q0.0",0,"%QX0.0",0
        db "%QX0.6",0,"~Q0.6",0
        db "%MX63",0,"%MX63",0
        db "M5",0,"%MX5",0
        db "%M12",0,"~M12",0
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
        db "R_TRIG3.CLK",0,"R_TRIG3.CLK",0
        db "F_TRIG0.Q",0,"F_TRIG0.Q",0
        db "SR1.S1",0,"SR1.S1",0
        db "RS2.R1",0,"RS2.R1",0
        db "MAIN",0,"MAIN",0
        db "MOTOR",0,"MOTOR",0
        ; errors
        db "%IX0.8",0,0
        db "%IX1.0",0,0
        db "M64",0,0
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
