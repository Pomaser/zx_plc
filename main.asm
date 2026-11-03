; ============================================================
; ZX-PLC - PLC editor and simulator (IEC 61131-3: IL, LD, FBD)
; ZX Spectrum 48K, Z80 assembler (sjasmplus)
; ============================================================
; Build:       sjasmplus main.asm            -> zxplc.sna
; Tests:       sjasmplus -DTEST main.asm     -> zxplc_test.sna
; ============================================================

        DEVICE ZXSPECTRUM48

        INCLUDE "src/defs.asm"

        ORG CODE_ORG

START:
        di
        ld sp,STACK_TOP
        ld iy,0x5C3A
        call im2_init
        ld a,BORDER
        out (0xFE),a
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        call scr_cls
        call menu_init
    IFDEF TEST
        jp run_tests
    ENDIF
        ld a,LANG_LD
        call proj_new
        ld a,SCR_POU
        ld (cur_screen),a
main_loop:
        call kb_release
        ld a,(cur_screen)
        ld hl,screen_tab
        call .disp              ; screen returns a command in A
        call cmd_target
        jr main_loop
.disp:  jp jump_table

screen_tab:
        dw scr_pou, scr_edit, scr_run

; ---- cmd_target: A = command -> selects the screen to show next
cmd_target:
        cp CMD_POU_MANAGE
        ret c
        ld b,SCR_POU
        jr z,.set
        cp CMD_EDIT
        jr c,.pou
        ld b,SCR_EDIT
        jr z,.set
        cp CMD_KEYS
        ret nc
        ld b,SCR_RUN
.set:   ld a,b
        ld (cur_screen),a
        ret
.pou:   ld (pou_pending),a      ; POU action, executed by the POU screen
        ld b,SCR_POU
        jr .set

cur_screen: db SCR_POU

; ---- IM2 interrupt: frame counter only
im2_init:
        ld hl,IM2_TAB
        ld bc,257
        ld a,IM2_JP & 0xFF
        call memset
        ld a,0xC3
        ld (IM2_JP),a
        ld hl,isr
        ld (IM2_JP+1),hl
        ld a,IM2_TAB>>8
        ld i,a
        im 2
        ei
        ret

isr:    push af
        push hl
        ld hl,(frames)
        inc hl
        ld (frames),hl
        pop hl
        pop af
        ei
        reti

frames: dw 0

        INCLUDE "src/util.asm"
        INCLUDE "src/screen.asm"
        INCLUDE "src/keyboard.asm"
        INCLUDE "src/ui.asm"
        INCLUDE "src/ptext.asm"
        INCLUDE "src/menu.asm"
        INCLUDE "src/project.asm"
        INCLUDE "src/operand.asm"
        INCLUDE "src/pou.asm"
        INCLUDE "src/app.asm"
    IFDEF TEST
        INCLUDE "src/tests.asm"
    ENDIF

        INCLUDE "src/font6.asm"

win_save: ds 9*24*12        ; cells saved under a popup window
CODE_END:
        DISPLAY "Code end: ",/H,CODE_END," (limit 0xC000), free: ",/D,PROJ-CODE_END
        ASSERT CODE_END <= PROJ

    IFDEF TEST
        SAVESNA "zxplc_test.sna", START
    ELSE
        SAVESNA "zxplc.sna", START
    ENDIF
