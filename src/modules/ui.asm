; SOUND_START
; Input:
;   A = duration in scan ticks
;   C = divider reload / half-period
; Output:
;   speaker state machine restarted
; Clobbers:
;   A
SOUND_START:
        LD      (SOUND_TIMER),A
        LD      A,C
        LD      (SOUND_DIVIDER_RELOAD),A
        LD      (SOUND_DIVIDER_COUNT),A
        XOR     A
        LD      (SPEAKER_PORT_STATE),A
        RET

; SOUND_TRIGGER_ROTATE
; Input:
;   none
; Output:
;   short rotate buzz started
; Clobbers:
;   A, C
SOUND_TRIGGER_ROTATE:
        LD      A,SOUND_ROTATE_LEN
        LD      C,SOUND_ROTATE_DIV
        JP      SOUND_START

; SOUND_TRIGGER_LOCK
; Input:
;   none
; Output:
;   short lock buzz started
; Clobbers:
;   A, C
SOUND_TRIGGER_LOCK:
        LD      A,SOUND_LOCK_LEN
        LD      C,SOUND_LOCK_DIV
        JP      SOUND_START

; SOUND_TRIGGER_CLEAR
; Input:
;   none
; Output:
;   line-clear buzz started
; Clobbers:
;   A, C
SOUND_TRIGGER_CLEAR:
        LD      A,SOUND_CLEAR_LEN
        LD      C,SOUND_CLEAR_DIV
        JP      SOUND_START

; SOUND_TRIGGER_GAME_OVER
; Input:
;   none
; Output:
;   game-over buzz started
; Clobbers:
;   A, C
SOUND_TRIGGER_GAME_OVER:
        LD      A,SOUND_GAME_OVER_LEN
        LD      C,SOUND_GAME_OVER_DIV
        JP      SOUND_START

; SERVICE_SOUND
; Input:
;   SOUND_TIMER / SOUND_DIVIDER_RELOAD / SOUND_DIVIDER_COUNT
; Output:
;   SPEAKER_PORT_STATE updated for current scan pass
; Clobbers:
;   A
SERVICE_SOUND:
        LD      A,(SOUND_TIMER)
        OR      A
        RET     Z
        DEC     A
        LD      (SOUND_TIMER),A
        JR      NZ,SERVICE_SOUND_ACTIVE
        XOR     A
        LD      (SPEAKER_PORT_STATE),A
        LD      (SOUND_DIVIDER_COUNT),A
        RET
SERVICE_SOUND_ACTIVE:
        LD      A,(SOUND_DIVIDER_COUNT)
        DEC     A
        LD      (SOUND_DIVIDER_COUNT),A
        RET     NZ
        LD      A,(SOUND_DIVIDER_RELOAD)
        LD      (SOUND_DIVIDER_COUNT),A
        LD      A,(SPEAKER_PORT_STATE)
        XOR     SPEAKER_BIT
        LD      (SPEAKER_PORT_STATE),A
        RET

; SCAN_SCORE_DIGIT — time-multiplex HUD + PWM speaker on PORT_DIGITS.
; Brief: first OUT publishes segment data on PORT_SEGS with digit driver showing
; only SPEAKER_PORT_STATE on PORT_DIGITS; second OUT ORs DIGIT_MASK_TABLE[C] into
; PORT_DIGITS so one cathode/anode selects the active digit without clobbering
; the speaker line (speaker + digit select share the latch).
; Input:
;   HUD_SEG_BUFFER / HUD_SCAN_INDEX / SPEAKER_PORT_STATE
; Output:
;   one seven-segment digit refreshed
; Clobbers:
;   A, B, C, DE, HL
SCAN_SCORE_DIGIT:
        LD      A,(HUD_SCAN_INDEX)
        LD      C,A
        LD      A,(SPEAKER_PORT_STATE)
        OUT     (PORT_DIGITS),A
        LD      A,C
        LD      L,A
        LD      H,0
        LD      DE,HUD_SEG_BUFFER
        ADD     HL,DE
        LD      A,(HL)
        OUT     (PORT_SEGS),A

        LD      A,C
        LD      L,A
        LD      H,0
        LD      DE,DIGIT_MASK_TABLE
        ADD     HL,DE
        LD      A,(HL)
        LD      B,A
        LD      A,(SPEAKER_PORT_STATE)
        OR      B
        OUT     (PORT_DIGITS),A

        LD      A,C
        INC     A
        CP      6
        JR      C,SCAN_SCORE_DIGIT_SAVE
        XOR     A
SCAN_SCORE_DIGIT_SAVE:
        LD      (HUD_SCAN_INDEX),A
        RET

; UPDATE_SCORE_DISPLAY
; Input:
;   SCORE_LO / SCORE_HI
; Output:
;   HUD_SEG_BUFFER updated with a six-digit score display
; Clobbers:
;   A, BC, DE, HL
UPDATE_SCORE_DISPLAY:
        LD      A,(DIAG_SEG_TABLE)
        LD      (HUD_SEG_BUFFER),A
        LD      HL,(SCORE_LO)
        LD      BC,HUD_SEG_BUFFER+1

        LD      DE,0x2710      ; 10000
        CALL    SCORE_WRITE_DIGIT
        LD      DE,0x03E8      ; 1000
        CALL    SCORE_WRITE_DIGIT
        LD      DE,0x0064      ; 100
        CALL    SCORE_WRITE_DIGIT
        LD      DE,0x000A      ; 10
        CALL    SCORE_WRITE_DIGIT
        LD      DE,0x0001      ; 1
        CALL    SCORE_WRITE_DIGIT
        RET

; SCORE_WRITE_DIGIT
; Input:
;   HL = score remainder
;   DE = divisor
;   BC = destination digit in HUD_SEG_BUFFER
; Output:
;   HL = updated score remainder
;   BC = advanced to next destination
; Clobbers:
;   A
SCORE_WRITE_DIGIT:
        XOR     A
SCORE_WRITE_DIGIT_LOOP:
        PUSH    AF
        LD      A,H
        CP      D
        JR      C,SCORE_WRITE_DIGIT_DONE
        JR      NZ,SCORE_WRITE_DIGIT_SUB
        LD      A,L
        CP      E
        JR      C,SCORE_WRITE_DIGIT_DONE
SCORE_WRITE_DIGIT_SUB:
        POP     AF
        OR      A
        SBC     HL,DE
        INC     A
        JR      SCORE_WRITE_DIGIT_LOOP
SCORE_WRITE_DIGIT_DONE:
        POP     AF
        PUSH    HL
        PUSH    BC
        LD      L,A
        LD      H,0
        LD      DE,DIAG_SEG_TABLE
        ADD     HL,DE
        LD      A,(HL)
        POP     BC
        LD      (BC),A
        INC     BC
        POP     HL
        RET

; LCD_BUSY
; Input:
;   none
; Output:
;   waits until LCD busy flag clears
; Clobbers:
;   none
LCD_BUSY:
        PUSH    AF
LCD_BUSY_LOOP:
        IN      A,(PORT_LCD_INST)
        RLCA
        JR      C,LCD_BUSY_LOOP
        POP     AF
        RET

; LCD_COMMAND
; Input:
;   B = LCD instruction byte
; Output:
;   instruction sent to LCD
; Clobbers:
;   none
LCD_COMMAND:
        PUSH    AF
        CALL    LCD_BUSY
        LD      A,B
        OUT     (PORT_LCD_INST),A
        POP     AF
        RET

; LCD_STRING
; Input:
;   HL = zero-terminated ASCII string
; Output:
;   string written at current LCD cursor position
; Clobbers:
;   A, HL
LCD_STRING:
        LD      A,(HL)
        INC     HL
        OR      A
        RET     Z
        CALL    LCD_BUSY
        OUT     (PORT_LCD_DATA),A
        JR      LCD_STRING

; LCD_SHOW_GAME_OVER
; Input:
;   none
; Output:
;   game-over text written to LCD
; Clobbers:
;   A, B, HL
LCD_SHOW_GAME_OVER:
        PUSH    BC
        PUSH    HL
        LD      B,0x01
        CALL    LCD_COMMAND
        LD      B,LCD_ROW1
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_GAME_OVER
        CALL    LCD_STRING
        LD      B,LCD_ROW2
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_STATE_GAME_OVER
        CALL    LCD_STRING
        LD      B,LCD_ROW3
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_RESET
        CALL    LCD_STRING
        POP     HL
        POP     BC
        RET

; LCD_SHOW_PAUSED
; Input:
;   none
; Output:
;   pause text written to LCD
; Clobbers:
;   A, B, HL
LCD_SHOW_PAUSED:
        PUSH    BC
        PUSH    HL
        LD      B,0x01
        CALL    LCD_COMMAND
        LD      B,LCD_ROW1
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_PAUSED
        CALL    LCD_STRING
        LD      B,LCD_ROW2
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_STATE_PAUSED
        CALL    LCD_STRING
        LD      B,LCD_ROW3
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_RESUME
        CALL    LCD_STRING
        POP     HL
        POP     BC
        RET

; LCD_SHOW_SPLASH
; Input:
;   none
; Output:
;   startup title and key mapping text written to LCD
; Clobbers:
;   A, B, HL
LCD_SHOW_SPLASH:
        PUSH    BC
        PUSH    HL
        LD      B,0x01
        CALL    LCD_COMMAND
        LD      B,LCD_ROW1
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_SPLASH_TITLE
        CALL    LCD_STRING
        LD      B,LCD_ROW2
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_SPLASH_MOVE
        CALL    LCD_STRING
        LD      B,LCD_ROW3
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_SPLASH_ROTATE
        CALL    LCD_STRING
        LD      B,LCD_ROW4
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_SPLASH_DROP
        CALL    LCD_STRING
        POP     HL
        POP     BC
        RET

; LCD_SHOW_RUNNING
; Input:
;   none
; Output:
;   live gameplay HUD written to LCD
; Clobbers:
;   A, B, C, D, E, HL
LCD_SHOW_RUNNING:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,0x01
        CALL    LCD_COMMAND
        LD      B,LCD_ROW1
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_RUNNING
        CALL    LCD_STRING
        LD      B,LCD_ROW2
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_STATE_RUNNING
        CALL    LCD_STRING
        LD      B,LCD_ROW3
        CALL    LCD_COMMAND
        LD      HL,LCD_TEXT_NEXT
        CALL    LCD_STRING
        LD      A,(NEXT_PIECE_INDEX)
        LD      L,A
        LD      H,0
        LD      DE,PIECE_NAME_TABLE
        ADD     HL,DE
        LD      A,(HL)
        CALL    LCD_PUTC
        POP     HL
        POP     DE
        POP     BC
        RET

; LCD_PUTC
; Input:
;   A = ASCII character
; Output:
;   character written at current LCD cursor position
; Clobbers:
;   A
LCD_PUTC:
        PUSH    AF
        CALL    LCD_BUSY
        POP     AF
        OUT     (PORT_LCD_DATA),A
        RET

; LCD_WRITE_DECIMAL3
; Input:
;   A = value 0..255
; Output:
;   three decimal digits written to LCD
; Clobbers:
;   A, B, C
LCD_WRITE_DECIMAL3:
        LD      C,A
        LD      B,0
LCD_WRITE_HUNDREDS:
        LD      A,C
        CP      100
        JR      C,LCD_WRITE_HUNDREDS_DONE
        SUB     100
        LD      C,A
        INC     B
        JR      LCD_WRITE_HUNDREDS
LCD_WRITE_HUNDREDS_DONE:
        LD      A,B
        ADD     A,'0'
        CALL    LCD_PUTC

        LD      B,0
LCD_WRITE_TENS:
        LD      A,C
        CP      10
        JR      C,LCD_WRITE_TENS_DONE
        SUB     10
        LD      C,A
        INC     B
        JR      LCD_WRITE_TENS
LCD_WRITE_TENS_DONE:
        LD      A,B
        ADD     A,'0'
        CALL    LCD_PUTC

        LD      A,C
        ADD     A,'0'
        JP      LCD_PUTC

; Seven-segment patterns for 0..F, copied from MON-3 hexToSegmentTable.
