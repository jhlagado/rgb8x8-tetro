; TEC-1G matrix ports
PORT_DIGITS:    EQU     0x01
PORT_SEGS:      EQU     0x02
PORT_LCD_INST:  EQU     0x04
PORT_ROW:       EQU     0x05
PORT_RED:       EQU     0x06
PORT_LCD_DATA:  EQU     0x84
PORT_GREEN:     EQU     0xF8
PORT_BLUE:      EQU     0xF9

LCD_ROW1:       EQU     0x80
LCD_ROW2:       EQU     0xC0
LCD_ROW3:       EQU     0x94
LCD_ROW4:       EQU     0xD4

; MON-3 API / keypad constants
API_SCANKEYS:   EQU     16
K_LEFT:         EQU     0x10
K_RIGHT:        EQU     0x11
K_ROTATE:       EQU     0x12
K_ROTATE_CCW:   EQU     0x13
K_ROTATE_ALT:   EQU     0x03
K_ROTATE_CCW_ALT: EQU   0x02
K_DROP:         EQU     0x00
K_PAUSE:        EQU     0x0F
NO_KEY:         EQU     0xFF

; Matrix / game constants
ROW_COUNT:      EQU     8
BYTES_PER_ROW:  EQU     4
FRAMEBUFFER_BYTES: EQU  32
MOVE_PERIOD:    EQU     16
DROP_PERIOD:    EQU     1
; Decremented once per full 8-slice pass (in slice 1). Larger = slower fall.
GRAVITY_PERIOD: EQU     160
LINE_CLEAR_HOLD: EQU    24
RNG_SEED_INIT:  EQU     0x5A
X_MIN:          EQU     0
Y_MIN:          EQU     0
Y_MAX:          EQU     7
SPAWN_Y:        EQU     0xFD
PIECE_COUNT:    EQU     7
SCAN_MASK_START: EQU    0x01
COLOR_RED:      EQU     0x01
COLOR_GREEN:    EQU     0x02
COLOR_BLUE:     EQU     0x04
SPEAKER_BIT:    EQU     0x80
SOUND_ROTATE_LEN: EQU   24
SOUND_ROTATE_DIV: EQU   2
SOUND_LOCK_LEN: EQU     32
SOUND_LOCK_DIV: EQU     4
SOUND_CLEAR_LEN: EQU    72
SOUND_CLEAR_DIV: EQU    2
SOUND_GAME_OVER_LEN: EQU 120
SOUND_GAME_OVER_DIV: EQU 6
