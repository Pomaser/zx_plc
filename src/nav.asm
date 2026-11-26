; ============================================================
; nav.asm - the way back after Go to definition (DATA bank, BCALL)
; ============================================================
; gd_run (tools.asm) calls nav_save before it jumps: the place in the
; editor of cur_pou goes to nav_rec (core) and nav_arm is set. Then the
; next BREAK does not open the menu: kb_get marks it (pal_req 2),
; menu_run returns CMD_BACK and menu_cmd calls nav_back. Opening the
; menu or the palette clears nav_arm (menu_run).
; ============================================================

; ---- nav_save: nav_rec = cur_pou, line, top row, position; nav_arm = 1
nav_save:
        ld a,(cur_pou)
        ld (nav_rec),a
        call pou_lang
        cp LANG_IL
        jr z,.il
        cp LANG_ST
        jr z,.st
        ld hl,ld_row            ; LD / FBD (core)
        ld de,nav_rec+1
        ldi                     ; line
        xor a
        ld (de),a
        inc de
        ld a,(ld_top)
        ld (de),a               ; top
        inc de
        xor a
        ld (de),a
        inc de
        ld a,(ld_pos)
        ld (de),a               ; pos
        jr .arm
.il:    ld hl,il_cur            ; il_cur, il_top (EDIT bank)
        ld a,BANK_EDIT
        call .cp4
        xor a
        ld (nav_rec+5),a
        jr .arm
.st:    ld hl,st_cur            ; st_cur, st_top, st_pos (FBD bank)
        ld a,BANK_FBD
        call .cp4
        ld hl,st_pos
        ld de,nav_rec+5
        ld bc,1
        ld a,BANK_FBD
        call bank_copy
.arm:   ld a,1
        ld (nav_arm),a
        ret
.cp4:   ld de,nav_rec+1
        ld bc,4
        jp bank_copy
        ASSERT il_top == il_cur+2 && st_top == st_cur+2

; ---- nav_back: -> A = CMD_EDIT (the editor opens at nav_rec), or 0 if
;      that POU is gone
nav_back:
        ld a,(nav_rec)
        call pou_used
        jr nz,.ok
        xor a
        ret
.ok:    ld a,(nav_rec)
        ld (cur_pou),a
        ld hl,(nav_rec+1)
        ld (xr_jl),hl
        ld hl,(nav_rec+3)
        ld (xr_jt),hl
        ld a,(nav_rec+5)
        ld (xr_jp),a
        ld a,1
        ld (xr_jf),a
        ld a,CMD_EDIT
        ret
