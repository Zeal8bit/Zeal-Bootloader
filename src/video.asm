; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "config.asm"
    INCLUDE "mmu_h.asm"
    INCLUDE "uart_h.asm"
    INCLUDE "pio_h.asm"
    INCLUDE "video_h.asm"
    INCLUDE "keyboard_h.asm"

    SECTION BOOTLOADER

    EXTERN keyboard_has_char
    EXTERN keyboard_get_char

    DEFC DEFAULT_VIDEO_MODE = VID_MODE_TEXT_640
    DEFC DEFAULT_CURSOR_BLINK = 30
    DEFC DEFAULT_TEXT_CTRL = 1 << IO_TEXT_AUTO_SCROLL_Y_BIT | 1 << IO_TEXT_WAIT_ON_WRAP_BIT

    MACRO MAP_TEXT_CTRL _
        xor a
        out (IO_MAPPER_BANK), a
    ENDM



    ; Initialize the video card
    ; Parameters:
    ;   None
    ; Returns:
    ;   None
    ; Alters:
    ;   A
    PUBLIC video_initialize
video_initialize:
    ; Map the text controller to the banked I/O
    xor a
    out (IO_MAPPER_BANK), a

    ld a, DEFAULT_VIDEO_MODE
    out (IO_CTRL_VID_MODE), a

  IF CONFIG_VIDEO_SHOW_LOGO
    ; Load the logo in memory
    call video_prepare_logo
  ENDIF

    ; Reset the cursor position, the scroll value and the color, it should already be set to default
    ; on coldboot, but maybe not on warmboot
    call video_clear_screen

    xor a
    out (IO_TEXT_CURS_CHAR), a
    ld a, DEFAULT_CHARS_COLOR
    out (IO_TEXT_COLOR), a
    ld a, DEFAULT_CHARS_COLOR_INV
    out (IO_TEXT_CURS_COLOR), a

    ; Hide the cursor, it shall only be shown if the user enters the menu
    xor a
    out (IO_TEXT_CURS_TIME), a

    ; Enable the screen
    ld a, 0x80
    out (IO_CTRL_STATUS_REG), a
    ; Enable auto scroll Y as well as wait-on-wrap
    ld a, DEFAULT_TEXT_CTRL
    out (IO_TEXT_CTRL_REG), a
    ret


    ; Print the given bytes on screen
    ; Parameters:
    ;   HL - Pointer to the sequence of bytes
    ;   BC - Size of the sequence
    ; Returns:
    ;   A - 0 on success, not zero else
    ;   HL - HL + BC
    ; Alters:
    ;   A, BC, HL
    PUBLIC video_write
video_write:
    ld a, b
    or c
    ret z
    ; DE and BC won't be altered by print_char. Use DE for the buffer address.
    push de
    ex de, hl
_video_write_loop:
    ld a, (de)
    call print_char
    inc de
    dec bc
    ld a, b
    or c
    jp nz, _video_write_loop
    ex de, hl
    pop de
    ret


    ; Routine showing the autoboot message and waiting for a keypress.
    ; Returns:
    ;   A - 0 if autoboot, 1 if key pressed
    PUBLIC video_autoboot
video_autoboot:
    ; Print the autoboot message
    ld hl, boot_message
    ld bc, boot_message_end - boot_message
    call video_write
    ASSERT(CONFIG_AUTOBOOT_DELAY_SECONDS * 60 < 0x10000)
    ; Wait CONFIG_AUTOBOOT_DELAY_SECONDS seconds while checking keyboard input
    ; We will wait (CONFIG_AUTOBOOT_DELAY_SECONDS * 60) v-blanks since the refresh rate is 60Hz
    ; TODO: Use the V-blank interrupts
    ld hl, CONFIG_AUTOBOOT_DELAY_SECONDS * 60
    ; Save the previous control status register in C
    ; This will let us check the edge and not the level of the v-blank
    xor a
_video_autoboot_loop:
    ld c, a ; previous ctrl status in C
    ; Check if any character is ready
    ; Preserves HL and C
    call keyboard_has_char
    or a
    jr z, _video_autoboot_loop_continue
    ; A character was received on the keyboard, check if it's the ESC key
    ; Preserves HL and C
    call keyboard_get_char
    sub KB_ESC
    ; If it's not the ESC key, ignore it and continue the loop
    jr nz, _video_autoboot_loop_continue
    ; It's the ESC key! Return a success ( > 0)
    inc a
    ret
_video_autoboot_loop_continue:
    ; No key pressed, check if we are in a v-blank
    in a, (IO_CTRL_STATUS_REG)
    and 2
    ; If A is 0, no v-blank, continue the loop
    jr z, _video_autoboot_loop
    ; Currently in V-blank, if the previous status was 0, we have to count this v-blank, else, skip it
    ; before we already counted it. In other words, we try to detect the rising edge.
    dec c
    inc c
    jr nz, _video_autoboot_loop
    ; Rising edge, count it!
    dec hl
    ld a, h
    or l
    ; If HL is 0, it's a timeout, return directly
    ret z
    ; Else, continue the loop with the previous status reg being 2
    ld a, 2
    jp _video_autoboot_loop

boot_message: DEFM "Booting...\n\nPress ESC key to enter menu"
boot_message_end:


    ; Print a single byte on the screen
    ; Parameters:
    ;   A - ASCII byte to print
    ; Alters:
    ;   A, BC
    PUBLIC video_put_char
video_put_char:
    ld b, h
    ld c, l
    call print_char
    ld h, b
    ld l, c
    ret


    PUBLIC video_newline
video_newline:
    push hl
    call _print_char_newline
    pop hl
    ret


    ; Alters:
    ;   A, HL
print_char:
    or a
    ret z   ; NULL-character, don't do anything
    cp '\n'
    jr z, _print_char_newline
    cp '\r'
    jr z, _print_char_carriage_return
    cp '\b'
    jr z, _print_char_backspace
    cp 0xF0
    jr nc, _print_char_set_color
    ; Tabulation is considered a space. Do nothing special.
    ; If by putting a character we end up scrolling the screen, we'll have to erase a line
_print_any_char:
    out (IO_TEXT_PRINT_CHAR), a
    ; X should be 1 if a scroll occured after outputting a character
    ld l, 1
_print_check_scroll:
    ; Check if scrolled in Y occurred
    in a, (IO_TEXT_CTRL_REG)
    ; Make the assumption that the flag is the bit 0
    ASSERT (IO_TEXT_SCROLL_Y_OCCURRED == 0)
    rrca
    ; No carry <=> No scroll Y
    ret nc
    ; Erase the current line else
    jp erase_line
_print_char_newline:
    ; Use the dedicated register to output a newline
    ld a, DEFAULT_TEXT_CTRL | 1 << IO_TEXT_CURSOR_NEXTLINE
    out (IO_TEXT_CTRL_REG), a
    ; If a scroll occurred, we need to clear the whole line, X is 0
    ld l, 0
    jp _print_check_scroll
_print_char_carriage_return:
    ; Reset cursor X to 0
    xor a
    out (IO_TEXT_CURS_X), a
    ret
_print_char_backspace:
    ; It is unlikely that X is 0 and even more unlikely that Y is too
    ; so save some time for the "best" case.
    in a, (IO_TEXT_CURS_X)
    dec a
    ; We know that the cursor X can be signed (0-127), so if the result is
    ; negative, it means that it was 0
    jp m, _print_char_backspace_x_negative
    ; X is valid, we can update it and return
    out (IO_TEXT_CURS_X), a
    ret
_print_char_backspace_x_negative:
    ; Set X to the maximum possible value
    ld a, VID_640480_X_MAX - 1
    out (IO_TEXT_CURS_X), a
    ; Y must be decremented
    in a, (IO_TEXT_CURS_Y)
    dec a
    jp p, _print_char_backspace_y_non_zero
    ; Y was 0, roll it back
    ld a, VID_640480_Y_MAX - 1
_print_char_backspace_y_non_zero:
    out (IO_TEXT_CURS_Y), a
    ; Should we manage the scroll?
    ret
_print_char_set_color:
    ; Get the color out of the character
    and 0x0f
    ; High byte is now 0 (black color)
    out (IO_TEXT_COLOR), a
    ret


    ; Erase a whole video line (writes blank character on the current line)
    ; Parameters:
    ;       L - Cursor X position
    ; Returns:
    ;       None
    ; Alters:
    ;       A, HL
erase_line:
    ld h, b ; BC must not be altered
    ; Calculate the number of characters remaining on the current line
    ld a, VID_640480_X_MAX
    sub l
    ld b, a
    ld a, ' '
_erase_line_loop:
    out (IO_TEXT_PRINT_CHAR), a
    djnz _erase_line_loop
    ; Restore B register
    ld b, h
    ; Reset X cursor position
    ld a, l
    out (IO_TEXT_CURS_X), a
    ret


    ; Clear the whole screen
    PUBLIC video_clear_screen
video_clear_screen:
    ; Reset the cursor on screen and the scrolling values
    xor a
    out (IO_TEXT_CURS_X), a
    out (IO_TEXT_CURS_Y), a
    out (IO_TEXT_SCROLL_Y), a
    out (IO_TEXT_SCROLL_X), a

    ; Make the cursor blink every 30 frames (~500ms)
    ld a, DEFAULT_CURSOR_BLINK
    out (IO_TEXT_CURS_TIME), a


    ; Save the current mapping
    MMU_GET_PAGE_NUMBER(MMU_PAGE_1)
    push af
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x100000)
    ; Clear layer 0
    ld hl, 0x4000
    ld bc, 3200
    ; D = 0
    ld d, l
_clear_screen_loop:
    ld (hl), d
    inc hl
    dec bc
    ld a, b
    or c
    jp nz, _clear_screen_loop
  IF CONFIG_VIDEO_SHOW_LOGO
    call _video_show_version
    jp video_show_logo
  ELSE ; CONFIG_VIDEO_SHOW_LOGO
    pop af
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ret
  ENDIF



  IF CONFIG_VIDEO_SHOW_LOGO

    EXTERN version_message
    EXTERN version_message_end
    DEFC VERSION_LENGTH = version_message_end - version_message - 1

    ; Show the current at the bottom right at the screen
_video_show_version:
    ; The VRAM is mapped at the first page (0x4000)
    ld de, 0x4000 + 3200 - VERSION_LENGTH
    ld bc, VERSION_LENGTH
    ld hl, version_message
    ldir
    ; Set the attributes too
    ld b, VERSION_LENGTH
    ld a, 0x0f  ; Black background, white foreground
    ld hl, 0x5000 + 3200 - VERSION_LENGTH
_show_version_loop:
    ld (hl), a
    inc hl
    djnz  _show_version_loop
    ret


video_prepare_logo:
    ; Save the current mapping
    MMU_GET_PAGE_NUMBER(MMU_PAGE_1)
    push af
    ; Map the video memory
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x100000)

    ; Save the font that we are going to erase
    ld hl, 0x4000 + 0x3000 + 128 * 12
    push hl ; VRAM address on the stack
    ld de, font_backup
    ld bc, tileset_end - tileset ; Size on the stack too
    push bc
    ldir

    ; Destination font table, starting from character 128 (12 byte per char)
    pop bc
    pop de
    ld hl, tileset
    ldir

    ; Set the violet color for the logo: 0x6A8E
    ld hl, 0x6A8E
    ; Use the color of index 5 (2 bytes per color)
    ld (0x4000 + 0xE00 + 5 * 2), hl
    jr _remap_page_1

video_show_logo:
    ld a, 0x80   ; Character to print
    ; 9 columns, 6 lines
    ld b, 9
    ld c, 6
    ld de, 71   ; 80 characters per line - 9 chars per column
    ld hl, 0x4000 + 0x1000 + 149    ; Start at character 149
_logo_loop:
    ; Set the color to 0x05
    ld (hl), 0x05
    ; Set the character (unset bit)
    res 4, h
    ld (hl), a
    set 4, h
    inc hl
    inc a
    djnz _logo_loop
    ; B is 0, go to the next line
    add hl, de
    ld b, 9
    dec c
    jr nz, _logo_loop
_remap_page_1:
    pop af
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ret


    PUBLIC video_unload_assets
video_unload_assets:
    push hl
    MMU_GET_PAGE_NUMBER(MMU_PAGE_1)
    push af
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x100000)
    ; Reset the color of index 5
    ld hl, 0xa815
    ld (0x4000 + 0xE00 + 5 * 2), hl
    ; Restore the font data
    ld de, 0x4000 + 0x3000 + 128 * 12
    ld hl, font_backup
    ld bc, tileset_end - tileset
    ldir
    ; Restore original page
    pop af
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    pop hl
    ret


tileset:
    INCBIN "tileset.bin"
tileset_end:


    SECTION BSS
font_backup: DEFS 1024


  ELSE

    ; Unload the custom color out of the palette and the fonts
    ; DO NOT ALTER HL
    PUBLIC video_unload_assets
video_unload_assets:
    ret


  ENDIF ; CONFIG_VIDEO_SHOW_LOGO