; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "mmu_h.asm"
    INCLUDE "video_h.asm"
    INCLUDE "pio_h.asm"
    INCLUDE "sys_table_h.asm"
    INCLUDE "uart_h.asm"

    EXTERN newline
    EXTERN uart_send_one_byte
    EXTERN i2c_write_device

    DEFC I2C_EEPROM_ADDRESS = 0x50

    SECTION BOOTLOADER

    PUBLIC format_eeprom
format_eeprom:
    PRINT_STR(size_choice)
    ; Wait for the user input
    call uart_receive_one_byte
    ; Print it back
    push af
    call uart_send_one_byte
    call newline
    pop af
    ; Convert the baudrate choice to the actual values
    cp '0'
    ld b, 64
    jr z, format_size_b
    cp '1'
    ld b, 32
    jr z, format_size_b
    cp '2'
    ld b, 16
    jr z, format_size_b
    ; Invalid choice, ask again
    jp format_eeprom

format_size_b:
    call clear_buffer
    ; Write the header in the buffer
    ld hl, page
    ; Magic byte
    ld (hl), 'Z'
    inc hl
    ; File system version
    ld (hl), 1
    inc hl
    ; Bitmap size, in 256-byte page unit. Divide B by 2 and store it.
    ; (= B * 1024 / 256 / 8 = B / 2)
    ld a, b
    rrca
    ld (hl), a
    inc hl
    ; Free pages count, bitmap size (A) * 8 - 1 (first page allocated)
    rlca
    rlca
    rlca
    dec a
    ld (hl), a
    inc hl
    ; Only modify the first byte of the bitmap, set it to 1.
    ld (hl), 1
    ; The rest can be skipped as the buffer has already been set to 0
    ; Write this page to the EEPROM
    ;   A - 7-bit device address
    ;   HL - Buffer to write on the bus
    ;   B - Size of the buffer
    ld a, I2C_EEPROM_ADDRESS
    ld hl, reg_addr
    ld b, page_end - reg_addr
    call i2c_write_device
    ; Check the return value
    or a
    jr nz, format_error
    ; We just wrote the first 64 bytes. We still have to write 256 - 64 bytes = 192 bytes
    ; These remaining bytes must be filled with 0s
    call clear_buffer
    ; 3 * 64 = 192
    ld b, page_end - reg_addr
    ld c, 3
    ld de, 6
_format_empty_page:
    ; Wait 6 milliseconds
    push bc
    push de
    call sleep_ms
    pop de
    pop bc
    ; Set the new physical address to write to
    ld hl, reg_addr + 1 ; High byte always 0
    ; C * 64 = C << 6 = C rotate right twice
    ld a, c
    rrca
    rrca
    ld (hl), a
    ; Reposition HL to the 16-bit address
    dec hl
    ld a, I2C_EEPROM_ADDRESS
    ; BC and DE are not altered by the routine
    call i2c_write_device
    or a
    jr nz, format_error
    dec c
    jr nz, _format_empty_page
    ; Now, we need to also clear the next
    ; Success
    PRINT_STR(success_msg)
    ret
format_error:
    PRINT_STR(write_error_msg)
    ret


clear_buffer:
    ; Clear the RAM buffer that will contain the ZealFS header
    push bc
    xor a
    ld hl, reg_addr
    ld (hl), 0
    ld d, h
    ld e, l
    inc de
    ld bc, page_end - reg_addr - 1
    ldir
    pop bc
    ret


    PUBLIC sleep_ms
sleep_ms:
_sleep_ms_again:
    ; 24 is the number of T-states below
    ld bc, 10000 / 24
_sleep_ms_waste_time:
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


success_msg:
    DEFM 0x1b, "[1;32mSuccess", 0x1b, "[0m\r\n"
success_msg_end:

write_error_msg:
    DEFM 0x1b, "[1;31mI2C write error", 0x1b, "[0m\r\n"
write_error_msg_end:

size_choice:
    DEFM "0 - 64KB\r\n"
    DEFM "1 - 32KB\r\n"
    DEFM "2 - 16KB\r\n"
    DEFM "Choose EEPROM size [0-2]: "
size_choice_end:

    SECTION BSS
reg_addr: DEFS 2
page: DEFS 64
page_end: