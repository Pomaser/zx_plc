; ============================================================
; shared.asm - code and data used by more than one memory bank
; (lives in the fixed core memory)
; ============================================================

; ---- from il_comp.asm
; ---- cp_operand_rec: HL = binary operand -> NC: cp_mode/cp_arg/cp_arg3, HL past it
cp_operand_rec:
        ld a,(hl)
        inc hl
        ld b,a
        and AR_MASK
        cp AR_K16
        jr z,.val
        cp AR_KT
        jr z,.val
        ld c,(hl)
        inc hl
        ld de,0
        jr .go
.val:   ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,0
.go:    ld (cp_ohl),hl
        ld a,b
        jr cp_operand_core

cp_badcall:
        ld hl,err_il_call
cp_fail:
        ld (il_err),hl
        scf
        ret

; ---- cp_operand: HL = operand text -> NC: cp_mode/cp_arg/cp_arg3, HL past it
cp_operand:
        call op_parse
        jr c,cp_operand_core.bad
        ld (cp_ohl),hl
        jr cp_operand_core
; cp_operand_av: A = area, C = index, DE = value (no text)
cp_operand_av:
        ld hl,0
        ld (cp_ohl),hl
cp_operand_core:
        push af
        xor a
        ld (cp_istime),a
        pop af
        ld (cp_arg),de
        ld (cp_oarea),a
        ld a,c
        ld (cp_oidx),a
        xor a
        ld (cp_arg3),a
        ld a,(cp_oarea)
        and AR_MASK
        cp AR_SM
        jr z,.smb
        cp AR_I
        jr z,.i
        cp AR_Q
        jr z,.q
        cp AR_M
        jr z,.m
        cp AR_SX
        jr z,.sx
        cp AR_MW
        jr z,.mw
        cp AR_KB
        jr z,.kb
        cp AR_K16
        jr z,.k
        cp AR_KT
        jr z,.k
        cp AR_FBM
        jr z,.fbm
.bad:   ld hl,err_il_op
        jp cp_fail
.i:     ld bc,RT_I              ; byte idx/8, bit idx&7
        jr .mbit
.q:     ld bc,RT_Q
        jr .mbit
.bitn:  ld (cp_arg),hl
        ld e,a
        ld d,0
        ld hl,bit_masks
        add hl,de
        ld a,(hl)
        ld (cp_arg3),a
        ld a,VM_MB
        jp .done
.sx:    ld bc,RT_STEP           ; step flags: byte idx/8, bit idx&7
        jr .mbit
.smb:   ld bc,RT_SM             ; system flags (read only)
        jr .mbit
.m:     ld bc,RT_M
.mbit:  ld a,(cp_oidx)
        ld e,a
        rrca
        rrca
        rrca
        and 7
        ld l,a
        ld h,0
        add hl,bc
        ld a,e
        and 7
        jr .bitn
.mw:    ld a,(cp_oidx)
        add a,a
        ld l,a
        ld h,0
        ld de,RT_MW
        add hl,de
        ld (cp_arg),hl
        ld a,VM_MW
        jr .done
.kb:    ld a,(cp_oidx)
        ld l,a
        ld h,0
        ld (cp_arg),hl
        ld a,VM_MIB
        jr .done
.k:     ld a,VM_MII
        jr .done
.fbm:   ; instance address
        ld a,(cp_oidx)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,RT_FB
        add hl,de
        push hl
        ; descriptor fb_mdesc[type*5 + member]
        ld a,(cp_oidx)
        rrca
        rrca
        and 0x3F
        ld e,a
        add a,a
        add a,a
        add a,e
        ld e,a
        ld a,(cp_oarea)
        rrca
        rrca
        rrca
        rrca
        and 7
        add a,e
        ld e,a
        ld d,0
        ld hl,fb_mdesc
        add hl,de
        ld a,(hl)
        pop hl
        bit 7,a
        jp z,.bitn
        and 0x7F
        ld e,a
        ld d,0
        add hl,de
        ld (cp_arg),hl
        ld a,(cp_oidx)          ; PT / ET of TON, TOF, TP are TIME values
        cp FBT_CTU*FB_PER_TYPE
        jr nc,.nt
        ld a,1
        ld (cp_istime),a
.nt:    ld a,VM_MW
.done:  ld (cp_mode),a
        ld hl,(cp_ohl)
        or a
        ret


; ---- from il_comp.asm
err_cp_dup:   db "Duplicate label",0
err_cp_lbls:  db "Too many labels",0
err_cp_nolbl: db "Unknown label",0
err_cp_big:   db "Program too large",0

; ---- from il_comp.asm
cp_pc:    dw 0
cp_start: dw 0
cp_slot:  db 0
cp_pass:  db 0
cp_nlbl:  db 0
cp_line:  dw 0
cp_rec:   dw 0
cp_end:   dw 0
cp_kind:  db 0
cp_op:    db 0
cp_opnd:  dw 0
cp_empty: db 0
cp_mode:  db 0
cp_arg:   dw 0
cp_arg3:  db 0
cp_dmode: db 0
cp_darg:  dw 0
cp_darg3: db 0
cp_ohl:   dw 0
cp_oarea: db 0
cp_oidx:  db 0
cp_istime: db 0           ; 1 = last operand is a TIME value
cp_after: dw 0
cp_carea: db 0
cp_cidx:  db 0
cp_npar:  db 0
cp_tlen:  db 0
cp_tend:  dw 0
cp_opb:   db 0
cp_class: db 0
cp_csize: db 0
cp_mptr:  dw 0
cp_name8: ds 8

; ---- from il_comp.asm
cp_mbuf:  ds 16

; ---- from vm.asm
; FB member descriptors: per type 5 members; bit 7 = word at offset, else bit number
fb_mdesc:
        db 0, 0x82, 1, 0x84, 0          ; TON  IN PT Q ET
        db 0, 0x82, 1, 0x84, 0          ; TOF
        db 0, 0x82, 1, 0x84, 0          ; TP
        db 0, 1, 0x82, 2, 0x84          ; CTU  CU R PV Q CV
        db 0, 1, 0x82, 2, 0x84          ; CTD  CD LD PV Q CV
        db 0, 1, 0, 0, 0                ; R_TRIG CLK Q
        db 0, 1, 0, 0, 0                ; F_TRIG
        db 0, 1, 2, 0, 0                ; SR   S1 R Q1
        db 0, 1, 2, 0, 0                ; RS   S R1 Q1


; ---- from vm.asm
bit_masks: db 1,2,4,8,16,32,64,128

; ---- from vm.asm
err_vm_wd:    db "Watchdog: scan too long",0
err_vm_paren: db "Parenthesis error",0
err_vm_depth: db "Call depth > 8",0

; ---- from vm.asm
vm_err:   dw 0
vm_dt:    dw 1

; ---- from sim.asm
sim_pending: db 0

; ---- from pou.asm
pou_pending: db 0

; ---- from pou.asm
err_bad_name:  db "Invalid name",0
err_reserved:  db "Reserved name",0
err_name_used: db "Name already used",0

; ---- from il_edit.asm
err_il_mem:   db "Out of memory",0

; ---- from ld_edit.asm
; ---- ld_nrows: A = number of rows (an empty body has one)
ld_nrows:
        ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        ld a,1
        ret z
        ld a,(hl)
        ret

; ---- ld_hdr: makes sure the body has its header byte; C = out of memory
ld_hdr: ld a,(cur_pou)
        call pou_body
        ld a,b
        or c
        ret nz
        ld de,0
        ld bc,1
        ld a,(cur_pou)
        call pou_insert
        ret c
        ld (hl),1
        or a
        ret

; ---- ld_isbox: A = type -> Z if it is a timer box (keeps BC, DE, HL)
ld_isbox:
        and LT_MASK
        cp LT_TON
        ret z
        cp LT_TOF
        ret z
        cp LT_TP
        ret

; ---- ld_tlen: A = type -> A = record length (keeps BC, DE, HL)
ld_tlen:
        call ld_isbox
        ld a,7
        ret z
        ld a,5
        ret

; ---- ld_rlen: HL = record -> A = its length (keeps BC, DE, HL)
ld_rlen:
        push hl
        inc hl
        inc hl
        ld a,(hl)
        and LT_MASK
        cp LT_CMT
        jr nz,.t
        inc hl
        ld a,(hl)
        add a,4
        pop hl
        ret
.t:     pop hl
        jp ld_tlen

; ---- ld_skip: HL = record -> next record (keeps BC)
ld_skip:
        call ld_rlen
        ld e,a
        ld d,0
        add hl,de
        ret

; ---- ld_find: D = row, E = pos -> NC: HL = record; C: HL = insertion point
ld_find:
        ld (lf_pos),de
        ld a,(cur_pou)
        call pou_body
        push hl
        add hl,bc
        ld (lf_end),hl
        pop hl
        ld a,b
        or c
        scf
        ret z
        inc hl                  ; header
.l:     push hl
        ld de,(lf_end)
        or a
        sbc hl,de
        pop hl
        jr nc,.nf
        ld a,(lf_row)
        cp (hl)
        jr c,.nf
        jr nz,.n
        inc hl
        ld a,(lf_pos)
        cp (hl)
        dec hl
        jr c,.nf
        jr z,.f
.n:     call ld_skip
        jr .l
.f:     or a
        ret
.nf:    scf
        ret

; ---- ld_get: D = row, E = pos -> A = type (0 = nothing), B = area, C = index
;      (keeps DE)
ld_get: push de
        call ld_find
        pop de
        jr c,.none
        inc hl
        inc hl
        ld a,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        push af
        call ld_isbox
        jr nz,.nb
        push de
        ld e,(hl)               ; PT of a timer box
        inc hl
        ld d,(hl)
        ld (ld_gpt),de
        pop de
.nb:    pop af
        ret
.none:  xor a
        ld b,a
        ld c,a
        ret


; ---- from ld_edit.asm
lf_pos:   db 0              ; ld_find key (must be followed by lf_row)
lf_row:   db 0
lf_end:   dw 0

; ---- from ld_edit.asm
ld_gpt:   dw 0              ; PT of the last ld_get box

; ---- from ld_comp.asm
err_lc_rows:  db "Rung longer than 16 rows",0
err_lc_edges: db "Too many P/N contacts",0
; ---- from il_edit.asm / ld_edit.asm (also set by the tests)
sp_m:      dw 0
sp_o:      dw 0
sp_c:      dw 0
ld_ppt:   dw 0              ; PT for ld_put
; ---- from ld_edit.asm (also used by the FBD editor in its own bank)
ld_row:   db 0
ld_pos:   db 0
ld_top:   db 0
ld_vbase: db 1
ld_vn:    db 11
ld_ar:    dw 0              ; area, index of the element operand
ld_kind:  db 0
ld_cbuf:  ds 40
xr_jf:    db 0              ; cross reference jump: the editor opens at
xr_jl:    dw 0              ;   line / row xr_jl, position xr_jp
xr_jp:    db 0
tl_cmd:   db 0              ; tl_run: CMD_XREF or CMD_WADD
