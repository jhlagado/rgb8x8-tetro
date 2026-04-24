; TEC-1G tetro
; ------------------
; Minimal interactive 8x8 RGB matrix example for the MON-3 layout.
;
; Goal:
;   Prove the scanline-tick architecture with the smallest visible program:
;   a 4x4 bitmap shape moved left/right and down by frame-driven gravity while
;   the display is scanned one row at a time, freezing into a landed board on
;   collision and respawning a new active piece.
;
; Controls (MON-3 key codes):
;   left  (0x10) = move left
;   right (0x11) = move right
;
; Design:
;   - One scanline is output per main-loop iteration.
;   - The scan state is persistent:
;       scan_mask = current row enable bit
;       scan_ptr  = framebuffer pointer for that row
;   - One full display frame = 8 scan ticks; LOGIC runs after every tick (no
;     gating on SCAN_MASK) so the CPU budget is spread between scanlines. That
;     evens the delay between row updates and gives more uniform row on-time
;     and POV (avoids one long gap every 8 lines).
;   - Game work is split across 8 slices (LOGIC_SLICE 0-7 on each pass):
;       slice0: input + clear 4 bytes of back buffer
;       slice1: gravity + clear 4 bytes
;       slices 2-6: each clears the next 4 bytes (covering 0..27 in order)
;       slice7: clear last 4 bytes, render 4x4 bitmap to back buffer, LDIR
;       32B to visible FB so the on-screen image updates in one copy (no
;       half-drawn frame in the live buffer).
;   - The framebuffer is 8 rows x 4 bytes:
;       byte 0 = red plane
;       byte 1 = green plane
;       byte 2 = blue plane
;       byte 3 = aux plane (reserved, not currently scanned)
;   - A monochrome landed board is rendered first.
;   - The active object is a 4x4 bitmap blitted in white over the board.
;   - Current test shape: T piece, rotation 0.
;   - Code and constant tables live together above an explicit RAM block.
;     Mutable state and framebuffers are laid out from RAM_START and are
;     initialized by INIT_STATE rather than relying on embedded ROM values.

        ORG     0x4000

; TEC-1G matrix ports
PORT_ROW:       EQU     0x05
PORT_RED:       EQU     0x06
PORT_GREEN:     EQU     0xF8
PORT_BLUE:      EQU     0xF9

; MON-3 API / keypad constants
API_SCANKEYS:   EQU     16
K_LEFT:         EQU     0x10
K_RIGHT:        EQU     0x11

; Matrix / game constants
ROW_COUNT:      EQU     8
BYTES_PER_ROW:  EQU     4
FRAMEBUFFER_BYTES: EQU  32
MOVE_PERIOD:    EQU     16
; Decremented once per full 8-slice pass (in slice 1). Larger = slower fall.
GRAVITY_PERIOD: EQU     128
X_MIN:          EQU     0
X_MAX:          EQU     5
Y_MIN:          EQU     0
Y_MAX:          EQU     4
SCAN_MASK_START: EQU    0x01

START:
        CALL    INIT_STATE

MAIN_LOOP:
        CALL    SCAN_TICK
        CALL    LOGIC_TICK
        JR      MAIN_LOOP

; INIT_STATE
; Input:
;   none
; Output:
;   initialized runtime state in RAM
; Clobbers:
;   A, HL
INIT_STATE:
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A

        XOR     A
        LD      (LAST_KEY),A
        LD      (FRAME_PHASE),A
        LD      (LOGIC_SLICE),A

        LD      A,SCAN_MASK_START
        LD      (SCAN_MASK),A

        LD      HL,FRAMEBUFFER
        LD      (SCAN_PTR),HL

        CALL    CLEAR_BOARD
        CALL    SPAWN_ACTIVE_PIECE
        JP      REBUILD_FRAMEBUFFER

; Output one scanline, then advance persistent scan state.
; SCAN_TICK
; Input:
;   uses SCAN_PTR / SCAN_MASK from RAM
; Output:
;   one matrix row emitted to hardware ports
; Clobbers:
;   A, HL
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
        CALL    RENDER_ACTIVE_TO_BACK
        CALL    COPY_BACK_TO_FRONT
        JR      LOGIC_SLICE_NEXT

LOGIC_SL0:
        CALL    POLL_INPUT_AND_UPDATE
        XOR     A
        CALL    CLEAR_BACK_4
        JR      LOGIC_SLICE_NEXT

LOGIC_SL1:
        CALL    APPLY_GRAVITY
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
        JR      NZ,RESET_MOVE_RATE

        CP      K_LEFT
        JR      Z,HANDLE_KEY_LEFT
        CP      K_RIGHT
        JR      Z,HANDLE_KEY_RIGHT

RESET_MOVE_RATE:
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        XOR     A
        LD      (LAST_KEY),A
        RET

HANDLE_KEY_RIGHT:
        LD      A,K_RIGHT
        JP      HANDLE_HELD_DIRECTION

HANDLE_KEY_LEFT:
        LD      A,K_LEFT
        ; fall through

; Input:
;   A = direction key (K_LEFT or K_RIGHT)
; HANDLE_HELD_DIRECTION
; Input:
;   A = direction key code
; Output:
;   may update PLAYER_X / MOVE_COOLDOWN / LAST_KEY
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

        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,E
        CP      K_LEFT
        JR      Z,MOVE_LEFT

; MOVE_RIGHT
; Input:
;   none
; Output:
;   may increment PLAYER_X if candidate placement is legal
; Clobbers:
;   A, D, E
MOVE_RIGHT:
        LD      A,(PLAYER_X)
        CP      X_MAX
        RET     Z
        INC     A
        LD      (PENDING_X),A
        LD      A,(PLAYER_Y)
        LD      (PENDING_Y),A
        LD      A,(PENDING_X)
        LD      D,A
        LD      A,(PENDING_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        RET     C
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
        LD      A,(PENDING_X)
        LD      D,A
        LD      A,(PENDING_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        RET     C
        LD      A,(PENDING_X)
        LD      (PLAYER_X),A
        RET

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
        LD      A,(PENDING_X)
        LD      D,A
        LD      A,(PENDING_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        JR      C,LOCK_ACTIVE_PIECE
        LD      A,(PENDING_Y)
        LD      (PLAYER_Y),A
        RET

LOCK_ACTIVE_PIECE:
        CALL    MERGE_ACTIVE_TO_BOARD
        CALL    SPAWN_ACTIVE_PIECE
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
;   BOARD_ROWS cleared to zero
; Clobbers:
;   A, B, HL
CLEAR_BOARD:
        LD      HL,BOARD_ROWS
        LD      B,ROW_COUNT
        XOR     A
CLEAR_BOARD_LOOP:
        LD      (HL),A
        INC     HL
        DJNZ    CLEAR_BOARD_LOOP
        RET

; SPAWN_ACTIVE_PIECE
; Input:
;   none
; Output:
;   active-piece state reset to spawn position
;   may clear BOARD_ROWS if spawn collides immediately
; Clobbers:
;   A, D, E
SPAWN_ACTIVE_PIECE:
        LD      A,3
        LD      (PLAYER_X),A
        XOR     A
        LD      (PLAYER_Y),A
        LD      A,MOVE_PERIOD
        LD      (MOVE_COOLDOWN),A
        LD      A,GRAVITY_PERIOD
        LD      (GRAVITY_COOLDOWN),A
        XOR     A
        LD      (LAST_KEY),A
        LD      A,3
        LD      (PENDING_X),A
        XOR     A
        LD      (PENDING_Y),A
        LD      A,(PENDING_X)
        LD      D,A
        LD      A,(PENDING_Y)
        LD      E,A
        CALL    CHECK_COLLISION_AT_DE
        RET     NC
        CALL    CLEAR_BOARD
        LD      A,3
        LD      (PLAYER_X),A
        XOR     A
        LD      (PLAYER_Y),A
        RET

; RENDER_BOARD_TO_BACK
; Input:
;   BOARD_ROWS, FRAMEBUFFER_BACK
; Output:
;   landed board ORed into FRAMEBUFFER_BACK in white
; Clobbers:
;   A, B, C, D, E, HL
RENDER_BOARD_TO_BACK:
        LD      HL,BOARD_ROWS
        LD      DE,FRAMEBUFFER_BACK
        LD      B,ROW_COUNT
RENDER_BOARD_ROW:
        LD      A,(HL)
        LD      C,A
        EX      DE,HL
        CALL    WRITE_WHITE_ROW_MASK
        INC     HL
        EX      DE,HL
        INC     HL
        DJNZ    RENDER_BOARD_ROW
        RET

; Draw the active 4x4 bitmap into the back buffer (same layout as live FB).
; RENDER_ACTIVE_TO_BACK
; Input:
;   PLAYER_X, PLAYER_Y, PIECE_T0
; Output:
;   active piece ORed into FRAMEBUFFER_BACK in white
; Clobbers:
;   A, B, C, D, E, HL
RENDER_ACTIVE_TO_BACK:
        LD      A,(PLAYER_Y)
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,FRAMEBUFFER_BACK
        ADD     HL,DE

        LD      A,(PLAYER_X)
        LD      (SHIFT_COUNT),A
        LD      DE,PIECE_T0
        LD      B,4

RENDER_SHAPE_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        CALL    WRITE_WHITE_ROW_MASK
        INC     HL
        INC     HL
        INC     DE
        DJNZ    RENDER_SHAPE_ROW
        RET

; Candidate placement test.
; Input:
;   D = candidate x
;   E = candidate y
; Output:
;   carry set if placement collides or is out of bounds
;   carry clear if placement is legal
; Clobbers:
;   A, B, C, D, E, HL, BC
CHECK_COLLISION_AT_DE:
        LD      A,D
        CP      X_MIN
        JR      C,COLLISION_TRUE
        CP      X_MAX+1
        JR      NC,COLLISION_TRUE
        LD      (SHIFT_COUNT),A
        LD      A,E
        CP      Y_MAX+1
        JR      NC,COLLISION_TRUE

        PUSH    DE
        LD      HL,PIECE_T0
        EX      DE,HL

        POP     DE
        LD      A,E
        LD      L,A
        LD      H,0
        LD      BC,BOARD_ROWS
        ADD     HL,BC
        LD      B,4

CHECK_COLLISION_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        LD      A,(HL)
        AND     C
        JR      NZ,COLLISION_TRUE
        INC     DE
        INC     HL
        DJNZ    CHECK_COLLISION_ROW
        OR      A
        RET
COLLISION_TRUE:
        SCF
        RET

; MERGE_ACTIVE_TO_BOARD
; Input:
;   PLAYER_X, PLAYER_Y, PIECE_T0
; Output:
;   active piece ORed into BOARD_ROWS
; Clobbers:
;   A, B, C, D, E, HL, BC
MERGE_ACTIVE_TO_BOARD:
        LD      A,(PLAYER_X)
        LD      (SHIFT_COUNT),A
        LD      DE,PIECE_T0

        LD      A,(PLAYER_Y)
        LD      L,A
        LD      H,0
        LD      BC,BOARD_ROWS
        ADD     HL,BC
        LD      B,4

MERGE_BOARD_ROW:
        LD      A,(DE)
        CALL    SHIFT_ROW_MASK
        LD      C,A
        LD      A,(HL)
        OR      C
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    MERGE_BOARD_ROW
        RET

; OR mask C into red, green, and blue of the row (HL = row R on entry).
; On exit, HL = this row's blue (aux byte 3 not used by scan, not written).
; WRITE_WHITE_ROW_MASK
; Input:
;   HL = framebuffer row red-byte address
;   C  = row mask
; Output:
;   mask ORed into red, green, blue bytes
;   HL = blue-byte address on return
; Clobbers:
;   A, HL
WRITE_WHITE_ROW_MASK:
        LD      A,(HL)
        OR      C
        LD      (HL),A
        INC     HL

        LD      A,(HL)
        OR      C
        LD      (HL),A
        INC     HL

        LD      A,(HL)
        OR      C
        LD      (HL),A
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

; Current test bitmap: T piece, rotation 0.
; Stored once, bottom-aligned in the 4x4 box. Horizontal placement is applied
; at runtime by shifting each row mask right by PLAYER_X / candidate x.
PIECE_T0:
        DB      %00000000
        DB      %00000000
        DB      %11100000
        DB      %01000000

; RAM layout.
; These bytes are mutable program state. INIT_STATE sets explicit defaults
; and clears the buffers that need a known startup value.
RAM_START:
PLAYER_X:
        DS      1

PLAYER_Y:
        DS      1

MOVE_COOLDOWN:
        DS      1

GRAVITY_COOLDOWN:
        DS      1

LAST_KEY:
        DS      1

PENDING_POS:
        DS      1

PENDING_X:
        DS      1

PENDING_Y:
        DS      1

SHIFT_COUNT:
        DS      1

FRAME_PHASE:
        DS      1

LOGIC_SLICE:
        DS      1

SCAN_MASK:
        DS      1

SCAN_PTR:
        DS      2

BOARD_ROWS:
        DS      ROW_COUNT

FRAMEBUFFER:
        DS      FRAMEBUFFER_BYTES

; Off-screen compose buffer; visible FB is updated atomically from here in slice 7.
FRAMEBUFFER_BACK:
        DS      FRAMEBUFFER_BYTES

RAM_END:
