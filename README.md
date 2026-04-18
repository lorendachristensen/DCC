# Dungeon Crawler Carl — NES

An FF3-style NES RPG themed on Matt Dinniman's *Dungeon Crawler Carl*.
Mapper 0 (NROM-128), 16KB PRG + 8KB CHR, NTSC.

## Status

**Assembles cleanly, link config was just fixed, not yet emulator-verified.**

The previous session ran out of tool budget right after fixing `nrom.cfg`
(vectors now live inside PRG at $FFFA instead of a separate region that
was padding the output to 24,598 bytes). Expected ROM size: **24,592 bytes**.

## Build

Requires `cc65` (provides `ca65` + `ld65`).

```bash
python3 make_chr.py                          # regenerate graphics.chr
ca65 main.s -o main.o
ld65 -C nrom.cfg main.o -o dungeon_crawler_carl.nes
ls -la dungeon_crawler_carl.nes              # must be 24592 bytes
```

## Test

Load `dungeon_crawler_carl.nes` in FCEUX, Mesen, or Nestopia.

Expected boot flow:
1. Title screen "DUNGEON CRAWLER CARL" → press **Start**
2. Intro text → press **A**
3. Overworld: D-pad moves Carl, Donut follows
4. Random encounter → battle menu (Attack / Talisman / Flee)
5. Victory grants XP, occasional floor descent; level-up boosts stats
6. HP = 0 → game over, Start returns to title

## Files

- `main.s` — all 6502 assembly (header, reset/NMI, state machine, screens)
- `nrom.cfg` — ld65 linker config (FIXED: vectors inside PRG)
- `make_chr.py` — generates graphics.chr from ASCII-art tile defs
- `graphics.chr` — 8KB CHR-ROM (pattern table 0 sprites, 1 background+font)

## Known gaps / next steps

- No APU / sound yet
- Single-screen overworld (no scrolling)
- No save system (or password)
- Enemy sprite art is placeholder-ish — tweak `make_chr.py` tiles $10-$1F
- Menu redraws disable rendering briefly — fine, but a PPU update queue
  would be cleaner long-term
- Could add Donut's follower Mongo, shops, bosses per floor, etc.

## Quick-ref: 6502 / NES cheats for future edits

- PPU writes only safe during vblank OR with rendering off
- OAM DMA ($4014) every frame from page $02
- ppu_addr is 2×8-bit writes: high byte first
- Nametable 0 at $2000, attribute table at $23C0
- Each nametable row = 32 tiles; row N at $2000 + N*$20
