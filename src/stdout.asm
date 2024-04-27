; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "config.asm"
    INCLUDE "stdout_h.asm"

  ; Changing the standard output and/or input is only available if have the video board
  ; enabled.
  IF CONFIG_ENABLE_VIDEO_BOARD

    SECTION BOOTLOADER

    ; In some cases, it may be needed to switch the standard input to the UART.
    ; Parameters:
    ;   A - New driver to select, STDOUT_DRIVER_UART OR STDOUT_DRIVER_VIDEO
    PUBLIC std_set_driver
std_set_driver:
    ld (stdmode), a
    ret


    PUBLIC stdout_initialize
stdout_initialize:
    ld a, STDOUT_DRIVER_VIDEO
    ld (stdmode), a
    jp video_initialize


    ; Parameters:
    ;   HL - Pointer to the sequence of bytes
    ;   BC - Size of the sequence
    PUBLIC stdout_write
stdout_write:
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    jp z, uart_send_bytes
    jp video_write


    ; Parameters:
    ;   A - ASCII byte to send on the UART
    ; Can alter:
    ;   A, BC ,D
    PUBLIC stdout_put_char
stdout_put_char:
    ld d, a
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    ld a, d
    jp z, uart_send_one_byte
    jp video_put_char


    PUBLIC stdout_put_char
stdout_newline:
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    jp z, uart_newline
    jp video_newline


    PUBLIC stdin_get_char
stdin_get_char:
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    jp z, uart_receive_one_byte
    ; Video/keyboard mode
    jp keyboard_next_char


    PUBLIC stdin_has_char
stdin_has_char:
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    jp z, uart_available_read
    ; Video/keyboard mode
    jp keyboard_has_char


    PUBLIC stdin_set_synchronous
stdin_set_synchronous:
    ld a, (stdmode)
    cp STDOUT_DRIVER_UART
    jp z, uart_disable_fifo
    ; Video/keyboard mode
    jp keyboard_set_synchronous


    SECTION BSS
stdmode: DEFS 1


  ENDIF ; CONFIG_ENABLE_VIDEO_BOARD