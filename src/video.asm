; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0
        INCLUDE "uart_h.asm"
        INCLUDE "pio_h.asm"
        INCLUDE "video_h.asm"

        SECTION BOOTLOADER
        
        PUBLIC video_initialize
video_initialize:
        ; Check if we have the video board connected
        ld a, 0x42
        ld b, a
        out (IO_VIDEO_SCROLL_Y), a
        ; Read back this register
        in a, (IO_VIDEO_SCROLL_Y)
        cp b
        ret nz
        ; We have the video board connected, save this info
        ld a, 1
        ld (has_video), a
        ; Set scroll to 0
        xor a
        out (IO_VIDEO_SCROLL_Y), a
        ; Initialize the characters color
        ld a, 0x0f
        jp set_chars_color


        ; Set the characters colors for the video board
set_chars_color:
        ld (chars_color), a
        ; Let video chip save this default color
        out (IO_VIDEO_SET_COLOR), a
        ; Save the color where background and foreground are inverted
        rlca
        rlca
        rlca
        rlca
        ld (invert_color), a
        ret


        SECTION BSS
has_video: DEFS 1
chars_color: DEFS 1
invert_color: DEFS 1
