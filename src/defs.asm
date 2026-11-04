; ============================================================
; ZX-PLC - global constants and memory map
; ============================================================

; ---- memory map (ZX Spectrum 128K) -------------------------
; 0x4000-0x7FFF bank 5 and 0x8000-0xBFFF bank 2 are fixed,
; 0xC000-0xFFFF is one of the paged banks (port 0x7FFD)
TEST_RES    EQU 0x5B00      ; test results (printer buffer)
STACK_TOP   EQU 0x5E00      ; stack 0x5B10-0x5DFF
CODE_ORG    EQU 0x5E00      ; core code 0x5E00-RT (fixed memory)
RT          EQU 0x8A00      ; runtime data 0x8A00-0x8FFF
PROJ        EQU 0x9000      ; project 0x9000-0xBFFF, 12 KB (saved to tape)
PROJ_END    EQU 0xC000
BANKED      EQU 0xC000      ; code of the paged banks
BCODE       EQU 0xF000      ; compiled bytecode 0xF000-0xF7FF (RUN bank)
BCODE_END   EQU 0xF800
IM2_JP      EQU 0xFDFD      ; JP isr        (in every paged bank)
IM2_TAB     EQU 0xFE00      ; 257 B vector table (in every paged bank)

; ---- paged banks
BANK_EDIT   EQU 0           ; POU list, IL / LD / symbol editors, simulation screen
BANK_RUN    EQU 4           ; compilers, VM, bytecode
BANK_DATA   EQU 1           ; buffers (popup save area)
BANK_DEMO   EQU 3           ; demo project image
BANK_SPARE  EQU 7           ; copy of the project while loading from tape
BANK_ROM48  EQU 0x10        ; port 0x7FFD: ROM 1 = 48 BASIC (tape routines)

; BCALL label: calls a routine in another paged bank (registers pass
; through in both directions, see bank.asm)
    MACRO BCALL target
        call bcall_
        dw target
        db $$target
    ENDM

; IM2STUB: JP isr + vector table, placed at the top of every paged bank
    MACRO IM2STUB
        ORG IM2_JP
        jp isr
        ORG IM2_TAB
        ds 257,IM2_JP & 0xFF
    ENDM

; ---- project format -----------------------------------------
P_SIG       EQU 0           ; "ZXPLC"
P_VER       EQU 5
P_NPOU      EQU 6           ; number of used slots
P_LEN       EQU 8           ; word: total project length
PROJ_VER    EQU 1
MAX_POU     EQU 8
POU_ESIZE   EQU 32
POU_TAB     EQU PROJ+16
PE_NAME     EQU 0           ; 8 chars, space padded; first byte 0 = free slot
PE_LANG     EQU 8
PE_FLAGS    EQU 9
PE_LEN      EQU 10          ; word: body length
PE_CMT      EQU 12          ; comment, max. 20 chars (0-terminated if shorter)
POU_CMAX    EQU 20
SYM_SLOT    EQU MAX_POU     ; hidden 9th slot: symbol table
POU_BODIES  EQU POU_TAB+(MAX_POU+1)*POU_ESIZE
HDR_LEN     EQU POU_BODIES-PROJ

LANG_IL     EQU 0
LANG_LD     EQU 1
LANG_FBD    EQU 2

; ---- application screens ------------------------------------
SCR_POU     EQU 0
SCR_EDIT    EQU 1
SCR_RUN     EQU 2
SCR_SYM     EQU 3

; ---- menu commands ------------------------------------------
CMD_NONE        EQU 0
CMD_NEW         EQU 1
CMD_LOAD        EQU 2
CMD_SAVE        EQU 3
CMD_ABOUT       EQU 4
CMD_POU_MANAGE  EQU 5
CMD_POU_NEW     EQU 6
CMD_POU_RENAME  EQU 7
CMD_POU_DELETE  EQU 8
CMD_POU_LANG    EQU 9
CMD_EDIT        EQU 10
CMD_RUN         EQU 11
CMD_STEP        EQU 12
CMD_RESET       EQU 13
CMD_KEYS        EQU 14
CMD_IL_INS      EQU 15
CMD_IL_DEL      EQU 16
CMD_SYMBOLS     EQU 17
CMD_VIEW_SYM    EQU 18
CMD_VIEW_ADDR   EQU 19
CMD_REDRAW      EQU 20
CMD_STOP        EQU 21
CMD_SOUND       EQU 22
CMD_DEMO        EQU 23

; ---- status bar text markers (st_left): symbol name shown inverted
ST_SYM      EQU 1           ; start of the symbol name
ST_SYME     EQU 2           ; end of it
ST_TAB      EQU 3           ; followed by x: continue at x (if not past it)

; ---- key codes ----------------------------------------------
K_HOME      EQU 1           ; SS + LEFT  (CS+SS+5): start of the line
K_END       EQU 2           ; SS + RIGHT (CS+SS+8): end of the line
K_PGUP      EQU 3           ; SS + UP    (CS+SS+7): page up
K_PGDN      EQU 4           ; SS + DOWN  (CS+SS+6): page down
K_SSENTER   EQU 5           ; SS + ENTER: IL new line below, LD next row
K_EDIT      EQU 7
K_LEFT      EQU 8
K_RIGHT     EQU 9
K_DOWN      EQU 10
K_UP        EQU 11
K_DEL       EQU 12
K_ENTER     EQU 13
K_BREAK     EQU 27

BORDER      EQU 7           ; white border

; ---- attributes ----------------------------------------------
ATTR_NORMAL  EQU 0x38       ; black on white
ATTR_CURSOR  EQU 0x87       ; flashing, white on black
ATTR_TITLE   EQU 0x39       ; dark blue (ink 1, no BRIGHT) on white
ATTR_LNUM    EQU 0x78       ; black on bright white (line numbers)
ATTR_MNEM    EQU 0x39       ; dark blue on white (IL instruction)
ATTR_COMMENT EQU 0x3C       ; dark green on white (comments)

; ---- operand areas ("area" byte) ----------------------------
AR_NONE     EQU 0
AR_I        EQU 1           ; %IX0.n      index 0-7
AR_Q        EQU 2           ; %QX0.n      index 0-7
AR_M        EQU 3           ; %MXn        index 0-63
AR_MW       EQU 4           ; %MWn        index 0-15
AR_SX       EQU 5           ; step flag %SXb.n, index = b*8+n (0-63)
AR_KB       EQU 6           ; TRUE/FALSE  index 1/0
AR_K16      EQU 7           ; INT constant, value in DE
AR_KT       EQU 8           ; TIME constant (20 ms ticks), value in DE
AR_FBI      EQU 9           ; FB instance, index = type*4+n
AR_FBM      EQU 10          ; FB member, area bits 4-6 = member
AR_POU      EQU 11          ; POU, index = slot
AR_MASK     EQU 0x0F

N_IN        EQU 8
N_Q         EQU 8
N_M         EQU 64
N_SB        EQU 8           ; step bytes S0-S7
N_MW        EQU 16
FB_PER_TYPE EQU 4
FB_TYPES    EQU 9
