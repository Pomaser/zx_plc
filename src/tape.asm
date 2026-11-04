; ============================================================
; tape.asm - saving the project to tape (EDIT bank)
; ============================================================
; A standard Spectrum tape file: header block (flag 0x00, type 3 = CODE,
; name, length, start 0x9000) and data block (flag 0xFF) with the project
; memory PROJ..PROJ+P_LEN. The saving routine is a copy of the ROM
; SA-BYTES (same timing) that returns on BREAK instead of reporting an
; error; it runs in bank 0, which is not contended.

; ---- tape_save: File > Save
tape_save:
        ld hl,txt_tp_nameq      ; tape name
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,tp_name
        ld de,0x0A00            ; max 10 chars, case kept
        call ui_input
        push af
        call win_close
        pop af
        ret c
        ld a,(tp_name)
        or a
        ret z
        ld hl,txt_tp_start      ; "Start tape, then press any key"
        call popup_open
        call kb_wait
        push af
        call win_close
        pop af
        cp K_BREAK
        ret z
        cp K_EDIT
        ret z
        ; header: type, name (space padded), length, start, 32768
        ld hl,tp_hdr+1
        ld b,10
        ld a,' '
.sp:    ld (hl),a
        inc hl
        djnz .sp
        ld hl,tp_name
        ld de,tp_hdr+1
        call put_str
        ld hl,(PROJ+P_LEN)
        ld (tp_hdr+11),hl
        ld ix,tp_hdr
        ld de,17
        xor a
        call tp_sa_bytes
        jr nc,.brk
        ei                      ; one second gap between the blocks
        ld b,50
.gap:   halt
        djnz .gap
        ld ix,PROJ
        ld de,(PROJ+P_LEN)
        ld a,0xFF
        call tp_sa_bytes
        jr nc,.brk
        call .end
        ld hl,txt_tp_ok
        jp msg_box
.brk:   call .end
        ld hl,txt_tp_brk
        jp ui_error
.end:   ld a,BORDER
        out (0xFE),a
        ei
        jp kb_flush

; ---- tp_sa_bytes: IX = start, DE = length, A = flag byte -> C = saved,
;      NC = BREAK (SPACE). Interrupts are left disabled.
tp_sa_bytes:
        ld hl,0x1F80            ; header: long leader
        bit 7,a
        jr z,.flag
        ld hl,0x0C98
.flag:  ex af,af'
        inc de
        dec ix
        di
        ld a,2
        ld b,a
.leader:
        djnz .leader
        out (0xFE),a
        xor 0x0F
        ld c,a                  ; BREAK also during the leader: +35 T per
        ld a,0x7F               ; pulse, compensated by 3 loops less (-39 T)
        in a,(0xFE)
        rra
        ld a,c
        ret nc
        ld b,0xA1
        dec l
        jr nz,.leader
        dec b
        dec h
        jp p,.leader
        ld b,0x2F
.sync1: djnz .sync1
        out (0xFE),a
        ld a,0x0D
        ld b,0x37
.sync2: djnz .sync2
        out (0xFE),a
        ld bc,0x3B0E
        ex af,af'
        ld l,a
        jp .start
.loop:  ld a,d
        or e
        jr z,.parity
        ld l,(ix+0)
.loopp: ld a,h
        xor l
.start: ld h,a
        ld a,1
        scf
        jp .bits8
.parity:
        ld l,h
        jr .loopp
.bit2:  ld a,c
        bit 7,b
.bit1:  djnz .bit1
        jr nc,.out
        ld b,0x42
.set:   djnz .set
.out:   out (0xFE),a
        ld b,0x3E
        jr nz,.bit2
        dec b
        xor a
        inc a
.bits8: rl l
        jp nz,.bit1
        dec de
        inc ix
        ld b,0x31
        ld a,0x7F
        in a,(0xFE)
        rra
        ret nc                  ; SPACE: break
        ld a,d
        inc a
        jp nz,.loop
        ld b,0x3B
.delay: djnz .delay
        scf
        ret

tp_hdr:  db 3                   ; CODE
         ds 10                  ; name
         dw 0                   ; length
         dw PROJ                ; start address
         dw 32768
tp_name: db "project",0,0,0,0

txt_tp_nameq: db "Save project as (tape name):",0," ",0," ",0,0
txt_tp_start: db "Start the tape recorder,",0,"then press any key.",0,"(BREAK cancels)",0,0
txt_tp_ok:    db "Project saved.",0,0
txt_tp_brk:   db "Saving interrupted",0
