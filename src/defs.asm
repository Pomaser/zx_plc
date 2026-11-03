; ============================================================
; ZX-PLC - global constants and memory map
; ============================================================

; ---- memory map ---------------------------------------------
STACK_TOP   EQU 0x6000      ; stack 0x5D00-0x5FFF
CODE_ORG    EQU 0x6000      ; editor code 0x6000-0xBFFF
PROJ        EQU 0xC000      ; project (saved to tape)
PROJ_END    EQU 0xF000
BCODE       EQU 0xF000      ; compiled bytecode 0xF000-0xF7FF
BCODE_END   EQU 0xF800
RT          EQU 0xF800      ; runtime data 0xF800-0xFDFC
IM2_JP      EQU 0xFDFD      ; JP isr
IM2_TAB     EQU 0xFE00      ; 257 B vector table
TEST_RES    EQU 0x5B00      ; test results (printer buffer)

; ---- project format -----------------------------------------
P_SIG       EQU 0           ; "ZXPLC"
P_VER       EQU 5
P_NPOU      EQU 6           ; number of used slots
P_LEN       EQU 8           ; word: total project length
PROJ_VER    EQU 1
MAX_POU     EQU 8
POU_ESIZE   EQU 16
POU_TAB     EQU PROJ+16
PE_NAME     EQU 0           ; 8 chars, space padded; first byte 0 = free slot
PE_LANG     EQU 8
PE_FLAGS    EQU 9
PE_LEN      EQU 10          ; word: body length
POU_BODIES  EQU POU_TAB+MAX_POU*POU_ESIZE
HDR_LEN     EQU POU_BODIES-PROJ

LANG_IL     EQU 0
LANG_LD     EQU 1
LANG_FBD    EQU 2

; ---- application screens ------------------------------------
SCR_POU     EQU 0
SCR_EDIT    EQU 1
SCR_RUN     EQU 2

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

; ---- key codes ----------------------------------------------
K_EDIT      EQU 7
K_LEFT      EQU 8
K_RIGHT     EQU 9
K_DOWN      EQU 10
K_UP        EQU 11
K_DEL       EQU 12
K_ENTER     EQU 13
K_BREAK     EQU 27

; ---- attributes ----------------------------------------------
ATTR_NORMAL  EQU 0x38       ; black on white
ATTR_SEL     EQU 0x68
ATTR_HINT    EQU 0x0F       ; white on blue
ATTR_ERR     EQU 0x57       ; white on red, bright
ATTR_INPUT   EQU 0x70       ; black on yellow, bright
ATTR_CURSOR  EQU 0x87       ; flashing, white on black
ATTR_TITLE   EQU 0x39       ; blue on white

; ---- operand areas ("area" byte) ----------------------------
AR_NONE     EQU 0
AR_I        EQU 1           ; %IX0.n      index 0-7
AR_Q        EQU 2           ; %QX0.n      index 0-7
AR_M        EQU 3           ; %MXn        index 0-63
AR_MW       EQU 4           ; %MWn        index 0-15
AR_S        EQU 5           ; scratch bit (compiler)
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
N_MW        EQU 16
FB_PER_TYPE EQU 4
FB_TYPES    EQU 9
