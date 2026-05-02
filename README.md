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

The visible result is a Tetris-class game: coloured tetrominoes, line clears, gravity, pause, splash, LCD next-piece hint, score on the multiplexed digits, and MON-3 sound hooks.

## Controls

- left key moves left
- right key moves right

## Why the loop comes first

The first problem to solve is not text, score, sprites, or richer colour usage. It is proving that the scan/poll/update loop is stable and understandable on the real hardware model.

This target keeps those constraints explicit even as gameplay grows:

- scan is time-sliced: one row per tick, not a whole-frame burst
- scan state is persistent:
  - `scan_mask`
  - `scan_ptr`
- framebuffer uses the 32-byte layout: `R,G,B,Aux` for each of 8 rows
- keypad polling uses MON-3 `scanKeys`
- movement is frame-gated so a held key does not step every scan tick
- pieces are expressed as fixed 4×4 bitmap masks in data tables

## Building

Assembler output (**`.hex`**, **`.bin`**, **`.lst`**) should live under **`build/`** (ignored by git), matching `debug80.json` **`outputDir`**.

With **[asm80](https://www.npmjs.com/package/asm80)**, paths are resolved from the directory of the main source file, so run it **from `src/`** and point **`-o`** at **`../build/...`**:

```bash
mkdir -p build
(cd src && asm80 -m Z80 -t hex -o ../build/tetro.hex tetro.asm)
(cd src && asm80 -m Z80 -t bin -o ../build/tetro.bin tetro.asm)
```

Emit **`.lst`** if your asm80 supports it (often `-l`); point listing output at **`../build/`** the same way. For in-editor emulation, **`debug80.json`** in **[debug80](../debug80)** can reference **`outputDir`** / **`mainFile`** for this project's **`build/`** tree.

## Design / next steps

Once this loop is solid, more ambitious layers can be added on top:

- score and status via LCD or 7-segment MON-3 routines
- multi-pixel sprites
- scrolling
- simple games

See [rgb8x8-tetro-design.md](rgb8x8-tetro-design.md) for the next-step falling-block game structure extracted from the Arduino reference, but adapted to the TEC-1G scan model.
