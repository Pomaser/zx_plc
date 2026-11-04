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
SM_RCOL   EQU 29            ; status bar: hints left, RUN / STOP from here
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
        ld (sm_mon),a           ; 1 = IL, 2 = LD, 3 = FBD
        cp 2
        jr nc,.ldm
        call il_count
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
        xor a
        ld (sim_tog),a
        ld (sim_tog+1),a
        ld (sm_ib),a
        ld (sm_run),a
        call sim_state
        BCALL il_compile
        ld a,0
        jr c,.cerr
        inc a
.cerr:  ld (sm_ok),a
        call sim_draw_panel
        call sim_draw_list
        ld a,(sm_ok)
        or a
        call z,sim_cerr
        call nz,sim_chk_called
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
.nrun:  call sim_update
        call kb_get
        or a
        jr z,.loop
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
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
        jr .loop
.letter:
        call to_upper
        cp 'B'                  ; B: the other input byte
        jr nz,.nb
        ld a,(sm_ib)
        xor 1
        ld (sm_ib),a
        call sim_mark
        jr .loop
.nb:
        cp 'R'                  ; R toggles run / stop
        jr nz,.nr
        ld b,CMD_RUN
        ld a,(sm_run)
        or a
        jr z,.c
        ld b,CMD_STOP
        jr .c
.nr:    ld b,CMD_STOP
        cp 'T'
        jr z,.c
        ld b,CMD_STEP
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
        cp CMD_REDRAW
        jr nz,.exit
        call sim_draw_list
        jp .loop
.mc:    call sim_cmd
        jp .loop
.exit:  push af
        xor a
        ld (sm_run),a           ; the simulation stops when leaving the screen
        ld hl,(sm_savecur)
        ld (il_cur),hl
        ld hl,0
        ld (st_right),hl
        pop af
        ret

; ---- sim_cmd: A = CMD_RUN, CMD_STOP, CMD_STEP, CMD_RESET
sim_cmd:
        cp CMD_RESET
        jr z,.reset
        cp CMD_STOP
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

; ---- sim_state: RUN / STOP in the status bar
sim_state:
        ld hl,txt_sm_stop
        ld a,(sm_run)
        or a
        jr z,.s
        ld hl,txt_sm_run
.s:     ld (st_right),hl
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
.st:    ld (RT_I),hl
        ret

; ---- sim_mark: a black line over the 16 cells of the selected input byte
;      (pixel line 7 of the separator row: its cells are black on white)
sim_mark:
        ld c,LED_COL0
        ld a,(sm_ib)
        or a
        call .grp
        ld c,LED_COL1
        ld a,(sm_ib)
        xor 1
.grp:   push af
        ld b,ROW_SEP
        call pix_addr
        ld de,7*256
        add hl,de               ; pixel line 7
        pop af
        ld a,0xFF
        jr z,.g
        xor a
.g:     ld b,16
.l:     ld (hl),a
        inc l
        djnz .l
        ret

; ---- sim_cerr: compile error popup "Error in NAME, line 012" + message
sim_cerr:
        ld de,sm_msg
        ld hl,txt_sm_err
        call put_str
        ld a,(cp_slot)
        call pou_entry
        call name_unpad
        ld hl,txt_sm_line
        call put_str
        ld hl,(cp_line)
        call dec3
        inc de
        ld hl,(il_err)
        call put_str
        xor a
        ld (de),a
        inc de
        ld (de),a
        ld hl,sm_msg
        call beep
        jp msg_box

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
        ld a,0xFF               ; force the LEDs to be drawn
        ld (sm_lf),a
        jp sim_mark
.row:   ld a,b                  ; 16 LEDs (bytes 0, 1), numbers 0-7 next to them
        ld (pt_row),a
        ld c,0
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
        push bc
        push de
        call pt_putc
        pop de
        pop bc
        inc c
        ld a,c
        cp 16
        jr c,.lbl
        ret

; ---- sim_draw_list: listing rows 1-19 + monitor descriptors
sim_draw_list:
        ld a,(sm_mon)
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
        ret z
        ld hl,rd_o
        call cp_operand
        ret c
        ld a,(cp_mode)
        cp VM_MB
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
        ld a,(sm_mon)
        cp 2
        jr c,.nld
        jr z,.ld
        BCALL fb_set_state
        jr .leds
.ld:    call ld_set_state
        jr .leds
.nld:   or a
        jr z,.leds
        xor a
        ld (sm_r),a
.l:     call sim_desc_addr
        ld a,(hl)
        or a
        jr z,.next
        push hl
        pop ix
        ; current value -> DE
        ld l,(ix+1)
        ld h,(ix+2)
        and 0x3F
        cp VM_MB
        jr nz,.w
        ld a,(ix+3)
        and (hl)
        ld de,0
        jr z,.cmp
        inc e
        jr .cmp
.w:     ld e,(hl)
        inc hl
        ld d,(hl)
.cmp:   bit 7,(ix+0)
        jr nz,.draw
        ld a,(ix+4)
        cp e
        jr nz,.draw
        ld a,(ix+5)
        cp d
        jr z,.next
.draw:  res 7,(ix+0)
        ld (ix+4),e
        ld (ix+5),d
        call sim_draw_val
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
        jp sim_mark             ; (the LEDs clear their cells)
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

txt_sm_run:   db "RUN",0
txt_sm_stop:  db "STOP",0
txt_sm_true:  db "TRUE",0
txt_sm_hint:  db "0-7 Force  SS+n Write  B Byte  R Run  S Step  E Res",0
txt_sm_nomon: db "No IL or LD POU to monitor.",0
txt_sm_err:   db "Error in ",0
txt_sm_line:  db ", line ",0

sim_tog:    dw 0              ; toggled inputs I0, I1
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
