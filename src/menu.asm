; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

        INCLUDE "config.asm"
        INCLUDE "mmu_h.asm"
        INCLUDE "sys_table_h.asm"
        INCLUDE "stdout_h.asm"
        INCLUDE "uart_h.asm"

        DEFC BUFFER_SIZE = 32

        EXTERN newline
        EXTERN test_hardware
        EXTERN format_eeprom
        EXTERN video_board_flash
        EXTERN video_wait_recovery

        SECTION BOOTLOADER

        PUBLIC bootloader_menu
bootloader_menu:
        call stdout_prepare_menu
        call stdin_set_synchronous
        ; Print the entering menu message
        ld hl, menu_msg
        ld bc, menu_msg_end - menu_msg
        call stdout_write
        ; Populate our "systems" table while printing each entry
        call populate_systems
        ; Show the advanced options
        ld hl, advanced_msg
        ld bc, advanced_msg_end - advanced_msg
        call stdout_write
        ; Wait for the user input
        call stdin_get_char
        ; Print is back
        push af
        call stdout_put_char
        call stdout_newline
        pop af
        call process_menu_choice
    IF CONFIG_ACK_CONTINUE
        ld hl, ack_str
        ld bc, ack_str_end - ack_str
        call stdout_write
        call stdin_get_char
    ENDIF
        ; No matter what the result is, print back the main menu
        jr bootloader_menu

        ; Alters:
        ;   A, BC, DE, HL
populate_systems:
        ; Loop through the table, looking for the first non-null name
        ld hl, sys_table_ram
        ld de, systems
        ; C contains the total amount of active entries
        ld c, 0
        ld b, SYS_TABLE_ENTRY_COUNT
        ; Make the assumption that we will always have at least one entry in the table
populate_systems_loop:
        ld a, (hl)
        ; Check the current entry
        or a
        jp z, populate_systems_empty
        ; Entry found, increment C, show C value in ASCII and print the entry (in HL)
        inc c
        push bc
        push de
        push hl
        ; Print C in ASCII followed by ' - Boot '
        ld a, c
        add '0'
        call stdout_put_char
        ld hl, separator
        ld bc, separator_end - separator
        call stdout_write
        ; Print the actual entry now
        pop hl
        push hl
        call print_entry
        pop hl
        pop de
        pop bc
        ; Populate the systems array (in DE)
        ex de, hl
        ld (hl), e
        inc hl
        ld (hl), d
        inc hl
        ex de, hl
populate_systems_empty:
        ; Next entry
        ld a, SYS_TABLE_ENTRY_SIZE
        ; HL += A
        add l
        ld l, a
        adc h
        sub l
        ld h, a
        djnz populate_systems_loop
        ; Store the number of entries in systems_count
        ld a, c
        ld (systems_count), a
        ret

        ; Print the entry pointed by HL on the UART
        ; Parameters:
        ;   HL - Address of the entry to print
        ; Alters:
        ;   A, HL, BC, DE
print_entry:
        ld bc, SYS_NAME_MAX_LENGTH
        call stdout_write
        ; HL is now pointing to the physical address
        push hl
        ld hl, parenthesis
        ld bc, parenthesis_end - parenthesis
        call stdout_write
        ; Print the physical address
        pop hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ld a, (hl)
        inc hl
        call print_abc_hex
        ; Print a ' -> '
        push hl
        ld hl, arrow
        ld bc, arrow_end - arrow
        call stdout_write
        pop hl
        ; Finally dereference the virtual address and print it
        ld c, (hl)
        inc hl
        ld b, (hl)
        call print_bc_hex
        ; Close parenthesis
        ld a, ')'
        call stdout_put_char
        jp stdout_newline


        ; Print 24-bit value in ABC on the UART
        ; Parameters:
        ;   ABC - 24-bit value
        ; Returns:
        ;   None
        ; Alters:
        ;   A, BC, DE
print_abc_hex:
        push bc
        call print_a_hex
        pop bc
print_bc_hex:
        push bc
        ld a, b
        call print_a_hex
        pop bc
        ld a, c
        jp print_a_hex

        ; Print, in hex, the 8-bit value in register A
        ; Parameters:
        ;   A - Value to print on the standard output
        ; Returns:
        ;   None
        ; Alters:
        ;   A, BC, DE
        PUBLIC print_a_hex
print_a_hex:
        ld e, a
        rlca
        rlca
        rlca
        rlca
        and 0xf
        call _byte_to_ascii_nibble
        call stdout_put_char
        ld a, e
        and 0xf
        call _byte_to_ascii_nibble
        jp stdout_put_char
_byte_to_ascii_nibble:
        ; If the byte is between 0 and 9 included, add '0'
        sub 10
        jp nc, _byte_to_ascii_af
        ; Byte is between 0 and 9
        add '0' + 10
        ret
_byte_to_ascii_af:
        ; Byte is between A and F
        add 'A'
        ret

        ; Process the choice made by the user
        ; Parameters:
        ;       A - ASCII char sent by the user
        ; Returns:
        ;       -
        ; Alters:
        ;       -
process_menu_choice:
        ; Check if the choice is between 1 and systems_count (excluded)
        ld b, a
        sub '1'
        jp c, invalid_choice
        ld hl, systems_count
        cp (hl)
        jp c, menu_number_choice
        ; Check if it's a letter we know
        ld a, b
        cp 'p'
        jp z, menu_load_from_uart
        cp 'a'
        jp z, menu_add_new_entry
        cp 'd'
        jp z, menu_delete_entry
        cp 's'
        jp z, menu_save_new_entry
        cp 'b'
        jp z, menu_change_baudrate
    IF CONFIG_ENABLE_VIDEO_BOARD
        cp 'v'
        jp z, menu_flash_video_board
    ENDIF ; CONFIG_ENABLE_VIDEO_BOARD
        cp 'f'
        jp z, menu_flash_rom
    IF CONFIG_ENABLE_TESTER
        cp 't'
        jp z, test_hardware
    ENDIF ; CONFIG_ENABLE_TESTER
        cp 'q'
        jp z, format_eeprom
        ; Fall-through
invalid_choice:
        ld hl, invalid_str
        ld bc, invalid_str_end - invalid_str
        jp stdout_write


        ; Routine called when the given choice is a number between [0,systems_count[
        ; In fact, this routine will simply boot the system described by this index
        ; Parameters:
        ;       A - Index of the system entry to boot
        ; Returns:
        ;       Does not return
        EXTERN bootloader_print_boot_entry
menu_number_choice:
        ; Dereference index to get the actual entry address from our array
        ld hl, systems
        ; HL += A * 2
        rlca
        add l
        ld l, a
        adc h
        sub l
        ld h, a
        ; Store the entry in HL
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        jp bootloader_print_boot_entry

        ; Routine called when "Flash/program the ROM" is selected
menu_flash_rom:
        ; Ask for the address to flash. Should be aligned on 4KB
        PRINT_STR(new_entry_notice_str)
_menu_flash_rom_addr:
        PRINT_STR(flash_rom_addr_str)
        ld hl, buffer
        call menu_read_input
        ld hl, buffer
        ld a, (hl)
        ; If nothing is provided, set address to 0
        or a
        jp z, _menu_flash_rom_zero
        ; Parse the given address
        call parse_hex
        or a
        ; Make sure the value given is a number
        jr nz, _menu_flash_rom_addr
        ; The 24-bit address is in CDE.
        ; Check that it's aligned on 4KB (i.e. bits 0 to 11 are 0)
        or e
        jr nz, _menu_flash_rom_addr
        ; Lowest nibble of D should be 0
        or d
        and 0xf
        jr nz, _menu_flash_rom_addr
        ; Address is valid, save the upper 16 bits on the stack!
        ld e, d
        ld d, c
        push de
_menu_flash_ask_binary:
        ; Receive the binary file (size will be asked) in RAM, at 0x80000
        call receive_binary
        or a
        jr nz, _menu_flash_ask_binary
        ; Print a message saying flash is in progress
        push bc
        push de
        PRINT_STR(flashing_flash_str)
        pop de
        pop bc
        ; Pop the upper 16-bit of the destination
        pop hl
        ; If the destination is the bootloader (0), reboot after flashing
        ld a, h
        or l
        jr z, _flash_and_reboot
        ; Flash the received file to the ROM(NOR Flash)
        call sys_table_flash_file_to_rom
        or a
        ; Error if A is not zero
        jr nz, _flash_erase_error
        PRINT_STR(success_str)
        ret
_flash_erase_error:
        PRINT_STR(flash_erase_error_str)
        ret
_flash_and_reboot:
        ; Store rst 0 (0xc7) instruction in RAM
        ld a, 0xc7
        push hl
        ld hl, reset_instruction
        ld (hl), a
        ; Set reset_instruction as the return address
        ex (sp), hl
        jp sys_table_flash_file_to_rom

_menu_flash_rom_zero:
        ; Put the upper 16 bit address (0) on the stack
        ld d, a
        ld e, a
        push de
        jr _menu_flash_ask_binary


    IF CONFIG_ENABLE_VIDEO_BOARD

        ; Routine to flash the video board with a binary file.
        ; This routine:
        ;   - Asks for a binary size on the standard input
        ;   - Asks for the recovery mode to be switched on
        ;   - Flashes the binary
        ;   - Waits for a hard reboot/power off
        ; Routine called when "Flash the video board" is selected from the menu.
        ; Parameters:
        ;   Z flag - This function is called from the menu, all the messages will be outputed.
        ;   NZ flag - This function is called from recovery, some messages won't be shown.
        PUBLIC menu_flash_video_board
menu_flash_video_board:
        push af
        ; If called from recovery, do not show the "hexadecimal" warning notice
        jr nz, _menu_flash_video_board_binary
        PRINT_STR(new_entry_notice_str)
        ; Ask for the size of the binary
_menu_flash_video_board_binary:
        call receive_binary
        or a
        jr nz, _menu_flash_video_board_binary
        ; Get back the flags from the stack but wait before testing them
        pop af
        push bc
        push de
        ; If we are already in the recovery, do not ask to switch
        jr nz, _menu_flash_video_board_recovery
        PRINT_STR(video_board_switch)
        call video_wait_recovery
_menu_flash_video_board_recovery:
        PRINT_STR_UART(flashing_flash_str)
        pop de
        pop bc
        ; Flash the received file to the video board
        ; Parameters:
        ;       CDE - Size of the data to flash
        call video_board_flash
        or a
        ; Error if A is not 0
        jr z, _menu_flash_video_board_reboot
        PRINT_STR_UART(flash_erase_error_str)
_menu_flash_video_board_reboot:
        PRINT_STR_UART(video_board_power_off)
_menu_wait_reboot:
        jr _menu_wait_reboot

        PUBLIC video_board_switch
        PUBLIC video_board_switch_end
video_board_switch: DEFM "Press the recovery button on the video board to start flashing\r\n"
video_board_switch_end:
video_board_power_off: DEFM "Please power off the board\r\n"
video_board_power_off_end:

    ENDIF

        ; Helper routine to ask for a size between 1 and 496KB, print a message and receive a binary
        ; Parameters:
        ;   None
        ; Returns:
        ;   CDE - 24-bit parsed size
        ;   A - 0 on success, non-zero on failure
        ; Alters:
        ;   A, BC, HL, DE, `buffer`
receive_binary:
        PRINT_STR(binary_size_str)
        ld hl, buffer
        call menu_read_input
        ld hl, buffer
        call parse_hex
        or a
        ret nz
        ; Check that the size is not 0!
        ld a, c
        or d
        or e
        jr z, _receive_binary_error
        ; As we have 512KB of RAM, but 16KB are mapped currently for the bootloader,
        ; make sure the given size doesn't exceed 512 - 16 = 496KB <=> CD <= 0x07c0
        ; Even though the flash is 256KB big, the hardware supports flash up to 512KB,
        ; so keep the code like this for any NOR flash.
        ld h, c
        ld l, d
        push de
        ld de, 0x7c1
        xor a
        sbc hl, de
        pop de
        jr nc, _receive_binary_error
        ; Success, print a message and return 0
        ; Print a message to send a file
        push bc
        push de
        PRINT_STR(binary_send_str)
        pop de
        pop bc
        ; Receive a file in RAM, at physical address 0x80000.
        ; Parameters:
        ;       CDE - Size of the file to receive
        ; Returns:
        ;       A - 0 (always)
        jp uart_receive_big_file
_receive_binary_error:
        inc a
        ret


        ; Routine called when "Change baudrate" is selected. This is useful even if the
        ; standard output is the video, since we can receive files.
menu_change_baudrate:
        PRINT_STR(baudrate_choice)
        ; Wait for the user input
        call stdin_get_char
        ; Print it back
        push af
        call stdout_put_char
        call stdout_newline
        pop af
        ; Convert the baudrate choice to the actual values
        cp '1'
        ld d, UART_BAUDRATE_57600
        jp z, uart_set_baudrate
        cp '2'
        ld d, UART_BAUDRATE_38400
        jp z, uart_set_baudrate
        cp '3'
        ld d, UART_BAUDRATE_19200
        jp z, uart_set_baudrate
        cp '4'
        ld d, UART_BAUDRATE_9600
        jp z, uart_set_baudrate
        ; Invalid choice, ask again
        jp menu_change_baudrate
baudrate_choice:
        DEFM "1 - 57600\r\n"
        DEFM "2 - 38400\r\n"
        DEFM "3 - 19200\r\n"
        DEFM "4 - 9600\r\n"
        DEFM "\r\nChoose a baudrate [1-4]:"
baudrate_choice_end:


        ; Routine called when "Load from UART" is selected
menu_load_from_uart:
        PRINT_STR(new_entry_notice_str)
menu_load_from_uart_virt:
        PRINT_STR(virt_dest_addr_str)
        ld hl, buffer
        call menu_read_input
        ; If the size is 0, use 0 as a default address
        ld de, 0
        ld hl, buffer
        ld a, (hl)
        or a
        jr z, menu_load_from_uart_default
        ; Else, parse the string and get the resulted address in CDE
        call parse_hex
        ; If an error occurred, ask again
        or a
        jr nz, menu_load_from_uart_virt
        ; Make sure C is 0, we need a 16-bit address
        or c
        jr nz, menu_load_from_uart_virt
        ; Make sure it's aligned on 16KB, it will simplify the rest
        or e
        jr nz, menu_load_must_be_aligned
        or d
        and 0x3f
        jr nz, menu_load_must_be_aligned
menu_load_from_uart_default:
        ; Destination address in DE, ask for the size now
        push de
menu_load_from_uart_size:
        ; Ask for the size to load now
        PRINT_STR(binary_size_str)
        ld hl, buffer
        call menu_read_input
        ld hl, buffer
        call parse_hex
        or a
        jr nz, menu_load_from_uart_size
        ; Check that the size is not 0!
        ld a, c
        or d
        or e
        jr z, menu_load_from_uart_size
        ; As we have 512KB of RAM, but 16KB are mapped currently for the bootloader,
        ; make sure the given size doesn't exceed 512 - 16 = 496KB <=> CD <= 0x07c0
        ld h, c
        ld l, d
        push de
        ld de, 0x7c1
        xor a
        sbc hl, de
        pop de
        jp nc, menu_load_from_uart_size
        ; Print a message to send a file
        push bc
        push de
        PRINT_STR(binary_send_str)
        pop de
        pop bc
        ; Now we have to wait for the file and save it to the RAM
        pop hl
        ; Parameters:
        ;       CDE - Size of the file to receive
        ; The file will be saved at the beginning of the RAM, physical address 0x80000
        call uart_receive_big_file
        ; Map at most three MMU pages where the data were saved
        push hl
        PRINT_STR(booting_ram_str)
        pop hl
        jp sys_boot_from_ram
menu_load_must_be_aligned:
        PRINT_STR(aligned_addr_str)
        jr menu_load_from_uart_virt


        ; Routine called when "Add an entry" is selected
menu_add_new_entry:
        ; Check if too many entries already
        ld a, (systems_count)
        cp SYS_TABLE_ENTRY_COUNT
        jp nz, menu_add_new_entry_start
        ; Error message and return
        PRINT_STR(system_table_full_str)
        ret
menu_add_new_entry_start:
        PRINT_STR(new_entry_notice_str)
_menu_add_new_entry_name:
        ; Wait for the entry name
        PRINT_STR(new_entry_name_str)
        ld hl, buffer_name
        call menu_read_input
        ; Check that the length is more than 0
        ld hl, buffer_name
        call strlen
        ; If the length is 0, ask for it again
        ld a, b
        or c
        jp z, _menu_add_new_entry_name
_menu_add_new_entry_phys_addr:
        ; Ask for the physical address now
        PRINT_STR(phys_addr_str)
        ld hl, buffer
        push hl
        call menu_read_input
        ; Parse the physical address
        pop hl
        call parse_hex
        ; Check if success
        or a
        jp nz, _menu_add_new_entry_phys_addr
        ; CDE contains the parsed address physical on success.
        ; Check that C upper 2 bits are 0 as we support 22 bits address only
        ld a, c
        and 0xc0
        jp nz, _menu_add_new_entry_phys_addr
        ; Check that it's aligned on 16KB, i.e. lowest 14 bits are 0
        or e
        jp nz, _menu_add_new_entry_phys_addr
        or d
        and 0x3f
        jp nz, _menu_add_new_entry_phys_addr
        ; Physical address is correct, as E is 0, only save CD on the stack
        ld e, d
        ld d, c
        push de
_menu_add_new_entry_virt_addr:
        ; Same for the virtual address now
        PRINT_STR(virt_dest_addr_str)
        ld hl, buffer
        push hl
        call menu_read_input
        pop hl
        call parse_hex
        ; Check if success
        or a
        jp nz, _menu_add_new_entry_virt_addr
        ; Check that it's a 16-bit value
        or c
        jp nz, _menu_add_new_entry_virt_addr
        ; Finally, add the entry to the systems array
        ; Parameters:
        ;       HL - Entry name
        ;       DE - 16-bit Virtual address
        ;       BC - Physical address's upper 16-bit
        pop bc
        ld hl, buffer_name
        jp sys_table_add_entry

        ; Routine called when "Delete an entry" is selected
        ; Parameters:
        ;       None
        ; Returns:
        ;       None
        ; Alters:
        ;       A, BC, DE, HL
menu_delete_entry:
        ; If we have a single entry, forbid removing it
        ld a, (systems_count)
        cp 1
        jp nz, menu_delete_entry_valid
        ; Print the error message and return
        PRINT_STR(delete_entry_too_less)
        ret
menu_delete_entry_valid:
        ; Use the buffer to store the "X]:" where X is the entry count
        ld hl, buffer
        add '0'
        ld (hl), a
        inc hl
        ld (hl), ']'
        inc hl
        ld (hl), ':'
        ; Ask for the entry to delete, save the count in E as it won'tbe altered
        PRINT_STR(delete_entry_str)
        ; Print the rest of the buffer
        ld hl, buffer
        ld bc, 3
        call stdout_write
        ; Wait for the answer
        call stdin_get_char
        push af
        call stdout_put_char
        call stdout_newline
        pop af
        ; Make sure the answer is between '1' and 'systems_count'
        sub '1'
        jp c, invalid_choice
        ld hl, systems_count
        ld e, (hl)
        cp e
        jp nc, invalid_choice
        ; Get the entry at the given index
        ld hl, systems
        ; HL += A * 2
        rlca
        add l
        ld l, a
        adc h
        sub l
        ld h, a
        ; Dereference the entry
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        jp sys_table_delete

        ; Save the current array to the flash memory.
        ; Routine called when the option "Save configuration to flash" is selected
menu_save_new_entry:
        call sys_table_save_flash
        or a
        jp nz, menu_save_new_entry_error
        PRINT_STR(flash_erase_success_str)
        ret
menu_save_new_entry_error:
        PRINT_STR(flash_erase_error_str)
        ret

        ; Receive bytes on the UART until we receive \r\n
        ; Parameters:
        ;       HL - Destination buffer
        ; Alters:
        ;       A, HL, BC
menu_read_input:
        ; C contains the current size received
        ld c, 0
_menu_read_input_loop:
        call stdin_get_char
        cp '\b'
        jp z, _menu_read_input_backspace
        cp 0x7f ; DEL key
        jp z, _menu_read_input_backspace
        cp '\r'
        jp z, _menu_read_input_cr
        cp '\n'
        jp z, _menu_read_input_cr
        ; Ignore non-printable characters
        cp ' '
        jp c, _menu_read_input_loop
        cp 0x7f
        jp nc, _menu_read_input_loop
        ; Check if we've reached the max size
        ld b, a
        ld a, c
        cp BUFFER_SIZE
        ; If that's the case, ignore the character
        jp z, _menu_read_input_loop
        ; Else, store in buffer and print back the character
        ld a, b
        ld (hl), a
        inc hl
        ld e, c
        call stdout_put_char
        ld c, e
        inc c
        jp _menu_read_input_loop
_menu_read_input_backspace:
        ; If size is 0, do nothing
        ld a, c
        or a
        jp z, _menu_read_input_loop
        ; Else, print back and remove one char from the buffer
        dec hl
        dec c
        ld e, c
        ld a, '\b'
        call stdout_put_char
        ld a, ' '
        call stdout_put_char
        ld a, '\b'
        call stdout_put_char
        ld c, e
        jp _menu_read_input_loop
_menu_read_input_cr:
        ; Terminate the buffer
        ld (hl), 0
        ; Print a newline
        jp stdout_newline


        ; Calculate the length of a NULL-terminated string
        ; Parameters:
        ;       HL - String to get the length of
        ; Returns:
        ;       BC - Length of the string
        ; Alters:
        ;       A, BC
strlen:
        push hl
        xor a
        ld b, a
        ld c, a
_strlen_loop:
        cp (hl)
        jr z, _strlen_end
        inc hl
        inc bc
        jr _strlen_loop
_strlen_end:
        pop hl
        ret


        ; Routine to parse a string containing a hex value
        ; Parameters:
        ;       HL - String to parse
        ; Returns:
        ;       A - 0 on success, non-zero else
        ;       CDE - 24-bit value parsed
        ; Alters:
        ;       A, BC, DE
parse_hex:
        push hl
        xor a
        ld c, a
        ld d, a
        ld e, a
        ; Make sure the length is not 0
        or (hl)
        jp z, _parse_hex_incorrect
_parse_hex_loop:
        call parse_hex_digit
        jr c, _parse_hex_incorrect
        ; Store the parse digit in B
        ld b, a
        ; Check that C upper 4 bits are 0, else, the given value was too big
        ld a, c
        and 0xf0
        jp nz, _parse_hex_incorrect
        ; Left shift CDE 4 times. To do so, use A instead of C and HL instead of DE
        ld a, c
        ex de, hl
        add hl, hl
        rla
        add hl, hl
        rla
        add hl, hl
        rla
        add hl, hl
        rla
        ; Restore CDE from AHL
        ld c, a
        ex de, hl
        ; Put the parsed char, B, in the lower bits of E
        ld a, e
        or b
        ld e, a
        ; Go to next character and check whether it is the end of the string or not
        inc hl
        ld a, (hl)
        or a
        jp z, _parse_hex_end
        jp _parse_hex_loop
_parse_hex_incorrect:
        ld a, 1
_parse_hex_end:
        pop hl
        ret

parse_hex_digit:
        cp '0'
        jp c, _parse_not_hex_digit
        cp '9' + 1
        jp c, _parse_hex_dec_digit
        cp 'A'
        jp c, _parse_not_hex_digit
        cp 'F' + 1
        jp c, _parse_upper_hex_digit
        cp 'a'
        jp c, _parse_not_hex_digit
        cp 'f' + 1
        jp nc, _parse_not_hex_digit
_parse_lower_hex_digit:
        ; A is a character between 'a' and 'f'
        sub 'a' - 10 ; CY will be reset
        ret
_parse_upper_hex_digit:
        ; A is a character between 'A' and 'F'
        sub 'A' - 10 ; CY will be reset
        ret
_parse_hex_dec_digit:
        ; A is a character between '0' and '9'
        sub '0' ; CY will be reset
        ret
_parse_not_hex_digit:
        scf
        ret


        ; Group together all the strings used in the routines above
    IF CONFIG_ACK_CONTINUE
ack_str:
        DEFM "\r\nPress any key to return..."
ack_str_end:
    ENDIF
success_str:
        GREEN_COLOR()
        DEFM "Success\r\n"
        END_COLOR()
success_str_end:

invalid_str:
        RED_COLOR()
        DEFM "Invalid choice, please try again"
        END_COLOR()
invalid_str_end:
flash_erase_success_str:
        DEFM "Configuration saved successfully"
flash_erase_success_str_end:
flash_erase_error_str:
        RED_COLOR()
        DEFM "Error while flashing binary"
        END_COLOR()
flash_erase_error_str_end:
system_table_full_str:
        DEFM "Systems table is full, consider deleting an entry first"
system_table_full_str_end:
delete_entry_str:
        DEFM "Choose the entry to delete [1-"
delete_entry_str_end:
delete_entry_too_less:
        RED_COLOR()
        DEFM "Only one entry remaining, cannot delete it"
        END_COLOR()
        DEFM "\r\n"
delete_entry_too_less_end:
new_entry_notice_str:
        YELLOW_COLOR()
        DEFM "Numbers must be provided in hexadecimal"
        END_COLOR()
        DEFM "\r\n"
new_entry_notice_str_end:
new_entry_name_str:
        DEFM "New entry name (max 32 chars): "
new_entry_name_str_end:
flash_rom_addr_str:
        DEFM "ROM address to flash, aligned on 4KB: "
flash_rom_addr_str_end:
flashing_flash_str:
        YELLOW_COLOR()
        DEFM "Flashing in progress, do not turn off..."
        END_COLOR()
        DEFM "\r\n"
flashing_flash_str_end:
phys_addr_str:
        DEFM "22-bit physical address, aligned on 16KB: "
phys_addr_str_end:
virt_dest_addr_str:
        DEFM "16-bit virtual address: "
virt_dest_addr_str_end:
aligned_addr_str:
        YELLOW_COLOR()
        DEFM  "Address must be aligned on 16KB"
        END_COLOR()
        DEFM "\r\n"
aligned_addr_str_end:
binary_size_str:
        DEFM "Binary size: "
binary_size_str_end:
binary_send_str:
        DEFM "Please, send file...\r\n"
binary_send_str_end:
booting_ram_str:
        DEFM "Booting from RAM\r\n"
booting_ram_str_end:
menu_msg:
        DEFM "\r\n\r\nPlease select an option:\r\n\r\n"
menu_msg_end:
advanced_msg:
        DEFM "p - Load program from UART\r\n"
        DEFM "a - Add a new entry\r\n"
        DEFM "d - Delete an existing entry\r\n"
        DEFM "s - Save configuration to flash\r\n"
        DEFM "b - Change UART baudrate\r\n"
        DEFM "f - Flash/Program the ROM\r\n"
    IF CONFIG_ENABLE_VIDEO_BOARD
        DEFM "v - Flash the video board\r\n"
    ENDIF
        DEFM "q - Quick format I2C EEPROM (ZealFS)\r\n"
    IF CONFIG_ENABLE_TESTER
        DEFM "t - Test hardware\r\n"
    ENDIF
        DEFM "\r\nEnter your choice: "
advanced_msg_end:
separator:
        DEFM " - Boot "
separator_end:
parenthesis:
        DEFM " (0x"
parenthesis_end:
arrow:
        DEFM " -> 0x"
arrow_end:

        SECTION BSS
        ; Array used to store the active systems in SYS TABLE
        ; We will show them with an index, so this array makes the translation
        ; between the shown index on screen and the entry address.
systems_count: DEFS 1
systems: DEFS SYS_TABLE_ENTRY_COUNT * 2
buffer: DEFS BUFFER_SIZE + 1    ; +1 for NULL byte
buffer_name: DEFS BUFFER_SIZE + 1    ; +1 for NULL byte
reset_instruction: DEFS 1
