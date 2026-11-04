; ============================================================
; sim.asm - RUN screen: simulation with live monitoring
; ============================================================
; Rows 1-18: IL listing of the monitored POU, current operand
; values on the right. Row 19 separator, rows 20/21 input and output
; LEDs, row 22 key hints. One PLC scan per frame while running.
; ============================================================
SIM_ROWS  EQU 18
SIM_VCOL  EQU 25            ; first cell of the value column
SIM_X_VAL EQU 252
ROW_SEP   EQU 19
ROW_IN    EQU 20
ROW_OUT   EQU 21
ROW_HINT  EQU 22
LED_COL0  EQU 9             ; cell of the first LED
ATTR_LED_I EQU 0x3C         ; green ink
ATTR_LED_Q EQU 0x3A         ; red ink
ATTR_BOOL  EQU 0x3B         ; dark magenta ink (TRUE/FALSE values)

scr_run:
        call screen_begin
        ; monitored POU: the current one if IL, else MAIN if IL        xor a
        ld (sm_mon),a
        ld a,(cur_pou)
        call pou_lang
        cp LANG_FBD
        jr c,.mon               ; IL or LD
        xor a
        call pou_lang
        cp LANG_FBD
        jr nc,.nomon
        xor a
        ld (cur_pou),a
        call status_draw
.mon:   ld a,(cur_pou)
        call pou_lang
        inc a
        ld (sm_mon),a           ; 1 = IL, 2 = LD
        cp 2
        jr z,.ldm
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
        call vm_reset
        xor a
        ld (sim_tog),a
        ld (sm_run),a
        call sim_state
        call il_compile
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
        jr z,.menu
        cp K_EDIT
        jr z,.menu
        cp '1'
        jr c,.letter
        cp '9'
        jr nc,.letter
        sub '1'                 ; toggle input
        ld e,a
        ld d,0
        ld hl,bit_masks
        add hl,de
        ld a,(sim_tog)
        xor (hl)
        ld (sim_tog),a
        jr .loop
.letter:
        call to_upper
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
        jr nz,.loop
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
.reset: call vm_reset
        xor a
        ld (sim_tog),a
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
        call vm_scan
        ret nc
        xor a
        ld (sm_run),a
        call sim_state
        ld hl,(vm_err)
        jp ui_error

; ---- sim_inputs: toggled inputs + SYMBOL SHIFT + 1-8 held (push buttons)
sim_inputs:
        ld e,0
        ld a,0x7F
        in a,(0xFE)
        bit 1,a
        jr nz,.no
        ld a,0xF7               ; keys 1-5
        in a,(0xFE)
        cpl
        and 0x1F
        ld e,a
        ld a,0xEF               ; keys 6 (bit 4), 7 (bit 3), 8 (bit 2)
        in a,(0xFE)
        cpl
        bit 4,a
        jr z,.k7
        set 5,e
.k7:    bit 3,a
        jr z,.k8
        set 6,e
.k8:    bit 2,a
        jr z,.no
        set 7,e
.no:    ld a,(sim_tog)
        or e
        ld (RT_I),a
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
        ld b,a
        ld hl,BCODE             ; look for CALL <slot> in the bytecode
.l:     push hl
        ld de,(cp_pc)
        or a
        sbc hl,de
        pop hl
        jr nc,.warn
        ld a,(hl)
        and 0x3F
        cp OP_CALL
        jr nz,.n
        inc hl
        ld a,(hl)
        dec hl
        cp b
        ret z                   ; called
.n:     ld de,5
        add hl,de
        jr .l
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
        ld hl,txt_sm_in
        ld b,ROW_IN
        ld e,ATTR_LED_I
        call .row
        ld hl,txt_sm_out
        ld b,ROW_OUT
        ld e,ATTR_LED_Q
        call .row
        ld a,ROW_HINT
        ld (pt_row),a
        ld a,4
        ld (pt_x),a
        ld hl,txt_sm_hint
        call pt_puts
        ld a,0xFF               ; force the LEDs to be drawn
        ld (sm_li),a
        ld (sm_lq),a
        ret
.row:   push de
        ld a,b
        ld (pt_row),a
        ld a,4
        ld (pt_x),a
        push bc
        call pt_puts
        pop bc
        pop de
        ; LED cells coloured, labels 0-7 next to them
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
        add a,'0'
        call pt_putc
        inc c
        ld a,c
        cp 8
        jr c,.lbl
        ret

; ---- sim_draw_list: listing rows 1-18 + monitor descriptors
sim_draw_list:
        ld a,(sm_mon)
        cp 2
        jr nz,.nld
        ld a,(sm_top)           ; LD diagram
        ld (ld_top),a
        call ld_draw_view
        jp ld_set_state
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
        jr nz,.nld
        call ld_set_state
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
.leds:  ld a,(RT_I)
        ld hl,sm_li
        ld b,ROW_IN
        call .led8
        ld a,(RT_Q)
        ld hl,sm_lq
        ld b,ROW_OUT
.led8:  cp (hl)
        ret z
        ld (hl),a
        ld c,a
        ld a,b
        ld (pt_row),a
        ld b,8
        ld e,LED_COL0
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
        ; value cells: dark magenta for BOOL, black for INT
        ld a,(pt_row)
        ld b,a
        ld c,SIM_VCOL
        ld d,32-SIM_VCOL
        ld e,ATTR_NORMAL
        ld a,(ix+0)
        and 0x3F
        cp VM_MB
        jr nz,.at
        ld e,ATTR_BOOL
.at:    call scr_fill_attr
        ld a,(ix+0)
        and 0x3F
        cp VM_MB
        jr nz,.int
        ld hl,kw_false
        ld a,(ix+4)
        or a
        jr z,.p
        ld hl,txt_sm_true
        ld a,SIM_X_VAL
        call pt_puts_r
        ; TRUE: inverted
        ld a,(pt_row)
        ld b,a
        ld c,SIM_X_VAL-21
        ld d,23
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span
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
txt_sm_in:    db "Inputs",0
txt_sm_out:   db "Outputs",0
txt_sm_hint:  db "1-8 toggle, SS+1-8 push, R run/stop, S step, E reset",0
txt_sm_nomon: db "No IL or LD POU to monitor.",0
txt_sm_err:   db "Error in ",0
txt_sm_line:  db ", line ",0

sim_pending: db 0
sim_tog:    db 0
sm_mon:     db 0
sm_ok:      db 0
sm_run:     db 0
sm_r:       db 0
sm_li:      db 0
sm_lq:      db 0
sm_top:     dw 0
sm_lastf:   dw 0
sm_savecur: dw 0
sm_num:     ds 16
sm_msg:     ds 100
