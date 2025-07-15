; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "mmu_h.asm"
    INCLUDE "pio_h.asm"
    INCLUDE "sys_table_h.asm"
    INCLUDE "stdout_h.asm"

    EXTERN newline
    EXTERN i2c_write_device

    DEFC I2C_EEPROM_ADDRESS = 0x50

    SECTION BOOTLOADER


get_char_and_print:
    ; Wait for the user input
    call stdin_get_char
    ; Print it back
    push af
    call stdout_put_char
    call stdout_newline
    pop af
    ret

    PUBLIC format_eeprom
format_eeprom:
    PRINT_STR(version_choice)
    ; Wait for the user input
    call get_char_and_print
    ; Convert the baudrate choice to the actual values
    cp '0'
    ld c, 1
    jr z, format_size
    cp '1'
    ld c, 2
    jr nz, format_eeprom
    ; ZealFSv2 choice, we have to prepare the header
format_size:
    push bc
    PRINT_STR(size_choice)
    call get_char_and_print
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
    ; Pop the filesystem version, keep the size
    ld a, b
    pop bc
    ld b, a
    ; Write the header in the buffer
    ld hl, page
    ; Magic byte
    ld (hl), 'Z'
    inc hl
    ; File system version
    ld (hl), c
    inc hl
    ; Bitmap size, in 256-byte page unit. Divide B by 2 and store it.
    ; (= B * 1024 / 256 / 8 = B / 2)
    ld a, b
    rrca
    ld (hl), a
    inc hl
    ; Check if v2, where bitmap size is 16-bit
    dec c
    jr z, v1_0
    ld (hl), 0
    inc hl
v1_0:
    inc c
    ; Free pages count, bitmap size (A) * 8 - 1 (first page allocated)
    add a   ; x2
    add a   ; x4
    add a   ; x8
    dec a
    ld (hl), a
    inc hl
    ; Again, check for ZealFSv2
    dec c
    jr z, v1_1
    ld (hl), 0
    inc hl
    ; Populate the page size (0 = 256-byte)
    ld (hl), 0
    inc hl
v1_1:
    inc c
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
    ; 7 * 64 = 512 - 64 = 448
    ld b, page_end - reg_addr
    ld c, 7
    ld de, 6
_format_empty_page:
    ; Wait 6 milliseconds
    push bc
    push de
    call sleep_ms
    pop de
    pop bc
    ; Set the new physical address to write to
    ; C * 64 = Shift C right twice. Put MSB in L instead of H since
    ; the address to send on the bus needs MSB first
    ld h, 0
    ld l, c
    srl l
    rr  h
    srl l
    rr  h
    ld (reg_addr), hl
    ld hl, reg_addr
    ; Perfom the write
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
    GREEN_COLOR()
    DEFM "Success"
    END_COLOR()
    DEFM "\r\n"
success_msg_end:

write_error_msg:
    RED_COLOR()
    DEFM "I2C write error"
    END_COLOR()
    DEFM "\r\n"
write_error_msg_end:

size_choice:
    DEFM "0 - 64KB\r\n"
    DEFM "1 - 32KB\r\n"
    DEFM "2 - 16KB\r\n"
    DEFM "Choose EEPROM size [0-2]: "
size_choice_end:

version_choice:
    DEFM "0 - ZealFS v1\r\n"
    DEFM "1 - ZealFS v2\r\n"
    DEFM "Choose file system [0-1]: "
version_choice_end:

    SECTION BSS
reg_addr: DEFS 2
page: DEFS 64
page_end: