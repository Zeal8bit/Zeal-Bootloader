; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

        INCLUDE "config.asm"
        INCLUDE "mmu_h.asm"
        INCLUDE "video_h.asm"
        INCLUDE "sys_table_h.asm"
        INCLUDE "stdout_h.asm"
        INCLUDE "uart_h.asm"

        SECTION BOOTLOADER

        EXTERN __BSS_head
        EXTERN __BSS_tail
        EXTERN video_initialize
        EXTERN pio_initialize
        EXTERN bootloader_menu

        PUBLIC bootloader_entry
bootloader_entry:
        ; Map the first 48KB of ROM
        MAP_PHYS_ADDR(MMU_PAGE_1, 0x4000)
        MAP_PHYS_ADDR(MMU_PAGE_2, 0x8000)
        ; Last 16KB of RAM in the last page
        MAP_PHYS_ADDR(MMU_PAGE_3, 0xfc000)
        ld sp, 0xFFFF

        ; Initialize the BSS section
        ; It is not needed to initialize the FIFO data itself
        ; as the bytes will be overwritten
        ld hl, __BSS_head
        ld (hl), 0
        ld de, __BSS_head + 1
        ld bc, __BSS_tail - __BSS_head - 1
        ldir

        call sys_table_init
        ; UART will be used to receive files in all cases
        call uart_initialize
        call pio_initialize
    IF CONFIG_ENABLE_VIDEO_BOARD
        call stdout_initialize
    ENDIF ; CONFIG_ENABLE_VIDEO_BOARD

        ; Ready to send and receive data over UART, show welcome message
        ld hl, start_message
        ld bc, start_message_end - start_message
        call stdout_write

        ; Wait for a user input, on return, if A is 0, autoboot shall be performed
        ; else, enter the menu
        call stdout_autoboot
        or a
        jp nz, bootloader_menu
        ; Boot the first system of the entry table
        call stdout_newline
        call sys_table_get_first
        jp bootloader_print_boot_entry


        ; Print the name of the system pointed by the entry and boot it
        ; Parameters:
        ;   HL - System entry address
        ; Returns:
        ;   Doesn't return
        ; Alters:
        ;   -
        PUBLIC bootloader_print_boot_entry
bootloader_print_boot_entry:
        push hl
        ; Print the "Now booting" message
        ld hl, autoboot_msg
        ld bc, autoboot_msg_end - autoboot_msg
        call stdout_write
        pop hl
        push hl
        ld bc, SYS_NAME_MAX_LENGTH
        call stdout_write
        call stdout_newline
        ; Pop the first entry address and boot it!
        pop hl
        jp sys_table_boot_entry
autoboot_msg:
        DEFM "\r\nNow booting "
autoboot_msg_end:


        PUBLIC version_message
        PUBLIC version_message_end
start_message:
        DEFM "\r\nZeal 8-bit Computer bootloader "
version_message:
        INCBIN "version.txt"
version_message_end:
        DEFM "\r\n\r\n"
start_message_end:


        SECTION BSS
        ORG 0xC000
