;==============================================================================
; DUNGEON CRAWLER CARL - NES
; FF-style mini-RPG themed on Matt Dinniman's "Dungeon Crawler Carl"
; Mapper 1 (MMC1), 32KB PRG + 8KB CHR, battery SRAM, NTSC
;==============================================================================

.segment "HEADER"
    .byte "NES", $1A        ; iNES signature
    .byte 2                 ; 2 x 16KB PRG-ROM = 32KB
    .byte 1                 ; 1 x  8KB CHR-ROM
    .byte $12               ; flags 6: mapper 1 low nybble, battery SRAM
    .byte $00               ; flags 7: mapper 1 high nybble
    .byte 0, 0, 0, 0, 0, 0, 0, 0

;==============================================================================
; PPU / APU / INPUT register equates
;==============================================================================
PPUCTRL     = $2000
PPUMASK     = $2001
PPUSTATUS   = $2002
OAMADDR     = $2003
OAMDATA     = $2004
PPUSCROLL   = $2005
PPUADDR     = $2006
PPUDATA     = $2007
OAMDMA      = $4014
APUSTATUS   = $4015
JOYPAD1     = $4016
JOYPAD2     = $4017

; Controller bit masks
BTN_A       = $80
BTN_B       = $40
BTN_SELECT  = $20
BTN_START   = $10
BTN_UP      = $08
BTN_DOWN    = $04
BTN_LEFT    = $02
BTN_RIGHT   = $01

; Game states
ST_TITLE    = 0
ST_INTRO    = 1
ST_OVERWORLD = 2
ST_BATTLE_INIT = 3
ST_BATTLE_MENU = 4
ST_BATTLE_ATK = 5
ST_BATTLE_ENEMY = 6
ST_BATTLE_WIN = 7
ST_BATTLE_LOSE = 8
ST_LEVELUP  = 9

;==============================================================================
; Zero Page variables
;==============================================================================
.segment "ZEROPAGE"
nmi_ready:      .res 1  ; nonzero when NMI has fired
frame_lo:       .res 1
frame_hi:       .res 1
pad1:           .res 1  ; current button state
pad1_prev:      .res 1  ; previous frame state
pad1_pressed:   .res 1  ; newly pressed this frame
rng_seed:       .res 2  ; 16-bit LFSR

game_state:     .res 1
state_timer:    .res 1  ; countdown timer for state changes

; Player
p_x:            .res 1  ; overworld tile x
p_y:            .res 1  ; overworld tile y
p_dir:          .res 1  ; 0=down,1=up,2=left,3=right
p_anim:         .res 1
p_hp:           .res 1
p_hp_max:       .res 1
p_mp:           .res 1
p_mp_max:       .res 1
p_atk:          .res 1
p_def:          .res 1
p_level:        .res 1
p_xp:           .res 1
p_xp_next:      .res 1
p_gold:         .res 1

; Donut (simple: follows Carl)
d_x:            .res 1
d_y:            .res 1

; Battle
enemy_type:     .res 1
enemy_hp:       .res 1
enemy_hp_max:   .res 1
enemy_atk:      .res 1
enemy_xp:       .res 1
enemy_gold:     .res 1
battle_cursor:  .res 1  ; 0=Attack 1=Talisman 2=Flee
battle_msg_ptr: .res 2
battle_anim:    .res 1

; Generic
tmp1:           .res 1
tmp2:           .res 1
tmp3:           .res 1
tmp4:           .res 1
ptr1:           .res 2
ptr2:           .res 2
damage:         .res 1
scroll_x:       .res 1
scroll_y:       .res 1

; Floor tracking (DCC: dungeon floors)
floor_num:      .res 1
step_count:     .res 1  ; counts steps until encounter
encounter_thresh: .res 1

; MMC1 bank tracking
current_prg_bank: .res 1
current_chr_bank: .res 1

;==============================================================================
; OAM (sprite buffer) - 256 bytes at $200
;==============================================================================
.segment "OAM"
oam_buffer:     .res 256

;==============================================================================
; BSS
;==============================================================================
.segment "BSS"
text_buffer:    .res 32
nametable_buf:  .res 64
msg_timer:      .res 1

;==============================================================================
; SRAM ($6000-$7FFF) - battery-backed save data
;==============================================================================
.segment "SAVERAM"
save_magic:     .res 4   ; "DCC!" to detect valid save
save_floor:     .res 1
save_hp:        .res 1
save_hp_max:    .res 1
save_mp:        .res 1
save_mp_max:    .res 1
save_atk:       .res 1
save_def:       .res 1
save_level:     .res 1
save_xp:        .res 1
save_xp_next:   .res 1
save_gold:      .res 1
save_p_x:       .res 1
save_p_y:       .res 1
save_checksum:  .res 1

;==============================================================================
; CODE
;==============================================================================
.segment "CODE"

;------------------------------------------------------------------------------
; RESET handler
;------------------------------------------------------------------------------
.proc reset
    sei                     ; disable IRQ
    cld                     ; clear decimal (unused on NES but standard)
    ldx #$40
    stx $4017               ; disable APU frame IRQ
    ldx #$FF
    txs                     ; set up stack
    inx                     ; X=0
    stx PPUCTRL             ; disable NMI
    stx PPUMASK             ; disable rendering
    stx $4010               ; disable DMC IRQ
    
    ; wait for PPU ready (first vblank)
    bit PPUSTATUS
:   bit PPUSTATUS
    bpl :-
    
    ; clear RAM
    lda #0
    tax
:   sta $00,x
    sta $100,x
    sta $300,x
    sta $400,x
    sta $500,x
    sta $600,x
    sta $700,x
    inx
    bne :-
    
    ; hide all sprites off-screen
    lda #$FE
    ldx #0
:   sta oam_buffer,x
    inx
    inx
    inx
    inx
    bne :-
    
    ; wait for second vblank (PPU ready)
:   bit PPUSTATUS
    bpl :-

    ; Initialize MMC1 mapper
    jsr mmc1_init

    ; seed RNG
    lda #$A5
    sta rng_seed
    lda #$5A
    sta rng_seed+1
    
    ; initialize player stats (DCC: Carl starts weak)
    lda #20
    sta p_hp
    sta p_hp_max
    lda #5
    sta p_mp
    sta p_mp_max
    lda #4
    sta p_atk
    lda #2
    sta p_def
    lda #1
    sta p_level
    lda #0
    sta p_xp
    sta p_gold
    lda #8
    sta p_xp_next
    lda #1
    sta floor_num
    lda #0
    sta step_count
    lda #12
    sta encounter_thresh
    
    ; Initial state: title screen
    lda #ST_TITLE
    sta game_state
    
    jsr load_palette
    jsr draw_title_screen

    ; reset scroll position before enabling rendering
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    sta scroll_x
    sta scroll_y

    ; enable NMI and rendering
    lda #%10010000          ; NMI on, sprites from $0000, BG from $1000
    sta PPUCTRL
    lda #%00011110          ; show bg, show sprites, no clipping
    sta PPUMASK
    
main_loop:
    lda nmi_ready
    beq main_loop
    lda #0
    sta nmi_ready
    
    jsr read_controller
    jsr update_game
    
    jmp main_loop
.endproc

;------------------------------------------------------------------------------
; NMI handler - runs at vblank
;------------------------------------------------------------------------------
.proc nmi
    pha
    txa
    pha
    tya
    pha
    
    ; OAM DMA
    lda #0
    sta OAMADDR
    lda #$02
    sta OAMDMA
    
    ; set scroll (PPUCTRL write restores nametable select in t register)
    bit PPUSTATUS
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    lda #%10010000
    sta PPUCTRL
    
    ; increment frame counter
    inc frame_lo
    bne :+
    inc frame_hi
:
    lda #1
    sta nmi_ready
    
    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.proc irq
    rti
.endproc

;------------------------------------------------------------------------------
; MMC1 mapper initialization and bank-switching routines
; These MUST live in the fixed bank ($C000-$FFFF)
;------------------------------------------------------------------------------

.proc mmc1_init
    ; Reset shift register
    lda #$80
    sta $8000

    ; Control register: horizontal mirroring, fix last PRG bank, 8KB CHR mode
    ; %01110 = $0E
    lda #$0E
    jsr mmc1_write_ctrl

    ; CHR bank 0
    lda #0
    jsr mmc1_write_chr0
    sta current_chr_bank

    ; PRG bank 0 at $8000 (SRAM enabled: bit 4 = 0)
    lda #0
    jsr mmc1_write_prg
    sta current_prg_bank
    rts
.endproc

; Write 5-bit value in A to MMC1 Control register ($8000)
.proc mmc1_write_ctrl
    sta $8000
    lsr a
    sta $8000
    lsr a
    sta $8000
    lsr a
    sta $8000
    lsr a
    sta $8000
    rts
.endproc

; Write 5-bit value in A to MMC1 CHR bank 0 register ($A000)
.proc mmc1_write_chr0
    sta $A000
    lsr a
    sta $A000
    lsr a
    sta $A000
    lsr a
    sta $A000
    lsr a
    sta $A000
    rts
.endproc

; Write 5-bit value in A to MMC1 CHR bank 1 register ($C000)
; Only used in 4KB CHR mode
.proc mmc1_write_chr1
    sta $C000
    lsr a
    sta $C000
    lsr a
    sta $C000
    lsr a
    sta $C000
    lsr a
    sta $C000
    rts
.endproc

; Write 5-bit value in A to MMC1 PRG bank register ($E000)
; Bit 4 = SRAM disable (keep 0 to enable SRAM)
.proc mmc1_write_prg
    sta $E000
    lsr a
    sta $E000
    lsr a
    sta $E000
    lsr a
    sta $E000
    lsr a
    sta $E000
    rts
.endproc

; Switch PRG bank (bank number in A)
.proc switch_prg_bank
    sta current_prg_bank
    jmp mmc1_write_prg
.endproc

; Switch CHR bank (bank number in A)
.proc switch_chr_bank
    sta current_chr_bank
    jmp mmc1_write_chr0
.endproc

;------------------------------------------------------------------------------
; Controller read (with DPCM-safe double read)
;------------------------------------------------------------------------------
.proc read_controller
    lda pad1
    sta pad1_prev
    
    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1
    
    ldx #$08
:   lda JOYPAD1
    lsr a
    rol pad1
    dex
    bne :-
    
    ; compute newly-pressed = current & ~previous
    lda pad1_prev
    eor #$FF
    and pad1
    sta pad1_pressed
    rts
.endproc

;------------------------------------------------------------------------------
; 16-bit LFSR RNG, returns byte in A
;------------------------------------------------------------------------------
.proc rand
    lda rng_seed+1
    asl
    asl
    eor rng_seed+1
    asl
    eor rng_seed+1
    asl
    asl
    eor rng_seed+1
    asl
    rol rng_seed            ; feedback bit into LSB
    rol rng_seed+1
    lda rng_seed
    rts
.endproc

;------------------------------------------------------------------------------
; Load palette
;------------------------------------------------------------------------------
.proc load_palette
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
:   lda palette_data,x
    sta PPUDATA
    inx
    cpx #32
    bne :-
    rts
.endproc

palette_data:
    ; Background palettes
    .byte $0F, $30, $10, $00   ; bg0: black, white, gray, dark - for text/UI
    .byte $0F, $07, $17, $27   ; bg1: dungeon browns
    .byte $0F, $01, $11, $21   ; bg2: blues (water/magic)
    .byte $0F, $06, $16, $26   ; bg3: reds (danger)
    ; Sprite palettes
    .byte $0F, $30, $16, $27   ; sp0: Carl (white/red/tan)
    .byte $0F, $30, $38, $16   ; sp1: Donut (white/tan/pink)
    .byte $0F, $1A, $2A, $3A   ; sp2: green enemies (goblins, kua-tin)
    .byte $0F, $06, $16, $30   ; sp3: red enemies

;------------------------------------------------------------------------------
; Wait for NMI (used during setup to ensure vblank writes)
;------------------------------------------------------------------------------
.proc wait_nmi
    lda #0
    sta nmi_ready
:   lda nmi_ready
    beq :-
    rts
.endproc

;------------------------------------------------------------------------------
; Clear the nametable at $2000 and attribute table
;------------------------------------------------------------------------------
.proc clear_nametable
    lda #0
    sta PPUMASK         ; turn off rendering during bulk write

    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldy #4              ; 4 pages of $100 bytes = 1024
    ldx #0
    lda #$20            ; space character = blank in our CHR
outer:
inner:
    sta PPUDATA
    inx
    bne inner
    dey
    bne outer

    ; clear attribute tables to palette 0
    bit PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    ldx #64
    lda #0
:   sta PPUDATA
    dex
    bne :-

    ; caller is responsible for re-enabling rendering
    rts
.endproc

;------------------------------------------------------------------------------
; Write string at ptr1 to PPU at (tmp1, tmp2)=(high,low)
; String terminated by $00
;------------------------------------------------------------------------------
.proc draw_string
    bit PPUSTATUS
    lda tmp1
    sta PPUADDR
    lda tmp2
    sta PPUADDR
    ldy #0
:   lda (ptr1),y
    beq done
    sta PPUDATA
    iny
    bne :-
done:
    rts
.endproc

; helper macro: set PPU addr from constant
.macro SET_PPU_ADDR addr
    lda #>addr
    sta tmp1
    lda #<addr
    sta tmp2
.endmacro

.macro SET_PTR1 label
    lda #<label
    sta ptr1
    lda #>label
    sta ptr1+1
.endmacro

;------------------------------------------------------------------------------
; Title screen draw
;------------------------------------------------------------------------------
.proc draw_title_screen
    jsr clear_nametable
    
    ; "DUNGEON CRAWLER" at row 10, col 8
    SET_PPU_ADDR $2148
    SET_PTR1 str_title1
    jsr draw_string
    
    ; "CARL" at row 12, col 14
    SET_PPU_ADDR $218E
    SET_PTR1 str_title2
    jsr draw_string
    
    ; Subtitle
    SET_PPU_ADDR $21E6
    SET_PTR1 str_title_sub
    jsr draw_string
    
    ; Press Start
    SET_PPU_ADDR $22A7
    SET_PTR1 str_press_start
    jsr draw_string
    
    ; Credit
    SET_PPU_ADDR $2362
    SET_PTR1 str_credit
    jsr draw_string
    
    rts
.endproc

str_title1:     .byte "DUNGEON CRAWLER", 0
str_title2:     .byte "C A R L", 0
str_title_sub:  .byte "AN 8-BIT ADVENTURE", 0
str_press_start: .byte "PRESS START", 0
str_credit:     .byte "BASED ON DINNIMANS NOVELS", 0

;------------------------------------------------------------------------------
; Intro screen (after pressing start)
;------------------------------------------------------------------------------
.proc draw_intro_screen
    jsr clear_nametable
    
    SET_PPU_ADDR $20C4
    SET_PTR1 str_intro1
    jsr draw_string
    SET_PPU_ADDR $2104
    SET_PTR1 str_intro2
    jsr draw_string
    SET_PPU_ADDR $2144
    SET_PTR1 str_intro3
    jsr draw_string
    SET_PPU_ADDR $2184
    SET_PTR1 str_intro4
    jsr draw_string
    SET_PPU_ADDR $21C4
    SET_PTR1 str_intro5
    jsr draw_string
    SET_PPU_ADDR $2244
    SET_PTR1 str_intro6
    jsr draw_string
    SET_PPU_ADDR $2284
    SET_PTR1 str_intro7
    jsr draw_string
    SET_PPU_ADDR $22C4
    SET_PTR1 str_intro8
    jsr draw_string
    SET_PPU_ADDR $2344
    SET_PTR1 str_intro_cont
    jsr draw_string
    rts
.endproc

str_intro1: .byte "THE EARTH IS GONE.", 0
str_intro2: .byte "WHAT REMAINS IS", 0
str_intro3: .byte "THE DUNGEON.", 0
str_intro4: .byte "YOU ARE CARL.", 0
str_intro5: .byte "YOUR CAT DONUT", 0
str_intro6: .byte "IS NOW A", 0
str_intro7: .byte "LEVEL 3 SORCERESS.", 0
str_intro8: .byte "GOOD LUCK.", 0
str_intro_cont: .byte "PRESS A TO BEGIN", 0

;------------------------------------------------------------------------------
; Overworld draw - dungeon floor with walls, floor tiles, etc.
;------------------------------------------------------------------------------
.proc draw_overworld
    jsr clear_nametable
    
    ; Draw top border (stone wall)
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #32
    lda #TILE_WALL_TOP
:   sta PPUDATA
    dex
    bne :-
    
    ; Draw floor rows (rows 1-22)
    ldy #22
row_loop:
    lda #TILE_WALL_SIDE
    sta PPUDATA         ; left wall
    ldx #30
col_loop:
    lda #TILE_FLOOR
    sta PPUDATA
    dex
    bne col_loop
    lda #TILE_WALL_SIDE
    sta PPUDATA         ; right wall
    dey
    bne row_loop
    
    ; Draw bottom border
    ldx #32
    lda #TILE_WALL_TOP
:   sta PPUDATA
    dex
    bne :-
    
    ; Scatter some decorative pillars
    bit PPUSTATUS
    lda #$21
    sta PPUADDR
    lda #$C8
    sta PPUADDR
    lda #TILE_PILLAR
    sta PPUDATA
    
    bit PPUSTATUS
    lda #$21
    sta PPUADDR
    lda #$D4
    sta PPUADDR
    lda #TILE_PILLAR
    sta PPUDATA
    
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$48
    sta PPUADDR
    lda #TILE_PILLAR
    sta PPUDATA
    
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$54
    sta PPUADDR
    lda #TILE_PILLAR
    sta PPUDATA
    
    ; Draw HUD box at bottom (rows 24-27 area using name table lower portion)
    ; (we'll put status in line 27)
    
    ; Draw floor label: "FLOOR 1"
    SET_PPU_ADDR $23A1
    SET_PTR1 str_floor
    jsr draw_string
    ; Draw floor number
    lda #$23
    sta PPUADDR
    lda #$A8
    sta PPUADDR
    lda floor_num
    clc
    adc #'0'
    sta PPUDATA
    
    ; "HP"
    SET_PPU_ADDR $23AA
    SET_PTR1 str_hp
    jsr draw_string
    jsr draw_hp
    
    rts
.endproc

str_floor:  .byte "FLOOR ", 0
str_hp:     .byte "HP ", 0

;------------------------------------------------------------------------------
; Draw player HP as 2-digit number at $23AE
;------------------------------------------------------------------------------
.proc draw_hp
    bit PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$AE
    sta PPUADDR
    lda p_hp
    jsr print_2digit
    lda #'/'
    sta PPUDATA
    lda p_hp_max
    jsr print_2digit
    rts
.endproc

;------------------------------------------------------------------------------
; Print 2-digit decimal value from A to PPUDATA
;------------------------------------------------------------------------------
.proc print_2digit
    ldx #0
:   cmp #10
    bcc done
    sec
    sbc #10
    inx
    jmp :-
done:
    pha
    txa
    clc
    adc #'0'
    sta PPUDATA
    pla
    clc
    adc #'0'
    sta PPUDATA
    rts
.endproc

;------------------------------------------------------------------------------
; Main update: dispatch based on game state
;------------------------------------------------------------------------------
.proc update_game
    lda game_state
    cmp #ST_TITLE
    bne :+
    jmp update_title
:   cmp #ST_INTRO
    bne :+
    jmp update_intro
:   cmp #ST_OVERWORLD
    bne :+
    jmp update_overworld
:   cmp #ST_BATTLE_INIT
    bne :+
    jmp update_battle_init
:   cmp #ST_BATTLE_MENU
    bne :+
    jmp update_battle_menu
:   cmp #ST_BATTLE_ENEMY
    bne :+
    jmp update_battle_enemy
:   cmp #ST_BATTLE_WIN
    bne :+
    jmp update_battle_win
:   cmp #ST_BATTLE_LOSE
    bne :+
    jmp update_gameover
:   rts
.endproc

;------------------------------------------------------------------------------
; Title screen update
;------------------------------------------------------------------------------
.proc update_title
    ; Hide all sprites
    jsr clear_sprites
    
    ; Wait for Start press
    lda pad1_pressed
    and #BTN_START
    beq done
    
    ; Transition to intro
    lda #0
    sta PPUMASK
    jsr draw_intro_screen
    lda #%00011110
    sta PPUMASK
    lda #ST_INTRO
    sta game_state
done:
    rts
.endproc

;------------------------------------------------------------------------------
; Intro screen update
;------------------------------------------------------------------------------
.proc update_intro
    jsr clear_sprites
    
    lda pad1_pressed
    and #BTN_A
    beq done
    
    ; Start the game: initialize player position, draw overworld
    lda #8
    sta p_x
    lda #10
    sta p_y
    lda #9
    sta d_x
    lda #10
    sta d_y
    lda #0
    sta p_dir
    
    lda #0
    sta PPUMASK
    jsr draw_overworld
    lda #%00011110
    sta PPUMASK
    
    lda #ST_OVERWORLD
    sta game_state
done:
    rts
.endproc

;------------------------------------------------------------------------------
; Overworld update - move Carl around, check for encounters
;------------------------------------------------------------------------------
.proc update_overworld
    ; Stir RNG
    jsr rand

    ; draw sprites every frame for smooth display
    jsr draw_carl_sprite
    jsr draw_donut_sprite

    ; Throttle movement to every 8 frames
    lda frame_lo
    and #$07
    beq do_move
    jmp skip_step
do_move:

    lda #0
    sta tmp1            ; tmp1 = 1 if moved this frame

    lda pad1
    and #BTN_UP
    beq not_up
    lda p_y
    cmp #2
    bcc not_up
    dec p_y
    lda #1
    sta p_dir
    lda #1
    sta tmp1
    jmp moved_check
not_up:
    lda pad1
    and #BTN_DOWN
    beq not_down
    lda p_y
    cmp #20
    bcs not_down
    inc p_y
    lda #0
    sta p_dir
    lda #1
    sta tmp1
    jmp moved_check
not_down:
    lda pad1
    and #BTN_LEFT
    beq not_left
    lda p_x
    cmp #2
    bcc not_left
    dec p_x
    lda #2
    sta p_dir
    lda #1
    sta tmp1
    jmp moved_check
not_left:
    lda pad1
    and #BTN_RIGHT
    beq not_right
    lda p_x
    cmp #28
    bcs not_right
    inc p_x
    lda #3
    sta p_dir
    lda #1
    sta tmp1
not_right:
moved_check:
    lda tmp1
    beq skip_step

    ; Step happened: update donut follow and check encounter
    jsr update_donut_follow

    inc step_count
    lda step_count
    cmp encounter_thresh
    bcc skip_step

    ; Random check - ~12.5% chance per eligible step
    jsr rand
    and #$1F
    cmp #4
    bcs skip_step

    ; Start encounter!
    lda #0
    sta step_count
    ; Randomize next encounter threshold (24-39 steps)
    jsr rand
    and #$0F
    clc
    adc #24
    sta encounter_thresh
    lda #ST_BATTLE_INIT
    sta game_state
skip_step:
    rts
.endproc

;------------------------------------------------------------------------------
; Donut follows Carl (simple: stays one tile behind in his facing direction)
;------------------------------------------------------------------------------
.proc update_donut_follow
    lda p_x
    sta d_x
    lda p_y
    sta d_y
    
    lda p_dir
    cmp #0              ; down -> donut above
    bne :+
    dec d_y
    rts
:   cmp #1              ; up -> donut below
    bne :+
    inc d_y
    rts
:   cmp #2              ; left -> donut right
    bne :+
    inc d_x
    rts
:   ; right -> donut left
    dec d_x
    rts
.endproc

;------------------------------------------------------------------------------
; Draw Carl sprite (16x16 = 4 hardware sprites) using tiles $01-$04
; OAM bytes: Y, tile, attr, X
;------------------------------------------------------------------------------
.proc draw_carl_sprite
    ; Compute pixel X = p_x * 8
    lda p_x
    asl
    asl
    asl
    sta tmp1            ; pixel X
    lda p_y
    asl
    asl
    asl
    sta tmp2            ; pixel Y
    
    ; Sprite 0: top-left
    lda tmp2
    sta oam_buffer+0
    lda #$01
    sta oam_buffer+1
    lda #$00            ; palette 0, front
    sta oam_buffer+2
    lda tmp1
    sta oam_buffer+3
    
    ; Sprite 1: top-right
    lda tmp2
    sta oam_buffer+4
    lda #$02
    sta oam_buffer+5
    lda #$00
    sta oam_buffer+6
    lda tmp1
    clc
    adc #8
    sta oam_buffer+7
    
    ; Sprite 2: bottom-left
    lda tmp2
    clc
    adc #8
    sta oam_buffer+8
    lda #$03
    sta oam_buffer+9
    lda #$00
    sta oam_buffer+10
    lda tmp1
    sta oam_buffer+11
    
    ; Sprite 3: bottom-right
    lda tmp2
    clc
    adc #8
    sta oam_buffer+12
    lda #$04
    sta oam_buffer+13
    lda #$00
    sta oam_buffer+14
    lda tmp1
    clc
    adc #8
    sta oam_buffer+15
    rts
.endproc

;------------------------------------------------------------------------------
; Draw Donut sprite (16x16) using tiles $05-$08, palette 1
;------------------------------------------------------------------------------
.proc draw_donut_sprite
    lda d_x
    asl
    asl
    asl
    sta tmp1
    lda d_y
    asl
    asl
    asl
    sta tmp2
    
    lda tmp2
    sta oam_buffer+16
    lda #$05
    sta oam_buffer+17
    lda #$01            ; palette 1
    sta oam_buffer+18
    lda tmp1
    sta oam_buffer+19
    
    lda tmp2
    sta oam_buffer+20
    lda #$06
    sta oam_buffer+21
    lda #$01
    sta oam_buffer+22
    lda tmp1
    clc
    adc #8
    sta oam_buffer+23
    
    lda tmp2
    clc
    adc #8
    sta oam_buffer+24
    lda #$07
    sta oam_buffer+25
    lda #$01
    sta oam_buffer+26
    lda tmp1
    sta oam_buffer+27
    
    lda tmp2
    clc
    adc #8
    sta oam_buffer+28
    lda #$08
    sta oam_buffer+29
    lda #$01
    sta oam_buffer+30
    lda tmp1
    clc
    adc #8
    sta oam_buffer+31
    rts
.endproc

;------------------------------------------------------------------------------
; Hide all sprites (Y = $FE for all 64)
;------------------------------------------------------------------------------
.proc clear_sprites
    ldx #0
    lda #$FE
:   sta oam_buffer,x
    inx
    inx
    inx
    inx
    bne :-
    rts
.endproc

;------------------------------------------------------------------------------
; Battle init - pick an enemy, draw battle screen
;------------------------------------------------------------------------------
.proc update_battle_init
    ; Pick enemy type by floor
    jsr rand
    and #$03
    sta enemy_type
    
    ; Load enemy stats based on floor + type
    ; HP = 6 + floor*3 + type*2
    lda floor_num
    asl
    clc
    adc floor_num       ; floor*3
    clc
    adc #6
    sta tmp1
    lda enemy_type
    asl
    clc
    adc tmp1
    sta enemy_hp
    sta enemy_hp_max
    
    ; ATK = 2 + floor + type
    lda floor_num
    clc
    adc enemy_type
    clc
    adc #2
    sta enemy_atk
    
    ; XP reward = 3 + floor + type*2
    lda enemy_type
    asl
    clc
    adc floor_num
    clc
    adc #3
    sta enemy_xp
    
    ; Gold reward = 1 + type
    lda enemy_type
    clc
    adc #1
    sta enemy_gold
    
    lda #0
    sta battle_cursor
    sta battle_anim
    
    ; Draw the battle screen
    lda #0
    sta PPUMASK
    jsr draw_battle_screen
    lda #%00011110
    sta PPUMASK
    
    jsr clear_sprites
    jsr draw_enemy_sprite
    
    lda #ST_BATTLE_MENU
    sta game_state
    rts
.endproc

;------------------------------------------------------------------------------
; Draw battle screen layout (FF style: enemy on top, menu box on bottom)
;------------------------------------------------------------------------------
.proc draw_battle_screen
    jsr clear_nametable
    
    ; Enemy name at top
    SET_PPU_ADDR $2086
    lda enemy_type
    cmp #0
    bne :+
    SET_PTR1 str_enemy0
    jmp draw_en
:   cmp #1
    bne :+
    SET_PTR1 str_enemy1
    jmp draw_en
:   cmp #2
    bne :+
    SET_PTR1 str_enemy2
    jmp draw_en
:   SET_PTR1 str_enemy3
draw_en:
    jsr draw_string
    
    ; Horizontal separator line (row 17 - bottom UI box top)
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$20
    sta PPUADDR
    ldx #32
    lda #TILE_WALL_TOP
:   sta PPUDATA
    dex
    bne :-
    
    ; Menu labels
    SET_PPU_ADDR $2284
    SET_PTR1 str_attack
    jsr draw_string
    
    SET_PPU_ADDR $22A4
    SET_PTR1 str_talisman
    jsr draw_string
    
    SET_PPU_ADDR $22C4
    SET_PTR1 str_flee
    jsr draw_string
    
    ; HP label area (right side of menu box)
    SET_PPU_ADDR $2292
    SET_PTR1 str_carl
    jsr draw_string
    SET_PPU_ADDR $22B2
    SET_PTR1 str_hp
    jsr draw_string
    jsr draw_hp_battle
    
    SET_PPU_ADDR $22D2
    SET_PTR1 str_ehp
    jsr draw_string
    jsr draw_enemy_hp_battle
    
    rts
.endproc

str_enemy0: .byte "KOBOLD WARRIOR", 0
str_enemy1: .byte "GOBLIN SCOUT", 0
str_enemy2: .byte "KUA-TIN THUG", 0
str_enemy3: .byte "MOSS MONSTER", 0

str_attack:    .byte "> ATTACK", 0
str_talisman:  .byte "  TALISMAN", 0
str_flee:      .byte "  FLEE", 0
str_attack_p:  .byte "  ATTACK", 0
str_talisman_p: .byte "> TALISMAN", 0
str_flee_p:    .byte "> FLEE", 0
str_carl:      .byte "CARL", 0
str_ehp:       .byte "FOE", 0

.proc draw_hp_battle
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$B5
    sta PPUADDR
    lda p_hp
    jsr print_2digit
    lda #'/'
    sta PPUDATA
    lda p_hp_max
    jsr print_2digit
    rts
.endproc

.proc draw_enemy_hp_battle
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$D5
    sta PPUADDR
    lda enemy_hp
    jsr print_2digit
    lda #'/'
    sta PPUDATA
    lda enemy_hp_max
    jsr print_2digit
    rts
.endproc

;------------------------------------------------------------------------------
; Draw enemy sprite (32x32 made of 16 hardware sprites using tiles $10-$1F)
;------------------------------------------------------------------------------
.proc draw_enemy_sprite
    ; Position enemy in upper center: pixel (112, 64)
    lda #64
    sta tmp2            ; Y
    lda #112
    sta tmp1            ; X
    
    ; Pick palette based on enemy type
    lda enemy_type
    and #$01
    clc
    adc #2              ; palette 2 or 3
    sta tmp3
    
    ldx #0              ; sprite index * 4
    ldy #0              ; tile counter
row_loop:
    lda #0
    sta tmp4            ; col counter
col_loop:
    ; Y position
    lda tmp2
    sta oam_buffer+32,x
    ; tile
    tya
    clc
    adc #$10
    sta oam_buffer+33,x
    ; attr
    lda tmp3
    sta oam_buffer+34,x
    ; X position
    lda tmp1
    sta oam_buffer+35,x
    
    ; advance X position by 8
    lda tmp1
    clc
    adc #8
    sta tmp1
    
    inx
    inx
    inx
    inx
    iny
    
    inc tmp4
    lda tmp4
    cmp #4
    bne col_loop
    
    ; Reset X, advance Y
    lda tmp1
    sec
    sbc #32
    sta tmp1
    lda tmp2
    clc
    adc #8
    sta tmp2
    
    cpy #16
    bne row_loop
    
    rts
.endproc

;------------------------------------------------------------------------------
; Battle menu update
;------------------------------------------------------------------------------
.proc update_battle_menu
    lda pad1_pressed
    and #BTN_UP
    beq not_up
    lda battle_cursor
    beq not_up
    dec battle_cursor
    jsr redraw_battle_menu
not_up:
    lda pad1_pressed
    and #BTN_DOWN
    beq not_down
    lda battle_cursor
    cmp #2
    bcs not_down
    inc battle_cursor
    jsr redraw_battle_menu
not_down:
    lda pad1_pressed
    and #BTN_A
    beq not_a
    jmp battle_action
not_a:
    rts
.endproc

;------------------------------------------------------------------------------
; Redraw menu labels with current cursor
;------------------------------------------------------------------------------
.proc redraw_battle_menu
    ; We can write during vblank only, so set nmi_ready trigger
    ; Simple approach: disable rendering briefly
    lda #0
    sta PPUMASK
    
    ; Clear the three menu lines and redraw based on cursor
    lda battle_cursor
    cmp #0
    bne :+
    SET_PPU_ADDR $2284
    SET_PTR1 str_attack
    jsr draw_string
    SET_PPU_ADDR $22A4
    SET_PTR1 str_talisman
    jsr draw_string
    SET_PPU_ADDR $22C4
    SET_PTR1 str_flee
    jsr draw_string
    jmp done
:   cmp #1
    bne :+
    SET_PPU_ADDR $2284
    SET_PTR1 str_attack_p
    jsr draw_string
    SET_PPU_ADDR $22A4
    SET_PTR1 str_talisman_p
    jsr draw_string
    SET_PPU_ADDR $22C4
    SET_PTR1 str_flee
    jsr draw_string
    jmp done
:   SET_PPU_ADDR $2284
    SET_PTR1 str_attack_p
    jsr draw_string
    SET_PPU_ADDR $22A4
    SET_PTR1 str_talisman
    jsr draw_string
    SET_PPU_ADDR $22C4
    SET_PTR1 str_flee_p
    jsr draw_string
done:
    ; reset scroll before re-enabling
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
    rts
.endproc

;------------------------------------------------------------------------------
; Dispatch the chosen battle action
;------------------------------------------------------------------------------
.proc battle_action
    lda battle_cursor
    cmp #0
    bne :+
    jmp do_attack
:   cmp #1
    bne :+
    jmp do_talisman
:   jmp do_flee
    
do_attack:
    ; damage = p_atk + rand(0..3) - 1
    jsr rand
    and #$03
    clc
    adc p_atk
    sta damage
    
    ; Subtract from enemy HP
    lda enemy_hp
    sec
    sbc damage
    bcs :+
    lda #0              ; clamp to 0
:   sta enemy_hp
    
    ; Redraw enemy HP
    lda #0
    sta PPUMASK
    jsr draw_enemy_hp_battle
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
    
    ; Check victory
    lda enemy_hp
    bne to_enemy_turn
    
    ; Victory!
    lda #ST_BATTLE_WIN
    sta game_state
    lda #30
    sta state_timer
    
    ; Award XP
    lda p_xp
    clc
    adc enemy_xp
    sta p_xp
    lda p_gold
    clc
    adc enemy_gold
    sta p_gold
    rts

to_enemy_turn:
    lda #ST_BATTLE_ENEMY
    sta game_state
    lda #20
    sta state_timer
    rts

do_talisman:
    ; Donut's lightning talisman - bigger hit but costs MP
    lda p_mp
    cmp #2
    bcc no_mp
    sec
    sbc #2
    sta p_mp
    jsr rand
    and #$07
    clc
    adc p_atk
    clc
    adc #3
    sta damage
    lda enemy_hp
    sec
    sbc damage
    bcs :+
    lda #0
:   sta enemy_hp
    lda #0
    sta PPUMASK
    jsr draw_enemy_hp_battle
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
    lda enemy_hp
    beq talisman_win
    jmp to_enemy_turn
talisman_win:
    lda #ST_BATTLE_WIN
    sta game_state
    lda #30
    sta state_timer
    lda p_xp
    clc
    adc enemy_xp
    sta p_xp
    lda p_gold
    clc
    adc enemy_gold
    sta p_gold
    rts
no_mp:
    rts

do_flee:
    ; 75% chance
    jsr rand
    and #$03
    beq to_enemy_turn
    ; Success - back to overworld
    lda #0
    sta PPUMASK
    jsr draw_overworld
    lda #%00011110
    sta PPUMASK
    lda #ST_OVERWORLD
    sta game_state
    rts
.endproc

;------------------------------------------------------------------------------
; Enemy turn - attacks Carl
;------------------------------------------------------------------------------
.proc update_battle_enemy
    dec state_timer
    bne wait
    
    ; damage = enemy_atk + rand(0..2) - p_def
    jsr rand
    and #$03
    clc
    adc enemy_atk
    sec
    sbc p_def
    bcs :+
    lda #1              ; min 1 damage
:   cmp #1
    bcs :+
    lda #1
:   sta damage
    
    lda p_hp
    sec
    sbc damage
    bcs :+
    lda #0
:   sta p_hp
    
    ; Redraw Carl HP
    lda #0
    sta PPUMASK
    jsr draw_hp_battle
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
    
    lda p_hp
    bne :+
    ; Defeat
    lda #ST_BATTLE_LOSE
    sta game_state
    lda #60
    sta state_timer
    rts
:   lda #ST_BATTLE_MENU
    sta game_state
wait:
    rts
.endproc

;------------------------------------------------------------------------------
; Victory screen - show briefly, then check level up / return
;------------------------------------------------------------------------------
.proc update_battle_win
    ; Draw victory message once when timer is at 30
    lda state_timer
    cmp #30
    bne :+
    lda #0
    sta PPUMASK
    SET_PPU_ADDR $2124
    SET_PTR1 str_victory
    jsr draw_string
    SET_PPU_ADDR $2164
    SET_PTR1 str_xp_gained
    jsr draw_string
    bit PPUSTATUS
    lda #$21
    sta PPUADDR
    lda #$6F
    sta PPUADDR
    lda enemy_xp
    jsr print_2digit
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
:   dec state_timer
    bne done
    
    ; Check for level up
    lda p_xp
    cmp p_xp_next
    bcc no_levelup
    
    ; Level up!
    lda p_xp
    sec
    sbc p_xp_next
    sta p_xp
    inc p_level
    ; Boost stats
    lda p_hp_max
    clc
    adc #5
    sta p_hp_max
    sta p_hp
    inc p_atk
    lda frame_lo
    and #1
    beq :+
    inc p_def
:   lda p_mp_max
    clc
    adc #1
    sta p_mp_max
    sta p_mp
    ; increase xp threshold
    lda p_xp_next
    clc
    adc #6
    sta p_xp_next

no_levelup:
    ; Sometimes descend a floor after victory
    jsr rand
    and #$07
    cmp #1
    bne stay_floor
    lda floor_num
    cmp #9
    bcs stay_floor
    inc floor_num
stay_floor:
    ; Back to overworld
    lda #0
    sta PPUMASK
    jsr draw_overworld
    lda #%00011110
    sta PPUMASK
    lda #ST_OVERWORLD
    sta game_state
done:
    rts
.endproc

str_victory:    .byte "VICTORY", 0
str_xp_gained:  .byte "XP GAINED ", 0

;------------------------------------------------------------------------------
; Game over screen
;------------------------------------------------------------------------------
.proc update_gameover
    lda state_timer
    cmp #60
    bne :+
    lda #0
    sta PPUMASK
    jsr clear_nametable
    SET_PPU_ADDR $214C
    SET_PTR1 str_gameover
    jsr draw_string
    SET_PPU_ADDR $218A
    SET_PTR1 str_gameover2
    jsr draw_string
    SET_PPU_ADDR $2228
    SET_PTR1 str_press_start2
    jsr draw_string
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
    sta PPUMASK
    jsr clear_sprites
:   dec state_timer
    bne skip
    lda #1
    sta state_timer     ; stay on game over
skip:
    ; Wait for start to return to title
    lda pad1_pressed
    and #BTN_START
    beq done
    
    ; Re-init everything
    jmp soft_reset
done:
    rts
.endproc

str_gameover:   .byte "YOUR CRAWL ENDS HERE", 0
str_gameover2:  .byte "THE SYSTEM IS AMUSED", 0
str_press_start2: .byte "PRESS START", 0

.proc soft_reset
    lda #20
    sta p_hp
    sta p_hp_max
    lda #5
    sta p_mp
    sta p_mp_max
    lda #4
    sta p_atk
    lda #2
    sta p_def
    lda #1
    sta p_level
    sta floor_num
    lda #0
    sta p_xp
    sta p_gold
    sta step_count
    lda #8
    sta p_xp_next
    lda #0
    sta PPUMASK
    jsr draw_title_screen
    lda #%00011110
    sta PPUMASK
    lda #ST_TITLE
    sta game_state
    rts
.endproc

;==============================================================================
; Tile number constants for background
;==============================================================================
TILE_FLOOR     = $01
TILE_WALL_TOP  = $02
TILE_WALL_SIDE = $03
TILE_PILLAR    = $04

;==============================================================================
; Switchable PRG bank 0 ($8000-$BFFF) - empty for now
;==============================================================================
.segment "BANK0"
    ; Future: string data, map data, enemy tables, etc.

;==============================================================================
; VECTORS (in fixed bank)
;==============================================================================
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq

;==============================================================================
; CHR-ROM (graphics) - included from generated binary
;==============================================================================
.segment "CHARS"
    .incbin "graphics.chr"
