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
        BCALL fb_editor         ; FBD (own bank)
        ret
