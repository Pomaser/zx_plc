; ============================================================
; project.asm - project format and POU management
; ============================================================
; Project (PROJ):
;   +0  "ZXPLC"  +5 version  +6 POU count  +8 project length (word)
;   +16 table of 8 POU slots + hidden slot 8 (symbol table), 32 B each
;       (name 8, language, flags, body length, comment 20)
;   +304 bodies in slot order (a free slot has length 0)
; A slot is a stable POU identifier (call references = slot number).
; ============================================================

; ---- proj_new: A = language of MAIN
proj_new:
        push af
        ld hl,PROJ
        ld bc,HDR_LEN
        xor a
        call memset
        ld hl,proj_sig
        ld de,PROJ
        ld bc,5
        ldir
        ld a,PROJ_VER
        ld (PROJ+P_VER),a
        ld a,1
        ld (PROJ+P_NPOU),a
        ld hl,HDR_LEN
        ld (PROJ+P_LEN),hl
        ld hl,name_main
        ld de,POU_TAB+PE_NAME
        ld bc,8
        ldir
        pop af
        ld (POU_TAB+PE_LANG),a
        xor a
        ld (cur_pou),a
        ret

; ---- proj_load_demo: copies the demo project from the DEMO bank
proj_load_demo:
        ld a,(cur_bank)
        push af
        ld a,BANK_DEMO
        call bank_set
        ld hl,demo_img
        ld de,PROJ
        ld bc,DEMO_LEN
        ld a,b
        or c
        jr z,.e                 ; (no image in the builder build)
        ldir
.e:     pop af
        call bank_set
        xor a
        ld (cur_pou),a
        ret

proj_sig:  db "ZXPLC"
name_main: db "MAIN    "

; ---- pou_entry: A = slot -> HL = table entry (destroys A)
pou_entry:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; *32
        push de
        ld de,POU_TAB
        add hl,de
        pop de
        ret

; ---- pou_used: A = slot -> NZ if the slot is used (preserves A)
pou_used:
        push hl
        push af
        call pou_entry
        pop af
        inc (hl)
        dec (hl)
        pop hl
        ret

; ---- pou_lang: A = slot -> A = language
pou_lang:
        push hl
        call pou_entry
        ld a,PE_LANG
        add a,l
        ld l,a
        ld a,(hl)
        pop hl
        ret

; ---- pou_body: A = slot -> HL = body start, BC = length
pou_body:
        push de
        push ix
        ld ix,POU_TAB
        ld hl,POU_BODIES
        ld de,POU_ESIZE
        or a
        jr z,.done
        ld b,a
.lp:    ld a,(ix+PE_LEN)
        add a,l
        ld l,a
        ld a,(ix+PE_LEN+1)
        adc a,h
        ld h,a
        add ix,de
        djnz .lp
.done:  ld c,(ix+PE_LEN)
        ld b,(ix+PE_LEN+1)
        pop ix
        pop de
        ret

; ---- proj_end: HL = address past the end of project data (preserves BC, DE)
proj_end:
        push de
        ld hl,(PROJ+P_LEN)
        ld de,PROJ
        add hl,de
        pop de
        ret

; ---- proj_free: HL = free bytes
proj_free:
        call proj_end
        ex de,hl
        ld hl,PROJ_END
        or a
        sbc hl,de
        ret

; ---- pou_add_len: A = slot, BC = length delta (signed) -> updates PE_LEN and P_LEN
pou_add_len:
        call pou_entry
        ld de,PE_LEN
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        add hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        ld hl,(PROJ+P_LEN)
        add hl,bc
        ld (PROJ+P_LEN),hl
        ret

; ---- pou_insert: A = slot, DE = offset in body, BC = byte count
;      creates a gap, HL = gap address; C = out of memory
pou_insert:
        ld (pt_slot),a
        ld (pt_off),de
        ld (pt_cnt),bc
        call proj_free
        ld bc,(pt_cnt)
        or a
        sbc hl,bc
        ret c
        ld a,(pt_slot)
        call pou_body
        ld de,(pt_off)
        add hl,de
        ld (pt_addr),hl
        ex de,hl            ; DE = insertion point
        call proj_end
        or a
        sbc hl,de           ; HL = bytes to move
        ld b,h
        ld c,l
        ld hl,(pt_cnt)
        add hl,de
        ex de,hl            ; DE = dest, HL = source
        call memmove
        ld a,(pt_slot)
        ld bc,(pt_cnt)
        call pou_add_len
        ld hl,(pt_addr)
        or a
        ret

; ---- pou_delete: A = slot, DE = offset in body, BC = number of bytes to remove
pou_delete:
        ld (pt_slot),a
        ld (pt_off),de
        ld (pt_cnt),bc
        ld a,b
        or c
        ret z
        ld a,(pt_slot)
        call pou_body
        ld de,(pt_off)
        add hl,de
        ld (pt_addr),hl     ; dest
        ld de,(pt_cnt)
        add hl,de           ; source = dest + cnt
        push hl
        ex de,hl
        call proj_end
        or a
        sbc hl,de           ; count = end - source
        ld b,h
        ld c,l
        pop hl
        ld de,(pt_addr)
        call memmove
        ld hl,(pt_cnt)
        call neg_hl
        ld b,h
        ld c,l
        ld a,(pt_slot)
        jp pou_add_len

pt_slot: db 0
pt_off:  dw 0
pt_cnt:  dw 0
pt_addr: dw 0

; ---- pou_add: HL = name (8 chars), A = language -> A = slot, C = full
pou_add:
        ld (pt_lang),a
        ld (pt_name),hl
        ld b,0
.find:  ld a,b
        call pou_used
        jr z,.got
        inc b
        ld a,b
        cp MAX_POU
        jr c,.find
        scf
        ret
.got:   ld a,b
        push af
        call pou_entry
        ex de,hl
        ld hl,(pt_name)
        ld bc,8
        ldir                ; name
        ld a,(pt_lang)
        ld (de),a
        ld hl,PROJ+P_NPOU
        inc (hl)
        pop af
        or a
        ret

pt_lang: db 0
pt_name: dw 0

; ---- pou_remove: A = slot (>0) - deletes body and entry
pou_remove:
        push af
        call pou_body       ; BC = length
        pop af
        push af
        ld de,0
        call pou_delete
        pop af
        call pou_entry
        ld bc,POU_ESIZE
        xor a
        call memset
        ld hl,PROJ+P_NPOU
        dec (hl)
        ret

; ---- pou_find: HL = name (8 chars) -> A = slot, NC = found
pou_find:
        ld b,0
.lp:    ld a,b
        call pou_used
        jr z,.next
        push hl
        push bc
        call pou_entry
        pop bc
        ex de,hl
        pop hl
        push hl
        push bc
        ld b,8
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.ne
        inc hl
        inc de
        djnz .cmp
.ne:    pop bc
        pop hl
        jr z,.found
.next:  inc b
        ld a,b
        cp MAX_POU
        jr c,.lp
        scf
        ret
.found: ld a,b
        or a
        ret

; ---- pou_next / pou_prev: A = slot -> A = next/previous used slot, C = none
pou_next:
        ld b,a
.l:     inc b
        ld a,b
        cp MAX_POU
        ccf
        ret c
        call pou_used
        jr z,.l
        or a
        ret

pou_prev:
        ld b,a
.l:     ld a,b
        or a
        scf
        ret z
        dec b
        ld a,b
        call pou_used
        jr z,.l
        or a
        ret

; ---- name_pad: HL = 0-terminated text (max 8) -> name8 (space padded)
name_pad:
        ld de,name8
        ld b,8
.l:     ld a,(hl)
        or a
        jr z,.sp
        ld (de),a
        inc hl
        inc de
        djnz .l
        ret
.sp:    ld a,' '
.s:     ld (de),a
        inc de
        djnz .s
        ret

; ---- name_unpad: HL = 8-char name -> DE buffer, 0-terminated (no spaces)
name_unpad:
        ld b,8
.l:     ld a,(hl)
        cp ' '
        jr z,.e
        ld (de),a
        inc hl
        inc de
        djnz .l
.e:     xor a
        ld (de),a
        ret

name8:   ds 8
cur_pou: db 0
