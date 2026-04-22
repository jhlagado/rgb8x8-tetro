# rgb8x8-tetro

Small TEC-1G experiments for working out the timing and structure of RGB matrix programs under MON-3.

## Current target

`tetro`

This is intentionally minimal. It exists to prove the full interactive loop:

- output one scanline per main-loop iteration
- keep persistent scan state in RAM
- poll keypad input through MON-3
- update a tiny bit of game state once per full display frame
- rebuild the framebuffer from logical state

The visible result is a 2x2 white block that moves left and right.

## Controls

- `+` moves left
- `-` moves right

## Why this shape

The first problem to solve is not text, score, sprites, or richer colour usage. It is proving that the scan/poll/update loop is stable and understandable on the real hardware model.

This target therefore keeps the design narrow:

- scan is time-sliced: one row per tick, not a whole-frame burst
- scan state is persistent:
  - `scan_mask`
  - `scan_ptr`
- framebuffer uses the new 32-byte layout: `R,G,B,Aux` for each of 8 rows
- keypad polling uses MON-3 `scanKeys`
- movement is frame-gated so a held key does not step every scan tick
- only one simple 2x2 block is drawn

Once this loop is solid, more ambitious layers can be added on top:

- score and status via LCD or 7-segment MON-3 routines
- multi-pixel sprites
- scrolling
- simple games

See [rgb8x8-tetro-design.md](/Users/johnhardy/Documents/projects/rgb8x8-tetro/rgb8x8-tetro-design.md) for the next-step falling-block game structure extracted from the Arduino reference, but adapted to the TEC-1G scan model.
