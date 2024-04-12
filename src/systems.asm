; SPDX-FileCopyrightText: 2022-2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "config.asm"
    INCLUDE "mmu_h.asm"
    INCLUDE "sys_table_h.asm"

    EXTERN __SYS_TABLE_head
    EXTERN video_unload_assets

    DEFC CPU_FREQ = 10000000
    DEFC RAM_CODE_DEST = 0xD600

    SECTION BOOTLOADER

    ; Initialize the system table. This will read the system table from Flash
    ; and make a copy in RAM. As such, the table can be changed at one's will
    ; until it decides to flush/apply the changes to Flash.
    ; Parameters:
    ;   None
    ; Returns:
    ;   None
    ; Alters:
    ;   A, HL, DE, BC
    PUBLIC sys_table_init
sys_table_init:
    ld de, sys_table_ram
    ld hl, __SYS_TABLE_head
    ld bc, SYS_TABLE_SIZE
    ldir
    ; Load sys_exec_ram with:
    ;   out (c), b  ; 0xED 0x41
    ;   jp (hl)     ; 0xE9
    ld hl, _sys_config_and_jp
    ld de, sys_exec_ram
    ld bc, 3
    ldir
    ; Copy flash functions to RAM
    ld hl, sys_table_save_flash_ROM
    ld de, RAM_CODE_DEST
    ld bc, sys_table_save_flash_ROM_END - sys_table_save_flash_ROM
    ldir
    ret

    ; Get the address of the first non-NULL entry in the table.
    ; Parameters:
    ;   None
    ; Returns:
    ;   HL - Entry address
    ; Alters:
    ;   A, HL, DE
    PUBLIC sys_table_get_first
sys_table_get_first:
    ; Loop through the table, looking for the first non-null name
    ld hl, sys_table_ram
    ld de, SYS_TABLE_ENTRY_SIZE
    xor a
    ; Make the assumption that we will always have at least one entry in the table
_sys_table_get_first_loop:
    or (hl)
    ret nz
    add hl, de
    jp _sys_table_get_first_loop


    ; Boot the system pointed by the given entry address
    ; Parameters:
    ;   HL - Address of the entry to boot
    ; Returns:
    ;   No return
    PUBLIC sys_table_boot_entry
sys_table_boot_entry:
  IF !CONFIG_UART_AS_STDOUT
    call video_unload_assets
  ENDIF
    ; Jump to the physical address directly
    ld de, SYS_NAME_MAX_LENGTH
    add hl, de
    ; We only need the bits from 14 to 21 (8-bit value), ignore the lowest byte
    inc hl
    ld b, (hl)
    inc hl
    ld a, (hl)
    inc hl
    ; Here AB is the highest 16-bit of our physical address
    rlc b
    rla
    rlc b
    rla
    ; A contains the MMU configuration for the physical address, keep it in B
    ld b, a
    ; Dereference the virtual address to calculate the virtual page to map it to
    ld e, (hl)
    inc hl
    ld d, (hl)
_sys_table_boot_de:
    ; Get the page out of the virtual address
    ld a, d
    rlca
    rlca
    and 3
    ex de, hl   ; Put the virtual address to jump to in HL
    ; Disable interrupts!
    di
    jp z, _sys_table_boot_entry_same_page
    ; "Convert" it to the real page configuration I/O address
    add MMU_PAGE_0
    ld c, a
_sys_config_and_jp:
    ; Configure virtual page in C with the physical page index in B
    out (c), b
    ; Finally, we can jump to the virtual address
    jp (hl)

_sys_table_boot_entry_same_page:
    ; If the destination is the first page of memory, we have to swap MMU pages
    ; from another location than the current one since this code is also in page 0
    add MMU_PAGE_0
    ld c, a
    ; Jump to the code in RAM, which is in a different page
    jp sys_exec_ram


    ; Delete an entry from the systems table
    ; Parameters:
    ;   HL - Address of the entry to remove
    ; Returns:
    ;   None
    ; Alters:
    ;   A, HL, BC, DE
    PUBLIC sys_table_delete
sys_table_delete:
    ; TODO: check if the given address is correct or not
    ; Erase the entry with LDIR
    ld (hl), 0
    ld d, h
    ld e, l
    inc de
    ld bc, SYS_TABLE_ENTRY_SIZE - 1
    ldir
    ret


    ; Add an entry to the systems table
    ; Parameters:
    ;       HL - Entry name
    ;       DE - 16-bit Virtual address
    ;       BC - Physical address's upper 16-bit
    ; Returns:
    ;       A - 0 on success, 1 on error
    PUBLIC sys_table_add_entry
sys_table_add_entry:
    push bc
    push de
    push hl
    call sys_table_get_first_empty_entry
    or a
    jr nz, sys_table_add_entry_error
    ; Copy the string first
    pop de  ; Pop the name out of the stack
    ex de, hl
    ld bc, SYS_NAME_MAX_LENGTH
    call strncpy
    ; Destination shall be DE + SYS_NAME_MAX_LENGTH now
    ex de, hl
    add hl, bc
    ; Pop the virtual address and the physical address
    pop de
    pop bc
    ; Copy the physical address then
    ld (hl), 0
    inc hl
    ld (hl), c
    inc hl
    ld (hl), b
    inc hl
    ; And finally the virtual address
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ; (Unused flags too)
    ld (hl), 0
    ; Success
    xor a
    ret
sys_table_add_entry_error:
    pop hl
    pop de
    pop bc
    ret

    ; Get the address of the first NULL entry in the table.
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - 0 on success, 1 on error
    ;   HL - Entry address
    ; Alters:
    ;   A, HL
sys_table_get_first_empty_entry:
    ; Loop through the table, looking for the first non-null name
    push de
    push bc
    ld hl, sys_table_ram
    ld de, SYS_TABLE_ENTRY_SIZE
    ld b, SYS_TABLE_ENTRY_COUNT
    xor a
_sys_table_get_first_empty_loop:
    ld a, (hl)
    or a
    jp z, _sys_table_get_first_empty_found
    add hl, de
    djnz _sys_table_get_first_empty_loop
    ; No more place in the array
    inc a
_sys_table_get_first_empty_found:
    pop bc
    pop de
    ret


    ; Map the RAM second page (where code was loaded beforehand) and boot it at the given
    ; virtual address.
    ; Parameters:
    ;   HL - Address to jump to (aligned on 16KB)
    ; Returns:
    ;   Doesn't not return
    ; Alters:
    ;   -
    PUBLIC sys_boot_from_ram
sys_boot_from_ram:
  IF !CONFIG_UART_AS_STDOUT
    call video_unload_assets
  ENDIF
    ; The user's program is in RAM page 0 (0x80000)
    ld b, 0x80000 >> 14
    ex de, hl
    ; Parameters:
    ;   DE - Virtual address to jump to
    ;   B  - Physical page index to map to the virtual page
    jp _sys_table_boot_de

    ; Save the current table to flash. This function will be in RAM!
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - 0 on success, non zero else
    ;   B - NOR Flash ID
    ; Alters:
    ;
sys_table_save_flash_ROM:
    PHASE RAM_CODE_DEST
    PUBLIC sys_table_save_flash
sys_table_save_flash:
    ; Map ROM to the first two page
    MAP_PHYS_ADDR(MMU_PAGE_0, 0x0000)
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x4000)
    ; Check if the ROM installed is an SST39SF0x0 NOR Flash
    call sys_table_get_id
    ; B will contain the NOR Flash ID
    ; Check that B is [0xB5, 0xB7]
    ld a, b
    and 0xF4
    cp 0xB4
    ret nz
    call sys_table_erase_flash
    ; Write the table stored in RAM to flash
    ld hl, sys_table_ram
    ld de, __SYS_TABLE_head
    ld bc, SYS_TABLE_SIZE
sys_table_save_loop:
    ld a, (hl)
    call sys_table_flash_byte
    inc hl
    inc de
    dec bc
    ld a, b
    or c
    jp nz, sys_table_save_loop
    xor a
    ret


    ; Flash the file store at 0x80000 into ROM-flash
    ; Parameters:
    ;   CDE - Size of the file, in bytes
    ;   HL - Upper 16-bit of the destination address in ROM
    ; Returns:
    ;   None
    ; Alters:
    ;   A, BC, DE, HL
    PUBLIC sys_table_flash_file_to_rom
sys_table_flash_file_to_rom:
    ; As erasing and writing to Flash requires writes to 0x2AAA and 0x5555,
    ; we need to map the first two MMU pages to ROM/Flash
    MAP_PHYS_ADDR(MMU_PAGE_0, 0x0000)
    MAP_PHYS_ADDR(MMU_PAGE_1, 0x4000)
    ; Check if the ROM installed is an SST39SF0x0 NOR Flash
    push hl
    push de
    call sys_table_get_id
    pop de
    pop hl
    ; B will contain the NOR Flash ID
    ; Check that B is [0xB5, 0xB7]
    ld a, b
    and 0xF4
    cp 0xB4
    ret nz
    ; Map the 16KB page containing the 4KB sector of destination in the third page.
    ; First calculate the page of it. HL contains the upper 16-bit of the 24-bit address
    ; We need to retrieve bit 14 to 22 in A
    ld a, l
    ; We know that L's lower nibble is 0
    rrc h
    rra
    rrc h
    rra
    rrc h
    rra
    rr h
    rrca
    ; Here, A lowest 2 bits will help us determine which part of the 16KB page,
    ; the current 4KB sector is in. Save that value in B.
    ld b, a
    ; Continue shifting
    rrc h
    rra
    rrc h
    rra
    ; A contains the index to map in the third MMU page
    out (MMU_PAGE_2), a
    ; A can be altered, use it to only save B's lowest 2 bits into the higher nibble
    ld a, b
    and 3
    rlca
    rlca
    rlca
    rlca
    ld b, a
    ; Now check if the size is smaller than a sector (4KB)
    ld a, c
    or a
    jp nz, _flash_rom_big
    ld hl, 4096
    sbc hl, de
    ld hl, 0    ; Reset HL in case we have a single sector to flash
    ; If no carry occurs, DE is smaller or equal to 4096
    jp nc, _flash_rom_single_sector
_flash_rom_big:
    ; Calculate the number of sector we will need to write
    ; In other word, divide CDE by 4KB, while keeping DE on the stack to calculate
    ; the remainder
    push de
    ; Shit CDE by 12
    ld a, d
    rrc c
    rra
    rrc c
    rra
    rrc c
    rra
    rrc c
    rra
    ld d, c
    ld e, a
    ; DE now contains the number of sectors to write, the sector is mapped in page 3.
    ; So the virtual addresses to flash are:
    ;   - 0x8000 when B = 0x00
    ;   - 0x9000 when B = 0x10
    ;   - 0xA000 when B = 0x20
    ;   - 0xB000 when B = 0x30
    ; HL is free and can be used here. Let's use it to determine how many 4KB blocks
    ; we flashed previously.
    ld hl, 0
_flash_rom_big_loop:
    ; Calculate the virtual address of the sector to erase
    push hl
    ld hl, 0x8000
    ; Add B to H to get the current sector virtual address
    ld a, h
    add b
    ld h, a
    ; Should not alter HL, BC nor DE
    call sys_table_erase_sector_no_wait
    ; Now we have 25ms to wait before erase finishes.
    ; We can take this time to copy the sector from "file" RAM to our current RAM.
    ; Parameters:
    ;   L - Index of the 4KB sector to copy
    ex (sp), hl
    ; Must not alter HL, this routine takes a bit more than 8ms
    call sys_table_buffer_file_sector_to_ram
    ; Thus, we still need to wait about 17ms
    push de
    ld de, 17
    call sleep_ms
    pop de
    ; We can proceed to flash write
    ;   HL - Virtual address to flash with the RAM-buffered sector
    ex (sp), hl
    call sys_table_write_sector
    ; Sector written, pop the index written from the stack and increment it
    pop hl
    inc hl
    ; "Increment" B to point to the next sector in page
    ld a, b
    add 0x10
    cp 0x40
    jr nz, _flash_rom_no_remap
    ; Map the next physical page
    ; Get the current index mapped in third page
    ld a, 0x80  ; 2 highest bit to 0b10
    in a, (MMU_PAGE_2)
    inc a
    out (MMU_PAGE_2), a
    ; Reset A as it will be assigned to B
    xor a
_flash_rom_no_remap:
    ld b, a
    ; Decrement the total amount of sectors to write
    dec de
    ld a, d
    or e
    jp nz, _flash_rom_big_loop
    ; No more 4KB sectors to write, check if we have to write a smaller sector
    pop de
    ; Calculate DE % 4KB <=> DE & (4KB - 1) <=> DE[11:0]
    ld a, d
    ; Keep D lowest 4 bits
    and 0xf
    ld d, a
    or e
    ret z
_flash_rom_single_sector:
    ; HL contains the index of the 4KB sector of the file to flash.
    ; So if HL = 1, the file offset to flash is 4KB.
    ; DE contains the size to flash (<= 4KB)
    ; B contains the index of sector in the page to flash:
    ; So the virtual addresses to flash are:
    ;   - 0x8000 when B = 0x00
    ;   - 0x9000 when B = 0x10
    ;   - 0xA000 when B = 0x20
    ;   - 0xB000 when B = 0x30
    ; The physical address is already mapped to the third virtual page
    ; Calculate the virtual address of the sector to erase
    push hl
    ld hl, 0x8000
    ; Add B to H to get the current sector virtual address
    ld a, h
    add b
    ld h, a
    ; Must not alter HL, BC nor DE
    call sys_table_erase_sector_no_wait
    ; Now we have 25ms to wait before erase finishes.
    push de
    ld de, 25
    call sleep_ms
    pop de
    ; We can take this time to copy the sector from "file" RAM to our current RAM.
    ; Parameters:
    ;   HL - Index of the 4KB sector to copy
    ex (sp), hl
    ; Copy the size in BC
    ld b, d
    ld c, e
    ; Must not alter BC
    call sys_table_buffer_file_size_to_ram
    ; We can proceed to flash write
    ;   HL - Virtual address to flash with the RAM-buffered sector
    ;   BC - Size to flash
    pop hl
    jp sys_table_write_size


    ; Erase the sector pointed by virtual address HL. This routine does NOT wait
    ; for the erase to be finished (25ms). It returns directly after initiating
    ; the erase.
    ; Parameters:
    ;   HL - Sector's virtual address. It must point to ROM/Flash
    ;   [0x0000, 0xC000] - Virtual address range must be mapped to ROM/Flash
    ; Returns:
    ;   None
    ; Alters:
    ;   A
sys_table_erase_sector_no_wait:
    push de
    push hl
    ld hl, 0x5555
    ld de, 0x2AAA
    ; Process to erase a sector:
    ;   - Write 0xAA @ 0x5555
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA
    ld a, l
    ld (de), a
    ;   - Write 0x80 @ 0x5555
    ld (hl), 0x80
    ;   - Write 0xAA @ 0x5555
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA
    ld (de), a
    ;   - Write 0x30 @ SectorAddress
    pop hl
    ld a, 0x30
    ld (hl), a
    pop de
    ret


    ; Copy 4KB from the file located at physical address 0x00000 to RAM currently being
    ; used and mapped in the last virtual page.
    ; Parameters:
    ;   HL - 4KB index of the file to copy (less than 256 in practice, so H is 0)
    ; Returns:
    ;   None
    ; Alters:
    ;   A
sys_table_buffer_file_sector_to_ram:
    ; The following takes 58 T-States (5.8us)
    push bc
    ld bc, 4096
    call sys_table_buffer_file_size_to_ram
    pop bc
    ret
    ; Same as above but BC is passed as a parameter
    ; Parameters:
    ;   HL - 4KB index of the file to copy (less than 256 in practice, so H is 0)
    ;   BC - Size to copy (Max 4KB)
sys_table_buffer_file_size_to_ram:
    ; This routine takes:
    ; 220 + 16 + 21 * BC T-states
    ; For a whole sector, it takes 86252 T-states = 8.652ms
    push de
    push hl
    push bc
    ; We will re-use the third virtual page. We first need to determine which
    ; 16KB page of the file to map there. Divide L by 4.
    ld a, l
    srl a
    srl a
    ; Add the offset where the file starts (beginning of the RAM, 0x80000, divide by page size, i.e. 16KB)
    add 0x80000 >> 14
    ; Before mapping page inside the third virtual page, backup the current page
    ; Write 0b10 in C's the upper bits
    ld c, MMU_PAGE_2
    ld b, 0x80
    in b, (c)
    ; Map the RAM page
    out (MMU_PAGE_2), a
    ; RAM is mapped, A can be re-used. Determine from which virtual address we should start
    ; copying:
    ;   - 0x8000 when L[1:0] = 0b00
    ;   - 0x9000 when L[1:0] = 0b01
    ;   - 0xA000 when L[1:0] = 0b10
    ;   - 0xB000 when L[1:0] = 0b11
    ld a, l
    and 3
    rlca
    rlca
    rlca
    rlca
    ; Third virtual page starts at 0x8000
    add 0x80
    ld h, a
    ld l, 0
    ; Source is set! Set the destination now.
    ld de, sys_sector_buffer
    ; Get the size for the stack but keep it on the stack too
    ld a, b
    pop bc
    push bc
    ldir
    ; Copy finished, remap the third virtual page, restore registers and return
    out (MMU_PAGE_2), a
    pop bc
    pop hl
    pop de
    ret


    ; Write the buffered file in RAM to ROM/Flash
    ; Parameters:
    ;   HL - Virtual address to flash with the RAM-buffered sector
    ; Returns:
    ;   None
    ; Alters:
    ;   A, HL
sys_table_write_sector:
    push bc
    ld bc, 4096
    call sys_table_write_size
    pop bc
    ret
    ; Same as above, but BC contains the size to write
    ; Parameters:
    ;   HL - Virtual address to flash with the RAM-buffered sector
    ;   BC - Size of the buffer to write
    ; Returns:
    ;   A - 0
    ; Alters:
    ;   A, HL
sys_table_write_size:
    push de
    ; HL here is in fact the destination, load the source
    ld de, sys_sector_buffer
    ex de, hl
_sys_table_flash_write:
    ld a, (hl)
    call sys_table_flash_byte
    inc hl
    inc de
    dec bc
    ld a, b
    or c
    jp nz, _sys_table_flash_write
    ; Sector has been flashed successfully, return
    pop de
    ret


    ; Get the NOR Flash ID
    ; Parameters:
    ;   None
    ; Returns:
    ;   B - NOR Flash ID as specified by the datasheet:
    ;       * 0xB5 for SST39SF010A
    ;       * 0xB6 for SST39SF020A
    ;       * 0xB7 for SST39SF040A
    ; Alters:
    ;   A, HL, DE
sys_table_get_id:
    ld hl, 0x5555
    ; Write 0xAA to 0x5555
    ld (hl), 0xAA
    ; Write 0x55 to 0x2AAA
    ld a, l
    ld (0x2AAA), a
    ; Write 0x90 to 0x5555
    ld (hl), 0x90
    ; We just entered Software ID mode, get the ID now by reading address 0x0001
    ld a, (1)
    ; Exit software ID by issuing a write 0xF0 command anywhere on the flash
    ld (hl), 0xf0
    ; Return the ID in B
    ld b, a
    ret

    ; Write a single byte to flash in an erased sector.
    ; NOTE: The sector containing the byte MUST be erased first.
    ; Parameters:
    ;   A - Byte to write to flash
    ;   DE - Address to write the byte to
    ; Returns:
    ;   None
    ; Alters:
    ;   A
sys_table_flash_byte:
    push hl
    ; To program a byte, the process is as follow:
    ; - Write 0xAA @ 0x5555
    ld hl, 0x5555
    ld (hl), 0xAA
    ; - Write 0x55 @ 0x2AAA
    ld hl, 0x2AAA
    ld (hl), 0x55
    ; - Write 0xA0 @ 0x5555
    ld hl, 0x5555
    ld (hl), 0xA0
    ; - Write the actual data at destination address
    ld (de), a
    ; - Wait for the data to be written. It shouldn't take more than 20us, but
    ; let's be save and wait until completion.
    ex de, hl
sys_table_flash_byte_wait:
    cp (hl)
    jp nz, sys_table_flash_byte_wait
    ; Byte flashed successfully, restore HL and DE before returning
    ex de, hl
    pop hl
    ret

    ; Erase the system table from the NOR Flash.
    ; This will erase (set bytes to 0xFF) the sector of 4KB, from
    ; SYS_TABLE address to SYS_TABLE + 4KB.
    ; Parameters:
    ;   None
    ; Returns:
    ;   None
    ; Alters:
    ;   A, HL, DE
sys_table_erase_flash:
    ; Flash memory is mapped to the first 32KB of memory, so no translation
    ; is required in the following algorithm.
    ; Erase the sector where SYS_TABLE is.
    ld hl, 0x5555
    ld de, 0x2AAA
    ; Process to erase a sector:
    ;   - Write 0xAA @ 0x5555
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA
    ld a, l
    ld (de), a
    ;   - Write 0x80 @ 0x5555
    ld (hl), 0x80
    ;   - Write 0xAA @ 0x5555
    ld (hl), e
    ;   - Write 0x55 @ 0x2AAA
    ld (de), a
    ;   - Write 0x30 @ SectorAddress
    ld a, 0x30
    ld (__SYS_TABLE_head), a
    ; Wait 25ms (= 250,000 T-States)
    ld de, 26
    jp sleep_ms


    ; Sleep for DE milliseconds
    ; Parameters:
    ;   DE - milliseconds
    ; Returns:
    ;   Nonde
    ; Alters:
    ;   A, DE
sleep_ms:
    push bc
_sleep_ms_loop:
    ld bc, CPU_FREQ / 1000 / 24
_sleep_ms_waste_time:
    ; 24 T-states for the following, until 'jp nz, _zos_waste_time'
    dec bc
    ld a, b
    or c
    jp nz, _sleep_ms_waste_time
    ; If we are here, a milliseconds has elapsed
    dec de
    ld a, d
    or e
    jp nz, _sleep_ms_loop
    pop bc
    ret
    DEPHASE
sys_table_save_flash_ROM_END:


    ; Same as strcpy but if src is smaller than the given size,
    ; the destination buffer will be filled with 0
    ; Parameters:
    ;       HL - src string
    ;       DE - dst string
    ;       BC - maximum bytes to write
    ; Alters:
    ;       A
    PUBLIC strncpy
strncpy:
    ; Make sure that BC is not 0, else, nothing to copy
    ld a, b
    or c
    ret z
    ; Size is not 0, we can proceed
    push hl
    push de
    push bc
_strncpy_loop:
    ; Read the src byte, to check null-byte
    ld a, (hl)
    ; We cannot use ldir here as we need to check the null-byte in src
    ldi
    or a
    jp z, _strncpy_zero
    ld a, b
    or c
    jp nz, _strncpy_loop
_strncpy_end:
    pop bc
    pop de
    pop hl
    ret
_strncpy_zero:
    ; Here too, we have to test whether BC is 0 or not
    ld a, b
    or c
    jp z, _strncpy_end
    ; 0 has just been copied to dst (DE), we can reuse this null byte to fill
    ; the end of the buffer using LDIR
    ld hl, de
    ; Make hl point to the null-byte we just copied
    dec hl
    ; Perform the copy
    ldir
    jp _strncpy_end



    SECTION BSS
    ; Mirror of systable in RAM
    PUBLIC sys_table_ram
sys_table_ram: DEFS SYS_TABLE_SIZE
    ; Executable code for booting a system
    ; Will be loaded on boot with:
    ;   out (c), b  ; 0xED 0x41
    ;   jp (hl)     ; 0xE9
sys_exec_ram: DEFS 3
sys_sector_buffer: DEFS 4096

    SECTION SYS_TABLE
    ; First and default entry in the table
    DEFS SYS_NAME_MAX_LENGTH, "Zeal 8-bit OS"
    DEFP 0x4000
    DEFW 0x0000
    DEFB 0
    ; Mark the rest as empty
    DEFS SYS_TABLE_SIZE - SYS_TABLE_ENTRY_SIZE, 0
