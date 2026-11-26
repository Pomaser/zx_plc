; ============================================================
; sim.asm - RUN screen: simulation with live monitoring
; ============================================================
; Rows 1-19: listing of the monitored POU, current operand
; values on the right. Row 20 separator, rows 21/22 input and output
; LEDs; the key hints are in the status bar. One PLC scan per frame while running.
; ============================================================
SIM_ROWS  EQU 19
SIM_VCOL  EQU 25            ; first cell of the value column
SIM_X_VAL EQU 252
ROW_SEP   EQU 20
ROW_IN    EQU 21
ROW_OUT   EQU 22
SM_RCOL   EQU 26            ; status bar: hints left, RUN / STOP from here
LED_COL0  EQU 0             ; cell of the first LED (LED + number: 2 cells)
LED_COL1  EQU 16            ; first LED of byte 1
ATTR_LED_I EQU 0x3C         ; green ink
ATTR_LED_Q EQU 0x3A         ; red ink

scr_run:
        call screen_begin
        ld hl,txt_sm_hint       ; status bar: key hints, RUN / STOP right
        ld (st_left),hl
        ld hl,txt_sm_stop
        ld (st_right),hl
        ld a,SM_RCOL
        ld (st_rcol),a
        call status_draw
        ; monitored POU: the current one if IL, else MAIN if IL        xor a
        ld (sm_mon),a
        ld a,(cur_pou)          ; (every language can be monitored)
        call pou_lang
        inc a
        ld (sm_mon),a           ; 1 = IL, 2 = LD, 3 = FBD, 4 = ST
        cp 4
        jr z,.lines
        cp 2
        jr nc,.ldm
.lines: call il_count
        jr .nomon
.ldm:   call ld_nrows           ; scrolling limit
        ld l,a
        ld h,0
        ld (il_n),hl
        ld a,1
        ld (ld_vbase),a
        ld a,SIM_ROWS/2
        ld (ld_vn),a
.nomon: ld hl,(il_cur)
        ld (sm_savecur),hl
        ld hl,0
        ld (sm_top),hl
        BCALL vm_reset
        ld hl,RT_FRC            ; no forced values, program page
        ld bc,WT_MAX*5
        xor a
        call memset
        BCALL tr_reset          ; empty trend history
        xor a
        ld (sm_page),a
        ld (sim_tog),a
        ld (sim_tog+1),a
        ld (sm_ib),a
        ld (sm_run),a
        call sim_state
        BCALL il_compile
        jp c,.cjump
        ld a,1
        ld (sm_ok),a
        call sim_draw_panel
        call sim_draw_list
        call sim_chk_called
        ; command requested from another screen
        ld hl,sim_pending
        ld a,(hl)
        ld (hl),0
        or a
        jr z,.loop
        call sim_cmd
.loop:  halt
        call sim_inputs
        ld a,(sm_run)
        or a
        jr z,.nrun
        ld hl,(frames)
        ld de,(sm_lastf)
        ld (sm_lastf),hl
        or a
        sbc hl,de               ; frames since the last scan
        ld a,h
        or a
        jr nz,.dtmax
        ld a,l
        cp 50
        jr c,.dt
.dtmax: ld l,50
.dt:    ld h,0
        call sim_scan
.nrun:  ld a,(ms_vis)           ; (no mouse pointer under the redraw)
        or a
        jr z,.nr2
        BCALL ms_hide
.nr2:   call sim_update
        ld a,(sm_page)          ; trend samples (drawn on page 2)
        BCALL tr_tick
        call ur_out
        call sim_state
        call kb_get
        or a
        jr z,.loop
        ld b,a                  ; watch page: its keys
        ld a,(sm_page)
        dec a
        ld a,b
        jr nz,.np
        cp K_UP
        jr z,.wk
        cp K_DOWN
        jr z,.wk
        cp K_ENTER
        jr z,.wk
        cp K_DEL
        jr z,.wk
        cp 'f'
        jr z,.wk
        cp 'w'                  ; (W: write a value, M: back to the monitor)
        jr z,.wk
        cp 'W'
        jr z,.wk
        cp 'F'
        jr nz,.np
.wk:    BCALL wt_key
        jp .loop
.np:
        cp K_MOUSE              ; a click on an input LED toggles it
        jr nz,.nmo
        BCALL ms_crow
        cp ROW_IN
        jp nz,.loop
        ld a,(ms_cx)            ; bit x / 16 (LED + number: 2 cells)
        rrca
        rrca
        rrca
        rrca
        and 15
        ld c,a
        and 7
        ld e,a
        ld d,0
        ld hl,bit_masks
        add hl,de
        ld b,(hl)
        ld a,c
        rrca
        rrca
        rrca
        and 1
        ld e,a
        ld hl,sim_tog
        add hl,de
        ld a,(hl)
        xor b
        ld (hl),a
        ld a,e                  ; (its byte becomes the active one)
        ld hl,sm_ib
        cp (hl)
        jp z,.loop
        ld (hl),a
        call sim_dim
        jp .loop
.nmo:   cp K_UP
        jp z,.up
        cp K_DOWN
        jp z,.down
        cp K_BREAK
        jp z,.menu
        cp K_EDIT
        jp z,.menu
        cp '0'
        jr c,.letter
        cp '8'
        jr nc,.letter
        sub '0'                 ; key n toggles input %IXb.n (b = sm_ib)
        ld e,a
        ld d,0
        ld hl,bit_masks
        add hl,de
        ld c,(hl)
        ld a,(sm_ib)
        ld e,a
        ld hl,sim_tog
        add hl,de
        ld a,(hl)
        xor c
        ld (hl),a
        jp .loop
.letter:
        call to_upper
        ld b,1
        cp 'M'                  ; M on the watch / trend page: back to the monitor
        jr nz,.nm
        ld a,(sm_page)
        or a
        jp z,.loop
        ld b,a                  ; (the page we are on: toggles it off)
        jr .pg
.nm:    cp 'W'                  ; W: program / watch page
        jr z,.pg
        inc b
        cp 'G'                  ; G: program / trend page
        jr z,.pg
        cp 'T'                  ; T on the watch page: the trend (else stop)
        jr nz,.nt
        ld a,(sm_page)
        dec a
        ld a,'T'
        jr z,.pg
.nt:    cp 'Z'                  ; Z: time base of the trend
        jr nz,.nw
        ld a,(sm_page)
        cp b
        jp nz,.loop
        BCALL tr_zoom
        call sim_draw_list
        jp .loop
.pg:    ld a,(sm_page)
        cp b
        ld a,b
        jr nz,.pg2
        xor a
.pg2:   ld (sm_page),a
        call sim_hint
        call sim_draw_list
        jp .loop
.nw:    cp 'B'                  ; B: the other input byte
        jr nz,.nb
        ld a,(sm_ib)
        xor 1
        ld (sm_ib),a
        call sim_dim            ; the active half bright
        jp .loop
.nb:
        cp 'R'                  ; R toggles run / stop
        jr nz,.nr
        ld b,CMD_RUN
        ld a,(sm_run)
        or a
        jr z,.c
        ld b,CMD_STOP
        jr .c
.nr:    ld b,CMD_STEP
        cp 'S'
        jr z,.c
        ld b,CMD_RESET
        cp 'E'
        jp nz,.loop
.c:     ld a,b
        call sim_cmd
        jp .loop
.up:    ld hl,(sm_top)
        ld a,h
        or l
        jp z,.loop
        dec hl
        ld (sm_top),hl
        call sim_draw_list
        jp .loop
.down:  ld hl,(sm_top)
        inc hl
        ld de,(il_n)
        or a
        sbc hl,de
        jp nc,.loop
        add hl,de
        ld (sm_top),hl
        call sim_draw_list
        jp .loop
.menu:  call menu_handle
        jp z,.loop
        cp CMD_RUN
        jr z,.mc
        cp CMD_STOP
        jr z,.mc
        cp CMD_STEP
        jr z,.mc
        cp CMD_RESET
        jr z,.mc
        cp CMD_WATCH
        jr z,.mc
        cp CMD_TREND
        jr z,.mc
        cp CMD_REDRAW
        jr nz,.exit
        call sim_draw_list
        jp .loop
.mc:    call sim_cmd
        jp .loop
.cjump: xor a                   ; compile error: the editor opens at the
        ld (sm_ok),a            ; faulty line / element, the message is in
        ld (sim_pending),a      ; the status bar
        call beep
        ld a,(cp_slot)
        ld (cur_pou),a
        ld hl,(cp_line)         ; (1-based)
        ld a,h
        or l
        jr z,.cj0
        dec hl
.cj0:   ld (xr_jl),hl
        ld (xr_jt),hl
        ld a,(cp_epos)
        ld (xr_jp),a
        ld a,1
        ld (xr_jf),a
        ld (xr_err),a
        ld a,CMD_EDIT
.exit:  push af
        xor a
        ld (sm_run),a           ; the simulation stops when leaving the screen
        call ur_out0            ; (UR-4 outputs off)
        ld hl,(sm_savecur)
        ld (il_cur),hl
        ld hl,0
        ld (st_right),hl
        pop af
        ret

; ---- sim_cmd: A = CMD_RUN, CMD_STOP, CMD_STEP, CMD_RESET
sim_cmd:
        ld b,1
        cp CMD_WATCH            ; the watch page
        jr z,.pg
        inc b
        cp CMD_TREND            ; the trend page
        jr nz,.nw
.pg:    ld a,b
        ld (sm_page),a
        call sim_hint
        jp sim_draw_list
.nw:    cp CMD_RESET
        jr z,.reset
        cp CMD_STOP
        jr z,.stop
        cp CMD_LOGIN            ; (login: online in STOP)
        jr z,.stop
        ld b,a
        ld a,(sm_ok)
        or a
        jr nz,.ok
        call beep               ; program not compiled
        ret
.ok:    ld a,b
        cp CMD_STEP
        jr z,.step
        ld a,1
        ld (sm_run),a
        ld hl,(frames)
        dec hl
        ld (sm_lastf),hl
        jr sim_state
.stop:  xor a
        ld (sm_run),a
        jr sim_state
.step:  xor a
        ld (sm_run),a
        call sim_state
        ld hl,1
        jr sim_scan
.reset: BCALL vm_reset
        xor a
        ld (sim_tog),a
        ld (sim_tog+1),a
        ret

; ---- sim_hint: key hints of the page in the status bar
sim_hint:
        ld a,(sm_page)          ; the menu bar: "Watch" / "Trend" (mp_alt
        or a                    ; 2 / 3) or the POU name
        jr z,.m
        inc a
.m:     ld (mp_alt),a
        call menu_pou
        ld hl,txt_sm_hint
        ld a,(sm_page)
        or a
        jr z,.s
        ld hl,txt_wt_hint
        dec a
        jr z,.s
        ld hl,txt_tr_hint
.s:     ld (st_left),hl
        jp status_left

; ---- sim_state: RUN / STOP in the status bar
sim_state:
        ld hl,txt_sm_stop
        ld a,(sm_run)
        or a
        jr z,.s
        ld hl,txt_sm_run
.s:     ld a,(ur_on)            ; "UR4/RUN": the outputs are live
        or a
        jr z,.s2
        ld de,-4                ; (the "UR4/" in front of the text)
        add hl,de
.s2:    ld (st_right),hl
        jp status_right

; ---- sim_scan: HL = elapsed ticks; one PLC scan, errors stop the simulation
sim_scan:
        ld (vm_dt),hl
        call sim_inputs
        BCALL vm_scan
        ret nc
        xor a
        ld (sm_run),a
        call sim_state
        ld hl,(vm_err)
        jp ui_error

; ---- sim_inputs: toggled inputs + SYMBOL SHIFT + 0-7 held (push buttons);
;      key n = input %IX0.n
sim_inputs:
        ld e,0
        ld a,0x7F
        in a,(0xFE)
        bit 1,a
        jr nz,.no
        ld a,0xF7               ; keys 1-5 -> bits 1-5
        in a,(0xFE)
        cpl
        and 0x1F
        add a,a
        ld e,a
        ld a,0xEF               ; keys 0 (bit 0), 6 (bit 4), 7 (bit 3)
        in a,(0xFE)
        cpl
        bit 0,a
        jr z,.k6
        set 0,e
.k6:    bit 4,a
        jr z,.k7
        set 6,e
.k7:    bit 3,a
        jr z,.no
        set 7,e
.no:    ld hl,(sim_tog)         ; push buttons on the selected byte
        ld a,(sm_ib)
        or a
        jr nz,.b1
        ld a,l
        or e
        ld l,a
        jr .st
.b1:    ld a,h
        or e
        ld h,a
.st:    ld a,(ur_on)            ; the UR-4: PA -> %IX0, PB -> %IX1
        or a
        jr z,.st2
        in a,(0x1F)
        or l
        ld l,a
        in a,(0x3F)
        or h
        ld h,a
.st2:   ld (RT_I),hl
        ret

; ---- ur_out: %QX0 to the UR-4 port PC while running, otherwise 0
ur_out: ld a,(sm_run)
        or a
        jr z,ur_out0
        ld a,(RT_Q)
ur_out0:
        ld b,a
        ld a,(ur_on)
        or a
        ret z
        ld a,b
        out (0x5F),a
        ret

; ---- sim_dim: the half of the panel the keys act on (its input byte, the
;      outputs and numbers of that byte) gets a bright white paper
sim_dim:
        ld b,ROW_IN
        ld e,ATTR_LED_I
        call .row
        ld b,ROW_OUT
        ld e,ATTR_LED_Q
.row:   ld c,0
.l:     push bc
        push de
        ld a,(sm_ib)            ; byte of this cell = c / 8: active -> BRIGHT
        rlca
        rlca
        rlca
        xor c
        and 8
        jr nz,.n
        set 6,e
.n:     ld a,c
        add a,a
        add a,LED_COL0
        ld c,a
        ld d,1
        push de
        push bc
        call scr_fill_attr      ; LED cell
        pop bc
        pop de
        inc c                   ; number cell: black on white
        ld a,e
        and 0x40
        or ATTR_NORMAL
        ld e,a
        call scr_fill_attr
        pop de
        pop bc
        inc c
        ld a,c
        cp 16
        jr c,.l
        ret

; ---- sim_chk_called: the monitored POU is not MAIN and nothing calls it
;      -> popup (only MAIN runs in the simulation)
sim_chk_called:
        ld a,(cur_pou)
        or a
        ret z
        BCALL cp_is_called
        ret z                   ; called
.warn:  ld de,sm_msg            ; "NAME is not called by MAIN." ...
        ld a,(cur_pou)
        call pou_entry
        call name_unpad
        ld hl,txt_sm_ncall
        ld bc,txt_sm_ncall_e-txt_sm_ncall
        ldir
        ld hl,sm_msg
        jp msg_box

txt_sm_ncall:
        db " is not called by MAIN.",0
        db "Only MAIN runs in the simulation,",0
        db "call this POU from MAIN (IL: CAL).",0
        db 0
txt_sm_ncall_e:

; ---- sim_draw_panel: separator, LED rows, hints
sim_draw_panel:
        ; separator line on pixel line 3 of ROW_SEP
        ld bc,ROW_SEP*256
        call pix_addr
        inc h
        inc h
        inc h
        ld b,32
.sep:   ld (hl),0xFF
        inc l
        djnz .sep
        ld b,ROW_IN
        ld e,ATTR_LED_I
        call .row
        ld b,ROW_OUT
        ld e,ATTR_LED_Q
        call .row
        call sim_digits
        call sim_dim
        ld a,0xFF               ; force the LEDs to be drawn
        ld (sm_lf),a
        ret
.row:   ld c,0                  ; LED cells coloured (bytes 0, 1)
.lbl:   push bc
        push de
        ld a,c
        add a,a
        add a,LED_COL0
        ld c,a
        ld d,1
        call scr_fill_attr
        pop de
        pop bc
        inc c
        ld a,c
        cp 16
        jr c,.lbl
        ret

; ---- sim_digits: the numbers 0-7 0-7 next to the LEDs of both rows
sim_digits:
        ld b,ROW_IN
        call .row
        ld b,ROW_OUT
.row:   ld c,0
.d:     push bc
        ld a,c                  ; clear the number cell
        add a,a
        add a,LED_COL0+1
        ld c,a
        call pix_addr
        ld b,8
.z:     ld (hl),0
        inc h
        djnz .z
        pop bc
        push bc
        ld a,b
        ld (pt_row),a
        ld a,c
        add a,a
        add a,LED_COL0+1
        add a,a
        add a,a
        add a,a
        inc a
        ld (pt_x),a
        ld a,c
        and 7
        add a,'0'
        call pt_putc
        pop bc
        inc c
        ld a,c
        cp 16
        jr c,.d
        ret

; ---- sim_draw_list: listing rows 1-19 + monitor descriptors
sim_draw_list:
        ld a,(sm_page)          ; watch / trend page
        or a
        jr z,.prog
        dec a
        jr nz,.tr
        BCALL wt_draw
        ret
.tr:    BCALL tr_draw
        ret
.prog:  ld a,(sm_mon)
        cp 4
        jr z,.st
        cp 2
        jr c,.nld
        ld a,(sm_top)           ; LD / FBD diagram
        ld (ld_top),a
        ld a,(sm_mon)
        cp 3
        jr z,.fbd
        call ld_draw_view
        jp ld_set_state
.fbd:   BCALL fb_draw_view
        BCALL fb_set_state
        ret
.nld:   or a
        jr nz,.go
        ld a,3
        ld (pt_row),a
        ld a,8
        ld (pt_x),a
        ld hl,txt_sm_nomon
        jp pt_puts
.go:    ld hl,(il_cur)
        push hl
        ld hl,0xFFFF            ; no current line while monitoring
        ld (il_cur),hl
        xor a
        ld (sm_r),a
.l:     ld a,(sm_r)
        ld e,a
        ld d,0
        ld hl,(sm_top)
        add hl,de
        ex de,hl
        add a,IL_ROW0
        ld b,a
        call il_draw_row
        call sim_mon_desc
        ld hl,sm_r
        inc (hl)
        ld a,(hl)
        cp SIM_ROWS
        jr c,.l
        pop hl
        ld (il_cur),hl
        ret
.st:    xor a                   ; ST: the lines (st_edit.asm), each with its
        ld (sm_r),a             ; assignment target / condition operand
.sl:    ld a,(sm_r)
        ld e,a
        ld d,0
        ld hl,(sm_top)
        add hl,de
        ex de,hl
        add a,IL_ROW0
        ld b,a
        BCALL st_sim_row        ; -> rd_o: the value fields of the line
        call stm_addr           ; -> stm_tab row sm_r (4 entries)
        ex de,hl
        ld hl,rd_o
        ld b,STM_PER
.fc:    ld a,(hl)
        cp 0xFF
        jr z,.fe
        push bc
        ld bc,5                 ; [col][mode][addr][mask]
        ldir
        pop bc
        dec de                  ; (mode: bit 7 = draw it)
        dec de
        dec de
        dec de
        ex de,hl
        set 7,(hl)
        inc hl
        inc hl
        inc hl
        inc hl
        inc hl                  ; (past the last value)
        inc hl
        ex de,hl
        djnz .fc
        jr .fd
.fe:    ld a,0xFF               ; the rest: unused
        ld (de),a
        push hl
        ld hl,STM_ESZ
        add hl,de
        ex de,hl
        pop hl
        djnz .fe
.fd:
        ld hl,sm_r
        inc (hl)
        ld a,(hl)
        cp SIM_ROWS
        jr c,.sl
        ret

; sim_mon_desc: after il_draw_row (rd_m/rd_o/dr_kind) -> descriptor of row sm_r
sim_mon_desc:
        call sim_desc_addr
        ld (hl),0               ; mode 0 = nothing to show
        ld a,(dr_kind)
        cp K_INSTR
        ret nz
        ld a,(rd_o)
        or a
        ret z
        ld hl,rd_m
        call il_mnem_find
        ret c
        ld a,(il_mclass)
        and 0x7F
        cp IC_LABEL
        ret z
        cp IC_CALL
        jr nz,sim_mon_op
        ld hl,rd_o              ; CAL of a timer: its ET ("NAME(..." ->
.cn:    ld a,(hl)               ; "NAME.ET"; POU calls do not resolve)
        or a
        jr z,.ce
        cp '('
        jr z,.ce
        inc hl
        jr .cn
.ce:    ld (hl),'.'
        inc hl
        ld (hl),'E'
        inc hl
        ld (hl),'T'
        inc hl
        ld (hl),0
; sim_mon_op: the operand text rd_o -> descriptor of row sm_r (if shown)
sim_mon_op:
        ld hl,rd_o
        call cp_operand
        ret c
        ld a,(cp_mode)
        cp VM_MB
        jr z,.ok
        cp VM_MBY               ; (a BYTE global: shown as a word)
        jr z,.ok
        cp VM_MW
        ret nz
.ok:    call sim_desc_addr
        ld a,(cp_istime)
        rrca
        rrca                    ; bit 6: TIME value
        ld b,a
        ld a,(cp_mode)
        or b
        or 0x80                 ; bit 7: value must be drawn
        ld (hl),a
        inc hl
        ld de,(cp_arg)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(cp_arg3)
        ld (hl),a
        ret

; HL = RT_MON + sm_r * 6
sim_desc_addr:
        ld a,(sm_r)
        ld l,a
        add a,a
        add a,l
        add a,a
        ld l,a
        ld h,0
        ld de,RT_MON
        add hl,de
        ret

; ---- sim_update: redraws changed values and LEDs
sim_update:
        ld a,(sm_page)
        or a
        jr z,.prog
        dec a                   ; (the trend draws in tr_tick)
        jp nz,.leds
        BCALL wt_update
        jr .leds
.prog:  ld a,(sm_mon)
        cp 4
        jr nz,.nst
        call stm_update
        jr .leds
.nst:
        cp 2
        jr c,.nld
        jr z,.ld
        BCALL fb_set_state
        jr .leds
.ld:    call ld_set_state
        jr .leds
.nld:   or a
        jr z,.leds
.mon:   xor a
        ld (sm_r),a
.l:     call sim_desc_addr
        ld a,(hl)
        or a
        jr z,.next
        push hl
        pop ix
        call sim_chk
        call nz,sim_draw_val
.next:  ld hl,sm_r
        inc (hl)
        ld a,(hl)
        cp SIM_ROWS
        jr c,.l
.leds:  ld hl,(RT_I)
        ld de,sm_li
        ld b,ROW_IN
        call .led16
        ld hl,(RT_Q)
        ld de,sm_lq
        ld b,ROW_OUT
        call .led16
        xor a
        ld (sm_lf),a
        ret
.led16: ld (sm_lv),hl           ; HL = state, DE = last drawn state
        ld a,(sm_lf)
        or a
        jr nz,.chg
        ex de,hl
        ld a,(sm_lv)
        cp (hl)
        jr nz,.chg0
        inc hl
        ld a,(sm_lv+1)
        cp (hl)
        dec hl
        ret z
.chg0:  ex de,hl
.chg:   ld hl,(sm_lv)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,b
        ld (pt_row),a
        ld a,(sm_lv)
        ld c,a
        ld e,LED_COL0
        call .led8
        ld a,(sm_lv+1)
        ld c,a
        ld e,LED_COL1
.led8:  ld b,8
.lb:    push bc
        push de
        ld a,(pt_row)
        ld b,a
        ld c,e
        call pix_addr
        ld b,8
.lc:    ld (hl),0
        inc h
        djnz .lc
        pop de
        pop bc
        ld a,e
        add a,a
        add a,a
        add a,a
        inc a
        ld (pt_x),a
        ld a,CH_LEDOFF
        srl c
        jr nc,.off
        ld a,CH_LEDON
.off:   call pt_putc
        inc e
        inc e
        djnz .lb
        ret

; sim_chk: IX = value descriptor [mode][addr lo hi][mask][last lo hi]
;      (mode bit 7: draw it, bit 6: TIME, bit 5: a local in the RUN bank)
;      -> NZ if it must be drawn (the value stored in last)
sim_chk:
        ld a,(ix+0)
        ld l,(ix+1)
        ld h,(ix+2)
        and 0x3F
        bit 5,a
        jr z,.nb
        push af
        BCALL st_lvrd           ; a local (RUN bank): a copy in rd_c
        pop af
        and 0x1F
.nb:    cp VM_MB
        jr nz,.w
        call rt_byte            ; (a global: in the RUN bank)
        and (ix+3)
        ld de,0
        jr z,.cmp
        inc e
        jr .cmp
.w:     call rt_byte
        ld e,a
        inc hl
        call rt_byte
        ld d,a
.cmp:   bit 7,(ix+0)
        jr nz,.draw
        ld a,(ix+4)
        cp e
        jr nz,.draw
        ld a,(ix+5)
        cp d
        ret z
.draw:  res 7,(ix+0)
        ld (ix+4),e
        ld (ix+5),d
        or 1
        ret

; ---- ST: a value field right behind each variable of a line (cells from
;      st_sim_row): stm_tab row r = STM_PER entries [col][descriptor]
STM_PER EQU 4
STM_ESZ EQU 7

; stm_addr: HL = stm_tab + sm_r * STM_PER * STM_ESZ
stm_addr:
        ld a,(sm_r)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de               ; * 28
        ld de,stm_tab
        add hl,de
        ret

; stm_update: redraws the changed values of the ST listing
stm_update:
        xor a
        ld (sm_r),a
.r:     call stm_addr
        ld b,STM_PER
.e:     push bc
        push hl
        ld a,(hl)
        cp 0xFF
        jr z,.n
        inc hl
        push hl
        pop ix
        call sim_chk
        call nz,stm_draw
.n:     pop hl
        ld de,STM_ESZ
        add hl,de
        pop bc
        djnz .e
        ld hl,sm_r
        inc (hl)
        ld a,(hl)
        cp SIM_ROWS
        jr c,.r
        ret

; stm_draw: IX = descriptor (its cell at IX-1) of row sm_r -> the field:
;      BOOL 4 cells TRUE (green) / FALSE (white), INT 5 / TIME 7 cells
;      (bright cyan); the text centred
stm_draw:
        ld a,(sm_r)
        add a,IL_ROW0
        ld (pt_row),a
        ld b,a
        ld c,(ix-1)
        ld a,(ix+0)
        and 0x1F
        ld d,4
        ld e,0x78               ; FALSE: bright white
        cp VM_MB
        jr z,.w
        ld d,5
        ld e,0x68               ; INT / TIME: bright cyan
        bit 6,(ix+0)
        jr z,.w
        ld d,7
.w:     ld a,(ix+0)             ; TRUE: green
        and 0x1F
        cp VM_MB
        jr nz,.w2
        ld a,(ix+4)
        or a
        jr z,.w2
        ld e,ATTR_ON
.w2:    push bc
        push de
        call scr_fill_attr
        pop de
        pop bc
        push bc
        push de
        ld a,c                  ; the pixels cleared
        add a,a
        add a,a
        add a,a
        ld c,a
        ld a,d
        add a,a
        add a,a
        add a,a
        ld d,a
        ld hl,0x0008
        ld e,PX_CLR
        call px_span
        pop de
        pop bc
        ld a,(ix+0)             ; the text
        and 0x1F
        cp VM_MB
        jr nz,.num
        ld hl,kw_false
        ld a,(ix+4)
        or a
        jr z,.ctr
        ld hl,txt_sm_true
        jr .ctr
.num:   push bc
        push de
        ld l,(ix+4)
        ld h,(ix+5)
        ld de,sm_num
        bit 6,(ix+0)
        jr nz,.t
        call itoa16
        jr .n
.t:     ld a,AR_KT              ; "T#1s260ms" without "T#"
        ld b,0
        call op_format
.n:     pop de
        pop bc
        ld hl,sm_num
        bit 6,(ix+0)
        jr z,.ctr
        inc hl
        inc hl
.ctr:   call pt_width           ; centred: x = field x + (width - text) / 2
        ld e,a
        ld a,d
        add a,a
        add a,a
        add a,a
        sub e
        jr nc,.c1
        xor a
.c1:    srl a
        ld e,a
        ld a,c
        add a,a
        add a,a
        add a,a
        add a,e
        inc a
        ld (pt_x),a
        jp pt_puts

stm_tab: ds SIM_ROWS*STM_PER*STM_ESZ

; ---- sim_draw_val: IX = descriptor (value in +4/+5), row sm_r
sim_draw_val:
        ld a,(sm_r)
        add a,IL_ROW0
        ld (pt_row),a
        ld b,a
        ld c,SIM_VCOL
        call pix_addr
        ld e,8
.cl:    push hl
        ld b,32-SIM_VCOL
        xor a
.z:     ld (hl),a
        inc l
        djnz .z
        pop hl
        inc h
        dec e
        jr nz,.cl
        ; value cells black on white; TRUE: black on bright green
        ld a,(pt_row)
        ld b,a
        ld c,SIM_VCOL
        ld d,32-SIM_VCOL
        ld e,ATTR_NORMAL
        call scr_fill_attr
        ld a,(ix+0)
        and 0x3F
        cp VM_MB
        jr nz,.int
        ld hl,kw_false
        ld a,(ix+4)
        or a
        jr z,.p
        ld a,(pt_row)
        ld b,a
        ld c,28
        ld de,0x0400+ATTR_ON
        call scr_fill_attr
        ld hl,txt_sm_true
        jr .p
.int:   ld l,(ix+4)
        ld h,(ix+5)
        ld de,sm_num
        bit 6,(ix+0)
        jr nz,.time
        call itoa16
        jr .num
.time:  ld a,AR_KT              ; "T#1s260ms"
        ld b,0
        call op_format
.num:   ld hl,sm_num
.p:     ld a,SIM_X_VAL
        jp pt_puts_r

              db "UR4/"
txt_sm_run:   db "RUN",0
              db "UR4/"
txt_sm_stop:  db "STOP",0
txt_sm_true:  db "TRUE",0
txt_wt_hint:  db ST_INV,"ENTER",ST_INV,"Edit ",ST_INV,"F",ST_INV,"orce ",ST_INV,"W",ST_INV,"rite ",ST_INV,"DEL",ST_INV,"ete ",ST_INV,"T",ST_INV,"rend ",ST_INV,"M",ST_INV,"onitor",0
txt_tr_hint:  db ST_INV,"0-7",ST_INV,"In ",ST_INV,"R",ST_INV,"un ",ST_INV,"Z",ST_INV,"oom ",ST_INV,"W",ST_INV,"atch ",ST_INV,"M",ST_INV,"onitor",0
txt_sm_hint:  db ST_INV,"0-7",ST_INV,"In ",ST_INV,"SS+n",ST_INV,"Set ",ST_INV,"B",ST_INV,"yte ",ST_INV,"R",ST_INV,"unStop ",ST_INV,"S",ST_INV,"tep R",ST_INV,"E",ST_INV,"set ",ST_INV,"W",ST_INV,"atch",0
txt_sm_nomon: db "No IL or LD POU to monitor.",0

sim_tog:    dw 0              ; toggled inputs I0, I1
sm_page:    db 0              ; 0 program listing, 1 watch / force table
sm_ib:      db 0              ; input byte of the keys 0-7
sm_lf:      db 0              ; LEDs: redraw all
sm_lv:      dw 0
sm_mon:     db 0
sm_ok:      db 0
sm_run:     db 0
sm_r:       db 0
sm_li:      dw 0
sm_lq:      dw 0
sm_top:     dw 0
sm_lastf:   dw 0
sm_savecur: dw 0
sm_num:     ds 16
sm_msg:     ds 100
