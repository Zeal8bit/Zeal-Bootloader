; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "config.asm"
    INCLUDE "pio_h.asm"

    IF CONFIG_ENABLE_VIDEO_BOARD
        DEFC IO_PIO_SYSTEM_INT_MASK = ~(1 << IO_KEYBOARD_PIN) & 0xff
        DEFC int_handler = keyboard_int_handler
    ELSE ; !CONFIG_ENABLE_VIDEO_BOARD
        DEFC IO_PIO_SYSTEM_INT_MASK = ~(1 << IO_UART_RX_PIN) & 0xff
        DEFC int_handler = uart_int_handler
    ENDIF ; CONFIG_ENABLE_VIDEO_BOARD

    EXTERN int_handlers_table
    EXTERN uart_int_handler
    EXTERN keyboard_int_handler


    SECTION BOOTLOADER

    PUBLIC pio_initialize
pio_initialize:
    ; Set system port as bit-control
    ld a, IO_PIO_BITCTRL
    out (IO_PIO_SYSTEM_CTRL), a
    ; Set the proper direction for each pin
    ld a, IO_PIO_SYSTEM_DIR
    out (IO_PIO_SYSTEM_CTRL), a
    ; Set default value for all the (output) pins
    ld a, IO_PIO_SYSTEM_VAL
    out (IO_PIO_SYSTEM_DATA), a
    ; Set interrupt vector to 2
    ld a, 2
    out (IO_PIO_SYSTEM_CTRL), a
    ; Enable the interrupts globally for the system port
    ld a, IO_PIO_ENABLE_INT
    out (IO_PIO_SYSTEM_CTRL), a
    ; Enable interrupts, for the required pins only
    ld a, IO_PIO_SYSTEM_INT_CTRL
    out (IO_PIO_SYSTEM_CTRL), a
    ; Mask must follow
    ld a, IO_PIO_SYSTEM_INT_MASK
    out (IO_PIO_SYSTEM_CTRL), a
    ; Initalize user port as input
    ld a, IO_PIO_INPUT
    out (IO_PIO_USER_CTRL), a
    ld a, IO_PIO_DISABLE_INT
    out (IO_PIO_USER_CTRL), a
    ; Enable interrupts
    ld a, int_handlers_table >> 8
    ld i, a
    im 2
    ei
    ret

    PUBLIC pio_disable_interrupt
pio_disable_interrupt:
    ld a, IO_PIO_DISABLE_INT
    out (IO_PIO_SYSTEM_CTRL), a
    ret


    PUBLIC default_handler
default_handler:
    jp int_handler