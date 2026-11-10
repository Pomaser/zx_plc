; ============================================================
; sd.asm - saving / loading the project on an SD card (RUN bank)
; ============================================================
; A divMMC with esxDOS: File > Save SD... / Load SD... (tape_save /
; tape_load with A = CMD_SAVE_SD / CMD_LOAD_SD; without a divMMC, found by
; sd_present, they report an error). The project is a file NAME.PLC in
; the current folder of the default drive, the same bytes as the data
; block on tape (PROJ, P_LEN bytes). Loading lists the .PLC files.
; esxDOS calls: RST 8 + function byte, A = drive / handle, HL (and IX,
; which dot commands use) = name / buffer, B = mode, BC = length; CF set
; on an error with A = the error code.
; ============================================================
M_DOSVERSION EQU 0x88
F_OPEN      EQU 0x9A
F_CLOSE     EQU 0x9B
F_READ      EQU 0x9D
F_WRITE     EQU 0x9E
F_OPENDIR   EQU 0xA3
F_READDIR   EQU 0xA4
FA_READ     EQU 0x01
FA_WRITE    EQU 0x02
FA_CREATE_AL EQU 0x0C       ; create, or truncate an existing file
SD_MAX      EQU 16          ; files listed
SD_NLEN     EQU 9           ; a name in the list: 8 characters + 0

    MACRO ESX fn
        rst 8
        db fn
    ENDM

; ---- sd_present: NZ = esxDOS is there: a divMMC whose memory (CONMEM,
;      port 0xE3 bit 7, maps the EEPROM at 0x0000 for a moment) holds the
;      text "ESXDOS", and RST 8 reaches it (sd_probe). An empty EEPROM or
;      a disabled automap would crash on RST 8
sd_present:
        di
        ld a,0x80
        out (0xE3),a
        ld hl,0
        ld bc,0x2000
.f:     ld a,'E'
        cpir
        jr nz,.no               ; (no more 'E')
        push hl
        push bc
        ld de,txt_sd_sig
        ld b,5
.c:     ld a,(de)
        cp (hl)
        jr nz,.m
        inc hl
        inc de
        djnz .c
.m:     pop bc
        pop hl
        jr z,.yes
        ld a,b
        or c
        jr nz,.f
.no:    ld c,0
        jr .e
.yes:   ld c,1
.e:     xor a
        out (0xE3),a
        ei
        ld a,c
        or a
        ret z
        ; fall through: does it also answer? (no automap: a ROM error)

; sd_probe: NZ = esxDOS answers RST 8 (M_DOSVERSION). Without automap
;      (e.g. the EEPROM write enabled) RST 8 is the ROM error report: ERR_SP
;      points at .fail for it, which the ROM returns to (it also writes
;      ERR_NR through IY and STKEND / MEM: system variables only)
sd_probe:
        push iy
        ld iy,0x5C3A
        ld hl,(0x5C3D)          ; ERR_SP
        push hl
        ld hl,.fail
        push hl
        ld (0x5C3D),sp
        ESX M_DOSVERSION
        pop hl                  ; (.fail)
        ld c,1
        jr .e
.fail:  ld c,0                  ; (SP as after the pop above)
.e:     pop hl
        ld (0x5C3D),hl
        pop iy
        ld a,c
        or a
        ret

; sd_nodev: no divMMC: an error, A = 0
sd_nodev:
        ld hl,txt_sd_nodev
        call ui_error
        xor a
        ret

; ---- sd_save: File > Save SD...
sd_save:
        call sd_present
        jr z,sd_nodev
        ld hl,txt_sd_nameq
        call popup_open
        ld a,(win_r)
        add a,2
        ld b,a
        ld a,(win_bx)
        add a,8
        ld c,a
        ld hl,sd_name
        ld de,0x0801            ; 8 characters, upper case
        call ui_input
        push af
        call win_close
        pop af
        ret c
        ld a,(sd_name)
        or a
        ret z
        ld hl,sd_name
        call sd_fname
        ld hl,txt_sd_badn
        jp c,ui_error
        ld a,'*'                ; an existing file: overwrite?
        ld b,FA_READ
        call sd_open
        jr c,.new
        ESX F_CLOSE
        ld hl,txt_sd_over
        call ui_confirm
        ret nz
.new:   ld a,'*'
        ld b,FA_WRITE|FA_CREATE_AL
        call sd_open
        jr c,sd_err
        ld (sd_h),a
        ld hl,PROJ
        ld ix,PROJ
        ld bc,(PROJ+P_LEN)
        ESX F_WRITE
        push af
        push bc
        ld a,(sd_h)
        ESX F_CLOSE
        pop bc
        pop af
        jr c,sd_err
        ld hl,(PROJ+P_LEN)      ; all written?
        or a
        sbc hl,bc
        ld a,0
        jr nz,sd_err
        ld hl,txt_tp_ok
        jp msg_box

; sd_err: A = esxDOS error code -> "SD card error n"
sd_err: call sd_etext
        jp ui_error

; sd_etext: A = error code -> HL = "SD card error n"
sd_etext:
        ld l,a
        ld h,0
        ld de,sd_enum
        call itoa16
        xor a
        ld (de),a
        ld hl,txt_sd_err
        ret

; sd_open: sd_fn, A = drive, B = mode -> esxDOS F_OPEN (A = handle, CF)
sd_open:
        ld hl,sd_fn
        ld ix,sd_fn
        ESX F_OPEN
        ret

; sd_fname: HL = name (1-8 characters) -> sd_fn = NAME.PLC; C: a character
;      other than A-Z, 0-9, _ and -
sd_fname:
        ld de,sd_fn
.l:     ld a,(hl)
        or a
        jr z,.e
        ld (de),a
        inc hl
        inc de
        cp '_'
        jr z,.l
        cp '-'
        jr z,.l
        cp '0'
        ret c
        cp '9'+1
        jr c,.l
        cp 'A'
        ret c
        cp 'Z'+1
        ccf
        ret c
        jr .l
.e:     ld hl,txt_sd_ext
        ld bc,5
        ldir
        or a
        ret

; ---- sd_load: File > Load from the SD card (tape_load has asked to
;      discard the project) -> A = command (as tape_load)
sd_load:
        call sd_list
        jr c,.er
        ld a,(sd_n)
        or a
        jr nz,.pick
        ld hl,txt_sd_none
        call ui_error
        xor a
        ret
.er:    call sd_err
        xor a
        ret
.pick:  call sd_pick
        ld a,0
        ret c
        ld a,(sd_sel)           ; the file name of item sd_sel
        ld l,a
        add a,a
        add a,a
        add a,a
        add a,l
        ld l,a
        ld h,0
        ld de,sd_files
        add hl,de
        push hl
        call sd_fname
        ld hl,tp_lhdr+1         ; and its name for "Project loaded:"
        ld b,10
.sp:    ld (hl),' '
        inc hl
        djnz .sp
        pop hl
        ld de,tp_lhdr+1
        call put_str
        ld hl,txt_sd_loading
        call popup_open
        ld a,BANK_SPARE         ; keep a copy of the project
        ld hl,PROJ
        ld de,UM_BAK
        ld bc,PROJ_END-PROJ
        call bank_copy
        BCALL um_reset          ; (the undo history is gone)
        ld a,'*'
        ld b,FA_READ
        call sd_open
        jr c,.rerr
        ld (sd_h),a
        ld hl,PROJ
        ld ix,PROJ
        ld bc,PROJ_END-PROJ
        ESX F_READ
        push af
        push bc
        ld a,(sd_h)
        ESX F_CLOSE
        pop bc
        pop af
        jr c,.rerr
        ld (tp_lhdr+11),bc      ; the length, checked like a tape block
        jp tape_load.chk
.rerr:  call sd_etext
        jp tape_load.rest

; sd_list: the .PLC files of the current folder -> sd_files, sd_n; C: A =
;      error code
sd_list:
        xor a
        ld (sd_n),a
        ld a,'*'
        ld hl,txt_sd_dir
        ld ix,txt_sd_dir
        ESX F_OPENDIR
        ret c
        ld (sd_h),a
.r:     ld a,(sd_n)
        cp SD_MAX
        jr nc,.e
        ld a,(sd_h)
        ld hl,sd_ent
        ld ix,sd_ent
        ESX F_READDIR           ; [attributes][name, 0][date][size]
        jr c,.e
        or a
        jr z,.e                 ; (no more entries)
        ld a,(sd_ent)
        and 0x10                ; a folder
        jr nz,.r
        ld a,(sd_n)             ; NAME.PLC: NAME into the list
        ld l,a
        add a,a
        add a,a
        add a,a
        add a,l
        ld e,a
        ld d,0
        ld hl,sd_files
        add hl,de
        ex de,hl                ; DE = list entry
        ld hl,sd_ent+1
        ld b,SD_NLEN
.n:     ld a,(hl)
        cp '.'
        jr z,.dot
        or a
        jr z,.r                 ; no extension
        ld (de),a
        inc hl
        inc de
        djnz .n
        jr .r                   ; name too long
.dot:   xor a
        ld (de),a
        ld de,txt_sd_ext        ; the extension, any case
        ld b,5
.x:     ld a,(hl)
        call to_upper
        ex de,hl
        cp (hl)
        ex de,hl
        jr nz,.r
        inc hl
        inc de
        djnz .x
        ld hl,sd_n
        inc (hl)
        jr .r
.e:     ld a,(sd_h)
        ESX F_CLOSE
        or a
        ret

; sd_pick: the list of sd_files -> NC: sd_sel = the chosen one; C: cancelled
sd_pick:
        ld hl,txt_sd_list       ; popup text: the title and the names
        ld de,sd_txt
        call sd_line
        ld hl,sd_files
        ld a,(sd_n)
        ld b,a
.t:     push bc
        push hl
        call sd_line
        pop hl
        ld bc,SD_NLEN
        add hl,bc
        pop bc
        djnz .t
        xor a
        ld (de),a
        ld (sd_sel),a
        ld hl,sd_txt
        call popup_open
.bar:   call .inv
.k:     call kb_wait
        cp K_MOUSE              ; a click on a name, or outside
        jr nz,.nm
        ld a,(sd_n)
        ld b,2
        BCALL ms_item
        jr c,.can
        ld (sd_sel),a
        jr .ok
.nm:    cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.dn
        cp K_ENTER
        jr z,.ok
        cp K_BREAK
        jr z,.can
        cp K_EDIT
        jr z,.can
        jr .k
.up:    ld a,(sd_sel)
        or a
        jr z,.k
        call .inv
        ld hl,sd_sel
        dec (hl)
        jr .bar
.dn:    ld a,(sd_n)
        dec a
        ld hl,sd_sel
        cp (hl)
        jr z,.k
        call .inv
        ld hl,sd_sel
        inc (hl)
        jr .bar
.can:   call win_close
        scf
        ret
.ok:    call win_close
        or a
        ret
.inv:   ld a,(win_r)            ; the selection bar (XOR)
        add a,2
        ld hl,sd_sel
        add a,(hl)
        ld b,a
        ld a,(win_bx)
        add a,4
        ld c,a
        ld a,(win_bw)
        sub 8
        ld d,a
        ld hl,0x0008
        ld e,PX_XOR
        jp px_span

; sd_line: HL = text -> copied to DE with its 0, DE past it
sd_line:
        call put_str
        xor a
        ld (de),a
        inc de
        ret

txt_sd_nodev: db "No esxDOS (divMMC) found",0
txt_sd_sig:   db "SXDOS"
txt_sd_nameq: db "File name on the SD card:",0," ",0," ",0,0
txt_sd_list:  db "Load from the SD card:",0
txt_sd_loading: db "Loading from the SD card...",0,0
txt_sd_over:  db "The file exists. Overwrite?",0
txt_sd_badn:  db "Use only A-Z, 0-9, _ and -",0
txt_sd_none:  db "No .PLC files on the SD card",0
txt_sd_err:   db "SD card error "
sd_enum:      ds 6
txt_sd_ext:   db ".PLC",0
txt_sd_dir:   db ".",0

sd_name:  db "PROJECT",0,0
sd_fn:    ds 13
sd_h:     db 0
sd_n:     db 0
sd_sel:   db 0
sd_ent:   ds 32             ; a folder entry
sd_files: ds SD_MAX*SD_NLEN
sd_txt:   ds 24+SD_MAX*SD_NLEN+1
