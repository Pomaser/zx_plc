; ============================================================
; sound.asm - AY-3-8912 sound effects (128K), played by the ISR
; ============================================================
; An effect is a table of frames [volume][period lo][period hi];
; volume 0 ends it. Channel A plays the key click (noise, fast envelope decay),
; channel B the error sound (soft low tone).

AY_SEL  EQU 0xFFFD
AY_DATA EQU 0xBFFD

; ---- ay_out: A = register, E = value (keeps all but F)
ay_out: push bc
        ld bc,AY_SEL
        out (c),a
        ld b,AY_DATA>>8
        out (c),e
        pop bc
        ret

; ---- snd_init: silence
snd_init:
        ld d,13
.l:     ld a,d
        ld e,0
        cp 7
        jr nz,.w
        ld e,0xFF               ; mixer: everything off
.w:     call ay_out
        dec d
        jp p,.l
        ld a,6
        ld e,10                 ; noise period of the click
        jp ay_out

; ---- snd_click / snd_error: start an effect (keep all registers)
snd_click:                      ; (called from the ISR only)
        push af
        push de
        push hl
        ld hl,snd_tclick
        ld (snd_a),hl
        ld a,11                 ; envelope: fast decay (~9 ms)
        ld e,4
        call ay_out
        ld a,12
        ld e,0
        call ay_out
        ld a,13                 ; shape \___, writing it restarts the envelope
        call ay_out
        pop hl
        pop de
        pop af
        ret
snd_error:
        push hl
        ld hl,snd_terr
        ld (snd_b),hl
        pop hl
        ret

; ---- snd_isr: one frame of both channels (called from the ISR)
snd_isr:
        ld a,(snd_on)
        or a
        jr nz,.on
        ld h,a                  ; sound off: stop the effects
        ld l,a
        ld (snd_a),hl
        ld (snd_b),hl
.on:    ld d,0xFF               ; mixer
        ld hl,snd_a
        ld c,0
        call snd_chan
        jr z,.nb
        ld d,0xF7               ; noise A
.nb:    ld hl,snd_b
        ld c,1
        call snd_chan
        jr z,.mix
        res 1,d                 ; tone B
.mix:   ld e,d
        ld a,7
        jp ay_out

; ---- snd_chan: HL = effect pointer variable, C = channel (0 = A, 1 = B)
;      -> NZ if the channel sounds in this frame (keeps D)
snd_chan:
        push de
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or h
        jr z,.done              ; idle (Z)
        ld a,c
        add a,8
        ld e,(hl)               ; volume
        call ay_out
        inc hl
        ld a,e
        or a
        jr z,.end
        ld a,c
        add a,a
        ld e,(hl)
        call ay_out             ; period lo
        inc hl
        inc a
        ld e,(hl)
        call ay_out             ; period hi
        inc hl
        ld e,l
        ld d,h
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        pop de
        or 0xFF                 ; NZ
        ret
.end:   ld e,a                  ; A = 0: pointer = 0
        pop hl
        ld (hl),a
        inc hl
        ld (hl),a
        pop de
        ret                     ; Z
.done:  pop hl
        pop de
        ret

; key click: noise burst shaped by the envelope (volume 16 = envelope)
snd_tclick:
        db 16, 0,0
        db 0
; error: soft two-note "du-dum", fading
snd_terr:
        db 8, 0x2A,0x02
        db 8, 0x2A,0x02
        db 6, 0x2A,0x02
        db 4, 0x2A,0x02
        db 7, 0xE0,0x02
        db 7, 0xE0,0x02
        db 6, 0xE0,0x02
        db 5, 0xE0,0x02
        db 4, 0xE0,0x02
        db 3, 0xE0,0x02
        db 2, 0xE0,0x02
        db 0

snd_on: db 1                    ; Options > Sound
snd_a:  dw 0                    ; channel A effect pointer (0 = idle)
snd_b:  dw 0                    ; channel B
