; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0
        INCLUDE "mmu_h.asm"
        INCLUDE "video_h.asm"
        INCLUDE "sys_table_h.asm"
        INCLUDE "uart_h.asm"

        SECTION BOOTLOADER

        EXTERN __BSS_head
        EXTERN __BSS_tail
        EXTERN video_initialize
        EXTERN bootloader_menu

        DEFC AUTOBOOT_DELAY_SECONDS = 5
        DEFC CPU_FREQ = 10000000

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
        call uart_initialize

        ; Ready to send and receive data over UART, show welcome message
        ld hl, start_message
        ld bc, start_message_end - start_message
        call uart_send_bytes

        ; Wait for a user input, on return, if A is 0, autoboot shall be performed
        ; else, enter the menu
        call autoboot
        or a
        jp nz, bootloader_menu
        ; Boot the first system of the entry table
        call newline
        call sys_table_get_first
        jp bootloader_print_boot_entry

        ; Routine showing the autoboot message and waiting for a keypress.
        ; Returns:
        ;   A - 0 if autoboot, 1 if key pressed
        DEFC MOVE_BACKWARD_COLS = seconds_message_end - seconds_message + 1
autoboot:
        ; Prepare the escape sequence for moving cursor backward:
        ;   ESC[#D where # is the number of columns to move backward
        ld hl, escape
        ld (hl), 0x1b   ; ESC
        inc hl
        ld (hl), '['
        inc hl
        ; Size of " ...seconds" message + 1, in ASCII
        ld (hl), MOVE_BACKWARD_COLS / 10 + '0'
        inc hl
        ld (hl), MOVE_BACKWARD_COLS % 10 + '0'
        inc hl
        ld (hl), 'D'
        ; Print the autoboot message
        ld hl, boot_message
        ld bc, boot_message_end - boot_message
        call uart_send_bytes
        ; Loop until E (not altered by uart_send_bytes) is 0 (included)
        ld e, AUTOBOOT_DELAY_SECONDS + 1
autoboot_loop:
        ; Convert E - 1 to an ASCII character
        ld a, e
        add '0' - 1
        call uart_send_one_byte
        ; Send "seconds" word then
        ld hl, seconds_message
        ld bc, seconds_message_end - seconds_message
        call uart_send_bytes
        dec e
        jp z, autoboot_loop_end
        ; Wait a bit less than 1 second, should also check keypress or UART receive
        push de
        ld de, 900
        call sleep_ms
        pop de
        ; Check if a character arrived
        or a
        ret nz
        ; No character arrived, move the cursor backward down to the seconds count
        ld hl, escape
        ld bc, 5
        call uart_send_bytes
        jr autoboot_loop
autoboot_loop_end:
        ; No keypress, no UART receive, return 0
        xor a
        ret

        ; Sleep for DE milliseconds while checking for a byte on the UART
        ; Returns:
        ;   A - 0 no character received, non-zero else
        ; Alters:
        ;   A, DE, BC
sleep_ms:
_sleep_ms_again:
        ; Divide by 1000 to get the number of T-states per milliseconds
        ; 50 is the number of T-states below
        ld bc, CPU_FREQ / 1000 / 50
_sleep_ms_waste_time:
        ; 50 T-states for the following, until 'jp nz, _zos_waste_time'
        call uart_available_read
        or a
        ret nz
        dec bc
        ld a, b
        or c
        jp nz, _sleep_ms_waste_time
        ; If we are here, a milliseconds has elapsed
        dec de
        ld a, d
        or e
        jp nz, _sleep_ms_again
        ret

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
        call uart_send_bytes
        pop hl
        push hl
        ld bc, SYS_NAME_MAX_LENGTH
        call uart_send_bytes
        call newline
        ; Pop the first entry address and boot it!
        pop hl
        jp sys_table_boot_entry
autoboot_msg:
        DEFM "\r\nNow booting "
autoboot_msg_end:


start_message:
        DEFM "\r\nZeal 8-bit Computer bootloader "
        INCBIN "version.txt"
        DEFM "\r\n\r\n"
start_message_end:
boot_message:
        DEFM "Press any key to enter menu. Booting automatically in "
boot_message_end:
seconds_message:
        DEFM " seconds..."
seconds_message_end:


        SECTION BSS
        ORG 0xC000
escape: DEFS 8
        ; Need to align on 16 for UART_FIFO
        ALIGN 16