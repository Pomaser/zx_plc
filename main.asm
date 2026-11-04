; ============================================================
; ZX-PLC - PLC editor and simulator (IEC 61131-3: IL, LD, FBD)
; ZX Spectrum 128K, Z80 assembler (sjasmplus)
; ============================================================
; Build:       sjasmplus main.asm            -> zxplc.sna (128K snapshot)
; Tests:       sjasmplus -DTEST -DTPART=1 main.asm -> zxplc_test1.sna (and TPART=2)
; ============================================================

        DEVICE ZXSPECTRUM128

        INCLUDE "src/defs.asm"

        ORG CODE_ORG

START:
        di
        ld sp,STACK_TOP
        ld iy,0x5C3A
        ld a,BANK_EDIT
        call bank_set
        call snd_init
        call im2_init
        ld a,BORDER
        out (0xFE),a
        ld a,ATTR_NORMAL
        ld (cur_attr),a
        call scr_cls
        call menu_init
    IFDEF TEST
        jp run_tests            ; (EDIT bank)
    ENDIF
        ld a,LANG_IL            ; default language of MAIN
        call proj_new
    IFNDEF NODEMO
    IFNDEF TEST
        BCALL demo_load         ; test program
    ENDIF
    ENDIF
        ld a,SCR_POU
        ld (cur_screen),a
main_loop:
        ld a,(cur_screen)
        BCALL scr_dispatch      ; screen returns a command in A
        call cmd_target
        jr main_loop

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
        cp CMD_SYMBOLS
        ld b,SCR_SYM
        jr z,.set
        cp CMD_KEYS
        ret nc
        ld (sim_pending),a      ; Run/Step/Reset, executed by the RUN screen
        ld b,SCR_RUN
.set:   ld a,b
        ld (cur_screen),a
        ret
.pou:   ld (pou_pending),a      ; POU action, executed by the POU screen
        ld b,SCR_POU
        jr .set

cur_screen: db SCR_POU

; ---- IM2 interrupt: frame counter and keyboard queue
; (every paged bank holds the vector table and JP isr, see IM2STUB)
im2_init:
        ld a,IM2_TAB>>8
        ld i,a
        im 2
        ei
        ret

isr:    push af
        push bc
        push de
        push hl
        ld hl,(frames)
        inc hl
        ld (frames),hl
        call kb_isr
        call snd_isr
        pop hl
        pop de
        pop bc
        pop af
        ei
        reti

frames: dw 0


; ---- core modules (fixed memory) ----------------------------
        INCLUDE "src/bank.asm"
        INCLUDE "src/util.asm"
        INCLUDE "src/screen.asm"
        INCLUDE "src/keyboard.asm"
        INCLUDE "src/sound.asm"
        INCLUDE "src/ui.asm"
        INCLUDE "src/ptext.asm"
        INCLUDE "src/menu.asm"
        INCLUDE "src/status.asm"
        INCLUDE "src/project.asm"
        INCLUDE "src/operand.asm"
        INCLUDE "src/il_parse.asm"
        INCLUDE "src/symbols.asm"
        INCLUDE "src/shared.asm"
        INCLUDE "src/font6.asm"
CORE_END:
        DISPLAY "Core:  ",/H,CODE_ORG,"-",/H,CORE_END-1,", free: ",/D,RT-CORE_END
        ASSERT CORE_END <= RT
        ASSERT RT_END <= PROJ

; ---- EDIT bank ----------------------------------------------
        MMU 3, BANK_EDIT, BANKED
        INCLUDE "src/pou.asm"
        INCLUDE "src/app.asm"
        INCLUDE "src/il_edit.asm"
        INCLUDE "src/sym_edit.asm"
        INCLUDE "src/ld_edit.asm"
        INCLUDE "src/sim.asm"
    IFNDEF TEST
        INCLUDE "src/demo.asm"
    ELSE
        INCLUDE "src/tests.asm"     ; tests use the editors' buffers directly
    ENDIF
EDIT_END:
        DISPLAY "EDIT:  free: ",/D,IM2_JP-EDIT_END
        ASSERT EDIT_END <= IM2_JP
        IM2STUB

; ---- RUN bank -----------------------------------------------
        MMU 3, BANK_RUN, BANKED
        INCLUDE "src/il_comp.asm"
        INCLUDE "src/vm.asm"
        INCLUDE "src/ld_comp.asm"
RUN_END:
        DISPLAY "RUN:   free: ",/D,BCODE-RUN_END
        ASSERT RUN_END <= BCODE
        IM2STUB

; ---- DATA bank ----------------------------------------------
        MMU 3, BANK_DATA, BANKED
win_save: ds 9*WIN_MAXC     ; cells saved under a popup window
        IM2STUB

; unused banks get the interrupt table too
        MMU 3, 3, BANKED
        IM2STUB
        MMU 3, 6, BANKED
        IM2STUB
        MMU 3, 7, BANKED
        IM2STUB

        MMU 3, BANK_EDIT, BANKED     ; bank paged in when the snapshot starts
    IFDEF TEST
    IF TPART==1
        SAVESNA "zxplc_test1.sna", START
    ELSE
        SAVESNA "zxplc_test2.sna", START
    ENDIF
    ELSE
        SAVESNA "zxplc.sna", START
    ENDIF
