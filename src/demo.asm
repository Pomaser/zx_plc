; ============================================================
; demo.asm - builds the demo project (only in the -DMKDEMO build)
; ============================================================
; tools/mkdemo.py runs zxplc_mkdemo.sna, which builds the project with
; the normal editor routines and stops; the script saves the project
; memory to src/demo_proj.bin, which the normal build puts into the DEMO
; bank (File > Open demo, loaded at start-up).
; TEST_RES+2 = 0xA5 when done, 0xEE on an error (TEST_RES+3 = step).

demo_build:
        ld a,LANG_IL
        call proj_new
        ld a,1
        ld (TEST_RES+3),a
        ld hl,dm_n_il           ; slot 1
        ld a,LANG_IL
        call pou_add
        jp c,dm_fail
        ld hl,dm_n_ld           ; slot 2
        ld a,LANG_LD
        call pou_add
        jp c,dm_fail
        ld hl,dm_n_fbd          ; slot 3
        ld a,LANG_FBD
        call pou_add
        jp c,dm_fail
        ; symbols (before the code, which refers to them)
        ld a,2
        ld (TEST_RES+3),a
        ld hl,dm_syms
.sy:    ld a,(hl)
        cp 0xFF
        jr z,.sye
        ld (dm_area),a
        inc hl
        ld a,(hl)
        ld (dm_idx),a
        inc hl
        ld (dm_name),hl
        call dm_skip            ; -> comment
        ld d,h
        ld e,l
        call dm_skip            ; -> next record
        push hl
        ld hl,(dm_name)
        ld a,(dm_idx)
        ld c,a
        ld a,(dm_area)
        call sym_store
        pop hl
        jr nc,.sy
        jp dm_fail
.sye:   ; IL code
        ld a,3
        ld (TEST_RES+3),a
        ld hl,dm_main
        xor a
        call il_load_text
        jp c,dm_fail
        ld a,4
        ld (TEST_RES+3),a
        ld hl,dm_il
        ld a,1
        call il_load_text
        jp c,dm_fail
        ; LD and FBD cells, network comments
        ld a,5
        ld (TEST_RES+3),a
        ld a,2
        ld (cur_pou),a
        ld hl,dm_ld
        call dm_cells
        jp c,dm_fail
        ld hl,dm_ldc
        call dm_cmts
        jp c,dm_fail
        ld a,6
        ld (TEST_RES+3),a
        ld a,3
        ld (cur_pou),a
        ld hl,dm_fbd
        call dm_cells
        jp c,dm_fail
        ld hl,dm_fbdc
        call dm_cmts
        jp c,dm_fail
        ; watch list (simulation, W)
        ld a,WATCH_SLOT
        ld de,0
        ld bc,DM_WLEN
        call pou_insert
        jp c,dm_fail
        ex de,hl
        ld hl,dm_watch
        ld bc,DM_WLEN
        ldir
        ; POU comments
        ld a,7
        ld (TEST_RES+3),a
        ld hl,dm_c_main
        xor a
        call dm_cmt
        ld hl,dm_c_il
        ld a,1
        call dm_cmt
        ld hl,dm_c_ld
        ld a,2
        call dm_cmt
        ld hl,dm_c_fbd
        ld a,3
        call dm_cmt
        ; everything must compile
        ld a,8
        ld (TEST_RES+3),a
        BCALL il_compile
        jr c,dm_fail
        xor a
        ld (cur_pou),a
        ld a,0xA5
        ld (TEST_RES+2),a
        ld a,4
        jr dm_halt
dm_fail:
        ld a,0xEE
        ld (TEST_RES+2),a
        ld a,2
dm_halt:
        out (0xFE),a
.h:     halt
        jr .h

; dm_cells: HL = cells (row, pos, type, area, index, PT; 0xFF) -> cur_pou
;      C = error
dm_cells:
        ld a,(hl)
        cp 0xFF
        ret z                   ; (NC)
        ld d,a
        inc hl
        ld e,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        push af
        ld a,(hl)
        inc hl
        ld (ld_ppt),a
        ld a,(hl)
        inc hl
        ld (ld_ppt+1),a
        pop af
        push hl
        call ld_put
        pop hl
        ret c
        jr dm_cells

; dm_cmts: HL = network comments (row, text; 0xFF) -> cur_pou; C = error
dm_cmts:
        ld a,(hl)
        cp 0xFF
        ret z
        ld (ld_row),a
        inc hl
        ld de,ld_cbuf
        call put_str
        xor a
        ld (de),a
        inc hl
        push hl
        call ld_put_cmt
        pop hl
        ret c
        jr dm_cmts

; HL = string -> HL past its 0
dm_skip:
        ld a,(hl)
        inc hl
        or a
        jr nz,dm_skip
        ret

; A = slot, HL = comment -> stored in the POU table (zero padded)
dm_cmt: push hl
        call pou_entry
        ld de,PE_CMT
        add hl,de
        push hl
        ld bc,POU_CMAX
        xor a
        call memset
        pop de
        pop hl
        ld b,POU_CMAX           ; (at most POU_CMAX chars)
.c:     ld a,(hl)
        or a
        ret z
        ld (de),a
        inc hl
        inc de
        djnz .c
        ret

dm_area: db 0
dm_idx:  db 0
dm_name: dw 0

dm_n_il: db "DEMO_IL "
dm_n_ld: db "DEMO_LD "
dm_n_fbd: db "DEMO_FBD"
dm_c_main: db "Calls the 3 demos",0
dm_c_il:   db "Traffic light (IL)",0
dm_c_ld:   db "Pump and fan (LD)",0
dm_c_fbd:  db "Valve and horn (FBD)",0

; ---- watch list: [area][index]
dm_watch:
        db AR_I,11                              ; HighLvl
        db AR_Q,8                               ; Valve
        db AR_Q,9                               ; Horn
        db AR_FBM+0x30,FBT_TOF*FB_PER_TYPE+1    ; TValve.ET
DM_WLEN EQU $-dm_watch

; ---- symbols: area, index, name, comment
dm_syms:
        db AR_I,0,"TL_Start",0,"Traffic light start",0
        db AR_I,1,"TL_Stop",0,"Traffic light stop",0
        db AR_I,4,"Start",0,"Pump start button",0
        db AR_I,5,"Stop",0,"Pump stop button (NC)",0
        db AR_I,6,"Fault",0,"Fault signal",0
        db AR_I,7,"Ack",0,"Fault acknowledge",0
        db AR_Q,0,"Red",0,"Red light",0
        db AR_Q,1,"Yellow",0,"Yellow light",0
        db AR_Q,2,"Green",0,"Green light",0
        db AR_Q,4,"Pump",0,"Pump contactor",0
        db AR_Q,5,"Fan",0,"Cooling fan",0
        db AR_Q,6,"Lamp",0,"Fault lamp",0
        db AR_M,0,"Alert",0,"Stored fault",0
        db AR_M,1,"BlOn",0,"Blink: lamp phase",0
        db AR_M,2,"BlOff",0,"Blink: dark phase",0
        db AR_SX,0,"S_Off",0,"Step: lights off",0
        db AR_SX,1,"S_Red",0,"Step: red",0
        db AR_SX,2,"S_RedYel",0,"Step: red + yellow",0
        db AR_SX,3,"S_Green",0,"Step: green",0
        db AR_SX,4,"S_Yellow",0,"Step: yellow",0
        db AR_FBI,FBT_TON*FB_PER_TYPE+0,"T_Red",0,"Red time",0
        db AR_FBI,FBT_TON*FB_PER_TYPE+1,"T_RedYel",0,"Red + yellow time",0
        db AR_FBI,FBT_TON*FB_PER_TYPE+2,"T_Green",0,"Green time",0
        db AR_FBI,FBT_TON*FB_PER_TYPE+3,"T_Yellow",0,"Yellow time",0
        db AR_FBI,FBT_TOF*FB_PER_TYPE+0,"TFan",0,"Fan run-on time",0
        db AR_FBI,FBT_TP*FB_PER_TYPE+0,"POn",0,"Blink: lamp pulse",0
        db AR_FBI,FBT_TP*FB_PER_TYPE+1,"POff",0,"Blink: dark pulse",0
        ; DEMO_FBD: I/O byte 1 only
        db AR_I,8,"Auto",0,"Valve: automatic mode",0
        db AR_I,9,"Manual",0,"Valve: open manually",0
        db AR_I,10,"LowLvl",0,"Tank level low",0
        db AR_I,11,"HighLvl",0,"Tank level high",0
        db AR_I,12,"HornAck",0,"Horn acknowledge",0
        db AR_Q,8,"Valve",0,"Inlet valve",0
        db AR_Q,9,"Horn",0,"Overflow horn",0
        db AR_FBI,FBT_RTRIG*FB_PER_TYPE+0,"OvEdge",0,"High level edge",0
        db AR_FBI,FBT_SR*FB_PER_TYPE+0,"HornMem",0,"Horn memory",0
        db AR_FBI,FBT_TOF*FB_PER_TYPE+1,"TValve",0,"Valve run-on",0
        db 0xFF

; ---- MAIN
dm_main:
        db "// Demo project: MAIN runs the",0
        db "// traffic light (IL), the pump (LD)",0
        db "// and the tank (FBD)",0
        db "CAL",9,"DEMO_IL",0
        db "CAL",9,"DEMO_LD",0
        db "CAL",9,"DEMO_FBD",0
        db 0xFF

; ---- DEMO_IL: traffic light as a step sequence (one step active in S0)
dm_il:
        db "// No step active: lights off",0
        db "LDN",9,"S_Red",0
        db "ANDN",9,"S_RedYel",0
        db "ANDN",9,"S_Green",0
        db "ANDN",9,"S_Yellow",0
        db "S",9,"S_Off",0
        db 0
        db "// Start and stop",0
        db "LD",9,"TL_Start",0
        db "AND",9,"S_Off",0
        db "S",9,"S_Red",0
        db "LD",9,"TL_Stop",0
        db "S",9,"S_Off",0
        db 0
        db "// Step times",0
        db "CAL",9,"T_Red(IN:=S_Red, PT:=T#4s)",0
        db "CAL",9,"T_RedYel(IN:=S_RedYel, PT:=T#1s)",0
        db "CAL",9,"T_Green(IN:=S_Green, PT:=T#4s)",0
        db "CAL",9,"T_Yellow(IN:=S_Yellow, PT:=T#2s)",0
        db 0
        db "// Next step when the time is up",0
        db "LD",9,"T_Red.Q",0
        db "S",9,"S_RedYel",0
        db "LD",9,"T_RedYel.Q",0
        db "S",9,"S_Green",0
        db "LD",9,"T_Green.Q",0
        db "S",9,"S_Yellow",0
        db "LD",9,"T_Yellow.Q",0
        db "S",9,"S_Red",0
        db 0
        db "// Lights",0
        db "LD",9,"S_Red",0
        db "OR",9,"S_RedYel",0
        db "ST",9,"Red",0
        db "LD",9,"S_RedYel",0
        db "OR",9,"S_Yellow",0
        db "ST",9,"Yellow",0
        db "LD",9,"S_Green",0
        db "ST",9,"Green",0
        db 0xFF

; ---- DEMO_LD: row, pos, type, area, index, PT (20 ms ticks)
    MACRO DM_WIRES row, from, to
.p = from
        WHILE .p <= to
        db row,.p,LT_WIRE,0,0
        dw 0
.p = .p + 1
        ENDW
    ENDM
dm_ld:
        ; pump with self-holding: (Start OR Pump) AND NOT Stop
        db 1,0,LT_NO|LT_VL,AR_I,4
        dw 0
        db 1,1,LT_NC,AR_I,5
        dw 0
        DM_WIRES 1,2,8
        db 1,9,LT_COIL,AR_Q,4
        dw 0
        db 2,0,LT_NO,AR_Q,4
        dw 0
        ; fan runs on 5 s after the pump stops
        db 4,0,LT_NO,AR_Q,4
        dw 0
        db 4,1,LT_TOF,AR_FBI,FBT_TOF*FB_PER_TYPE+0
        dw 250
        DM_WIRES 4,2,8
        db 4,9,LT_COIL,AR_Q,5
        dw 0
        ; fault memory: set by a rising fault edge, reset by acknowledge
        db 6,0,LT_P,AR_I,6
        dw 0
        DM_WIRES 6,1,8
        db 6,9,LT_SET,AR_M,0
        dw 0
        db 7,0,LT_P,AR_I,7
        dw 0
        DM_WIRES 7,1,8
        db 7,9,LT_RES,AR_M,0
        dw 0
        ; blinking: two pulse timers start each other
        db 9,0,LT_NO,AR_M,0
        dw 0
        db 9,1,LT_NC,AR_M,2
        dw 0
        db 9,2,LT_TP,AR_FBI,FBT_TP*FB_PER_TYPE+0
        dw 25
        DM_WIRES 9,3,8
        db 9,9,LT_COIL,AR_M,1
        dw 0
        db 10,0,LT_NO,AR_M,0
        dw 0
        db 10,1,LT_NC,AR_M,1
        dw 0
        db 10,2,LT_TP,AR_FBI,FBT_TP*FB_PER_TYPE+1
        dw 25
        DM_WIRES 10,3,8
        db 10,9,LT_COIL,AR_M,2
        dw 0
        db 11,0,LT_NO,AR_M,1
        dw 0
        DM_WIRES 11,1,8
        db 11,9,LT_COIL,AR_Q,6
        dw 0
        db 0xFF

; ---- DEMO_LD network comments: row, text
dm_ldc:
        db 0,"Pump with self-holding",0
        db 3,"Fan runs on 5 s after the pump",0
        db 5,"Alert: fault edge, acknowledge",0
        db 8,"Blinking fault lamp (2 x TP)",0
        db 0xFF

; ---- DEMO_FBD: row, pos, type, area, index, PT
    MACRO DM_FWIRES row, from, to
.p = from
        WHILE .p <= to
        db row,.p,FT_WIRE,0,0
        dw 0
.p = .p + 1
        ENDW
    ENDM
dm_fbd:
        ; valve: Auto AND (Manual OR (LowLvl AND NOT HighLvl)), 2 s run-on (TOF)
        db 1,0,FT_IN,AR_I,8
        dw 0
        DM_FWIRES 1,1,2
        db 1,3,FT_AND,2,0
        dw 0
        DM_FWIRES 1,4,4
        db 1,5,FT_TOF,AR_FBI,FBT_TOF*FB_PER_TYPE+1
        dw 100                  ; 2 s run-on
        db 1,6,FT_OUT,AR_Q,8
        dw 0
        db 2,0,FT_IN,AR_I,9
        dw 0
        DM_FWIRES 2,1,1
        db 2,2,FT_OR,2,0
        dw 0
        db 3,0,FT_IN,AR_I,10
        dw 0
        db 3,1,FT_AND,2,0
        dw 0
        db 4,0,FT_IN|FT_NEG,AR_I,11
        dw 0
        ; horn: set by the rising edge of HighLvl, reset by HornAck
        db 6,0,FT_IN,AR_I,11
        dw 0
        db 6,1,FT_RTRIG,AR_FBI,FBT_RTRIG*FB_PER_TYPE+0
        dw 0
        db 6,2,FT_SR,AR_FBI,FBT_SR*FB_PER_TYPE+0
        dw 0
        db 6,3,FT_OUT,AR_Q,9
        dw 0
        db 7,0,FT_IN,AR_I,12
        dw 0
        DM_FWIRES 7,1,1
        db 0xFF
dm_fbdc:
        db 0,"Valve: auto, manual or low, 2 s run-on",0
        db 5,"Horn: overflow until acknowledged",0
        db 0xFF
