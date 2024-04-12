; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "config.asm"

    IFNDEF STDOUT_H
    DEFINE STDOUT_H

    ; It is possible to choose either the UART or video board as the standard output
    IF CONFIG_UART_AS_STDOUT
        INCLUDE "uart_h.asm"

        DEFC stdout_initialize = uart_initialize
        DEFC stdout_autoboot   = uart_autoboot
        DEFC stdout_write      = uart_send_bytes
        DEFC stdout_put_char   = uart_send_one_byte
        DEFC stdout_newline    = uart_newline
        DEFC stdin_get_char    = uart_receive_one_byte
        DEFC stdin_has_char    = uart_available_read
        DEFC stdin_set_synchronous = uart_disable_fifo
        DEFC stdout_prepare_menu = uart_clear_screen

        MACRO YELLOW_COLOR _
            DEFM 0x1b, "[1;33m"
        ENDM
        MACRO GREEN_COLOR _
            DEFM 0x1b, "[1;32m"
        ENDM
        MACRO RED_COLOR _
            DEFM 0x1b, "[1;31m"
        ENDM

        MACRO END_COLOR _
            DEFM  0x1b, "[0m"
        ENDM

    ELSE ; !CONFIG_UART_AS_STDOUT

        INCLUDE "video_h.asm"
        INCLUDE "keyboard_h.asm"

        DEFC stdout_initialize = video_initialize
        DEFC stdout_autoboot   = video_autoboot
        DEFC stdout_write      = video_write
        DEFC stdout_put_char   = video_put_char
        DEFC stdout_newline    = video_newline
        DEFC stdin_get_char    = keyboard_next_char
        DEFC stdin_has_char    = keyboard_has_char
        DEFC stdin_set_synchronous = keyboard_set_synchronous
        DEFC stdout_prepare_menu = video_clear_screen

        ; Use a prefix for the colors
        MACRO YELLOW_COLOR _
            DEFM 0xFE
        ENDM
        MACRO GREEN_COLOR _
            DEFM 0xF2
        ENDM
        MACRO RED_COLOR _
            DEFM 0xF4
        ENDM

        MACRO END_COLOR _
            DEFM 0xff
        ENDM

    ENDIF


    MACRO PRINT_STR label
        ld hl, label
        ld bc, label ## _end - label
        call stdout_write
    ENDM

    MACRO PRINT_STR_UART label
        ld hl, label
        ld bc, label ## _end - label
        call uart_send_bytes
    ENDM

    ENDIF