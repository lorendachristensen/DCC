# Dungeon Crawler Carl — NES

An FF3-style NES RPG themed on Matt Dinniman's *Dungeon Crawler Carl*.
Mapper 1 (MMC1), 32KB PRG + 8KB CHR, battery-backed SRAM, NTSC.

## Status

**Emulator-verified and playable in Mesen 2.** Title screen, intro,
overworld movement with Donut follower, random encounters, and battle
system all functional. Recently migrated from NROM (mapper 0) to MMC1
(mapper 1) for bank switching and save RAM support.

## Build

Requires `cc65` (provides `ca65` + `ld65`).

```bash
python3 make_chr.py                          # regenerate graphics.chr
ca65 main.s -o main.o
ld65 -C mmc1.cfg main.o -o dungeon_crawler_carl.nes
ls -la dungeon_crawler_carl.nes              # should be 40976 bytes
```

## Test

We use **Mesen 2** for testing (https://github.com/SourMesen/Mesen2/releases).

Load `dungeon_crawler_carl.nes` in Mesen.

Default Mesen key bindings:
- **D-pad**: Arrow keys
- **A**: Z
- **B**: X
- **Start**: Enter (check Settings > Input if unresponsive)
- **Select**: Tab

Expected boot flow:
1. Title screen "DUNGEON CRAWLER CARL" → press **Start**
2. Intro text → press **A**
3. Overworld: D-pad moves Carl, Donut follows
4. Random encounter → battle menu (Attack / Talisman / Flee)
5. Victory grants XP, occasional floor descent; level-up boosts stats
6. HP = 0 → game over, Start returns to title

## Files

- `main.s` — all 6502 assembly (header, reset/NMI, MMC1 init, state machine, screens)
- `mmc1.cfg` — ld65 linker config for MMC1 (fixed bank + switchable bank + SRAM)
- `nrom.cfg` — old NROM linker config (kept for reference)
- `make_chr.py` — generates graphics.chr from ASCII-art tile defs
- `graphics.chr` — 8KB CHR-ROM (pattern table 0 sprites, 1 background+font)

## Known gaps / next steps

- No APU / sound yet
- Single-screen overworld (no scrolling)
- Save/load routines not yet wired up (SRAM structure defined, needs UI)
- Enemy sprite art is placeholder-ish — tweak `make_chr.py` tiles $10-$1F
- Menu redraws disable rendering briefly — fine, but a PPU update queue
  would be cleaner long-term
- Per-floor CHR tilesets not yet implemented (MMC1 CHR banking ready)
- Switchable PRG bank empty — move string/map/enemy data there as content grows
- Could add Donut's follower Mongo, shops, bosses per floor, etc.

## Quick-ref: 6502 / NES cheats for future edits

- PPU writes only safe during vblank OR with rendering off
- OAM DMA ($4014) every frame from page $02
- ppu_addr is 2×8-bit writes: high byte first
- Nametable 0 at $2000, attribute table at $23C0
- Each nametable row = 32 tiles; row N at $2000 + N*$20
