; ============================================================
; bank.asm - 128K memory paging (core)
; ============================================================

; ---- bank_set: A = bank -> paged in at 0xC000 (keeps all but AF)
bank_set:
        ld (cur_bank),a
        push bc
        or BANK_ROM48
        ld bc,0x7FFD
        out (c),a
        pop bc
        ret

; ---- bcall_: called by the BCALL macro, followed by "dw target, db bank".
;      Pages the bank, calls the target with AF, BC, DE, HL as given,
;      restores the caller's bank and returns AF, BC, DE, HL of the target.
bcall_:
        ld (bt_hl),hl
        push af
        pop hl
        ld (bt_af),hl
        pop hl                  ; inline data
        ld a,(hl)
        ld (bt_jp+1),a
        inc hl
        ld a,(hl)
        ld (bt_jp+2),a
        inc hl
        ld a,(hl)               ; target bank
        inc hl
        push hl                 ; return address
        ld hl,(cur_bank)        ; L = caller's bank
        push hl
        call bank_set
        ld hl,(bt_af)
        push hl
        pop af
        ld hl,(bt_hl)
        call bt_jp
        ld (bt_hl),hl
        push af
        pop hl
        ex (sp),hl              ; result AF on the stack, L = caller's bank
        ld a,l
        call bank_set
        pop af
        ld hl,(bt_hl)
        ret
bt_jp:  jp 0

; ---- rt_byte: HL = address of PLC data -> A = its byte; addresses from
;      0xC000 (the globals / ST locals at LV_BASE) are read in the RUN bank
;      (keeps BC, DE, HL)
rt_byte:
        ld a,h
        cp 0xC0
        jr nc,.r
        ld a,(hl)
        ret
.r:     push bc
        ld a,(cur_bank)
        ld b,a
        ld a,BANK_RUN
        call bank_set
        ld c,(hl)
        ld a,b
        call bank_set
        ld a,c
        pop bc
        ret

; ---- data_in / data_out: page the DATA bank in and back (keep all registers)
data_in:
        push af
        ld a,(cur_bank)
        ld (data_ob),a
        ld a,BANK_DATA
        call bank_set
        pop af
        ret
data_out:
        push af
        ld a,(data_ob)
        call bank_set
        pop af
        ret

cur_bank: db BANK_EDIT, 0      ; (read as a word by bcall_)
data_ob:  db 0
bt_hl:    dw 0
bt_af:    dw 0
