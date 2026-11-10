; ============================================================
; undo.asm - multi-level undo / redo (bank 7, BANK_SPARE)
; ============================================================
; The project (fixed memory) and this bank are both visible here, so all
; copies are plain ldir. Layout of the bank:
;   UM_REC ..       records, oldest first (um_cend = end of record um_cur)
;   .. UM_TOP       the shadow S: a copy of the project as of the last
;                   finalize, ending at UM_TOP (start um_sbeg, length um_slen)
; A record holds one step (all changes after one key, um_arm in core) in
; both directions:
;   [size w]
;   header runs: [len b][offset w][old bytes][new bytes] ... [0]
;   bodies: [p w][mo w][mn w][old middle mo][new middle mn]
;   [size w]
; Header runs are the differing bytes of the fixed header (HDR_LEN); the
; bodies differ only between a common prefix p and a common suffix.
; A step becomes a record at the next change, undo or redo (um_fin);
; until then S holds the project from before it (um_pend = 1).
; The tape load uses UM_BAK (= UM_REC) for its copy and calls um_reset.
; ============================================================

UM_TOP  EQU IM2_JP

; ---- um_save: before a change (called by undo_save once per key);
;      keeps BC, DE, HL
um_save:
        push bc
        push de
        push hl
        ld a,(um_valid)
        or a
        jr nz,.v
        call um_scopy           ; the first change: S = the project
        ld a,1
        ld (um_valid),a
        jr .p
.v:     ld a,(um_pend)
        or a
        call nz,um_fin
        ld a,(um_cur)           ; a new change: the redo steps go
        ld (um_n),a
.p:     ld a,1
        ld (um_pend),a
        pop hl
        pop de
        pop bc
        ret

; ---- um_reset: no history (after a tape load)
um_reset:
        xor a
        ld (um_valid),a
        ld (um_pend),a
        ld (um_n),a
        ld (um_cur),a
        ld hl,UM_REC
        ld (um_cend),hl
        ret

; ---- um_scopy: S = the project
um_scopy:
        ld bc,(PROJ+P_LEN)
        ld (um_slen),bc
        ld hl,UM_TOP
        or a
        sbc hl,bc
        ld (um_sbeg),hl
        ex de,hl
        ld hl,PROJ
        ldir
        ret

; ---- um_undo: the step before the cursor back -> C = nothing to undo
um_undo:
        call um_fpend
        ret c
        ld a,(um_cur)
        or a
        scf
        ret z
        dec a
        ld (um_cur),a
        ld hl,(um_cend)         ; the record ends at um_cend
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)
        inc hl
        inc hl
        or a
        sbc hl,de
        ld (um_cend),hl
        xor a                   ; its old side
        jr um_apply

; ---- um_back: undo of a change that failed (FBD "no room"): no redo
um_back:
        call um_undo
        ld a,(um_cur)
        ld (um_n),a
        ret

; ---- um_redo: the step at the cursor again -> C = nothing to redo
um_redo:
        call um_fpend
        ret c
        ld a,(um_cur)
        ld hl,um_n
        cp (hl)
        jr c,.ok
        scf
        ret
.ok:    inc a
        ld (um_cur),a
        ld hl,(um_cend)         ; the record starts at um_cend
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
        push hl
        add hl,de
        ld (um_cend),hl
        pop hl
        ld a,1                  ; its new side
        ; fall through

; um_apply: HL = record, A = 0 old side / 1 new side -> the project
um_apply:
        ld (um_side),a
        inc hl
        inc hl
        ld (um_hdp),hl          ; header runs
.sk:    ld a,(hl)               ; skip them
        or a
        jr z,.sb
        ld c,a
        ld b,0
        inc hl
        inc hl
        inc hl
        add hl,bc
        add hl,bc
        jr .sk
.sb:    inc hl
        ld de,um_p
        ld bc,6
        ldir                    ; p, mo, mn; HL = old middle
        ld a,(um_side)
        or a
        ld de,(um_mo)
        ld bc,(um_mn)
        jr nz,.r
        ld (um_to),de           ; undo: mn bytes -> mo bytes (old)
        ld (um_from),bc
        jr .mv
.r:     add hl,de               ; redo: mo bytes -> mn bytes (new)
        ld (um_to),bc
        ld (um_from),de
.mv:    ld (um_dat),hl
        ld hl,(PROJ+P_LEN)      ; BC = tail = body - p - from
        ld de,HDR_LEN
        or a
        sbc hl,de
        ld de,(um_p)
        sbc hl,de
        ld de,(um_from)
        sbc hl,de
        ld b,h
        ld c,l
        ld hl,(um_to)
        or a
        sbc hl,de               ; to - from
        jr z,.cp
        jr c,.shr
        ld hl,POU_BODIES-1      ; grows: the tail moves up (from its end)
        ld de,(um_p)
        add hl,de
        add hl,bc
        push hl
        ld de,(um_to)
        add hl,de
        ex de,hl
        pop hl
        push de
        ld de,(um_from)
        add hl,de
        pop de
        ld a,b
        or c
        jr z,.cp
        lddr
        jr .cp
.shr:   ld hl,POU_BODIES        ; shrinks: the tail moves down
        ld de,(um_p)
        add hl,de
        push hl
        ld de,(um_to)
        add hl,de
        ex de,hl
        pop hl
        push de
        ld de,(um_from)
        add hl,de
        pop de
        call um_ldir
.cp:    ld hl,POU_BODIES        ; the middle
        ld de,(um_p)
        add hl,de
        ex de,hl
        ld hl,(um_dat)
        ld bc,(um_to)
        call um_ldir
        ld hl,(um_hdp)          ; the header runs
.h:     ld a,(hl)
        or a
        jr z,.he
        ld c,a
        ld b,0
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,PROJ
        add hl,de
        ex de,hl
        pop hl
        ld a,(um_side)
        or a
        jr z,.ho
        add hl,bc
.ho:    push bc
        ldir
        pop bc
        ld a,(um_side)
        or a
        jr nz,.h
        add hl,bc
        jr .h
.he:    call um_scopy
        or a
        ret

; um_fpend: C = no history; otherwise the pending step becomes a record
um_fpend:
        ld a,(um_valid)
        or a
        scf
        ret z
        ld a,(um_pend)
        or a
        call nz,um_fin
        or a
        ret

um_ldir:
        ld a,b
        or c
        ret z
        ldir
        ret

; ---- um_fin: the change S -> project becomes a record; S = the project
um_fin: xor a
        ld (um_pend),a
        ld de,HDR_LEN           ; body lengths
        ld hl,(um_slen)
        or a
        sbc hl,de
        ld (um_bo),hl
        ld hl,(PROJ+P_LEN)
        or a
        sbc hl,de
        ld (um_bn),hl
        ld de,(um_bo)
        or a
        sbc hl,de
        ld hl,(um_bn)
        jr c,.m                 ; min(bo, bn)
        ex de,hl
.m:     ld b,h
        ld c,l
        push bc
        ld hl,(um_sbeg)         ; the common prefix
        ld de,HDR_LEN
        add hl,de
        ld de,POU_BODIES
.pf:    ld a,b
        or c
        jr z,.pe
        ld a,(de)
        cp (hl)
        jr nz,.pe
        inc hl
        inc de
        dec bc
        jr .pf
.pe:    pop hl
        or a
        sbc hl,bc
        ld (um_p),hl
        push bc                 ; the common suffix (at most min - p)
        ld hl,(um_sbeg)
        ld de,(um_slen)
        add hl,de
        dec hl
        push hl
        ld hl,PROJ-1
        ld de,(PROJ+P_LEN)
        add hl,de
        ex de,hl
        pop hl
.sf:    ld a,b
        or c
        jr z,.se
        ld a,(de)
        cp (hl)
        jr nz,.se
        dec hl
        dec de
        dec bc
        jr .sf
.se:    pop hl
        or a
        sbc hl,bc
        ex de,hl                ; DE = suffix
        ld bc,(um_p)
        ld hl,(um_bo)
        or a
        sbc hl,de
        sbc hl,bc
        ld (um_mo),hl
        ld hl,(um_bn)
        or a
        sbc hl,de
        sbc hl,bc
        ld (um_mn),hl
        ld hl,(um_slen)         ; the limit: below the old and the new S
        ld de,(PROJ+P_LEN)
        or a
        sbc hl,de
        jr c,.lp
        ld de,(um_slen)
.lp:    ld hl,UM_TOP
        or a
        sbc hl,de
        ld (um_lim),hl
        xor a                   ; the header runs: size only
        call um_hdr
        ld hl,(um_mo)           ; nothing changed: no record
        ld de,(um_mn)
        ld a,h
        or l
        or d
        or e
        jr nz,.ch
        ld hl,(um_hsz)
        dec hl
        ld a,h
        or l
        ret z
.ch:    ld hl,(um_hsz)          ; the size of the record
        ld de,10
        add hl,de
        ld de,(um_mo)
        add hl,de
        ld de,(um_mn)
        add hl,de
        ld (um_rsz),hl
        ld (um_need),hl
        ld hl,UM_REC
        ld (um_base),hl
.fit:   ld a,(um_n)             ; room for it (n = cur here); the records
        inc a                   ; below um_base are being dropped
        jr z,.drop
        ld hl,(um_cend)
        ld de,(um_base)
        or a
        sbc hl,de
        ld de,UM_REC
        add hl,de
        ld de,(um_need)
        add hl,de
        jr c,.drop
        ex de,hl
        ld hl,(um_lim)
        or a
        sbc hl,de
        jr nc,.mv
.drop:  ld a,(um_n)             ; the oldest record goes
        or a
        jr z,.last
        dec a
        ld (um_n),a
        ld (um_cur),a
        ld hl,(um_base)
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
        add hl,de
        ld (um_base),hl
        ld hl,(um_rsz)          ; from now on 2 KB more, so that it is not
        ld de,2048              ; needed again at the next step
        add hl,de
        ld (um_need),hl
        jr .fit
.last:  ld hl,UM_REC            ; none left: without the margin
        ld (um_cend),hl
        ld (um_base),hl
        ld hl,(um_need)
        ld de,(um_rsz)
        or a
        sbc hl,de
        jp z,um_scopy           ; (too big even alone: no record)
        ld (um_need),de
        jr .fit
.mv:    ld hl,(um_cend)         ; the dropped records go (one move)
        ld de,(um_base)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        ld de,UM_REC
        call um_ldir
        ld (um_cend),de
.wr:    ld hl,(um_cend)         ; write it
        ld de,(um_rsz)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (um_wp),hl
        ld a,1
        call um_hdr
        ld de,(um_wp)
        ld hl,um_p
        ld bc,6
        ldir
        ld hl,(um_sbeg)         ; old middle
        ld bc,HDR_LEN
        add hl,bc
        ld bc,(um_p)
        add hl,bc
        ld bc,(um_mo)
        call um_ldir
        ld hl,POU_BODIES        ; new middle
        ld bc,(um_p)
        add hl,bc
        ld bc,(um_mn)
        call um_ldir
        ld hl,(um_rsz)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (um_cend),hl
        ld hl,um_n
        inc (hl)
        ld hl,um_cur
        inc (hl)
        jp um_scopy

; um_hdr: the header runs of S -> project; A = 0: only their size
;      (um_hsz), 1: also written at um_wp (moved on)
um_hdr: ld (um_wr),a
        ld hl,1                 ; (the terminator)
        ld (um_hsz),hl
        dec hl                  ; HL = offset
.l:     ld de,HDR_LEN
        or a
        sbc hl,de
        add hl,de
        jp nc,.end
        call .cmp
        jr nz,.run
        inc hl
        jr .l
.run:   ld (um_rs),hl
        ld (um_rl),hl
.r:     inc hl
        ld de,HDR_LEN
        or a
        sbc hl,de
        add hl,de
        jr nc,.emit
        push hl
        ld de,(um_rs)
        or a
        sbc hl,de
        ld a,l
        pop hl
        cp 250
        jr nc,.emit
        call .cmp
        jr z,.same
        ld (um_rl),hl
        jr .r
.same:  push hl
        ld de,(um_rl)
        or a
        sbc hl,de
        ld a,l
        pop hl
        cp 4                    ; a gap of 4 equal bytes ends the run
        jr c,.r
.emit:  ld hl,(um_rl)
        ld de,(um_rs)
        or a
        sbc hl,de
        inc l
        ld a,l
        ld (um_len),a
        ld e,a
        ld d,0
        ld hl,(um_hsz)
        add hl,de
        add hl,de
        inc hl
        inc hl
        inc hl
        ld (um_hsz),hl
        ld a,(um_wr)
        or a
        jr z,.nx
        ld hl,(um_wp)
        ld a,(um_len)
        ld (hl),a
        inc hl
        ld de,(um_rs)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ex de,hl                ; DE = write pointer
        ld hl,(um_sbeg)
        ld bc,(um_rs)
        add hl,bc
        ld c,a
        ld b,0
        ldir
        ld hl,PROJ
        ld bc,(um_rs)
        add hl,bc
        ld c,a
        ld b,0
        ldir
        ld (um_wp),de
.nx:    ld hl,(um_rl)
        inc hl
        jp .l
.end:   ld a,(um_wr)
        or a
        ret z
        ld hl,(um_wp)
        ld (hl),0
        inc hl
        ld (um_wp),hl
        ret
.cmp:   push hl                 ; Z = the same byte at offset HL
        ld de,(um_sbeg)
        add hl,de
        ld a,(hl)
        pop hl
        push hl
        ld de,PROJ
        add hl,de
        cp (hl)
        pop hl
        ret

um_valid: db 0                  ; S holds a project
um_pend:  db 0                  ; a change since S was taken
um_n:     db 0                  ; records
um_cur:   db 0                  ; records before the cursor (undo)
um_cend:  dw UM_REC             ; the end of record um_cur - 1
um_slen:  dw 0
um_sbeg:  dw 0
um_p:     dw 0                  ; (um_p, um_mo, um_mn in this order)
um_mo:    dw 0
um_mn:    dw 0
um_bo:    dw 0
um_bn:    dw 0
um_lim:   dw 0
um_hsz:   dw 0
um_rsz:   dw 0
um_need:  dw 0
um_base:  dw 0
um_wp:    dw 0
um_rs:    dw 0
um_rl:    dw 0
um_hdp:   dw 0
um_dat:   dw 0
um_to:    dw 0
um_from:  dw 0
um_wr:    db 0
um_len:   db 0
um_side:  db 0

UM_REC:
UM_BAK  EQU UM_REC              ; the tape load's copy of the project
        ASSERT UM_REC + PROJ_END-PROJ <= UM_TOP
