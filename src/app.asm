; ============================================================
; app.asm - screen dispatch, EDIT screen
; ============================================================

; ---- scr_dispatch: A = screen -> runs it, returns its command in A
;      (called from the core main loop through BCALL)
scr_dispatch:
        ld hl,screen_tab
        jp jump_table

screen_tab:
        dw scr_pou_b, scr_edit, scr_run, scr_sym

scr_pou_b:                      ; the POU list lives in the RUN bank
        BCALL scr_pou
        ret

; ---- EDIT screen: opens the editor for the current POU language
scr_edit:
        ld a,(cur_pou)
        call pou_lang
        cp LANG_IL
        jp z,il_editor
        cp LANG_LD
        jp z,ld_editor
        cp LANG_ST
        jr z,.st
        BCALL fb_editor         ; FBD (own bank)
        ret
.st:    BCALL st_editor         ; ST (in the FBD bank)
        ret

; ---- st_load_text: HL = ST lines (0-terminated, the list ends with 0xFF),
;      A = slot -> replaces the POU body (demo, tests)
st_load_text:
        ld (stl_s),a
        push hl
        call pou_body
        ld de,0
        ld a,(stl_s)
        call pou_delete
        pop hl
.l:     ld a,(hl)
        cp 0xFF
        ret z
        ld de,il_out
        call put_str
        xor a
        ld (de),a
        inc hl
        push hl
        ld a,(stl_s)
        ld hl,il_out
        BCALL st_add_line
        pop hl
        jr .l
stl_s:  db 0
