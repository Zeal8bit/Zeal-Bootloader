; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0
    INCLUDE "mmu_h.asm"
    INCLUDE "sys_table_h.asm"

    EXTERN __SYS_TABLE_head

    DEFC CPU_FREQ = 10000000
    DEFC RAM_CODE_DEST = 0xD000
    
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
sys_boot_from_ram:
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
    ; - Wait for the data to be written. It hsouldn't take more than 20us, but
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


sleep_ms:
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
        jp nz, sleep_ms
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


    SECTION SYS_TABLE
    ; First and default entry in the table
    DEFS SYS_NAME_MAX_LENGTH, "Zeal 8-bit OS v0.1"
    DEFP 0x4000
    DEFW 0x0000
    DEFB 0
    ; Mark the rest as empty
    DEFS SYS_TABLE_SIZE - SYS_TABLE_ENTRY_SIZE, 0
