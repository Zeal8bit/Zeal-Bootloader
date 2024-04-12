; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "keyboard_h.asm"
    INCLUDE "pio_h.asm"

    EXTERN pio_disable_interrupt

    SECTION BOOTLOADER

    ; Receive a character from the keyboard (synchronous, blocking)
    ; Parameters:
    ;       None
    ; Returns:
    ;       A - ASCII byte received
    ; Alters:
    ;       A, B, DE
    PUBLIC keyboard_next_char
keyboard_next_char:
    xor a
    ld (received), a

    PUBLIC keyboard_get_char
keyboard_get_char:
    ld de, received

_keyboard_get_char_loop:
    ld a, (de)
    or a
    jr z, _keyboard_get_char_loop
    ; Check if it's release key
    cp KB_RELEASE_SCAN
    jr z, _release_scan
    ; Character is not a "release command"
    ; Check if the character is a printable char
    push hl
    cp KB_PRINTABLE_CNT - 1
    jp nc, _special_code ; jp nc <=> A >= KB_PRINTABLE_CNT - 1
    ; Save the char in BC as it represents the index
    ld hl, base_scan
    jr get_from_scan
_special_code:
    ; Special character is still in A
    cp KB_EXTENDED_SCAN
    ret z
    add -KB_SPECIAL_START
    ld hl, special_scan
get_from_scan:
    add l
    ld l, a
    adc h
    sub l
    ld a, (hl)
    pop hl
    ret


_release_scan:
    ; Ignore the next character
    call keyboard_next_char
    ; Return the next character
    jp keyboard_next_char

base_scan:
        DEFB 0,   0,    0,   0,   0,   0,   0, 0, 0,   0,    0,   0,   0, '\t', '`', 0
        DEFB 0,   0,    0,   0,   0, 'q', '1', 0, 0,   0,  'z', 's', 'a',  'w', '2', 0
        DEFB 0, 'c',  'x', 'd', 'e', '4', '3', 0, 0, ' ',  'v', 'f', 't',  'r', '5', 0
        DEFB 0, 'n',  'b', 'h', 'g', 'y', '6', 0, 0,   0,  'm', 'j', 'u',  '7', '8', 0
        DEFB 0, ',',  'k', 'i', 'o', '0', '9', 0, 0, '.',  '/', 'l', ';',  'p', '-', 0
        DEFB 0,   0, '\'',   0, '[', '=',   0, 0, 0,   0, '\n', ']',   0, '\\'
special_scan:
        DEFB '\b', 0, 0, '1', 0, '4', '7', 0, 0, 0, '0'
        DEFB '.', '2', '5', '6', '8', KB_ESC
        DEFB 0, 0, '+', '3', '-', '*'
        DEFB '9', 0, 0, 0, 0, 0, 0, 0, 0



    ; Checks if any byte was pressed on the keyboard
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - 0 if no key was pressed, any non-zero value else
    ; Alters:
    ;   None
    PUBLIC keyboard_has_char
keyboard_has_char:
    ld a, (received)
    ret


    ; Set the keyboard input to synchronous
    PUBLIC keyboard_set_synchronous
keyboard_set_synchronous:
    ret


    ; Interrupt handler
    PUBLIC keyboard_int_handler
keyboard_int_handler:
    ex af, af'
    in a, (KB_IO_ADDRESS)
    ld (received), a
    ex af, af'
    ei
    reti


    SECTION BSS
received: DEFS 1