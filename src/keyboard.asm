; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "keyboard_h.asm"
    INCLUDE "pio_h.asm"

    EXTERN pio_disable_interrupt

    SECTION BOOTLOADER

    ; Receive a character from the keyboard, non-blocking version
    ; Returns:
    ;   A - 0 if no valid character was received, character value else
    ; Alters:
    ;       A, B, HL, DE
    PUBLIC keyboard_get_char_nonblocking
keyboard_get_char_nonblocking:
    ld hl, received
    ld b, 0
    ; Atomic test and set
    di
    ld a, (hl)
    ld (hl), b
    ei
    or a
    ret z
    ; Make HL point to the 'flag' variable
    inc hl
    ; Set a flag if release key
    cp KB_RELEASE_SCAN
    jr z, _release_scan_received
    ; Check if we received a release scan previously
    ld b, (hl)
    ; Check if flag is 0
    inc b
    dec b
    jr nz, _flag_not_zero
    ; Flag is not 0, we just received a real character, parse it
    ; Check if it is a printable character
    cp KB_PRINTABLE_CNT - 1
    jp nc, _special_code ; jp nc <=> A >= KB_PRINTABLE_CNT - 1
    ; Save the scan size in B
    ld hl, base_scan
    ld b, base_scan_end - base_scan
    jr _get_from_scan
_special_code:
    ; Special character is still in A
    sub KB_EXTENDED_SCAN
    ; Ignore extended scan characters for now, return 0
    ret z
    ; We just subtracted KB_EXTENDED_SCAN, add it back
    add KB_EXTENDED_SCAN-KB_SPECIAL_START
    ld hl, special_scan
    ld b, special_scan_end - special_scan
_get_from_scan:
    ; Check if there would be an overflow
    cp b
    ; If there no carry, A is equal or bigger than the length, consider this
    ; an invalid character, return 0
    jr nc, _overflow_ret_zero
    ; Get the value of A from the scan table pointed by HL
    add l
    ld l, a
    adc h
    sub l
    ld h, a
    ld a, (hl)
    ret
_overflow_ret_zero:
    xor a
    ret
_flag_not_zero:
    ; Clear the flag and ignore the current character, return 0
    xor a
    ; Fall-through
_release_scan_received:
    ; Set the flag to a non-zero value
    ld (hl), a
    ; Return not-valid character
    xor a
    ret


    ; Receive a character from the keyboard (synchronous, blocking)
    ; Parameters:
    ;       None
    ; Returns:
    ;       A - ASCII byte received
    ; Alters:
    ;       A, B, DE
    PUBLIC keyboard_next_char
keyboard_next_char:
    ; Clear the previously received keys
    xor a
    ld (received), a
    push hl
_keyboard_next_char_loop:
    call keyboard_get_char_nonblocking
    or a
    ; If character is invalid, continue the loop
    jr z, _keyboard_next_char_loop
    pop hl
    ret

base_scan:
        DEFB 0,   0,    0,   0,   0,   0,   0, 0, 0,   0,    0,   0,   0, '\t', '`', 0
        DEFB 0,   0,    0,   0,   0, 'q', '1', 0, 0,   0,  'z', 's', 'a',  'w', '2', 0
        DEFB 0, 'c',  'x', 'd', 'e', '4', '3', 0, 0, ' ',  'v', 'f', 't',  'r', '5', 0
        DEFB 0, 'n',  'b', 'h', 'g', 'y', '6', 0, 0,   0,  'm', 'j', 'u',  '7', '8', 0
        DEFB 0, ',',  'k', 'i', 'o', '0', '9', 0, 0, '.',  '/', 'l', ';',  'p', '-', 0
        DEFB 0,   0, '\'',   0, '[', '=',   0, 0, 0,   0, '\n', ']',   0, '\\'
base_scan_end:
special_scan:
        DEFB '\b', 0, 0, '1', 0, '4', '7', 0, 0, 0, '0'
        DEFB '.', '2', '5', '6', '8', KB_ESC
        DEFB 0, 0, '+', '3', '-', '*'
        DEFB '9', 0, 0, 0, 0, 0, 0, 0, 0
special_scan_end:



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
flag: DEFS 1