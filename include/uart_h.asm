; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

        IFNDEF UART_H
        DEFINE UART_H

        ; Baudrates for receiving bytes from the UART
        DEFC UART_BAUDRATE_57600 = 0
        DEFC UART_BAUDRATE_38400 = 1
        DEFC UART_BAUDRATE_19200 = 4
        DEFC UART_BAUDRATE_9600  = 10
        DEFC UART_BAUDRATE_COUNT = 4

        ; Default baudrate for UART
        DEFC UART_BAUDRATE_DEFAULT = UART_BAUDRATE_57600

        ; Public routines
        EXTERN uart_initialize
        EXTERN uart_autoboot
        EXTERN uart_clear_screen
        EXTERN uart_send_bytes
        EXTERN uart_send_one_byte
        EXTERN uart_available_read
        EXTERN uart_fifo_reset
        EXTERN uart_disable_fifo
        EXTERN uart_receive_one_byte
        EXTERN uart_receive_big_file
        EXTERN uart_set_baudrate
        EXTERN uart_newline

        ENDIF
