; ============================================================
; keyboard.asm - vlastní čtení klávesnice s autorepeatem
; ============================================================
KB_DELAY  EQU 18            ; snímků do prvního opakování
KB_RATE   EQU 3             ; snímků mezi opakováními

; ---- kb_scan: E = index klávesy (řádek*5+bit) nebo 0xFF, D = bit0 CS, bit1 SS
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

; ---- kb_read: A = kód stisknuté klávesy nebo 0
kb_read:
        call kb_scan
        ld a,e
        cp 0xFF
        jr z,.none
        ld hl,kt_norm
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

; ---- kb_poll: volat 1x za snímek. A = nová klávesa (s autorepeatem) nebo 0
kb_poll:
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
        ld a,b
        ret
.no:    xor a
        ret

; ---- kb_wait: čeká na klávesu (HALT), A = kód
kb_wait:
        halt
        call kb_poll
        or a
        jr z,kb_wait
        ret

; ---- kb_release: čeká až nebude nic stisknuto
kb_release:
        halt
        call kb_read
        or a
        jr nz,kb_release
        ld (kb_last),a
        ret

kb_last: db 0
kb_cnt:  db 0

; řádky: CS Z X C V | A S D F G | Q W E R T | 1 2 3 4 5
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
        db K_ENTER,'=','+','-','^'
        db ' ',0,'.',',','*'
