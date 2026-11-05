; ============================================================
; tape.asm - saving / loading the project to / from tape (EDIT bank)
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

; ---- tape_load: File > Load -> A = CMD_POU_MANAGE (NZ) when loaded, else 0
;      The project is copied to BANK_SPARE first and restored when the
;      loading fails or is interrupted.
tape_load:
        ld hl,txt_new_q         ; "Discard current project?"
        call ui_confirm
        jr z,.go
        xor a
        ret
.go:    ld hl,txt_tp_play
        call popup_open
        ld a,BANK_SPARE         ; keep a copy of the project
        ld hl,PROJ
        ld de,BANKED
        ld bc,PROJ_END-PROJ
        call bank_copy
        xor a                   ; (the undo copy is gone)
        ld (um_valid),a
.hdr:   ld ix,tp_lhdr           ; wait for a header of a project file
        ld de,17
        xor a
        scf
        call tp_ld_bytes
        jr c,.got
        call tp_space
        jp c,.brk
        jr .hdr
.got:   ld a,(tp_lhdr)          ; CODE, start 0x9000, fits the project area
        cp 3
        jr nz,.hdr
        ld hl,(tp_lhdr+13)
        ld de,PROJ
        or a
        sbc hl,de
        jr nz,.hdr
        ld hl,(tp_lhdr+11)
        ld de,HDR_LEN
        or a
        sbc hl,de
        jr c,.hdr
        ld hl,(tp_lhdr+11)
        ld de,PROJ_END-PROJ+1
        or a
        sbc hl,de
        jr nc,.hdr
        ld ix,PROJ              ; data block
        ld de,(tp_lhdr+11)
        ld a,0xFF
        scf
        call tp_ld_bytes
        jr nc,.err
        ld hl,PROJ              ; a ZX-PLC project of that length?
        ld de,proj_sig
        ld b,5
.sig:   ld a,(de)
        cp (hl)
        jr nz,.bad
        inc hl
        inc de
        djnz .sig
        ld hl,(PROJ+P_LEN)
        ld de,(tp_lhdr+11)
        or a
        sbc hl,de
        jr nz,.bad
        call .end
        ld hl,tp_lhdr+1         ; "Project loaded:" + name
        ld de,tp_lname
        ld bc,10
        ldir
        xor a
        ld (cur_pou),a
        ld hl,txt_tp_loaded
        call msg_box
        ld a,CMD_POU_MANAGE
        or a
        ret
.bad:   ld hl,err_tp_bad
        jr .rest
.err:   call tp_space
        jr c,.brk
        ld hl,err_tp_load
        jr .rest
.brk:   ld hl,err_tp_brk
.rest:  push hl                 ; the old project back
        ld a,BANK_SPARE
        ld hl,BANKED
        ld de,PROJ
        ld bc,PROJ_END-PROJ
        call bank_copy
        call .end
        pop hl
        call ui_error
        xor a
        ret
.end:   ld a,BORDER
        out (0xFE),a
        ei
        call win_close
        jp kb_flush

; tp_space: C if SPACE is held
tp_space:
        ld a,0x7F
        in a,(0xFE)
        rra
        ccf
        ret

; ---- tp_ld_bytes: IX = start, DE = length, A = flag, CF set (load)
;      -> C = loaded, NC = error or BREAK. A copy of the ROM LD-BYTES
;      (same timing) without the error report; interrupts left disabled.
tp_ld_bytes:
        inc d
        ex af,af'
        dec d
        di
        ld a,0x0F
        out (0xFE),a
        in a,(0xFE)
        rra
        and 0x20
        or 0x02
        ld c,a
        cp a
.break: ret nz
.start: call tp_edge1
        jr nc,.break
        ld hl,0x0415
.wait:  djnz .wait
        dec hl
        ld a,h
        or l
        jr nz,.wait
        call tp_edge2
        jr nc,.break
.leader:
        ld b,0x9C
        call tp_edge2
        jr nc,.break
        ld a,0xC6
        cp b
        jr nc,.start
        inc h
        jr nz,.leader
.sync:  ld b,0xC9
        call tp_edge1
        jr nc,.break
        ld a,b
        cp 0xD4
        jr nc,.sync
        call tp_edge1
        ret nc
        ld a,c
        xor 0x03
        ld c,a
        ld h,0
        ld b,0xB0
        jr .marker
.loop:  ex af,af'
        jr nz,.flag
        jr nc,.verify
        ld (ix+0),l
        jr .next
.flag:  rl c
        xor l
        ret nz
        ld a,c
        rra
        ld c,a
        inc de
        jr .dec
.verify:
        ld a,(ix+0)
        xor l
        ret nz
.next:  inc ix
.dec:   dec de
        ex af,af'
        ld b,0xB2
.marker:
        ld l,1
.bits8: call tp_edge2
        ret nc
        ld a,0xCB
        cp b
        rl l
        ld b,0xB0
        jp nc,.bits8
        ld a,h
        xor l
        ld h,a
        ld a,d
        or e
        jr nz,.loop
        ld a,h
        cp 1
        ret

tp_edge2:
        call tp_edge1
        ret nc
tp_edge1:
        ld a,0x16
.delay: dec a
        jr nz,.delay
        and a
.sample:
        inc b
        ret z
        ld a,0x7F
        in a,(0xFE)
        rra
        ret nc
        xor c
        and 0x20
        jr z,.sample
        ld a,c
        cpl
        ld c,a
        and 0x07
        or 0x08
        out (0xFE),a
        scf
        ret

tp_lhdr:  ds 17                 ; header read from the tape

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
txt_tp_play:  db "Start the tape player.",0,"Searching for a project...",0,"(BREAK cancels)",0,0
txt_tp_loaded: db "Project loaded:",0
tp_lname:     ds 10
              db 0,0
err_tp_load:  db "Tape loading error",0
err_tp_bad:   db "Not a ZX-PLC project",0
err_tp_brk:   db "Loading interrupted",0
