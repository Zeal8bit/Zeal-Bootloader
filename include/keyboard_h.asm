; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    IFNDEF KEYBOARD_H
    DEFINE KEYBOARD_H

    EXTERN keyboard_get_char
    EXTERN keyboard_next_char
    EXTERN keyboard_has_char
    EXTERN keyboard_set_synchronous

    DEFC KB_IO_ADDRESS = 0xe8

    DEFC KB_PRINTABLE_CNT = 0x60
    DEFC KB_SPECIAL_START = 0x66	; Between 0x60 and 0x66, nothing special
    DEFC KB_EXTENDED_SCAN = 0xe0	; Extended characters such as keypad or arrows
    DEFC KB_RELEASE_SCAN  = 0xf0
    DEFC KB_RIGHT_ALT_SCAN  = 0x11
    DEFC KB_RIGHT_CTRL_SCAN = 0x14
    DEFC KB_LEFT_SUPER_SCAN = 0x1f
    DEFC KB_NUMPAD_DIV_SCAN = 0x4a
    DEFC KB_NUMPAD_RET_SCAN = 0x5a
    DEFC KB_PRT_SCREEN_SCAN = 0x12	; When Print Screen is received, the scan is 0xE0 0x12
    DEFC KB_MAPPED_EXT_SCANS = 0x69 ; Extended characters which scan code is 0xE0 0x69 and above
                                    ; are treated with a mapped array

    DEFC KB_ESC = 0x80

    ENDIF
