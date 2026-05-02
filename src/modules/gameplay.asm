; INIT_STATE
; Input:
;   none
; Output:
;   initialized runtime state in RAM
; Clobbers:
;   A, HL
INIT_STATE:
        CALL    INIT_STATE_BASE
        LD      A,1
        LD      (SPLASH_TIMER),A
        CALL    LCD_SHOW_SPLASH
        JP      REBUILD_FRAMEBUFFER

; INIT_STATE_RESTART
; Input:
;   none
; Output:
;   initialized runtime state for immediate post-game restart
; Clobbers:
;   A, HL
INIT_STATE_RESTART:
        CALL    INIT_STATE_BASE
        XOR     A
        LD      (SPLASH_TIMER),A
        CALL    RNG_NEXT_PIECE
        LD      (NEXT_PIECE_INDEX),A
        CALL    SPAWN_ACTIVE_PIECE
        CALL    UPDATE_SCORE_DISPLAY
        CALL    LCD_SHOW_RUNNING
        JP      REBUILD_FRAMEBUFFER

; INIT_STATE_BASE
; Input:
;   none
; Output:
;   common runtime state initialized in RAM
; Clobbers:
;   A, HL
INIT_STATE_BASE:
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A

        XOR     A
        LD      (GAME_OVER),A
        LD      (ACTIVE_PIECE_ENABLED),A
        LD      (CLEAR_PENDING),A
        LD      (CLEAR_MASK),A
        LD      (CLEAR_TIMER),A
        LD      (DROP_LOCKOUT),A
        LD      (FRAME_PHASE),A
        LD      (LOGIC_SLICE),A
        LD      (PAUSED),A
        LD      (CURRENT_ROTATION),A
        LD      (CURRENT_PIECE_INDEX),A
        LD      (NEXT_PIECE_INDEX),A
        LD      (LINES_CLEARED_TOTAL),A
        LD      (SCORE_LO),A
        LD      (SCORE_HI),A
        LD      A,1
        LD      (INPUT_LOCKOUT),A
        LD      A,NO_KEY
        LD      (LAST_KEY),A
        XOR     A
        LD      (HUD_SCAN_INDEX),A
        LD      (SPEAKER_PORT_STATE),A
        LD      (SOUND_TIMER),A
        LD      (SOUND_DIVIDER_RELOAD),A
        LD      (SOUND_DIVIDER_COUNT),A

        LD      A,SCAN_MASK_START
        LD      (SCAN_MASK),A

        LD      HL,FRAMEBUFFER
        LD      (SCAN_PTR),HL

        CALL    CLEAR_BOARD
        CALL    UPDATE_SCORE_DISPLAY
        RET

; Output one scanline, then advance persistent scan state.
; SCAN_TICK
; Input:
;   uses SCAN_PTR / SCAN_MASK from RAM
; Output:
;   one matrix row emitted to hardware ports
;   one seven-segment digit emitted to hardware ports
; Clobbers:
;   A, BC, DE, HL
SCAN_TICK:
        XOR     A
        OUT     (PORT_ROW),A

        LD      HL,(SCAN_PTR)

        LD      A,(HL)
        OUT     (PORT_RED),A
        INC     HL

        LD      A,(HL)
        OUT     (PORT_GREEN),A
        INC     HL

        LD      A,(HL)
        OUT     (PORT_BLUE),A

        LD      A,(SCAN_MASK)
        OUT     (PORT_ROW),A

        CALL    SERVICE_SOUND
        CALL    SCAN_SCORE_DIGIT
        CALL    ADVANCE_SCAN_STATE
        RET

; ADVANCE_SCAN_STATE
; Input:
;   uses SCAN_MASK / SCAN_PTR from RAM
; Output:
;   updated SCAN_MASK / SCAN_PTR, FRAME_PHASE incremented on wrap
; Clobbers:
;   A, HL, DE
ADVANCE_SCAN_STATE:
        LD      A,(SCAN_MASK)
        RLC     A
        LD      (SCAN_MASK),A

        LD      HL,(SCAN_PTR)
        LD      DE,BYTES_PER_ROW
        ADD     HL,DE

        CP      SCAN_MASK_START
        JR      NZ,SAVE_NEXT_SCAN_PTR

        LD      HL,FRAMEBUFFER
        LD      A,(FRAME_PHASE)
        INC     A
        LD      (FRAME_PHASE),A

SAVE_NEXT_SCAN_PTR:
        LD      (SCAN_PTR),HL
        RET

; Run one slice of logic per main-loop pass (1 slice per scanline, 0..7 then wrap).
; Distributes work so each inter-row interval is similar, helping even brightness/POV.
; LOGIC_TICK
; Input:
;   uses LOGIC_SLICE from RAM
; Output:
;   one logic slice executed, LOGIC_SLICE advanced
; Clobbers:
;   A, HL, and whatever the called slice routines clobber
LOGIC_TICK:
        CALL    SANITIZE_ACTIVE_POSITION
        LD      A,(GAME_OVER)
        OR      A
        JR      Z,LOGIC_TICK_GAME_OVER_DONE
        CALL    POLL_GAME_OVER_RESTART
        RET
LOGIC_TICK_GAME_OVER_DONE:
        LD      A,(SPLASH_TIMER)
        OR      A
        JR      Z,LOGIC_TICK_SPLASH_DONE
        CALL    HANDLE_SPLASH_STATE
        RET
LOGIC_TICK_SPLASH_DONE:
        LD      A,(CLEAR_PENDING)
        OR      A
        JR      Z,LOGIC_TICK_CLEAR_DONE
        CALL    HANDLE_LINE_CLEAR_STATE
        JR      LOGIC_TICK_ACTIVE
LOGIC_TICK_CLEAR_DONE:
        LD      A,(PAUSED)
        OR      A
        JR      Z,LOGIC_TICK_ACTIVE
        CALL    POLL_INPUT_AND_UPDATE
        RET
LOGIC_TICK_ACTIVE:
        LD      A,(INPUT_LOCKOUT)
        OR      A
        JR      Z,LOGIC_TICK_LOCKOUT_DONE
        CALL    WAIT_FOR_KEY_RELEASE
        RET
LOGIC_TICK_LOCKOUT_DONE:
        LD      A,(LOGIC_SLICE)
        AND     7
        CP      0
        JR      Z,LOGIC_SL0
        CP      1
        JR      Z,LOGIC_SL1
        CP      2
        JR      Z,LOGIC_SL2
        CP      3
        JR      Z,LOGIC_SL3
        CP      4
        JR      Z,LOGIC_SL4
        CP      5
        JR      Z,LOGIC_SL5
        CP      6
        JR      Z,LOGIC_SL6
; --- slice 7: final 4B clear, render to back buffer, copy to live framebuffer
        LD      A,28
        CALL    CLEAR_BACK_4
        CALL    RENDER_BOARD_TO_BACK
        CALL    RENDER_ACTIVE_TO_BACK
        CALL    COPY_BACK_TO_FRONT
        JR      LOGIC_SLICE_NEXT

LOGIC_SL0:
        LD      A,(CLEAR_PENDING)
        OR      A
        JR      NZ,LOGIC_SL0_NO_INPUT
        CALL    POLL_INPUT_AND_UPDATE
LOGIC_SL0_NO_INPUT:
        XOR     A
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL1:
        LD      A,(CLEAR_PENDING)
        OR      A
        JR      NZ,LOGIC_SL1_NO_GRAVITY
        CALL    APPLY_GRAVITY
LOGIC_SL1_NO_GRAVITY:
        LD      A,4
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL2:
        LD      A,8
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL3:
        LD      A,12
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL4:
        LD      A,16
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL5:
        LD      A,20
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL6:
        LD      A,24
        CALL    CLEAR_BACK_4
        ; fall through

LOGIC_SLICE_NEXT:
        LD      HL,LOGIC_SLICE
        LD      A,(HL)
        INC     A
        AND     7
        LD      (HL),A
        RET

; Poll MON-3 keypad state and update PLAYER_X at a controlled rate.
;
; scanKeys return contract:
;   Z  = key is pressed
;   C  = new key press
;   NZ = no key / invalid key
;   A  = key code
; POLL_INPUT_AND_UPDATE
; Input:
;   none
; Output:
;   may update PLAYER_X / MOVE_COOLDOWN / LAST_KEY
; Clobbers:
;   A, C, D, E
POLL_INPUT_AND_UPDATE:
        LD      C,API_SCANKEYS
        RST     0x10
        JR      NZ,CLEAR_INPUT_REPEAT_STATE
        LD      E,A
        JR      C,KEY_NEW_PRESS
        LD      A,E
        CP      K_PAUSE
        JP      Z,CLEAR_INPUT_REPEAT_STATE
        LD      A,(PAUSED)
        OR      A
        JR      NZ,CLEAR_INPUT_REPEAT_STATE
        LD      A,E
        CP      K_ROTATE
        JR      Z,CLEAR_INPUT_REPEAT_STATE
        CP      K_ROTATE_CCW
        JR      Z,CLEAR_INPUT_REPEAT_STATE
        CP      K_ROTATE_ALT
        JR      Z,CLEAR_INPUT_REPEAT_STATE
        CP      K_ROTATE_CCW_ALT
        JR      Z,CLEAR_INPUT_REPEAT_STATE
        JR      HANDLE_DIRECTION_KEY

KEY_NEW_PRESS:
        LD      A,(PAUSED)
        OR      A
        JP      NZ,HANDLE_UNPAUSE_KEY
        LD      A,E
        CP      K_PAUSE
        JP      Z,HANDLE_PAUSE_KEY
        LD      A,E
        CP      K_ROTATE
        JP      Z,HANDLE_ROTATE_PRESS
        CP      K_ROTATE_CCW
        JP      Z,HANDLE_ROTATE_CCW_PRESS
        CP      K_ROTATE_ALT
        JP      Z,HANDLE_ROTATE_PRESS
        CP      K_ROTATE_CCW_ALT
        JP      Z,HANDLE_ROTATE_CCW_PRESS
        ; fall through

HANDLE_DIRECTION_KEY:
        LD      A,E
        CP      K_LEFT
        JP      Z,HANDLE_KEY_LEFT
        CP      K_RIGHT
        JP      Z,HANDLE_KEY_RIGHT
        CP      K_DROP
        JP      Z,HANDLE_KEY_DROP

; CLEAR_INPUT_REPEAT_STATE
; Restores MOVE_COOLDOWN full period, clears LAST_KEY and soft-drop latch.
; Used when leaving held-autorepeat path (invalid/no key, pause, rotate presses, etc.).
CLEAR_INPUT_REPEAT_STATE:
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,NO_KEY
        LD      (LAST_KEY),A
        XOR     A
        LD      (DROP_LOCKOUT),A
        RET

; POLL_GAME_OVER_RESTART
; Input:
;   none
; Output:
;   restarts the game on a fresh key press
; Clobbers:
;   A, C
POLL_GAME_OVER_RESTART:
        LD      C,API_SCANKEYS
        RST     0x10
        RET     NC
        JP      INIT_STATE_RESTART

; WAIT_FOR_KEY_RELEASE
; Input:
;   INPUT_LOCKOUT
; Output:
;   clears INPUT_LOCKOUT once no key is pressed
; Clobbers:
;   A, C
WAIT_FOR_KEY_RELEASE:
        LD      C,API_SCANKEYS
        RST     0x10
        RET     Z
        XOR     A
        LD      (INPUT_LOCKOUT),A
        RET

HANDLE_PAUSE_KEY:
        LD      A,(PAUSED)
        XOR     1
        LD      (PAUSED),A
        OR      A
        JR      Z,HANDLE_PAUSE_SHOW_RUNNING
        CALL    LCD_SHOW_PAUSED
        JP      CLEAR_INPUT_REPEAT_STATE
HANDLE_PAUSE_SHOW_RUNNING:
        CALL    LCD_SHOW_RUNNING
        JP      CLEAR_INPUT_REPEAT_STATE

HANDLE_UNPAUSE_KEY:
        XOR     A
        LD      (PAUSED),A
        CALL    LCD_SHOW_RUNNING
        JP      CLEAR_INPUT_REPEAT_STATE

HANDLE_ROTATE_PRESS:
        CALL    ROTATE_CW
        JP      CLEAR_INPUT_REPEAT_STATE

HANDLE_ROTATE_CCW_PRESS:
        CALL    ROTATE_LEFT
        JP      CLEAR_INPUT_REPEAT_STATE

HANDLE_KEY_RIGHT:
        LD      A,K_RIGHT
        JP      HANDLE_HELD_DIRECTION

HANDLE_KEY_LEFT:
        LD      A,K_LEFT
        JP      HANDLE_HELD_DIRECTION

; HANDLE_HELD_DIRECTION
; Input:
;   A = K_LEFT, K_RIGHT, or K_DROP (held/repeat timing path via LAST_KEY/MOVE_COOLDOWN)
; Output:
;   may update PLAYER_X / PLAYER_Y / MOVE_COOLDOWN / LAST_KEY
; Clobbers:
;   A, D, E
HANDLE_HELD_DIRECTION:
        LD      E,A
        LD      A,(LAST_KEY)
        CP      E
        JR      Z,SAME_DIRECTION

        LD      A,E
        LD      (LAST_KEY),A
        LD      A,1
        LD      (MOVE_COOLDOWN),A

SAME_DIRECTION:
        LD      A,(MOVE_COOLDOWN)
        DEC     A
        LD      (MOVE_COOLDOWN),A
        RET     NZ

        LD      A,E
        CP      K_DROP
        JR      NZ,HELD_DIRECTION_NORMAL_RATE
        LD      A,DROP_PERIOD
        JR      HELD_DIRECTION_RATE_SET
HELD_DIRECTION_NORMAL_RATE:
        LD      A,MOVE_PERIOD
HELD_DIRECTION_RATE_SET:
        LD      (MOVE_COOLDOWN),A
        LD      A,E
        CP      K_LEFT
        JR      Z,MOVE_LEFT
        CP      K_DROP
        JP      Z,SOFT_DROP

; LOAD_DE_FROM_PENDING
; Output: D = PENDING_X, E = PENDING_Y (arguments for CHECK_COLLISION_AT_DE)
; Clobbers: A
LOAD_DE_FROM_PENDING:
        LD      A,(PENDING_X)
        LD      D,A
        LD      A,(PENDING_Y)
        LD      E,A
        RET

; MOVE_RIGHT
; Input:
;   none
; Output:
;   may increment PLAYER_X if candidate placement is legal
; Clobbers:
;   A, D, E
MOVE_RIGHT:
        LD      A,(PLAYER_X)
        INC     A
        LD      (PENDING_X),A
        LD      A,(PLAYER_Y)
        LD      (PENDING_Y),A
        CALL    LOAD_DE_FROM_PENDING
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,MOVE_RIGHT_COMMIT
        RET
MOVE_RIGHT_COMMIT:
        LD      A,(PENDING_X)
        LD      (PLAYER_X),A
        RET

; MOVE_LEFT
; Input:
;   none
; Output:
;   may decrement PLAYER_X if candidate placement is legal
; Clobbers:
;   A, D, E
MOVE_LEFT:
        LD      A,(PLAYER_X)
        OR      A
        RET     Z
        DEC     A
        LD      (PENDING_X),A
        LD      A,(PLAYER_Y)
        LD      (PENDING_Y),A
        CALL    LOAD_DE_FROM_PENDING
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,MOVE_LEFT_COMMIT
        RET
MOVE_LEFT_COMMIT:
        LD      A,(PENDING_X)
        LD      (PLAYER_X),A
        RET

HANDLE_KEY_DROP:
        LD      A,(DROP_LOCKOUT)
        OR      A
        RET     NZ
        LD      A,K_DROP
        JP      HANDLE_HELD_DIRECTION

; APPLY_GRAVITY
; Input:
;   none
; Output:
;   may update PLAYER_Y, or lock and respawn active piece on collision
; Clobbers:
;   A, D, E
APPLY_GRAVITY:
        LD      A,(GRAVITY_COOLDOWN)
        DEC     A
        LD      (GRAVITY_COOLDOWN),A
        RET     NZ

        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A

        LD      A,(PLAYER_X)
        LD      (PENDING_X),A
        LD      A,(PLAYER_Y)
        INC     A
        LD      (PENDING_Y),A
        CALL    LOAD_DE_FROM_PENDING
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,GRAVITY_COMMIT
        JR      LOCK_ACTIVE_PIECE
GRAVITY_COMMIT:
        LD      A,(PENDING_Y)
        LD      (PLAYER_Y),A
        RET

; SOFT_DROP
; Input:
;   none
; Output:
;   may update PLAYER_Y, or lock and respawn active piece on collision
; Clobbers:
;   A, D, E
SOFT_DROP:
        LD      A,(PLAYER_X)
        LD      (PENDING_X),A
        LD      A,(PLAYER_Y)
        INC     A
        LD      (PENDING_Y),A
        CALL    LOAD_DE_FROM_PENDING
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,SOFT_DROP_COMMIT
        LD      A,1
        LD      (DROP_LOCKOUT),A
        JR      LOCK_ACTIVE_PIECE
SOFT_DROP_COMMIT:
        LD      A,(PENDING_Y)
        LD      (PLAYER_Y),A
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A
        RET

LOCK_ACTIVE_PIECE:
        CALL    CHECK_TOP_OUT_ON_LOCK
        JR      C,LOCK_GAME_OVER
        CALL    MERGE_ACTIVE_TO_BOARD
        CALL    CHECK_FULL_ROWS
        JR      NC,LOCK_ACTIVE_NO_CLEAR
        CALL    SOUND_TRIGGER_CLEAR
        XOR     A
        LD      (ACTIVE_PIECE_ENABLED),A
        LD      A,1
        LD      (CLEAR_PENDING),A
        LD      A,LINE_CLEAR_HOLD
        LD      (CLEAR_TIMER),A
        RET
LOCK_ACTIVE_NO_CLEAR:
        CALL    SOUND_TRIGGER_LOCK
        CALL    SPAWN_ACTIVE_PIECE
        RET

LOCK_GAME_OVER:
        CALL    MERGE_ACTIVE_TO_BOARD
        LD      A,4
        CALL    ENTER_GAME_OVER
        RET

; SANITIZE_ACTIVE_POSITION
; Input:
;   PLAYER_X, PLAYER_Y in RAM
; Output:
;   PLAYER_X clamped to X_MIN..X_MAX
;   PLAYER_Y clamped to Y_MIN..Y_MAX
; Clobbers:
;   A
SANITIZE_ACTIVE_POSITION:
        LD      A,(PLAYER_X)
        LD      HL,CURRENT_PIECE_RIGHT
        ADD     A,(HL)
        CP      ROW_COUNT
        JR      C,SANITIZE_X_DONE
        LD      A,ROW_COUNT-1
        SUB     (HL)
        LD      (PLAYER_X),A
SANITIZE_X_DONE:
        LD      A,(PLAYER_Y)
        BIT     7,A
        JR      NZ,SANITIZE_Y_DONE
        CP      Y_MAX+1
        JR      C,SANITIZE_Y_DONE
        LD      A,Y_MAX
        LD      (PLAYER_Y),A
SANITIZE_Y_DONE:
        RET

; Full rebuild (used at init). Build in back buffer, then copy to live FB.
; REBUILD_FRAMEBUFFER
; Input:
;   current board and active-piece state in RAM
; Output:
;   FRAMEBUFFER rebuilt from scratch
; Clobbers:
;   A, B, C, D, E, HL, BC
REBUILD_FRAMEBUFFER:
        CALL    CLEAR_BACK_ALL
        CALL    RENDER_BOARD_TO_BACK
        CALL    RENDER_ACTIVE_TO_BACK
        JP      COPY_BACK_TO_FRONT

; Clear all 32 bytes of the back buffer (init or if you need a full clear).
; CLEAR_BACK_ALL
; Input:
;   none
; Output:
;   FRAMEBUFFER_BACK cleared to zero
; Clobbers:
;   A, B, HL
CLEAR_BACK_ALL:
        LD      HL,FRAMEBUFFER_BACK
        LD      B,FRAMEBUFFER_BYTES
        XOR     A
CLEAR_BACK_ALL_LOOP:
        LD      (HL),A
        INC     HL
        DJNZ    CLEAR_BACK_ALL_LOOP
        RET

; Clear 4 bytes at FRAMEBUFFER_BACK + A (A = 0,4,8,...,28).
; CLEAR_BACK_4
; Input:
;   A = byte offset into FRAMEBUFFER_BACK, expected 0,4,8,...,28
; Output:
;   selected 4-byte row cleared
; Clobbers:
;   A, D, E, HL
CLEAR_BACK_4:
        LD      E,A
        LD      D,0
        LD      HL,FRAMEBUFFER_BACK
        ADD     HL,DE
        XOR     A
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        LD      (HL),A
        RET

; Copy composed back buffer to the framebuffer the scanout reads.
; COPY_BACK_TO_FRONT
; Input:
;   FRAMEBUFFER_BACK contains completed image
; Output:
;   FRAMEBUFFER overwritten from FRAMEBUFFER_BACK
; Clobbers:
;   HL, DE, BC
COPY_BACK_TO_FRONT:
        LD      HL,FRAMEBUFFER_BACK
        LD      DE,FRAMEBUFFER
        LD      BC,FRAMEBUFFER_BYTES
        LDIR
        RET

; CLEAR_BOARD
; Input:
;   none
; Output:
;   BOARD_ROWS and landed RGB planes cleared to zero
; Clobbers:
;   A, B, HL
CLEAR_BOARD:
        LD      HL,BOARD_ROWS
        LD      B,ROW_COUNT*4
        XOR     A
CLEAR_BOARD_LOOP:
        LD      (HL),A
        INC     HL
        DJNZ    CLEAR_BOARD_LOOP
        LD      A,1
        LD      (BOARD_EMPTY),A
        RET

; SELECT_NEXT_PIECE
; Input:
;   NEXT_PIECE_INDEX in RAM
; Output:
;   CURRENT_PIECE_INDEX / CURRENT_ROTATION updated
;   CURRENT_PIECE_PTR / CURRENT_PIECE_BOTTOM / CURRENT_PIECE_RIGHT /
;   CURRENT_PIECE_COLOR updated
;   NEXT_PIECE_INDEX advanced modulo PIECE_COUNT
; Clobbers:
;   A, BC, DE, HL
SELECT_NEXT_PIECE:
        LD      A,(NEXT_PIECE_INDEX)
        LD      (CURRENT_PIECE_INDEX),A
        XOR     A
        LD      (CURRENT_ROTATION),A
        CALL    LOAD_CURRENT_ROTATION_STATE

        CALL    RNG_NEXT_PIECE
        LD      (NEXT_PIECE_INDEX),A
        RET

; RNG_NEXT_PIECE
; Input:
;   RNG_SEED
; Output:
;   A = next piece index 0..6
;   RNG_SEED advanced
; Clobbers:
;   A
RNG_NEXT_PIECE:
        CALL    RNG_NEXT8
        AND     0x07
        CP      PIECE_COUNT
        JR      NC,RNG_NEXT_PIECE
        RET

; RNG_NEXT8
; Input:
;   RNG_SEED
; Output:
;   A = next pseudo-random byte
;   RNG_SEED advanced
; Clobbers:
;   A
RNG_NEXT8:
        LD      A,(RNG_SEED)
        OR      A
        JR      NZ,RNG_NEXT8_STEP
        LD      A,RNG_SEED_INIT
RNG_NEXT8_STEP:
        SRL     A
        JR      NC,RNG_NEXT8_SAVE
        XOR     0xB8
RNG_NEXT8_SAVE:
        LD      (RNG_SEED),A
        RET

; LOAD_CURRENT_ROTATION_STATE
; Input:
;   CURRENT_PIECE_INDEX / CURRENT_ROTATION in RAM
; Output:
;   CURRENT_PIECE_PTR / CURRENT_PIECE_BOTTOM / CURRENT_PIECE_RIGHT updated
; Clobbers:
;   A, BC, DE, HL
LOAD_CURRENT_ROTATION_STATE:
        LD      A,(CURRENT_PIECE_INDEX)
        ADD     A,A
        ADD     A,A
        LD      C,A
        LD      A,(CURRENT_ROTATION)
        ADD     A,C
        LD      E,A
        LD      D,0

        LD      HL,PIECE_BOTTOM_TABLE
        ADD     HL,DE
        LD      A,(HL)
        LD      (CURRENT_PIECE_BOTTOM),A

        LD      HL,PIECE_RIGHT_TABLE
        ADD     HL,DE
        LD      A,(HL)
        LD      (CURRENT_PIECE_RIGHT),A

        PUSH    DE
        LD      A,(CURRENT_PIECE_INDEX)
        LD      E,A
        LD      D,0
        LD      HL,PIECE_COLOR_TABLE
        ADD     HL,DE
        LD      A,(HL)
        LD      (CURRENT_PIECE_COLOR),A
        POP     DE

        LD      HL,PIECE_PTR_TABLE
        ADD     HL,DE
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      HL,CURRENT_PIECE_PTR
        LD      (HL),E
        INC     HL
        LD      (HL),D
        RET

; ROTATE_CW
; Input:
;   current active piece state in RAM
; Output:
;   may update CURRENT_ROTATION if rotated placement is legal
; Clobbers:
;   A, D, E
ROTATE_CW:
        LD      A,(CURRENT_ROTATION)
        LD      (PENDING_ROTATION),A
        INC     A
        AND     3
        LD      (CURRENT_ROTATION),A
        CALL    LOAD_CURRENT_ROTATION_STATE

        LD      A,(PLAYER_X)
        LD      D,A
        LD      A,(PLAYER_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,ROTATE_CW_COMMIT

        LD      A,(PENDING_ROTATION)
        LD      (CURRENT_ROTATION),A
        JP      LOAD_CURRENT_ROTATION_STATE
ROTATE_CW_COMMIT:
        CALL    SOUND_TRIGGER_ROTATE
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A
        RET

; ROTATE_LEFT
; Input:
;   current active piece state in RAM
; Output:
;   may update CURRENT_ROTATION if rotated placement is legal
; Clobbers:
;   A, D, E
ROTATE_LEFT:
        LD      A,(CURRENT_ROTATION)
        LD      (PENDING_ROTATION),A
        OR      A
        JR      NZ,ROTATE_LEFT_DEC
        LD      A,4
ROTATE_LEFT_DEC:
        DEC     A
        LD      (CURRENT_ROTATION),A
        CALL    LOAD_CURRENT_ROTATION_STATE

        LD      A,(PLAYER_X)
        LD      D,A
        LD      A,(PLAYER_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        JR      NC,ROTATE_LEFT_COMMIT

        LD      A,(PENDING_ROTATION)
        LD      (CURRENT_ROTATION),A
        JP      LOAD_CURRENT_ROTATION_STATE
ROTATE_LEFT_COMMIT:
        CALL    SOUND_TRIGGER_ROTATE
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A
        RET

; SPAWN_ACTIVE_PIECE
; Input:
;   none
; Output:
;   active-piece state reset to spawn position
;   returns fault if spawn collides immediately
;   (`LCD_SHOW_RUNNING` left to callers on transitions that need UI refresh —
;    e.g. INIT_STATE_RESTART, HANDLE_SPLASH_STATE; omitted on mid-game respawn.)
; Clobbers:
;   A, D, E
SPAWN_ACTIVE_PIECE:
        CALL    SELECT_NEXT_PIECE
        LD      A,3
        LD      (PLAYER_X),A
        LD      A,SPAWN_Y
        LD      (PLAYER_Y),A
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A
        LD      A,NO_KEY
        LD      (LAST_KEY),A
        LD      A,3
        LD      (PENDING_X),A
        LD      A,SPAWN_Y
        LD      (PENDING_Y),A
        CALL    LOAD_DE_FROM_PENDING
        CALL    CHECK_COLLISION_AT_DE
        JR      C,SPAWN_FAILED
        LD      A,1
        LD      (ACTIVE_PIECE_ENABLED),A
        RET
SPAWN_FAILED:
        LD      A,0
        CALL    ENTER_GAME_OVER
        RET

; RENDER_BOARD_TO_BACK
; Input:
;   BOARD_RED / BOARD_GREEN / BOARD_BLUE, FRAMEBUFFER_BACK
; Output:
;   landed board copied into FRAMEBUFFER_BACK in native colours
; Clobbers:
;   A, C, D, E
RENDER_BOARD_TO_BACK:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      HL,FRAMEBUFFER_BACK
        LD      B,ROW_COUNT
        LD      C,0
RENDER_BOARD_ROW:
        LD      E,C
        LD      D,0
        PUSH    HL
        LD      HL,BOARD_RED
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        LD      (HL),A
        INC     HL

        PUSH    HL
        LD      HL,BOARD_GREEN
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        LD      (HL),A
        INC     HL

        PUSH    HL
        LD      HL,BOARD_BLUE
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        LD      (HL),A
        INC     HL
        INC     HL

        LD      A,(CLEAR_PENDING)
        OR      A
        JR      Z,RENDER_BOARD_ROW_NEXT
        PUSH    HL
        LD      H,0
        LD      L,C
        LD      DE,ROW_BIT_TABLE
        ADD     HL,DE
        LD      A,(CLEAR_MASK)
        AND     (HL)
        POP     HL
        JR      Z,RENDER_BOARD_ROW_NEXT
        DEC     HL
        DEC     HL
        DEC     HL
        DEC     HL
        LD      A,0xFF
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        LD      (HL),A
        INC     HL
        INC     HL
RENDER_BOARD_ROW_NEXT:
        INC     C
        DJNZ    RENDER_BOARD_ROW
RENDER_BOARD_TO_BACK_EXIT:
        POP     HL
        POP     DE
        POP     BC
        RET

; Draw the active 4x4 bitmap into the back buffer (same layout as live FB).
; RENDER_ACTIVE_TO_BACK
; Input:
;   PLAYER_X, PLAYER_Y, CURRENT_PIECE_PTR, CURRENT_PIECE_COLOR
; Output:
;   active piece ORed into FRAMEBUFFER_BACK in piece colour
; Clobbers:
;   A, C
RENDER_ACTIVE_TO_BACK:
        LD      A,(ACTIVE_PIECE_ENABLED)
        OR      A
        RET     Z
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,(PLAYER_X)
        LD      (SHIFT_COUNT),A
        LD      A,(PLAYER_Y)
        LD      L,A
        LD      H,0
        LD      DE,(CURRENT_PIECE_PTR)
        LD      B,4

RENDER_SHAPE_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        LD      A,C
        OR      A
        JR      Z,RENDER_SHAPE_NEXT_ROW
        BIT     7,L
        JR      NZ,RENDER_SHAPE_NEXT_ROW
        LD      A,L
        CP      ROW_COUNT
        JR      NC,RENDER_SHAPE_NEXT_ROW
        PUSH    HL
        PUSH    DE
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,FRAMEBUFFER_BACK
        ADD     HL,DE
        CALL    WRITE_COLORED_ROW_MASK
        POP     DE
        POP     HL
RENDER_SHAPE_NEXT_ROW:
        INC     DE
        INC     HL
        DJNZ    RENDER_SHAPE_ROW
RENDER_ACTIVE_TO_BACK_EXIT:
        POP     HL
        POP     DE
        POP     BC
        RET

; Candidate placement test.
; Input:
;   D = candidate x
;   E = candidate y
; Output:
;   carry set if placement collides or is out of bounds
;   carry clear if placement is legal
; Clobbers:
;   A, C
CHECK_COLLISION_AT_DE:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,D
        CP      X_MIN
        JR      C,COLLISION_TRUE_XBOUND
        LD      C,A
        LD      A,(CURRENT_PIECE_RIGHT)
        ADD     A,C
        CP      ROW_COUNT
        JR      NC,COLLISION_TRUE_XBOUND
        LD      A,D
        LD      (SHIFT_COUNT),A
        LD      A,E
        LD      L,A
        LD      H,0
        LD      B,4
        LD      DE,(CURRENT_PIECE_PTR)
        LD      A,(BOARD_EMPTY)
        OR      A
        JR      Z,CHECK_COLLISION_ROW
        JR      CHECK_COLLISION_EMPTY_BOARD_SIMPLE

CHECK_COLLISION_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        OR      A
        JR      Z,COLLISION_NEXT_ROW
        BIT     7,L
        JR      NZ,COLLISION_NEXT_ROW
        LD      A,L
        CP      ROW_COUNT
        JR      NC,COLLISION_TRUE_ROW_BOTTOM
        PUSH    HL
        PUSH    DE
        LD      H,0
        LD      DE,BOARD_ROWS
        ADD     HL,DE
        LD      A,(HL)
        AND     C
        POP     DE
        POP     HL
        JR      NZ,COLLISION_TRUE_ROW_OVERLAP
COLLISION_NEXT_ROW:
        INC     DE
        INC     HL
        DJNZ    CHECK_COLLISION_ROW
        OR      A
        JR      COLLISION_EXIT_OK

CHECK_COLLISION_EMPTY_BOARD_SIMPLE:
        LD      A,L
        LD      C,A
        LD      A,(CURRENT_PIECE_BOTTOM)
        ADD     A,C
        BIT     7,A
        JR      NZ,COLLISION_EMPTY_OK
        CP      ROW_COUNT
        JR      NC,COLLISION_TRUE_ROW_BOTTOM
COLLISION_EMPTY_OK:
        OR      A
        JR      COLLISION_EXIT_OK

COLLISION_TRUE_XBOUND:
        SCF
        JR      COLLISION_EXIT_OK

COLLISION_TRUE_ROW_BOTTOM:
        SCF
        JR      COLLISION_EXIT_OK

COLLISION_TRUE_ROW_OVERLAP:
        SCF
COLLISION_EXIT_OK:
        POP     HL
        POP     DE
        POP     BC
        RET

; CHECK_TOP_OUT_ON_LOCK
; Input:
;   PLAYER_Y, CURRENT_PIECE_PTR
; Output:
;   carry set if any occupied row of the active piece is still above the
;   visible field when the piece is about to lock
;   carry clear otherwise
; Clobbers:
;   A, B, DE, HL
CHECK_TOP_OUT_ON_LOCK:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,(PLAYER_Y)
        LD      L,A
        LD      H,0
        LD      DE,(CURRENT_PIECE_PTR)
        LD      B,4
TOP_OUT_ROW_LOOP:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        OR      A
        JR      Z,TOP_OUT_NEXT_ROW
        BIT     7,L
        JR      NZ,TOP_OUT_TRUE
TOP_OUT_NEXT_ROW:
        INC     DE
        INC     HL
        DJNZ    TOP_OUT_ROW_LOOP
        OR      A
        JR      TOP_OUT_EXIT
TOP_OUT_TRUE:
        SCF
TOP_OUT_EXIT:
        POP     HL
        POP     DE
        POP     BC
        RET

; ENTER_GAME_OVER
; Input:
;   A = game-over reason code
; Output:
;   GAME_OVER latched, active piece disabled, framebuffer rebuilt, LCD updated
; Clobbers:
;   A, B, HL
ENTER_GAME_OVER:
        PUSH    AF
        XOR     A
        LD      (ACTIVE_PIECE_ENABLED),A
        LD      A,1
        LD      (GAME_OVER),A
        POP     AF
        CALL    SOUND_TRIGGER_GAME_OVER
        CALL    REBUILD_FRAMEBUFFER
        JP      LCD_SHOW_GAME_OVER

; HANDLE_SPLASH_STATE
; Input:
;   SPLASH_TIMER / FRAME_PHASE
; Output:
;   waits for a fresh key press, then seeds the RNG and starts a new game
; Clobbers:
;   A, C
HANDLE_SPLASH_STATE:
        LD      C,API_SCANKEYS
        RST     0x10
        RET     NC
        XOR     A
        LD      (SPLASH_TIMER),A
        LD      A,(FRAME_PHASE)
        OR      A
        JR      NZ,HANDLE_SPLASH_SEED_READY
        LD      A,RNG_SEED_INIT
HANDLE_SPLASH_SEED_READY:
        LD      (RNG_SEED),A
        CALL    RNG_NEXT_PIECE
        LD      (NEXT_PIECE_INDEX),A
        LD      A,1
        LD      (INPUT_LOCKOUT),A
        CALL    SPAWN_ACTIVE_PIECE
        CALL    UPDATE_SCORE_DISPLAY
        CALL    LCD_SHOW_RUNNING
        JP      REBUILD_FRAMEBUFFER

; HANDLE_LINE_CLEAR_STATE
; Input:
;   CLEAR_PENDING / CLEAR_TIMER / LOGIC_SLICE in RAM
; Output:
;   advances clear-hold countdown once per full logic cycle
;   collapses full rows and spawns next piece when timer expires
; Clobbers:
;   A, B, D, E, HL
HANDLE_LINE_CLEAR_STATE:
        LD      A,(LOGIC_SLICE)
        OR      A
        RET     NZ
        LD      A,(CLEAR_TIMER)
        DEC     A
        LD      (CLEAR_TIMER),A
        RET     NZ
        CALL    COLLAPSE_FULL_ROWS
        CALL    APPLY_CLEAR_SCORE
        XOR     A
        LD      (CLEAR_PENDING),A
        CALL    RECOMPUTE_BOARD_EMPTY
        JP      SPAWN_ACTIVE_PIECE

; CHECK_FULL_ROWS
; Input:
;   BOARD_ROWS
; Output:
;   CLEAR_MASK updated
;   carry set if one or more rows are full
; Clobbers:
;   A, B, C, E, HL
CHECK_FULL_ROWS:
        LD      HL,BOARD_ROWS
        LD      B,ROW_COUNT
        LD      C,1
        XOR     A
        LD      E,A
CHECK_FULL_ROWS_LOOP:
        LD      A,(HL)
        CP      0xFF
        JR      NZ,CHECK_FULL_ROWS_NEXT
        LD      A,E
        OR      C
        LD      E,A
CHECK_FULL_ROWS_NEXT:
        INC     HL
        SLA     C
        DJNZ    CHECK_FULL_ROWS_LOOP
        LD      A,E
        LD      (CLEAR_MASK),A
        OR      A
        JR      Z,CHECK_FULL_ROWS_NONE
        SCF
        RET
CHECK_FULL_ROWS_NONE:
        OR      A
        RET

; COUNT_CLEAR_ROWS
; Input:
;   CLEAR_MASK
; Output:
;   A = number of set bits in CLEAR_MASK (0..8)
; Clobbers:
;   A, B, C
COUNT_CLEAR_ROWS:
        LD      A,(CLEAR_MASK)
        LD      C,A
        LD      B,0
COUNT_CLEAR_ROWS_LOOP:
        LD      A,C
        OR      A
        JR      Z,COUNT_CLEAR_ROWS_DONE
        SRL     C
        JR      NC,COUNT_CLEAR_ROWS_LOOP
        INC     B
        JR      COUNT_CLEAR_ROWS_LOOP
COUNT_CLEAR_ROWS_DONE:
        LD      A,B
        RET

; APPLY_CLEAR_SCORE
; Input:
;   CLEAR_MASK
; Output:
;   LINES_CLEARED_TOTAL incremented by number of cleared rows
;   SCORE updated using 100/300/500/800 for 1/2/3/4+ rows
; Clobbers:
;   A, D, E, HL
APPLY_CLEAR_SCORE:
        CALL    COUNT_CLEAR_ROWS
        OR      A
        RET     Z
        LD      E,A
        LD      A,(LINES_CLEARED_TOTAL)
        ADD     A,E
        LD      (LINES_CLEARED_TOTAL),A

        LD      A,E
        CP      1
        JR      NZ,APPLY_CLEAR_SCORE_CHECK2
        LD      DE,100
        JR      APPLY_CLEAR_SCORE_ADD
APPLY_CLEAR_SCORE_CHECK2:
        CP      2
        JR      NZ,APPLY_CLEAR_SCORE_CHECK3
        LD      DE,300
        JR      APPLY_CLEAR_SCORE_ADD
APPLY_CLEAR_SCORE_CHECK3:
        CP      3
        JR      NZ,APPLY_CLEAR_SCORE_CHECK4
        LD      DE,500
        JR      APPLY_CLEAR_SCORE_ADD
APPLY_CLEAR_SCORE_CHECK4:
        LD      DE,800
APPLY_CLEAR_SCORE_ADD:
        LD      HL,(SCORE_LO)
        ADD     HL,DE
        LD      (SCORE_LO),HL
        JP      UPDATE_SCORE_DISPLAY

; COLLAPSE_FULL_ROWS
; Input:
;   CLEAR_MASK, BOARD_ROWS, BOARD_RED, BOARD_GREEN, BOARD_BLUE
; Output:
;   completed rows removed, rows above collapsed downward
; Clobbers:
;   A, B, C, D, E, HL
COLLAPSE_FULL_ROWS:
        LD      B,ROW_COUNT
        LD      D,ROW_COUNT-1
        LD      E,ROW_COUNT-1
COLLAPSE_SCAN_LOOP:
        LD      A,D
        LD      L,A
        LD      H,0
        PUSH    BC
        LD      BC,ROW_BIT_TABLE
        ADD     HL,BC
        LD      A,(CLEAR_MASK)
        AND     (HL)
        POP     BC
        JR      NZ,COLLAPSE_SKIP_ROW
        LD      A,D
        CP      E
        JR      Z,COLLAPSE_ROW_DONE
        PUSH    BC
        PUSH    DE
        CALL    COPY_BOARD_ROW_DE_TO_E
        POP     DE
        POP     BC
COLLAPSE_ROW_DONE:
        DEC     E
COLLAPSE_SKIP_ROW:
        DEC     D
        DJNZ    COLLAPSE_SCAN_LOOP

        LD      A,E
        INC     A
        RET     Z
        LD      B,A
        XOR     A
        LD      D,A
COLLAPSE_CLEAR_TOP_LOOP:
        PUSH    BC
        CALL    CLEAR_BOARD_ROW_D
        POP     BC
        INC     D
        DJNZ    COLLAPSE_CLEAR_TOP_LOOP
        RET

; COPY_BOARD_ROW_D_TO_E
; Input:
;   D = source row index
;   E = destination row index
; Output:
;   BOARD_ROWS and landed RGB planes copied from D to E
; Clobbers:
;   A, BC, HL
COPY_BOARD_ROW_DE_TO_E:
        LD      A,D
        LD      L,A
        LD      H,0
        LD      BC,BOARD_ROWS
        ADD     HL,BC
        LD      A,(HL)
        PUSH    AF
        LD      A,E
        LD      L,A
        LD      H,0
        LD      BC,BOARD_ROWS
        ADD     HL,BC
        POP     AF
        LD      (HL),A

        LD      A,D
        LD      L,A
        LD      H,0
        LD      BC,BOARD_RED
        ADD     HL,BC
        LD      A,(HL)
        PUSH    AF
        LD      A,E
        LD      L,A
        LD      H,0
        LD      BC,BOARD_RED
        ADD     HL,BC
        POP     AF
        LD      (HL),A

        LD      A,D
        LD      L,A
        LD      H,0
        LD      BC,BOARD_GREEN
        ADD     HL,BC
        LD      A,(HL)
        PUSH    AF
        LD      A,E
        LD      L,A
        LD      H,0
        LD      BC,BOARD_GREEN
        ADD     HL,BC
        POP     AF
        LD      (HL),A

        LD      A,D
        LD      L,A
        LD      H,0
        LD      BC,BOARD_BLUE
        ADD     HL,BC
        LD      A,(HL)
        PUSH    AF
        LD      A,E
        LD      L,A
        LD      H,0
        LD      BC,BOARD_BLUE
        ADD     HL,BC
        POP     AF
        LD      (HL),A
        RET

; CLEAR_BOARD_ROW_D
; Input:
;   D = row index
; Output:
;   row cleared in occupancy and RGB planes
; Clobbers:
;   A, BC, HL
CLEAR_BOARD_ROW_D:
        XOR     A
        LD      L,D
        LD      H,0
        LD      BC,BOARD_ROWS
        ADD     HL,BC
        LD      (HL),A
        LD      L,D
        LD      H,0
        LD      BC,BOARD_RED
        ADD     HL,BC
        LD      (HL),A
        LD      L,D
        LD      H,0
        LD      BC,BOARD_GREEN
        ADD     HL,BC
        LD      (HL),A
        LD      L,D
        LD      H,0
        LD      BC,BOARD_BLUE
        ADD     HL,BC
        LD      (HL),A
        RET

; RECOMPUTE_BOARD_EMPTY
; Input:
;   BOARD_ROWS
; Output:
;   BOARD_EMPTY updated from occupancy rows
; Clobbers:
;   A, B, HL
RECOMPUTE_BOARD_EMPTY:
        LD      HL,BOARD_ROWS
        LD      B,ROW_COUNT
RECOMPUTE_BOARD_EMPTY_LOOP:
        LD      A,(HL)
        OR      A
        JR      NZ,BOARD_NOT_EMPTY
        INC     HL
        DJNZ    RECOMPUTE_BOARD_EMPTY_LOOP
        LD      A,1
        LD      (BOARD_EMPTY),A
        RET
BOARD_NOT_EMPTY:
        XOR     A
        LD      (BOARD_EMPTY),A
        RET

; MERGE_ACTIVE_TO_BOARD
; Input:
;   PLAYER_X, PLAYER_Y, CURRENT_PIECE_PTR, CURRENT_PIECE_COLOR
; Output:
;   active piece ORed into BOARD_ROWS and landed RGB planes
; Clobbers:
;   A, C
MERGE_ACTIVE_TO_BOARD:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        XOR     A
        LD      (BOARD_EMPTY),A
        LD      A,(PLAYER_X)
        LD      (SHIFT_COUNT),A
        LD      A,(PLAYER_Y)
        LD      L,A
        LD      H,0
        LD      DE,(CURRENT_PIECE_PTR)
        LD      B,4

MERGE_BOARD_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        LD      A,C
        OR      A
        JR      Z,MERGE_BOARD_NEXT
        BIT     7,L
        JR      NZ,MERGE_BOARD_NEXT
        LD      A,L
        CP      ROW_COUNT
        JR      NC,MERGE_BOARD_NEXT
        PUSH    HL
        PUSH    DE
        LD      H,0
        LD      DE,BOARD_ROWS
        ADD     HL,DE
        LD      A,(HL)
        OR      C
        LD      (HL),A
        POP     DE
        POP     HL
        PUSH    HL
        PUSH    DE
        LD      A,(CURRENT_PIECE_COLOR)
        BIT     0,A
        JR      Z,MERGE_SKIP_RED
        LD      H,0
        LD      DE,BOARD_RED
        ADD     HL,DE
        LD      A,(HL)
        OR      C
        LD      (HL),A
MERGE_SKIP_RED:
        POP     DE
        POP     HL
        PUSH    HL
        PUSH    DE
        LD      A,(CURRENT_PIECE_COLOR)
        BIT     1,A
        JR      Z,MERGE_SKIP_GREEN
        LD      H,0
        LD      DE,BOARD_GREEN
        ADD     HL,DE
        LD      A,(HL)
        OR      C
        LD      (HL),A
MERGE_SKIP_GREEN:
        POP     DE
        POP     HL
        PUSH    HL
        PUSH    DE
        LD      A,(CURRENT_PIECE_COLOR)
        BIT     2,A
        JR      Z,MERGE_SKIP_BLUE
        LD      H,0
        LD      DE,BOARD_BLUE
        ADD     HL,DE
        LD      A,(HL)
        OR      C
        LD      (HL),A
MERGE_SKIP_BLUE:
        POP     DE
        POP     HL
MERGE_BOARD_NEXT:
        INC     DE
        INC     HL
        DJNZ    MERGE_BOARD_ROW
MERGE_ACTIVE_TO_BOARD_EXIT:
        POP     HL
        POP     DE
        POP     BC
        RET

; OR mask C into the colour planes selected by CURRENT_PIECE_COLOR.
; On exit, HL = this row's blue (aux byte 3 not used by scan, not written).
; WRITE_COLORED_ROW_MASK
; Input:
;   HL = framebuffer row red-byte address
;   C  = row mask
; Output:
;   mask ORed into enabled red, green, blue bytes
;   HL = blue-byte address on return
; Clobbers:
;   A, HL
WRITE_COLORED_ROW_MASK:
        LD      A,(CURRENT_PIECE_COLOR)
        BIT     0,A
        JR      Z,WRITE_SKIP_RED
        LD      A,(HL)
        OR      C
        LD      (HL),A
WRITE_SKIP_RED:
        INC     HL

        LD      A,(CURRENT_PIECE_COLOR)
        BIT     1,A
        JR      Z,WRITE_SKIP_GREEN
        LD      A,(HL)
        OR      C
        LD      (HL),A
WRITE_SKIP_GREEN:
        INC     HL

        LD      A,(CURRENT_PIECE_COLOR)
        BIT     2,A
        JR      Z,WRITE_SKIP_BLUE
        LD      A,(HL)
        OR      C
        LD      (HL),A
WRITE_SKIP_BLUE:
        RET

; Shift row mask in A right by SHIFT_COUNT positions to place it at global x.
; SHIFT_ROW_MASK
; Input:
;   A = unshifted row mask
;   SHIFT_COUNT = logical x placement
; Output:
;   A = shifted row mask
; Clobbers:
;   A, C
SHIFT_ROW_MASK:
        LD      C,A
        LD      A,(SHIFT_COUNT)
        OR      A
        JR      Z,SHIFT_ROW_DONE
SHIFT_ROW_LOOP:
        SRL     C
        DEC     A
        JR      NZ,SHIFT_ROW_LOOP
SHIFT_ROW_DONE:
        LD      A,C
        RET
