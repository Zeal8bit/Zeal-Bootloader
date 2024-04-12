; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    IFNDEF CONFIG_H
    DEFINE CONFIG_H

; When set, the UART will be used as the standard output. When not set or set to 0, the video driver will
; be used. The UART driver will still be used to receive files.
DEFC CONFIG_UART_AS_STDOUT = 1

; When set, the Zeal logo will be shown on screen, this takes more RAM at runtime but won't affect the
; OS or program running after the bootloader as the modified tiles are saved and restored.
DEFC CONFIG_VIDEO_SHOW_LOGO = 1

; When set, the hardware tester will be available in the menu.
DEFC CONFIG_ENABLE_TESTER = 1

; When set, the user will be asked to press a key before returnig to the menu
DEFC CONFIG_ACK_CONTINUE = 1

; Number of secodns to wait before autoboot
DEFC CONFIG_AUTOBOOT_DELAY_SECONDS = 3

    ENDIF ; CONFIG_H