; ============================================================
; st_comp.asm - Structured Text compiler (RUN bank)
; ============================================================
; Recursive descent over the tokens of all lines of the POU (statements
; may span lines). Expressions are compiled for the accumulator machine
; of vm.asm: "a + b" -> LD a / ADD b; a right side that is not a single
; operand -> PUSH op / (right side) / POP, at most 8 levels deep.
; Precedence: OR < XOR < AND & < = <> < < > <= >= < + - < * / MOD < NOT -.
; Forward jumps are chained through their arg field (0 = end of the
; chain) and patched when the target is known (sc_patchl).
; Errors leave through sc_err (SP restored, C), the message in il_out
; (fixed memory), cp_line = the line of the token (1-based).
; ============================================================

; ---- st_compile: compiles ST POU cp_slot at cp_pc (cp_pass = 2); C = error
st_compile:
        ld (sc_sp),sp
        ld a,(cp_slot)
        call pou_body
        ld (sc_rec),hl
        add hl,bc
        ld (cp_end),hl
        ld hl,0
        ld (cp_line),hl
        ld (sc_exitl),hl
        ld (sc_lrec),hl
        xor a
        ld (sc_loops),a
        ld (sc_pdep),a
        ld (cp_text),a
        ld hl,cp_text
        ld (stc.lx_p),hl
        call tk_next
        ld a,(stc.lx_type)      ; local variables: VAR ... END_VAR first
        cp T_KW
        jr nz,.st
        ld a,(stc.lx_kw)
        cp KW_VAR
        call z,sc_var
.st:    call sc_stmts
        ld a,(stc.lx_type)      ; everything used?
        or a
        ret z
        jp sc_syntax

; ============================================================
; tokens
; ============================================================

; ---- tk_next: the next token of the POU (comments skipped); T_END = end
tk_next:
.l:     call stc.lx_next
        ld a,(stc.lx_type)
        or a
        jr z,.eol
        cp T_CMT
        jr z,.cmt
        cp T_BAD
        ret nz
        ld hl,err_sc_char
        jp sc_err
.cmt:   ld a,(stc.lx_bad)
        or a
        jr z,.l
        ld hl,err_sc_cmt
        jp sc_err
.eol:   ld hl,(sc_rec)          ; the next line
        ld de,(cp_end)
        or a
        sbc hl,de
        ret nc
        add hl,de
        ld de,(cp_line)
        inc de
        ld (cp_line),de
        call sc_load
        jr .l

; sc_load: HL = line record -> its text in cp_text, sc_rec = the next one
sc_load:
        ld (sc_lrec),hl
        ld c,(hl)
        ld b,0
        push hl
        add hl,bc
        ld (sc_rec),hl
        pop hl
        ld de,cp_text
        inc hl
        ld a,(hl)
        inc hl
        inc hl
        cp K_STXT
        jr nz,.e
        ld a,c
        sub 3
        jr z,.e
        jr c,.e
        cp 63
        jr c,.ok
        ld a,63
.ok:    ld c,a
        ldir
.e:     xor a
        ld (de),a
        ld hl,cp_text
        ld (stc.lx_p),hl
        ret

; sc_mark: the position of the current token -> HL = line record,
;      DE = line number, BC = offset in the line
sc_mark:
        ld hl,(stc.lx_start)
        ld de,cp_text
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ld hl,(sc_lrec)
        ld de,(cp_line)
        ret

; sc_goto: HL, DE, BC from sc_mark -> that token is the current one again
sc_goto:
        ld (cp_line),de
        push bc
        ld de,(sc_lrec)
        or a
        sbc hl,de
        add hl,de
        call nz,sc_load
        pop bc
        ld hl,cp_text
        add hl,bc
        ld (stc.lx_p),hl
        jp tk_next

; sc_word: the current token is an operand / name -> op_parse:
;      sc_oa = area, sc_oi = index, sc_ov = value, sc_wbuf = the word;
;      A = area AND AR_MASK; next token
sc_word:
        ld a,(stc.lx_type)
        cp T_WORD
        jp nz,sc_syntax
        ld hl,stc.lx_word
        ld de,sc_wbuf
        call put_str
        xor a
        ld (de),a
        ld a,(cp_slot)          ; a local variable of the POU?
        ld hl,sc_wbuf
        call stc.st_vfind
        jr c,.glob
        call sc_lvop
        call tk_next
        ld a,AR_LV
        ret
.glob:  ld hl,sc_wbuf
        call op_parse
        jr c,.unk
        ld b,a
        ld a,(hl)
        or a
        jr nz,.unk
        ld a,b
        ld (sc_oa),a
        ld a,c
        ld (sc_oi),a
        ld (sc_ov),de
        call tk_next
        ld a,(sc_oa)
        and AR_MASK
        ret
.unk:   ld hl,err_sc_name
        ld de,il_out
        call put_str
        ld hl,sc_wbuf
        call put_str
        xor a
        ld (de),a
        jp sc_err_buf

; sc_wrchk: A = area (masked) -> error if it cannot be written
sc_wrchk:
        cp AR_LV
        ret z
        cp AR_Q
        ret z
        cp AR_M
        ret z
        cp AR_MW
        ret z
        cp AR_SX
        ret z
        cp AR_FBM
        ret z
        ld hl,err_il_wr
        jp sc_err

; sc_const: [-] number -> HL = value; next token
sc_const:
        ld a,(stc.lx_type)
        cp T_SYM
        ld b,0
        jr nz,.p
        ld a,(stc.lx_sym)
        cp '-'
        jp nz,sc_syntax
        inc b
        push bc
        call tk_next
        pop bc
.p:     push bc
        call sc_word
        pop bc
        cp AR_K16
        ld hl,err_sc_const
        jp nz,sc_err
        ld hl,(sc_ov)
        dec b
        ret nz
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
        ret

; sc_issym: A = char -> Z if the current token is that symbol
sc_issym:
        ld b,a
        ld a,(stc.lx_type)
        cp T_SYM
        ret nz
        ld a,(stc.lx_sym)
        cp b
        ret

; sc_expect: A = symbol -> next token, or the error "'x' expected"
sc_expect:
        call sc_issym
        jp z,tk_next
        ld hl,il_out
        ld (hl),"'"
        inc hl
        ld a,b
        cp S_ASG
        jr nz,.c
        ld (hl),':'
        inc hl
        ld a,'='
.c:     ld (hl),a
        inc hl
        ld (hl),"'"
        inc hl
        jr sc_expd

; sc_expect_kw: A = keyword -> next token, or the error "KEYWORD expected"
sc_expect_kw:
        ld b,a
        ld a,(stc.lx_type)
        cp T_KW
        jr nz,.e
        ld a,(stc.lx_kw)
        cp b
        jp z,tk_next
.e:     ld hl,stc.lx_kwtab      ; the name of keyword B
.f:     ld e,(hl)
        inc hl
        dec b
        jr z,.cp
        ld d,0
        add hl,de
        jr .f
.cp:    ld c,e
        ld b,0
        ld de,il_out
        ldir
        ex de,hl
sc_expd:                        ; HL = end of the text in il_out
        ex de,hl
        ld hl,txt_sc_exp
        call put_str
        xor a
        ld (de),a
        jr sc_err_buf

sc_semi:
        ld a,';'
        jr sc_expect
sc_optsemi:                     ; (";" after END_IF etc. is optional)
        ld a,';'
        call sc_issym
        ret nz
        jp tk_next

sc_syntax:
        ld hl,err_sc_syn
; ---- sc_err: HL = message -> compile error (SP of st_compile, C)
sc_err: ld de,il_out
        call put_str
        xor a
        ld (de),a
sc_err_buf:
        ld hl,il_out
        ld (il_err),hl
sc_errx:
        ld sp,(sc_sp)
        scf
        ret

; ============================================================
; code
; ============================================================

; sc_emit: A = op, operand in cp_mode / cp_arg / cp_arg3
sc_emit:
        call cp_emit
        ret nc
        jr sc_errx
sc_emit0:
        call cp_emit0
        ret nc
        jr sc_errx

; sc_emitv: A = op with the operand sc_oa / sc_oi / sc_ov
sc_emitv:
        push af
        ld a,(sc_oa)
        and AR_MASK
        cp AR_LV
        jr nz,.g
        call sc_lvmode          ; a local variable (st_var.asm)
        pop af
        jr sc_emit
.g:     ld a,(sc_oi)
        ld c,a
        ld de,(sc_ov)
        ld a,(sc_oa)
        call cp_operand_av
        jr c,sc_errx
        pop af
        jr sc_emit

; sc_emitk: A = op with the INT constant HL
sc_emitk:
        ld (sc_ov),hl
        ld b,a
        ld a,AR_K16
        ld (sc_oa),a
        ld a,b
        jr sc_emitv

; sc_emitj: A = jump op, HL = target (or the chain) -> HL = its address
sc_emitj:
        ld (cp_arg),hl
        ld b,a
        xor a
        ld (cp_mode),a
        ld (cp_arg3),a
        ld hl,(cp_pc)
        push hl
        ld a,b
        call sc_emit
        pop hl
        ret

; sc_push: A = op applied by the matching POP
sc_push:
        ld (cp_mode),a
        ld hl,sc_pdep
        inc (hl)
        ld a,(hl)
        cp 9
        ld hl,err_sc_deep
        jp nc,sc_err
        xor a
        ld (cp_arg3),a
        ld hl,0
        ld (cp_arg),hl
        ld a,OP_PUSH
        jr sc_emit
sc_pop: ld hl,sc_pdep
        dec (hl)
        ld a,OP_POP
        jr sc_emit0

; sc_patch1: HL = jump (0: none) -> its target = cp_pc (keeps DE)
sc_patch1:
        ld a,h
        or l
        ret z
        inc hl
        inc hl
        push de
        ld de,(cp_pc)
        ld (hl),e
        inc hl
        ld (hl),d
        pop de
        ret

; sc_patchl: HL = chain of jumps -> all of them to cp_pc
sc_patchl:
.l:     ld a,h
        or l
        ret z
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld de,(cp_pc)
        ld (hl),d
        dec hl
        ld (hl),e
        pop hl
        jr .l

; ============================================================
; expressions
; ============================================================

; ---- sc_expr: the expression at the current token -> CR
sc_expr:
        xor a
; sc_lvl: A = precedence level 0-6 (binary operators), 7 = unary
sc_lvl: cp 7
        jp z,sc_unary
        push af
        inc a
        call sc_lvl
        pop af
; sc_loop: A = level -> the operators of this level and their right sides
sc_loop:
.l:     push af
        call sc_binop
        jr c,.no
        pop af
        cp b
        ret nz
        push af
        push bc
        call tk_next
        pop bc
        pop af
        push af
        call sc_right
        pop af
        jr .l
.no:    pop af
        ret

; sc_right: A = level, C = op -> CR = CR op (right side)
sc_right:
        ld b,a
        ld a,(stc.lx_type)
        cp T_WORD
        jr nz,.gen
        push bc
        call sc_word
        call sc_binop           ; an operator binding stronger after it?
        pop de                  ; D = level, E = op
        jr c,.simple
        ld a,b
        cp d
        jr c,.simple
        jr z,.simple
        push de                 ; PUSH op / LD operand / the stronger ops / POP
        ld a,e
        call sc_push
        ld a,OP_LD
        call sc_emitv
        pop de
        ld a,6
.cl:    cp d
        jp z,sc_pop
        push af
        push de
        call sc_loop
        pop de
        pop af
        dec a
        jr .cl
.simple:
        ld a,e
        jp sc_emitv
.gen:   push bc
        ld a,c
        call sc_push
        pop bc
        ld a,b
        inc a
        call sc_lvl
        jp sc_pop

; sc_unary: NOT x, -x, +x, (expr), operand -> CR
sc_unary:
        ld a,(stc.lx_type)
        cp T_KW
        jr nz,.nk
        ld a,(stc.lx_kw)
        cp KW_NOT
        jp nz,sc_syntax
        call tk_next
        call sc_unary
        ld a,OP_NOT
        jp sc_emit0
.nk:    cp T_SYM
        jr nz,.w
        ld a,(stc.lx_sym)
        cp '('
        jr z,.par
        cp '-'
        jr z,.neg
        cp '+'
        jp nz,sc_syntax
        call tk_next
        jr sc_unary
.par:   call tk_next
        call sc_expr
        ld a,')'
        jp sc_expect
.neg:   call tk_next
        ld a,(stc.lx_type)
        cp T_WORD
        jr nz,.ng
        ld a,(stc.lx_word)      ; -number: a negative constant
        cp '0'
        jr c,.ng
        cp '9'+1
        jr nc,.ng
        call sc_word
        ld hl,0
        ld de,(sc_ov)
        or a
        sbc hl,de
        ld (sc_ov),hl
        jr .ld
.ng:    ld hl,0                 ; 0 - x
        ld a,OP_LD
        call sc_emitk
        ld a,OP_SUB
        call sc_push
        call sc_unary
        jp sc_pop
.w:     call sc_word
.ld:    ld a,OP_LD
        jp sc_emitv

; sc_binop: the current token -> NC: B = level, C = op; C: not an operator
sc_binop:
        ld a,(stc.lx_type)
        ld d,a
        ld a,(stc.lx_sym)
        ld e,a
        ld a,d
        cp T_KW
        jr nz,.s
        ld a,(stc.lx_kw)
        ld e,a
.s:     ld hl,sc_ops
.l:     ld a,(hl)
        or a
        scf
        ret z
        cp d
        inc hl
        jr nz,.n
        ld a,(hl)
        cp e
        jr nz,.n
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        or a
        ret
.n:     inc hl
        inc hl
        inc hl
        jr .l

sc_ops: db T_KW,KW_OR,0,OP_OR
        db T_KW,KW_XOR,1,OP_XOR
        db T_KW,KW_AND,2,OP_AND
        db T_SYM,'&',2,OP_AND
        db T_SYM,'=',3,OP_EQ
        db T_SYM,S_NE,3,OP_NE
        db T_SYM,'<',4,OP_LT
        db T_SYM,'>',4,OP_GT
        db T_SYM,S_LE,4,OP_LE
        db T_SYM,S_GE,4,OP_GE
        db T_SYM,'+',5,OP_ADD
        db T_SYM,'-',5,OP_SUB
        db T_SYM,'*',6,OP_MUL
        db T_SYM,'/',6,OP_DIV
        db T_KW,KW_MOD,6,OP_MOD
        db 0

; ============================================================
; statements
; ============================================================

; ---- sc_stmts: statements up to END_x / ELSIF / ELSE / UNTIL / a CASE
;      label / the end
sc_stmts:
.l:     ld a,(stc.lx_type)
        or a
        ret z
        cp T_KW
        jr nz,.nk
        ld a,(stc.lx_kw)
        ld hl,sc_ends
.f:     ld b,(hl)
        inc hl
        inc b
        dec b
        jr z,.s
        cp b
        ret z
        jr .f
.nk:    cp T_SYM
        jr nz,.nw
        ld a,(stc.lx_sym)
        cp '-'
        ret z
        jr .s
.nw:    ld a,(stc.lx_word)      ; a number
        cp '0'
        jr c,.s
        cp '9'+1
        ret c
.s:     call sc_stmt
        jr .l

sc_ends: db KW_ELSIF,KW_ELSE,KW_END_IF,KW_END_CASE,KW_END_FOR
         db KW_END_WHILE,KW_UNTIL,KW_END_REPEAT,0

; ---- sc_stmt: one statement
sc_stmt:
        ld a,(stc.lx_type)
        cp T_SYM
        jr nz,.n1
        ld a,(stc.lx_sym)
        cp ';'
        jp z,tk_next            ; empty statement
        jp sc_syntax
.n1:    cp T_KW
        jr nz,.word
        ld a,(stc.lx_kw)
        cp KW_IF
        jp z,sc_if
        cp KW_CASE
        jp z,sc_case
        cp KW_FOR
        jp z,sc_for
        cp KW_WHILE
        jp z,sc_while
        cp KW_REPEAT
        jp z,sc_repeat
        cp KW_EXIT
        jp z,sc_exit
        cp KW_RETURN
        jp z,sc_return
        cp KW_VAR
        jp c,sc_syntax
        ld hl,err_sc_vfirst     ; VAR: only at the start of the POU
        jr z,.verr
        ld hl,err_sc_nyet       ; VAR_GLOBAL ...: later
.verr:  jp sc_err
.word:  call sc_word
        cp AR_FBI
        jp z,sc_fbcall
        cp AR_POU
        jp z,sc_poucall
        call sc_wrchk           ; ---- assignment
        ld hl,(sc_ov)
        push hl
        ld a,(sc_oa)
        ld b,a
        ld a,(sc_oi)
        ld c,a
        push bc
        ld a,S_ASG
        call sc_expect
        call sc_expr
        pop bc
        pop hl
        call sc_setop
        ld a,OP_ST
        call sc_emitv
        jp sc_semi

; sc_setop: B = area, C = index, HL = value -> sc_oa / sc_oi / sc_ov
sc_setop:
        ld a,b
        ld (sc_oa),a
        ld a,c
        ld (sc_oi),a
        ld (sc_ov),hl
        ret

; ---- IF c THEN ... {ELSIF c THEN ...} [ELSE ...] END_IF
sc_if:  call tk_next
        call sc_expr
        ld a,KW_THEN
        call sc_expect_kw
        ld hl,0
        ld a,OP_JMPCN
        call sc_emitj           ; HL = jump to the next branch
        ld de,0                 ; DE = chain of jumps to the end
.body:  push de
        push hl
        call sc_stmts
        pop hl
        pop de
        ld a,(stc.lx_type)
        cp T_KW
        jr nz,.err
        ld a,(stc.lx_kw)
        cp KW_ELSIF
        jr z,.elsif
        cp KW_ELSE
        jr z,.else
        cp KW_END_IF
        jr nz,.err
        call sc_patch1
        ex de,hl
        call sc_patchl
        call tk_next
        jp sc_optsemi
.elsif: call .tend
        push de
        call tk_next
        call sc_expr
        ld a,KW_THEN
        call sc_expect_kw
        ld hl,0
        ld a,OP_JMPCN
        call sc_emitj
        pop de
        jr .body
.else:  call .tend
        push de
        call tk_next
        call sc_stmts
        ld a,KW_END_IF
        call sc_expect_kw
        pop hl
        call sc_patchl
        jp sc_optsemi
.err:   ld a,KW_END_IF
        jp sc_expect_kw
.tend:  push hl                 ; JMP to the end, the open branch jump here
        ex de,hl
        ld a,OP_JMP
        call sc_emitj
        ex de,hl
        pop hl
        jp sc_patch1

; ---- WHILE c DO ... END_WHILE
sc_while:
        ld hl,(cp_pc)
        push hl                 ; top
        call tk_next
        call sc_expr
        ld a,KW_DO
        call sc_expect_kw
        ld hl,(sc_exitl)
        push hl
        ld hl,0
        ld a,OP_JMPCN
        call sc_emitj
        ld (sc_exitl),hl
        call sc_body
        ld a,KW_END_WHILE
        call sc_expect_kw
        pop de                  ; the outer EXIT chain
        pop hl                  ; top
        push de
        ld a,OP_JMP
        call sc_emitj
sc_lend:                        ; the loop's exits here, the outer chain back
        ld hl,(sc_exitl)
        call sc_patchl
        pop hl
        ld (sc_exitl),hl
        jp sc_optsemi

; sc_body: statements of a loop (EXIT allowed)
sc_body:
        ld hl,sc_loops
        inc (hl)
        call sc_stmts
        ld hl,sc_loops
        dec (hl)
        ret

; ---- REPEAT ... UNTIL c END_REPEAT
sc_repeat:
        ld hl,(cp_pc)
        push hl
        ld hl,(sc_exitl)
        push hl
        ld hl,0
        ld (sc_exitl),hl
        call tk_next
        call sc_body
        ld a,KW_UNTIL
        call sc_expect_kw
        call sc_expr
        pop de
        pop hl
        push de
        ld a,OP_JMPCN
        call sc_emitj
        ld a,KW_END_REPEAT
        call sc_expect_kw
        jr sc_lend

; ---- EXIT; RETURN;
sc_exit:
        ld a,(sc_loops)
        or a
        ld hl,err_sc_exit
        jp z,sc_err
        ld hl,(sc_exitl)
        ld a,OP_JMP
        call sc_emitj
        ld (sc_exitl),hl
        jr sc_ret1
sc_return:
        ld a,OP_RET
        call sc_emit0
sc_ret1:
        call tk_next
        jp sc_semi

; ---- FOR v := a TO b [BY k] DO ... END_FOR
;      v := a; top: LD v / GT b (LT if k < 0) / JMPC end; body;
;      LD v / ADD k / ST v / JMP top; end:
sc_for: call tk_next
        call sc_word
        call sc_wrchk
        call sc_fsave
        ld a,S_ASG
        call sc_expect
        call sc_expr
        call sc_fload
        ld a,OP_ST
        call sc_emitv
        ld a,KW_TO
        call sc_expect_kw
        call sc_mark            ; look ahead for BY k
        push hl
        push de
        push bc
        ld hl,1
        ld (sc_step),hl
.find:  ld a,(stc.lx_type)
        or a
        jr z,.nf
        cp T_KW
        jr nz,.fn
        ld a,(stc.lx_kw)
        cp KW_DO
        jr z,.nf
        cp KW_BY
        jr nz,.fn
        call tk_next
        call sc_const
        ld (sc_step),hl
        jr .nf
.fn:    call tk_next
        jr .find
.nf:    pop bc
        pop de
        pop hl
        call sc_goto
        ld hl,(cp_pc)
        ld (sc_ftop),hl
        call sc_fload           ; top: LD v / GT b (LT if k < 0)
        ld a,OP_LD
        call sc_emitv
        ld a,(sc_step+1)
        ld c,OP_GT
        bit 7,a
        jr z,.cmp
        ld c,OP_LT
.cmp:   ld a,4
        call sc_right
        ld hl,(sc_exitl)
        push hl                 ; the outer EXIT chain
        ld hl,0
        ld a,OP_JMPC
        call sc_emitj
        ld (sc_exitl),hl
        ld a,(stc.lx_type)      ; skip BY k
        cp T_KW
        jr nz,.do
        ld a,(stc.lx_kw)
        cp KW_BY
        jr nz,.do
        call tk_next
        call sc_const
.do:    ld hl,(sc_fv)           ; this loop's data over the body
        push hl
        ld hl,(sc_fval)
        push hl
        ld hl,(sc_step)
        push hl
        ld hl,(sc_ftop)
        push hl
        ld a,KW_DO
        call sc_expect_kw
        call sc_body
        ld a,KW_END_FOR
        call sc_expect_kw
        pop hl
        ld (sc_ftop),hl
        pop hl
        ld (sc_step),hl
        pop hl
        ld (sc_fval),hl
        pop hl
        ld (sc_fv),hl
        call sc_fload           ; LD v / ADD k / ST v / JMP top
        ld a,OP_LD
        call sc_emitv
        ld hl,(sc_step)
        ld a,OP_ADD
        call sc_emitk
        call sc_fload
        ld a,OP_ST
        call sc_emitv
        ld hl,(sc_ftop)
        ld a,OP_JMP
        call sc_emitj
        jp sc_lend

; sc_fsave / sc_fload: the operand sc_o* <-> the FOR variable sc_fv / sc_fval
sc_fsave:
        ld a,(sc_oa)
        ld (sc_fv),a
        ld a,(sc_oi)
        ld (sc_fv+1),a
        ld hl,(sc_ov)
        ld (sc_fval),hl
        ret
sc_fload:
        ld a,(sc_fv)
        ld b,a
        ld a,(sc_fv+1)
        ld c,a
        ld hl,(sc_fval)
        jp sc_setop

; ---- CASE e OF k[..m]{, ...}: ... ; ... [ELSE ...] END_CASE
;      per label: <e> / EQ k / JMPC body (a range: <e> / GE k / JMPCN next
;      item / <e> / LE m / JMPC body), then JMP next label; body; JMP end.
;      The selector e is compiled again for every label (sc_sel).
sc_case:
        call tk_next
        ld hl,(sc_sel)          ; (nested CASE: the outer selector kept)
        push hl
        ld hl,(sc_sel+2)
        push hl
        ld hl,(sc_sel+4)
        push hl
        call sc_mark
        ld (sc_sel),hl
        ld (sc_sel+2),de
        ld (sc_sel+4),bc
        ld hl,(cp_pc)           ; the selector checked, no code
        push hl
        ld a,1
        ld (cp_pass),a
        call sc_expr
        ld a,2
        ld (cp_pass),a
        pop hl
        ld (cp_pc),hl
        ld a,KW_OF
        call sc_expect_kw
        ld hl,0
        push hl                 ; chain of jumps to the end
.lab:   ld a,(stc.lx_type)
        cp T_KW
        jr nz,.item0
        ld a,(stc.lx_kw)
        cp KW_ELSE
        jp z,.else
        cp KW_END_CASE
        jp z,.end
        jp sc_syntax
.item0: ld hl,0
        ld (sc_match),hl
.item:  call sc_const
        ld (sc_lo),hl
        ld a,S_RNG
        call sc_issym
        jr nz,.one
        call tk_next
        call sc_const
        ld (sc_hi),hl
        call sc_gensel
        ld hl,(sc_lo)
        ld a,OP_GE
        call sc_emitk
        ld hl,0
        ld a,OP_JMPCN
        call sc_emitj
        ld (sc_skip),hl
        call sc_gensel
        ld hl,(sc_hi)
        ld a,OP_LE
        call sc_emitk
        call .jm
        ld hl,(sc_skip)
        call sc_patch1
        jr .more
.one:   call sc_gensel
        ld hl,(sc_lo)
        ld a,OP_EQ
        call sc_emitk
        call .jm
.more:  ld a,','
        call sc_issym
        jr nz,.colon
        call tk_next
        jr .item
.colon: ld a,':'
        call sc_expect
        ld hl,0
        ld a,OP_JMP
        call sc_emitj
        push hl                 ; jump to the next label
        ld hl,(sc_match)
        call sc_patchl
        call sc_stmts
        pop bc
        pop hl
        push bc
        ld a,OP_JMP
        call sc_emitj
        pop bc
        push hl
        ld h,b
        ld l,c
        call sc_patch1
        jp .lab
.jm:    ld hl,(sc_match)
        ld a,OP_JMPC
        call sc_emitj
        ld (sc_match),hl
        ret
.else:  call tk_next
        call sc_stmts
        ld a,KW_END_CASE
        call sc_expect_kw
        jr .fin
.end:   call tk_next
.fin:   pop hl
        call sc_patchl
        pop hl
        ld (sc_sel+4),hl
        pop hl
        ld (sc_sel+2),hl
        pop hl
        ld (sc_sel),hl
        jp sc_optsemi

; sc_gensel: compiles the CASE selector again (at the current position)
sc_gensel:
        call sc_mark
        ld (sc_tst),hl
        ld (sc_tst+2),de
        ld (sc_tst+4),bc
        ld hl,(sc_sel)
        ld de,(sc_sel+2)
        ld bc,(sc_sel+4)
        call sc_goto
        call sc_expr
        ld hl,(sc_tst)
        ld de,(sc_tst+2)
        ld bc,(sc_tst+4)
        jp sc_goto

; ---- FB call: INST(IN := expr, PT := expr, Q => v, ...);
;      inputs: <expr> / ST INST.m; CALFB; outputs: LD INST.m / ST v
sc_fbcall:
        ld a,(sc_oi)
        ld (sc_fbi),a
        ld hl,sc_wbuf
        ld de,sc_inst
        call put_str
        ld (sc_instd),de
        xor a
        ld (sc_nout),a
        ld a,'('
        call sc_expect
.par:   ld a,')'
        call sc_issym
        jp z,.call
        ld a,(stc.lx_type)      ; INST.member
        cp T_WORD
        jp nz,sc_syntax
        ld de,(sc_instd)
        ld a,'.'
        ld (de),a
        inc de
        ld hl,stc.lx_word
        call put_str
        xor a
        ld (de),a
        ld hl,sc_inst
        call op_parse
        jr c,.bad
        ld b,a
        and AR_MASK
        cp AR_FBM
        jr nz,.bad
        ld a,(hl)
        or a
        jr nz,.bad
        ld a,b
        ld (sc_moa),a
        call tk_next
        ld a,S_OUT
        call sc_issym
        jr z,.out
        ld a,S_ASG
        call sc_expect
        call sc_expr
        ld a,(sc_moa)
        ld b,a
        ld a,(sc_fbi)
        ld c,a
        call sc_setop
        ld a,OP_ST
        call sc_emitv
        jr .next
.out:   call tk_next            ; member => v
        call sc_word
        call sc_wrchk
        ld a,(sc_nout)
        cp 4
        ld hl,err_sc_outs
        jp nc,sc_err
        inc a
        ld (sc_nout),a
        dec a
        add a,a
        add a,a
        ld hl,sc_outs
        add a,l
        ld l,a
        jr nc,.o1
        inc h
.o1:    ld a,(sc_moa)
        ld (hl),a
        inc hl
        ld a,(sc_oa)
        ld (hl),a
        inc hl
        ld a,(sc_oi)
        ld (hl),a
        inc hl
        ld a,(sc_ov)            ; (outputs are variables: value unused)
        ld (hl),a
.next:  ld a,','
        call sc_issym
        jr nz,.cl
        call tk_next
        jp .par
.cl:    ld a,')'
        call sc_expect
        jr .emit
.bad:   ld hl,err_sc_par
        jp sc_err
.call:  call tk_next
.emit:  ld a,(sc_fbi)           ; CALFB: mode = type, arg = instance
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
        call sc_emit
        ld hl,sc_outs
.ol:    ld a,(sc_nout)
        or a
        jp z,sc_semi
        dec a
        ld (sc_nout),a
        push hl
        ld b,(hl)               ; LD INST.member
        ld a,(sc_fbi)
        ld c,a
        call sc_setop
        ld a,OP_LD
        call sc_emitv
        pop hl
        inc hl
        ld b,(hl)               ; ST v
        inc hl
        ld c,(hl)
        inc hl
        inc hl
        push hl
        ld hl,0
        call sc_setop
        ld a,OP_ST
        call sc_emitv
        pop hl
        jr .ol

; ---- POU call: NAME();
sc_poucall:
        ld a,'('
        call sc_expect
        ld a,')'
        call sc_expect
        ld a,(sc_oi)
        ld (cp_mode),a
        ld a,OP_CALL
        call cp_emit0m
        jp c,sc_errx
        jp sc_semi

err_sc_syn:   db "Syntax error",0
err_sc_char:  db "Invalid character",0
err_sc_cmt:   db "Comment not closed",0
err_sc_name:  db "Unknown name: ",0
err_sc_const: db "Constant expected",0
err_sc_deep:  db "Expression too complex",0
err_sc_exit:  db "EXIT outside a loop",0
err_sc_nyet:  db "Declarations not supported yet",0
err_sc_par:   db "Invalid parameter",0
err_sc_outs:  db "Max. 4 outputs (=>)",0
txt_sc_exp:   db " expected",0

sc_sp:    dw 0
sc_rec:   dw 0
sc_lrec:  dw 0
sc_exitl: dw 0
sc_loops: db 0
sc_pdep:  db 0
sc_oa:    db 0
sc_oi:    db 0
sc_ov:    dw 0
sc_step:  dw 0
sc_fv:    dw 0
sc_fval:  dw 0
sc_ftop:  dw 0
sc_sel:   ds 6
sc_tst:   ds 6
sc_match: dw 0
sc_lo:    dw 0
sc_hi:    dw 0
sc_skip:  dw 0
sc_fbi:   db 0
sc_moa:   db 0
sc_nout:  db 0
sc_outs:  ds 4*4
sc_instd: dw 0
sc_wbuf:  ds stc.LX_WMAX+1
sc_inst:  ds 2*stc.LX_WMAX+2

