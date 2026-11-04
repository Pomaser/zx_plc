; ============================================================
; keyboard.asm - custom keyboard driver with autorepeat
; ============================================================
KB_DELAY  EQU 18            ; frames before first repeat
KB_RATE   EQU 3             ; frames between repeats

; ---- kb_scan: E = key index (row*5+bit) or 0xFF, D = bit0 CS, bit1 SS
kb_scan:
        ld de,0x00FF
        ld bc,0xFEFE
        ld l,0
.row:   in a,(c)
        cpl
        and 0x1F
        ld h,a
        ld a,l
        or a
        jr nz,.n0
        bit 0,h
        jr z,.n0
        set 0,d
        res 0,h
.n0:    ld a,l
        cp 35
        jr nz,.n7
        bit 1,h
        jr z,.n7
        set 1,d
        res 1,h
.n7:    ld a,h
        or a
        jr z,.next
        ld a,l
.bit:   srl h
        jr c,.found
        inc a
        jr .bit
.found: ld e,a
.next:  ld a,l
        add a,5
        ld l,a
        rlc b
        jr c,.row
        ret

; ---- kb_read: A = code of the pressed key or 0
kb_read:
        call kb_scan
        ld a,e
        cp 0xFF
        jr z,.none
        ld a,d                  ; CS+SS+5..8 = SS + cursor key: jumps
        cp 3
        jr nz,.tab
        ld a,e
        sub 19                  ; key 5
        jr z,.home
        sub 3                   ; 8
        jr z,.end
        dec a                   ; 7
        jr z,.pgup
        dec a                   ; 6
        jr nz,.tab
        ld a,K_PGDN
        ret
.home:  ld a,K_HOME
        ret
.end:   ld a,K_END
        ret
.pgup:  ld a,K_PGUP
        ret
.tab:   ld hl,kt_norm
        bit 1,d
        jr z,.nss
        ld hl,kt_sym
        jr .look
.nss:   bit 0,d
        jr z,.look
        ld hl,kt_caps
.look:  ld c,e
        ld b,0
        add hl,bc
        ld a,(hl)
        ret
.none:  xor a
        ret

; ---- kb_poll: edge detection + autorepeat, called once per frame from the ISR.
;      A = new key or repeat (kb_rep = 1) or 0
kb_poll:
        xor a
        ld (kb_rep),a
        call kb_read
        or a
        jr nz,.some
        ld (kb_last),a
        ret
.some:  ld hl,kb_last
        cp (hl)
        jr z,.same
        ld (hl),a
        ld b,a
        ld a,KB_DELAY
        ld (kb_cnt),a
        ld a,b
        ret
.same:  ld b,a
        ld hl,kb_cnt
        dec (hl)
        jr nz,.no
        ld (hl),KB_RATE
        ld a,1
        ld (kb_rep),a
        ld a,b
        ret
.no:    xor a
        ret

; ---- kb_isr: polls the keyboard and queues the key (all registers kept by caller)
;      a repeat is queued only when the queue is empty (no run-on after release)
kb_isr:
        call kb_poll
        or a
        ret z
        ld c,a
        ld a,(kb_head)
        ld b,a
        ld a,(kb_tail)
        ld e,a
        cp b
        jr z,.put               ; empty queue
        ld a,(kb_rep)
        or a
        ret nz                  ; drop repeats while keys are waiting
.put:   ld a,e
        inc a
        and KB_QLEN-1
        cp b
        ret z                   ; queue full
        ld d,0
        ld hl,kb_q
        add hl,de
        ld (hl),c
        ld (kb_tail),a
        jp snd_click            ; key click

; ---- kb_get: A = next queued key or 0
kb_get:
        ld a,(kb_tail)
        ld b,a
        ld a,(kb_head)
        cp b
        jr z,.none
        ld e,a
        ld d,0
        ld hl,kb_q
        add hl,de
        inc a
        and KB_QLEN-1
        ld (kb_head),a
        ld a,(hl)
        ret
.none:  xor a
        ret

; ---- kb_wait: waits for a queued key, A = code
kb_wait:
        call kb_get
        or a
        ret nz
        halt
        jr kb_wait

; ---- kb_flush: waits until no key is held, then empties the queue
kb_flush:
        halt
        call kb_read
        or a
        jr nz,kb_flush
        ld (kb_head),a
        ld (kb_tail),a
        ret

KB_QLEN EQU 8
kb_q:    ds KB_QLEN
kb_head: db 0
kb_tail: db 0
kb_rep:  db 0
kb_last: db 0
kb_cnt:  db 0

; rows:  CS Z X C V | A S D F G | Q W E R T | 1 2 3 4 5
;        0 9 8 7 6 | P O I U Y | EN L K J H | SP SS M N B
kt_norm:
        db 0,'z','x','c','v'
        db 'a','s','d','f','g'
        db 'q','w','e','r','t'
        db '1','2','3','4','5'
        db '0','9','8','7','6'
        db 'p','o','i','u','y'
        db K_ENTER,'l','k','j','h'
        db ' ',0,'m','n','b'
kt_caps:
        db 0,'Z','X','C','V'
        db 'A','S','D','F','G'
        db 'Q','W','E','R','T'
        db K_EDIT,0,0,0,K_LEFT
        db K_DEL,0,K_RIGHT,K_UP,K_DOWN
        db 'P','O','I','U','Y'
        db K_ENTER,'L','K','J','H'
        db K_BREAK,0,'M','N','B'
kt_sym:
        db 0,':',0x60,'?','/'
        db 0,0,0,0,0
        db 0,0,0,'<','>'
        db '!','@','#','$','%'
        db '_',')','(',0x27,'&'
        db '"',';',0,0,0
        db K_SSENTER,'=','+','-','^'
        db ' ',0,'.',',','*'
