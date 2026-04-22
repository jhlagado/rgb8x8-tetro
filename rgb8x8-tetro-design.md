# Falling-Block Data Model for TEC-1G / Z80

This note extracts the useful game-logic ideas from the Arduino WS2812 implementation and rewrites them for the real TEC-1G constraints.

The Arduino version is **not** a timing model for this project. It assumes a self-refreshing LED strip and uses `millis()` / `delay()`. On the TEC-1G RGB matrix, the display must be scanned continuously, so game logic must fit around the scan loop instead of blocking it.

## Scope

This is a data-model and update-model note only. It does **not** define:

- the final matrix scan implementation
- keypad driver internals
- LCD / 7-seg HUD routines
- sound

It does define:

- board representation
- piece representation
- update phases
- framebuffer rendering contract

## Core rule

The raster is the metronome.

That means:

- one frame = one full 8-row matrix refresh
- input polling happens at a frame boundary
- game logic runs at a frame boundary
- delays are counted in frames, not blind busy-waits

The current `tetro.asm` already proves that loop shape at the simplest playable-object level.

## Logical layers

The game should stay split into three layers:

1. **Board state**
   Fixed occupied cells already landed.

2. **Active piece state**
   Current tetromino type, rotation, and position.

3. **Render projection**
   Convert board + active piece into the 32-byte RGB+Aux scan framebuffer.

That separation is the main reusable architectural idea from the Arduino code.

## Board representation

For an 8x8 display, the simplest useful board is:

- width: 8
- height: 8
- each cell stores either empty or occupied
- optional second plane stores colour

Recommended first representation:

```text
board_rows[8] : 1 byte per row
```

Each byte uses one bit per column:

- bit 7 = x 0
- bit 6 = x 1
- ...
- bit 0 = x 7

This gives:

- cheap collision checks
- cheap line-full tests
- cheap line clears and row shifts

If colour is needed, add parallel colour planes:

```text
board_red[8]
board_green[8]
board_blue[8]
```

That matches the scan-native framebuffer model directly.

## Active piece representation

The Arduino `Tetromino` struct is conceptually good, and its piece set / rotation geometry should be treated as the current design reference:

- 7 piece types
- 4 rotations
- 4 cells per rotation

The intended piece set is:

- `I`
- `O`
- `T`
- `S`
- `Z`
- `J`
- `L`

The intended rotation geometry is:

```text
I:
  rot0: (0,0) (1,0) (2,0) (3,0)
  rot1: (0,0) (0,1) (0,2) (0,3)
  rot2: (0,0) (1,0) (2,0) (3,0)
  rot3: (0,0) (0,1) (0,2) (0,3)

O:
  rot0..3: (0,0) (1,0) (0,1) (1,1)

T:
  rot0: (0,0) (1,0) (2,0) (1,1)
  rot1: (1,0) (0,1) (1,1) (1,2)
  rot2: (1,0) (0,1) (1,1) (2,1)
  rot3: (0,0) (0,1) (0,2) (1,1)

S:
  rot0: (1,0) (2,0) (0,1) (1,1)
  rot1: (0,0) (0,1) (1,1) (1,2)
  rot2: (1,0) (2,0) (0,1) (1,1)
  rot3: (0,0) (0,1) (1,1) (1,2)

Z:
  rot0: (0,0) (1,0) (1,1) (2,1)
  rot1: (1,0) (0,1) (1,1) (0,2)
  rot2: (0,0) (1,0) (1,1) (2,1)
  rot3: (1,0) (0,1) (1,1) (0,2)

J:
  rot0: (0,0) (0,1) (1,1) (2,1)
  rot1: (1,0) (2,0) (1,1) (1,2)
  rot2: (0,0) (1,0) (2,0) (2,1)
  rot3: (0,0) (0,1) (0,2) (1,0)

L:
  rot0: (2,0) (0,1) (1,1) (2,1)
  rot1: (0,0) (1,0) (1,1) (1,2)
  rot2: (0,0) (1,0) (2,0) (0,1)
  rot3: (0,0) (0,1) (0,2) (1,2)
```

For Z80, the cleaner representation is a packed bitmap per rotation rather than a list of four coordinate pairs.

Recommended shape:

```text
piece_table[7][4]
```

Each entry is a 16-bit 4x4 bitmap:

- bits represent a 4x4 local cell grid
- top nibble = local row 0
- next nibble = local row 1
- next nibble = local row 2
- bottom nibble = local row 3

Example idea:

```text
I horizontal = 1111 0000 0000 0000
I vertical   = 1000 1000 1000 1000
O piece      = 1100 1100 0000 0000
```

Why this is better for Z80:

- fixed-size data
- fixed-cost row extraction
- easier clipping and collision loops
- avoids coordinate-table chasing in hot code

## Active piece state

Keep the current falling piece state minimal:

```text
current_piece      ; 0..6
current_rotation   ; 0..3
current_x          ; board x of 4x4 local origin
current_y          ; board y of 4x4 local origin
```

Optional later:

```text
next_piece
score
level
lines_cleared
```

## Update phases

The Arduino loop had the right high-level phases but the wrong timing source. For TEC-1G the phases should be driven by frame counts.

Recommended outer structure:

1. refresh matrix for one frame
2. poll keypad
3. update per-frame timers
4. process player action
5. process gravity tick if due
6. rebuild framebuffer
7. repeat

That becomes two time domains:

- **frame domain**
  Runs every full matrix refresh.

- **game tick domain**
  Runs every `N` frames.

Example:

- poll input every frame
- horizontal move repeat every 4 frames
- gravity every 20 frames

This is much better than trying to run all gameplay every raw scan pass.

## State machine

The active game should be treated as a small explicit state machine:

1. `spawn`
2. `control`
3. `fall`
4. `lock`
5. `clear`
6. `game_over`

That matters because it keeps worst-case work bounded.

### Spawn

- choose piece
- reset rotation / position
- validate spawn position
- if invalid: `game_over`

### Control

- read one player intent from current input state
- try move left / right
- optionally try rotate

This should stay bounded:

- one lateral move attempt
- one rotation attempt

### Fall

- only when gravity timer expires
- try `y + 1`
- if valid: move piece down
- if invalid: transition to `lock`

### Lock

- merge active piece into board bitmaps
- transition to `clear`

### Clear

- check full rows
- compact board downward if needed
- update score / counters
- transition to `spawn`

This is the first place where multi-step handling may be useful if the line-clear animation becomes expensive. The initial version can do it in one pass because the board is only 8x8.

## Collision contract

The Arduino `isValidPosition()` abstraction is worth keeping.

On Z80 it should become something like:

```text
piece_fits(piece, rotation, x, y) -> carry clear/set or zero/nonzero
```

It must check:

- piece cells stay within board bounds
- piece cells do not overlap occupied board cells

Do not make this a variable-shape routine that walks sparse coordinates in different-length branches. Prefer a fixed 4-row loop over the 4x4 bitmap.

## Rendering contract

The scan loop should never know about tetromino rules.

Rendering should happen in two steps:

1. clear or rebuild a logical framebuffer from game state
2. scan that framebuffer to hardware

Current scan-native framebuffer:

```text
framebuffer[32]
row0: R,G,B,Aux
row1: R,G,B,Aux
...
row7: R,G,B,Aux
```

Recommended render flow:

1. clear framebuffer or compose into a back buffer
2. copy landed board colours into framebuffer
3. overlay active piece colour into framebuffer

For a first falling-block game, colour can stay simple:

- each piece type owns one RGB colour
- landed blocks keep their piece colour

## Colour model

The hardware supports 3-bit colour:

- red
- green
- blue

So the natural colour encoding is:

```text
0 = black
1 = red
2 = green
3 = yellow
4 = blue
5 = magenta
6 = cyan
7 = white
```

Store either:

- packed colour per board cell, then expand during render

or:

- separate landed colour bitplanes directly

For the smallest and fastest renderer on this machine, separate bitplanes are likely better once the game graduates from the single-pixel demo.

## Input model

Do not copy the Arduino debounce approach.

Use MON-3 key services and express behavior in frame counters:

- new press
- held repeat
- repeat period in frames

That matches the current `tetro.asm` direction, including the newer scanline-sliced logic model.

## What to build next

Recommended progression after `tetro`:

1. **4x4 solid test box**
   Prove the general blitter and scan-sliced rendering path.

2. **Single non-solid 4x4 bitmap**
   Swap in a recognizable shape such as `T` or `L`.

3. **Board collision**
   First real collision against landed board state.

4. **Spawn + lock**
   Introduce active-piece lifecycle.

5. **Board row clear**
   First scoring / clear behavior.

6. **Full 7-piece table**
   Add the full `I O T S Z J L` set with the reference rotation geometry above.

This path keeps the real-time loop stable while the game model grows.

## What not to copy from the Arduino code

Do not import these assumptions:

- `millis()` and `delay()` as primary timing
- redraw-then-idle display model
- matrix text as the main score UI
- long blocking flash / sound effects in gameplay path

Those are valid on WS2812 and wrong for the TEC-1G raster problem.

## Bottom line

The Arduino project is useful as a **game-logic reference**, not as a runtime model.

For the TEC-1G version:

- keep the board / piece / collision / state-machine ideas
- replace the timing, input, and display assumptions completely
- render into the 32-byte RGB+Aux framebuffer
- treat frame count as time

That is the correct bridge from the Arduino implementation to a Z80 / MON-3 / scan-driven design.
