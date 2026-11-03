; ============================================================
; ZX-PLC - globální konstanty a mapa paměti
; ============================================================

; ---- mapa paměti -------------------------------------------
STACK_TOP   EQU 0x6000      ; zásobník 0x5D00-0x5FFF
CODE_ORG    EQU 0x6000      ; kód editoru 0x6000-0xBFFF
PROJ        EQU 0xC000      ; projekt (ukládá se na kazetu)
PROJ_END    EQU 0xF000
BCODE       EQU 0xF000      ; zkompilovaný bytekód 0xF000-0xF7FF
BCODE_END   EQU 0xF800
RT          EQU 0xF800      ; runtime data 0xF800-0xFDFC
IM2_JP      EQU 0xFDFD      ; JP isr
IM2_TAB     EQU 0xFE00      ; 257 B vektorová tabulka
TEST_RES    EQU 0x5B00      ; výsledek testů (printer buffer)

; ---- formát projektu ---------------------------------------
P_SIG       EQU 0           ; "ZXPLC"
P_VER       EQU 5
P_NPOU      EQU 6           ; počet použitých slotů
P_LEN       EQU 8           ; word: celková délka projektu
PROJ_VER    EQU 1
MAX_POU     EQU 8
POU_ESIZE   EQU 16
POU_TAB     EQU PROJ+16
PE_NAME     EQU 0           ; 8 znaků, mezery; první bajt 0 = volný slot
PE_LANG     EQU 8
PE_FLAGS    EQU 9
PE_LEN      EQU 10          ; word: délka těla
POU_BODIES  EQU POU_TAB+MAX_POU*POU_ESIZE
HDR_LEN     EQU POU_BODIES-PROJ

LANG_IL     EQU 0
LANG_LD     EQU 1
LANG_FBD    EQU 2

; ---- obrazovky aplikace ------------------------------------
SCR_POU     EQU 0
SCR_EDIT    EQU 1
SCR_RUN     EQU 2
SCR_FILE    EQU 3

; ---- kódy kláves -------------------------------------------
K_EDIT      EQU 7
K_LEFT      EQU 8
K_RIGHT     EQU 9
K_DOWN      EQU 10
K_UP        EQU 11
K_DEL       EQU 12
K_ENTER     EQU 13
K_BREAK     EQU 27

; ---- atributy ----------------------------------------------
ATTR_NORMAL  EQU 0x38       ; černá na bílé
ATTR_BAR     EQU 0x4F       ; bílá na modré, jas
ATTR_BAR_CUR EQU 0x4E       ; žlutá na modré, jas
ATTR_BAR_SEL EQU 0x68       ; černá na azurové, jas
ATTR_SEL     EQU 0x68
ATTR_HINT    EQU 0x0F       ; bílá na modré
ATTR_ERR     EQU 0x57       ; bílá na červené, jas
ATTR_INPUT   EQU 0x70       ; černá na žluté, jas
ATTR_CURSOR  EQU 0x87       ; bliká, bílá na černé
ATTR_TITLE   EQU 0x39       ; modrá na bílé

; ---- oblasti operandů (bajt "area") -------------------------
AR_NONE     EQU 0
AR_I        EQU 1           ; %IX0.n      index 0-7
AR_Q        EQU 2           ; %QX0.n      index 0-7
AR_M        EQU 3           ; %MXn        index 0-63
AR_MW       EQU 4           ; %MWn        index 0-15
AR_S        EQU 5           ; scratch bit (kompilátor)
AR_KB       EQU 6           ; TRUE/FALSE  index 1/0
AR_K16      EQU 7           ; INT konstanta, hodnota ve DE
AR_KT       EQU 8           ; TIME konstanta (tiky 20 ms), hodnota ve DE
AR_FBI      EQU 9           ; instance FB, index = typ*4+n
AR_FBM      EQU 10          ; člen FB, bity 4-6 area = člen
AR_POU      EQU 11          ; POU, index = slot
AR_MASK     EQU 0x0F

N_IN        EQU 8
N_Q         EQU 8
N_M         EQU 64
N_MW        EQU 16
FB_PER_TYPE EQU 4
FB_TYPES    EQU 9
