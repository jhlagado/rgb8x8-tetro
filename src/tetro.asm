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
;   rotate (0x12) = clockwise rotate
;   AD     (0x13) = counter-clockwise rotate
;   3      (0x03) = clockwise rotate
;   2      (0x02) = counter-clockwise rotate
;   0      (0x00) = soft drop
;   F      (0x0F) = pause
;
; Design:
;   - One scanline is output per main-loop iteration.
;   - Game work is split across 8 slices (LOGIC_SLICE 0-7 on each pass).
;   - The framebuffer is 8 rows x 4 bytes (R/G/B/Aux).
;   - The landed board is stored as RGB bitplanes plus monochrome occupancy.
;   - The active object is a 4x4 bitmap blitted in its piece colour over the board.
;   - Pieces are selected from a PRNG-driven 7-piece stream with preview.

        ORG     0x4000

        .include "inc/constants.asm"

START:
        CALL    INIT_STATE

MAIN_LOOP:
        CALL    SCAN_TICK
        CALL    LOGIC_TICK
        JR      MAIN_LOOP

        .include "modules/gameplay.asm"
        .include "modules/ui.asm"
        .include "modules/data.asm"
        .include "modules/ram.asm"
