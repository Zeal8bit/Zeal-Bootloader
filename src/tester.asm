; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "mmu_h.asm"
    INCLUDE "video_h.asm"
    INCLUDE "sys_table_h.asm"
    INCLUDE "uart_h.asm"

    EXTERN newline
    EXTERN uart_send_one_byte
    EXTERN print_a_hex

    SECTION BOOTLOADER

    ; Test whether everything is working fine on the board, this includes:
    ;   - MMU
    ;   - RAM (which should be 512KB big)
    ;   - NOR Flash (256KB by default)
    ;   - I2C RTC
    ;   - I2C EEPROM
    ;   - PS/2 Keyboard decoder
    ; PIO should be tested too, but if the I2C and UART work, we can make the assumption it is
    ; working properly too.
    PUBLIC test_hardware
test_hardware:
    di
    ; Start by testing the MMU, print a message
    PRINT_STR(test_message)
    ; Backup the current mapping
    MMU_GET_PAGE_NUMBER(MMU_PAGE_1)
    ld h, a
    MMU_GET_PAGE_NUMBER(MMU_PAGE_2)
    ld l, a
    push hl
    ; Run all the tests!
    ;call test_mmu
    ;call test_nor_flash
    ;call test_ram
    call test_rtc
    ;call test_eeprom
    ;call test_keyboard
    pop hl
    ld a, h
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ld a, l
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ; Print an end message
    PRINT_STR(test_terminated)
    ei
    ret

    ; Taken from:
    ;   https://wikiti.brandonw.net/index.php?title=Z80_Routines:Math:Division
div_hl_c:
    xor a
    ld b, 16
_div_loop:
    add hl, hl
    rla
    jr c, $+5
    cp c
    jr c, $+4
    sub c
    inc l
    djnz _div_loop
    ret


    ; Parameters:
    ;   HL - Byte array to print
    ;   B - Size of the array
print_array:
    ld a, b
    or a
    ret z
_print_array_loop:
    ld a, (hl)
    inc hl
    push hl
    push bc
    call print_a_hex
    ld a, ' '
    call uart_send_one_byte
    pop bc
    pop hl
    djnz _print_array_loop
    call newline
    ret


test_success:
    DEFM 0x1b, "[1;32mSuccess", 0x1b, "[0m\r\n"
test_success_end:

test_message:
    DEFM "Testing the hardware:\r\n"
test_message_end:
test_terminated:
    DEFM "\r\nTests finished\r\n"
test_terminated_end:
read_error_msg:
    DEFM 0x1b, "[1;31mRead error", 0x1b, "[0m\r\n"
read_error_msg_end:
write_error_msg:
    DEFM 0x1b, "[1;31mWrite error", 0x1b, "[0m\r\n"
write_error_msg_end:


    ; =============================================================== ;
    ; ==================== M M U   T E S T S ======================== ;
    ; =============================================================== ;
test_mmu:
    ; Print MMU message
    PRINT_STR(mmu_start_msg)
    ; Check that reading from the MMU works correctly.
    ; Reading page 0 value should return 0, reading from page 3 should return
    ; 0xfc000 >> 14 = 0x3f
    MMU_GET_PAGE_NUMBER(MMU_PAGE_0)
    or a
    jp nz, mmu_read_error
    MMU_GET_PAGE_NUMBER(MMU_PAGE_3)
    cp 0x3f
    jp nz, mmu_read_error
    ; Map page 1, 2, and 3 to this current code (phys address 0)
    ; Check that the content is identical.
    MAP_PHYS_ADDR(MMU_PAGE_1, 0)
    MAP_PHYS_ADDR(MMU_PAGE_2, 0)
    ; Compare the page 0 and page 1 of memory
    ld hl, PAGE0_VIRT_ADDR
    ld de, PAGE1_VIRT_ADDR
    ld bc, 0x4000
    call mem_compare
    or a
    jp nz, mmu_write_error
    ; Same for page 1 and page 2
    ld hl, PAGE1_VIRT_ADDR
    ld de, PAGE2_VIRT_ADDR
    ld bc, 0x4000
    call mem_compare
    or a
    jp nz, mmu_write_error
    ; Page 3 is a bit more special as it contains the stack, we cannot call after
    ; mapping, so let's call before mapping
    call mmu_test_page_3
    or a
    jp nz, mmu_write_error
    ; Success here!
    PRINT_STR(test_success)
    ret
mmu_read_error:
    PRINT_STR(read_error_msg)
    ret
mmu_write_error:
    PRINT_STR(write_error_msg)
    ret

mmu_start_msg:
    DEFM "MMU......................"
mmu_start_msg_end:

    ; HL - Source pointer
    ; DE - Destination pointer
    ; BC - Size of comparison
    ; A - 0 if identical, non-zero else
mem_compare:
    ld a, (de)
    sub (hl)
    ret nz
    inc de
    inc hl
    dec bc
    ld a, b
    or c
    ret z
    jp mem_compare

mmu_test_page_3:
    MAP_PHYS_ADDR(MMU_PAGE_3, 0)
    ld hl, PAGE2_VIRT_ADDR
    ld de, PAGE3_VIRT_ADDR
    ld bc, 0x4000
mmu_test_page_loop:
    ld a, (de)
    sub (hl)
    jp nz, mmu_test_page_error
    inc de
    inc hl
    dec bc
    ld a, b
    or c
    jp z, mmu_test_page_success
    jp mmu_test_page_loop
mmu_test_page_error:
    ; Remap the RAM
    MAP_PHYS_ADDR(MMU_PAGE_3, 0xfc000)
    ld a, 1
    ret
mmu_test_page_success:
    MAP_PHYS_ADDR(MMU_PAGE_3, 0xfc000)
    xor a
    ret


    ; =============================================================== ;
    ; ==================== N O R   F L A S H ======================== ;
    ; =============================================================== ;

test_nor_flash:
    PRINT_STR(nor_flash_start_msg)
    ; Try to detect the size of the flash. The flash is mapped from 0 to 512KB
    ; (excluded) on the physical memory mapping.
    ; If at any time, the first 8 bytes of any page is the same as the the current
    ; page (0), then, the flash is cycling, meaning we have reached the size limit.
    xor a
test_nor_flash_detect_size:
    inc a
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ; Compare the first 8 bytes
    push af
    ld hl, PAGE0_VIRT_ADDR
    ld de, PAGE1_VIRT_ADDR
    ld bc, 8
    call mem_compare
    or a
    jp z, test_nor_flash_size_end
    pop af
    ; Check if we have reached the maximum
    cp 31
    jp nz, test_nor_flash_detect_size
    PRINT_STR(nor_flash_512KB_msg)
    jp test_nor_flash_write
test_nor_flash_size_end:
    pop af
    ; We arrive here when the page we just mapped is the same as the first one
    ; A contains the number of 16KB pages the flash contains.
    ; Multiply by 16
    ld h, 0
    ld l, a
    add hl, hl  ; x2
    add hl, hl  ; x4
    add hl, hl  ; x8
    add hl, hl  ; x16
    ; Divide by 100
    ld c, 100
    call div_hl_c
    ; Quotient in L (we know H is 0), A contains the remainder
    ld e, l
    ld d, a
    ; Divide remainder by 10 now
    ld h, 0
    ld l, a
    ld c, 10
    call div_hl_c
    ; Quotient in L, remainder in A. Final BCD representation in ELA
    ld d, e
    ld e, l
    ld c, a
    ld hl, buffer
    ; Convert DEC to ASCII
    ld b, '0'
    ld a, d
    or a
    jr z, _skip_zero
    add b
    ld (hl), a
_skip_zero:
    inc hl
    ld a, e
    add b
    ld (hl), a
    inc hl
    ld a, c
    add b
    ld (hl), a
    ld hl, buffer
    ld bc, 3
    call uart_send_bytes
    PRINT_STR(nor_flash_detected)
test_nor_flash_write:
    ; We will write a sector of the flash, to make sure we can write
    ; Map RAM first page in page 1
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x80000)
    ; Backup the sector starting at address 0x4000
    ld de, PAGE1_VIRT_ADDR
    ld hl, 0x4000
    ld bc, 0x1000
    ldir
    ; Modify the data to increment each byte
    ld hl, PAGE1_VIRT_ADDR
    ld bc, 0x1000
test_nor_flash_write_loop:
    inc (hl)
    inc hl
    dec bc
    ld a, b
    or c
    jp nz, test_nor_flash_write_loop
    ; Flash this section
    ld c, 0
    ld de, 0x1000
    ld hl, 0x40
    ; Parameters:
    ;   CDE - Size of the section to flash
    ;   HL - Upper 16-bit of the flash to flash
    call sys_table_flash_file_to_rom
    ; Check that everything has been written correctly
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x80000)
    ld hl, 0x4000
    ld de, PAGE1_VIRT_ADDR
    ld bc, 0x1000
    call mem_compare
    ; If A is 0, both sectors are equal
    or a
    jp nz, test_nor_flash_write_error
    ; No error, writing succeeded, restore the old sector
    ld hl, PAGE1_VIRT_ADDR
    ld bc, 0x1000
test_nor_flash_write_loop_dec:
    dec (hl)
    inc hl
    dec bc
    ld a, b
    or c
    jp nz, test_nor_flash_write_loop_dec
    ; Re-flash the sector
    ld c, 0
    ld de, 0x1000
    ld hl, 0x40
    call sys_table_flash_file_to_rom
    PRINT_STR(test_success)
    ret
test_nor_flash_write_error:
    PRINT_STR(write_error_msg)
    ret


nor_flash_start_msg:
    DEFM "NOR FLASH................"
nor_flash_start_msg_end:

nor_flash_512KB_msg:
    DEFM "512"
nor_flash_detected:
    DEFM "KB detected / "
nor_flash_512KB_msg_end:
nor_flash_detected_end:


    ; =============================================================== ;
    ; ==================== R A M   T E S T S ======================== ;
    ; =============================================================== ;

test_ram:
    PRINT_STR(ram_start_msg)
    ; Try to detect the size of the RAM. The flash is mapped from 512KB to 1MB
    ; (excluded) on the physical memory mapping.
    ; If at any time, the first 8 bytes of any page is the same as the the RAM
    ; page (3), then, the RAM is cycling, meaning we have reached the size limit.
    ld a, 0x1f ; RAM starts at page 32
    ld b, 0 ; Number of "fake" RAM pages, i.e., pages not writable
test_ram_size:
    inc a
    MMU_SET_PAGE_NUMBER(MMU_PAGE_1)
    ; Check if we can actually write to this page
    push af
    ld hl, PAGE1_VIRT_ADDR
    ld a, (hl)
    inc (hl)
    inc (hl)
    inc (hl)
    ; Read back the result and restore data
    cp (hl)
    ld (hl), a ; doesn't alter flags
    jp nz, test_ram_size_not_fake_page
    ; Fake page, increment B
    inc b
test_ram_size_not_fake_page:
    push bc
    ; Compare the first 8 bytes
    ld hl, PAGE1_VIRT_ADDR
    ld de, PAGE3_VIRT_ADDR
    ld bc, 8
    call mem_compare
    pop bc
    or a
    jp z, test_ram_size_end
    pop af
    ; Check if we have reached the maximum
    cp 62
    jp nz, test_ram_size
    PRINT_STR(ram_512KB_msg)
    ret
test_ram_size_end:
    pop af
    ; Subtract the start page index for RAM
    sub 31
    ; Subtract the fake pages
    sub b
    ; Multiply A by 16
    ld h, 0
    ld l, a
    add hl, hl  ; x2
    add hl, hl  ; x4
    add hl, hl  ; x8
    add hl, hl  ; x16
    ; Divide by 100
    ld c, 100
    call div_hl_c
    ; Quotient in L (we know H is 0), A contains the remainder
    ld e, l
    ld d, a
    ; Divide remainder by 10 now
    ld h, 0
    ld l, a
    ld c, 10
    call div_hl_c
    ; Quotient in L, remainder in A. Final BCD representation in ELA
    ld d, e
    ld e, l
    ld c, a
    ld hl, buffer
    ; Convert DEC to ASCII
    ld b, '0'
    ld a, d
    or a
    jr z, _ram_skip_zero
    add b
    ld (hl), a
_ram_skip_zero:
    inc hl
    ld a, e
    add b
    ld (hl), a
    inc hl
    ld a, c
    add b
    ld (hl), a
    ld hl, buffer
    ld bc, 3
    call uart_send_bytes
    PRINT_STR(ram_detected)
    ret


ram_start_msg:
    DEFM "RAM......................"
ram_start_msg_end:

ram_512KB_msg:
    DEFM "512"
ram_detected:
    DEFM "KB detected\r\n"
ram_detected_end:
ram_512KB_msg_end:

    ; =============================================================== ;
    ; ==================== R T C   T E S T S ======================== ;
    ; =============================================================== ;
    EXTERN i2c_write_read_device
    EXTERN i2c_write_device
    EXTERN i2c_read_device

    DEFC I2C_RTC_ADDRESS = 0x68

test_rtc:
    PRINT_STR(rtc_start_msg)
    ; Read all the registers from the RTC (8 registers), write register
    ; number first in the buffer.
    ld hl, buffer
    ld (hl), 0
    ; Parameters:
    ;   A - 7-bit device address
    ;   HL - Write buffer (bytes to write)
    ;   DE - Read buffer (bytes read from the bus)
    ;   B - Size of the write buffer
    ;   C - Size of the read buffer
    ; Returns:
    ;   A - 0: Success
    ;       1: No device responded
    ld d, h
    ld e, l
    inc de
    ld b, 1
    ld c, 8
    ld a, I2C_RTC_ADDRESS
    call i2c_write_read_device
    or a
    jp nz, test_rtc_read_error
    ; Check if the highest bit of the first register is 1. If that's the case,
    ; the clock is halted.
    ld a, (de)
    rlca
    jp c, test_rtc_disabled
    ; Now, print the value of each register
    push de
    PRINT_STR(test_success)
    PRINT_STR(date_msg)
    ; Put the byte array in HL
    pop hl
    ld b, 8
    jp print_array
test_rtc_disabled:
    PRINT_STR(rtc_warning_msg)
    ; Turn the RTC on
    ld hl, rtc_config
    ; Parameters:
    ;   A - 7-bit device address
    ;   HL - Buffer to write on the bus
    ;   B - Size of the buffer
    ; Returns:
    ;   A - 0: Success
    ;       1: No device responded
    ld b, 9
    ld a, I2C_RTC_ADDRESS
    jp i2c_write_device
test_rtc_read_error:
    PRINT_STR(read_error_msg)
    ret

rtc_config:
    DEFM 0, 0, 0, 0, 0, 0, 0, 0, 0

rtc_start_msg:
    DEFM "I2C RTC.................."
rtc_start_msg_end:
date_msg:
    DEFM "Date & Time.............."
date_msg_end:

rtc_warning_msg:
    DEFM 0x1b, "[1;33mDisabled (no battery?)", 0x1b, "[0m\r\n"
rtc_warning_msg_end:


    ; =============================================================== ;
    ; ================ E E P R O M   T E S T S ====================== ;
    ; =============================================================== ;

    DEFC I2C_EEPROM_ADDRESS = 0x50

    EXTERN i2c_write_device
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

test_eeprom:
    PRINT_STR(eeprom_start_msg)
    ; Write random bytes into the first page. Read all the remaining pages to check where it rolls
    ld hl, eeprom_write_buffer
    ; Parameters:
    ;   A - 7-bit device address
    ;   HL - Buffer to write on the bus
    ;   B - Size of the buffer
    ; Returns:
    ;   A - 0: Success
    ;       1: No device responded
    ld b, 6
    ld a, I2C_EEPROM_ADDRESS
    call i2c_write_device
    or a
    jp nz, test_eeprom_error
    ; Writing takes around 5ms, let's wait 6ms to be sure it'll work
    ld de, 6
    call sleep_ms
    ; Success, try reading bytes at 16KB, then 32KB and finally 64KB
    REPTI addr, 0x40, 0x80
    ld a, addr
    call test_eeprom_read_from
    or a
    jp nz, test_eeprom_error
    ; If the data is the same as the one we wrote, we have a 16KB EEPROM.
    ; HL - Source pointer
    ; DE - Destination pointer
    ; BC - Size of comparison
    ; A - 0 if identical, non-zero else
    ld hl, eeprom_write_buffer + 2
    ld de, buffer + 2
    ld bc, 4
    call mem_compare
    or a
    jp z, test_eeprom_ ## addr
    ENDR
    ; 64KB detected
    PRINT_STR(eeprom_64kb_detected)
    ret
test_eeprom_64:
    PRINT_STR(eeprom_16kb_detected)
    ret
test_eeprom_128:
    PRINT_STR(eeprom_32kb_detected)
    ret

test_eeprom_read_from:
    ld hl, buffer
    ld (hl), a
    inc hl
    ld (hl), 0
    ld d, h
    ld e, l
    inc de
    dec hl
    ; Parameters:
    ;   HL - Write buffer (bytes to write)
    ;   DE - Read buffer (bytes read from the bus)
    ;   B - Size of the write buffer
    ;   C - Size of the read buffer
    ld a, I2C_EEPROM_ADDRESS
    ld b, 2
    ld c, 4
    jp i2c_write_read_device

test_eeprom_error:
    PRINT_STR(write_error_msg)
    ret


eeprom_write_buffer:
    DEFM 0x0, 0x0, 0x42, 0x98, 0xa6, 0xcf
eeprom_write_buffer_end:

eeprom_start_msg:
    DEFM "I2C EEPROM..............."
eeprom_start_msg_end:

eeprom_16kb_detected:
    DEFM "16KB detected\r\n"
eeprom_16kb_detected_end:
eeprom_32kb_detected:
    DEFM "32KB detected\r\n"
eeprom_32kb_detected_end:
eeprom_64kb_detected:
    DEFM "64KB detected\r\n"
eeprom_64kb_detected_end:


    ; =============================================================== ;
    ; ================ P S / 2   K E Y B O A R D ==================== ;
    ; =============================================================== ;

test_keyboard:
    PRINT_STR(keyboard_start_msg)
    ret


keyboard_start_msg:
    DEFM "PS/2 Keyboard............Type: QWERTY"
keyboard_start_msg_end:

    SECTION BSS
buffer: DEFS 16