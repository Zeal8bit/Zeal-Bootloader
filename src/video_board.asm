
; SPDX-FileCopyrightText: 2023 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0
    INCLUDE "mmu_h.asm"
    INCLUDE "uart_h.asm"
    INCLUDE "stdout_h.asm"

    SECTION BOOTLOADER

    DEFC CPU_FREQ = 10000000

    ; SPI Flash protocol related constants
    DEFC SPI_READ_STA_CMD   = 0x05
    DEFC SPI_WRITE_STA_CMD  = 0x01

    DEFC SPI_PAGE_PROG_CMD  = 0x02

    DEFC SPI_WRITE_ENA_CMD  = 0x06
    DEFC SPI_WRITE_DIS_CMD  = 0x04

    DEFC SPI_PWR_DOWN_CMD   = 0xb9
    DEFC SPI_ERASE_64KB_CMD = 0xd8

    ; Version register
    DEFC VID_VER_REV = 0x80
    DEFC VID_VER_MIN = 0x81
    DEFC VID_VER_MAJ = 0x82

    ; Features registers
    DEFC VID_MAP_DEVICE = 0x8e
        DEFC VID_SPI_DEVICE = 0x1
    ; LED control register
    DEFC LED_CTRL_REG = 0x8d
        DEFC LED_CTRL_OFF      = 0
        DEFC LED_CTRL_BLK_SYNC = 1
        DEFC LED_CTRL_BLK_ASYN = 2
        DEFC LED_CTRL_ON       = 3


    ; SPI controller-related contants
    DEFC SPI_REG_BASE = 0xa0
    DEFC REG_VERSION = (SPI_REG_BASE + 0)
    DEFC REG_CTRL    = (SPI_REG_BASE + 1)
        DEFC REG_CTRL_START    = 1 << 7   ; Start SPI transaction
        DEFC REG_CTRL_RESET    = 1 << 6   ; Reset the SPI controller
        DEFC REG_CTRL_CS_START = 1 << 5   ; Assert chip select (low)
        DEFC REG_CTRL_CS_END   = 1 << 4   ; De-assert chip select signal (high)
        DEFC REG_CTRL_CS_SEL   = 1 << 3   ; Select among two chip selects (0 and 1)
        DEFC REG_CTRL_RSV2     = 1 << 2
        DEFC REG_CTRL_RSV1     = 1 << 1
        DEFC REG_CTRL_STATE    = 1 << 0   ; SPI controller in IDLE state (no transaction)
    DEFC REG_CLK_DIV  = (SPI_REG_BASE + 2)
    DEFC REG_RAM_LEN  = (SPI_REG_BASE + 3)
    DEFC REG_CHECKSUM = (SPI_REG_BASE + 4)
    ; ... ;
    DEFC REG_RAM_FIFO = (SPI_REG_BASE + 7)
    DEFC REG_RAM_FROM = (SPI_REG_BASE + 8)
    DEFC REG_RAM_TO   = (SPI_REG_BASE + 15)

    ; Calculate the contanst to start the transfer and assert Chip-Select
    DEFC SPI_START_TRANSFER = REG_CTRL_START | REG_CTRL_CS_START | REG_CTRL_CS_SEL
    DEFC SPI_END_TRANSFER   = REG_CTRL_CS_END | REG_CTRL_CS_SEL


    EXTERN video_board_switch
    EXTERN video_board_switch_end

    ; Check if the video board is in recovery mode
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - 0 if in recovery mode, positive value else
    ; Alters:
    ;   A
    PUBLIC video_is_in_recovery
video_is_in_recovery:
    in a, (VID_VER_REV)
    sub 0xde
    ret nz
    in a, (VID_VER_MIN)
    cp 0xad
    ret nz
    in a, (VID_VER_MAJ)
    cp 0x23
    ret


    ; Wait for the recovery mode to be entered by the video board
    ; Parameters:
    ;   None
    PUBLIC video_wait_recovery
video_wait_recovery:
    ; TODO: refactor to make this cleaner instead of referencing labels from a
    ; different file
    PRINT_STR_UART(video_board_switch)
    ; Wait for 500 milliseconds
    ld de, 500
    call sleep_ms
    ; Check if we are in the recovery mode
    call video_is_in_recovery
    ret z
    jr video_wait_recovery

    ; Flash the NOR Flash located on the video board through SPI.
    ; Parameters:
    ;   RAM[0x80000]: Data to flash at offset 0 of the flash
    ;   CDE: 24-bit size of the data
    ; Returns:
    ;   A - 0 on success, error code else
    PUBLIC video_board_flash
video_board_flash:
    ; To signify a flash is in progress, make the LEDs blink at the same time
    ld a, LED_CTRL_BLK_SYNC
    out (LED_CTRL_REG), a
    ; Enable the SPI component
    ld a, VID_SPI_DEVICE
    out (VID_MAP_DEVICE), a
    ; Configure the SPI clock to 25MHz
    ld a, 2
    out (REG_CLK_DIV), a
    ; Even though the NOR Flash may support erasing smaller sectors than 64KB ones,
    ; let's keep it like this to support as many flashes as possible.
    ; Calculate the number of sectors to erase: round_up(CDE/64KB)
    ; This is equivalent o C + ((D | E) ? 1 : 0)
    ld a, d
    or e
    ; Pre-load A since it doesn't alter the flags
    ld a, c
    jr z, _no_inc
    inc a
_no_inc:
    ; A contains the number of sectors to erase, erase them
    call video_board_erase_A_sectors
    ; We have to program the data as pages, each page is 256 bytes, so we have
    ; CD pages in total. Let's forget about the "incomplete" page for now
    push de
    ; Store number of pages in BC
    ld b, c
    ld c, d
    ; Store in H the virtual address highest byte
    ld h, 0x40
    ; Store in DE the upper 16-bit of physical address
    ld de, 0
    ; Map the pages 1 and 2 to physical address 0x80000
    ld a, 0x80000 >> 14
    out (MMU_PAGE_1), a
    inc a
    out (MMU_PAGE_2), a
    inc a
    ; Store the next pages to map in L
    ld l, a
    ; Check if we have any 256-byte page to program
    ld a, b
    or c
    jr z, _no_full_pages
_program_page:
    ; Iterate over BC pages
    push hl
    push de
    push bc
    call video_board_program_page
    pop bc
    pop de
    pop hl
    ; Increment the virtual page, if it reaches (0xC), we have already sent 32KB
    ; Go back to 0x40
    inc h
    ld a, 0xc0
    cp h
    jr nz, _program_page_no_overflow
    ; Map the next pages too!
    ld a, l
    out (MMU_PAGE_1), a
    inc a
    out (MMU_PAGE_2), a
    inc a
    ; Store the next pages in L again
    ld l, a
    ld h, 0x40
_program_page_no_overflow:
    ; In all cases, increment the physical address by 256
    inc de
    ; Decrement the total number of pages to write
    dec bc
    ld a, b
    or c
    jr nz, _program_page
_no_full_pages:
    ; Program the remaining bytes
    pop bc
    ; A is zero, test C directly
    or c
    jr z, _video_board_flash_disable_write
    ; Program remaining bytes (less than 256), H contains the virtual address MSB
    ; A contains the number of bytes to send
    dec a   ; Decrement as requested by the routine below
    call video_board_program_A_bytes
_video_board_flash_disable_write:
    ; Issue a WRITE-DISABLE command to the SPI flash
    ld a, SPI_WRITE_DIS_CMD
    call spi_start_single_byte_command
    ; Save returned value in B
    ld b, a
    ; Notify that the flash is finished by turning LEDs on
    ld a, LED_CTRL_ON
    out (LED_CTRL_REG), a
    ; Restore returned value
    ld a, b
    ret


    ; Erase A sectors starting at 0x000000 on the flash
    ; Parameters:
    ;   A - Number of sectors to erase (guaranteed not 0)
    ; Returns:
    ;   None
    ; Alters:
    ;   A
video_board_erase_A_sectors:
    push de
    push bc
    ; Iterate over all the sectors
    ld b, a
    ; Prepare the hardware buffer with the lowest 16-bit bytes of sector address
    xor a
    ; Second and third address bytes (always 0)
    out (REG_RAM_FROM + 2), a
    out (REG_RAM_FROM + 3), a
_erase_sector:
    call spi_start_write_enable_cmd
    ; Erase command
    ld a, SPI_ERASE_64KB_CMD
    out (REG_RAM_FROM), a
    ; Sector address highest byte (count - 1)
    ld a, b
    dec a
    out (REG_RAM_FROM + 1), a
    ; Set the HW buffer length: command + 3 bytes = 4 bytes
    ld a, 4
    call spi_start_transfer
    ; Save BC since B contains the erase sector count
    push bc
_erase_sector_wait_status:
    ; The erase command has been started, it is going to take a while, not less than
    ; 75ms. Let's not flood the SPI bus with STATUS commands, and stall for a while
    ld de, 75
    call sleep_ms
    ; Wait for completion
    call spi_get_status
    rrca
    jr c, _erase_sector_wait_status
    ; Sector is erased, continue!
    pop bc
    djnz _erase_sector
    ; Restore original BC and DE and return
    pop bc
    pop de
    ret


    ; Program BC pages into the video board flash.
    ; Parameters:
    ;   H  - Upper 8-bit of the virtual address
    ;   DE - Upper 16-bit of the physical address to write
    ; Returns:
    ;   None
    ; Alters:
    ;   A, BC, DE, HL
video_board_program_page:
    ld a, 0xff
    ; Fall-through

    ; Program the last page, which is strictly smaller than 256 bytes
    ; Parameters:
    ;   H  - Upper 8-bit of the virtual address
    ;   DE - Upper 16-bit of the physical address to write
    ;   A - Number of bytes to write MINUS 1!
    ;   0x8000-0xC000 - mapped to the actual data to write
    ; Returns:
    ;   A - 0 on success, postiive value else
video_board_program_A_bytes:
    ; Save the number of bytes to flash in register B
    ld b, a
    ; Issue a write-enable command
    call spi_start_write_enable_cmd
    call spi_start_write_page_command
    ; Send the 256 bytes, use HL as the virtual address
    ld l, 0
    ; We can now re-use DE registers
    ; Store (number_of_bytes % 8) in D
    ld a, b
    inc a
    and 0x7 ; <=> (B+1) % 8
    ld d, a
    ; Let E store the number of loops to perform by dividing number_of_bytes by 8
    ld a, b
    add 1   ; cannot use `inc a` since we need the carry in case of overflow!
    rra
    rra
    rra
    ; Remove the uppest two bits, since we counted CY as the 8th bit
    and 0x3f
    ; If A is 0, we have less than 8 bytes to write
    jr z, _program_less_than_8
    ld e, a
    call spi_write_E_pages_8_bytes
_program_less_than_8:
    ; Number of bytes to transfer is in D (less than 8)
    ; if it is 0, we can return already
    ld a, d
    or a
    jr z, spi_end_transfer_wait_write
    ; We still have some bytes to write, let's do this, reset the FIFO
    or 0x80     ; clear pseudo-FIFO indexes
    out (REG_RAM_LEN), a
    ; Store number of bytes to transfer in B, as required by otir instruction
    ld b, d
    ld c, REG_RAM_FIFO
    ; Load the bytes in the hardware RAM thanks to the pseudo-FIFO register
    otir
    ; Start the transfer
    ld a, SPI_START_TRANSFER
    out (REG_CTRL), a
    ; Wait for the SPI Idle state, the SPI flash has NOT started writing, so no
    ; need to wait for it for now
    call spi_wait_idle
    jp spi_end_transfer_wait_write


    ; Start an SPI command by asserting the CS low and send the physical page address
    ; Parameters:
    ;   DE - Physical address to write
spi_start_write_page_command:
    ; Send the command and the address to write
    ld a, SPI_PAGE_PROG_CMD
    out (REG_RAM_FROM + 0), a
    ; Highest bytes
    ld a, d
    out (REG_RAM_FROM + 1), a
    ld a, e
    out (REG_RAM_FROM + 2), a
    ; 0 as the lowest byte
    xor a
    out (REG_RAM_FROM + 3), a
    ; Set the RAM length to 4
    ld a, 4
    out (REG_RAM_LEN), a
    ; Start the SPI transfer
    ld a, SPI_START_TRANSFER
    out (REG_CTRL), a
    ret


    ; Start an SPI transfer that writes E pages of 8 bytes
    ; Alters:
    ;   A, BC, E, HL
spi_write_E_pages_8_bytes:
    ; RAM Length is never modified by the hardware, so it is persistent.
    ; Let's use the pseudo-FIFO mode, reset the indexes by setting the highest bit.
    ld a, 0x88
    out (REG_RAM_LEN), a
    ; C will contain the address of the register
    ld c, REG_RAM_FIFO
_spi_write_E_pages_8_bytes_next_batch:
    ; B must contain the number of bytes to transfer (8)
    ld b, 8
    ; Load the bytes in the hardware RAM thanks to the pseudo-FIFO register
    otir
    ld a, SPI_START_TRANSFER
    out (REG_CTRL), a
    ; Wait for the SPI Idle state, the SPI flash has NOT started writing, so no
    ; need to wait for it for now
    call spi_wait_idle
    ; Continue the loop to transfer the rest of the bytes
    dec e
    jr nz, _spi_write_E_pages_8_bytes_next_batch
    ret


    ; Wait for the SPI controller to go to Idle state
    ; Alters:
    ;   A
spi_wait_idle:
    in a, (REG_CTRL)
    rrca    ; Check bit 0, must be 0 too
    ret nc
    jr spi_wait_idle


    ; End the SPI (write) transfer and wait for the transaction to terminate on the flash end
    ; Returns:
    ;   A - 0 (Success)
spi_end_transfer_wait_write:
    ld a, SPI_END_TRANSFER
    out (REG_CTRL), a
_spi_end_transfer_wait_write_loop:
    call spi_get_status
    rrca
    ret nc
    jr _spi_end_transfer_wait_write_loop

    ; Get the current status of the SPI flash
spi_get_status:
    ; Issue a status command
    ld a, SPI_READ_STA_CMD
    out (REG_RAM_FROM), a
    ; Provide a 2-byte size since we need to read a byte (the second byte will be discarded)
    ld a, 2
    call spi_start_transfer
    ; The transaction is finished since `spi_start_transfer` waits for idle state
    ; Read the status reply from the flash
    in a, (REG_RAM_FROM + 1)
    ; Lowest bit is 1 if write is in progress, 0 else
    ret


    ; Issue a write-enable command
spi_start_write_enable_cmd:
    ld a, SPI_WRITE_ENA_CMD
    ; Fall-through

    ; Start a sungle byte command
    ; Parameters:
    ;   A - Command to send
spi_start_single_byte_command:
    out (REG_RAM_FROM), a
    ld a, 1
    ; Fall-through

    ; Start an SPI transfer by setting the buffer length and asserting the chip select
    ; Parameters:
    ;   A - Length of the HW buffer
    ; Returns:
    ;   A - 0 (Success)
spi_start_transfer:
    out (REG_RAM_LEN), a
    ; Start the command and assert chip select at the same time
    ld a, SPI_START_TRANSFER
    out (REG_CTRL), a
    ; Wait for the transaction to be finished
    call spi_wait_idle
    ; De-assert the chip-select
    ld a, SPI_END_TRANSFER
    out (REG_CTRL), a
    ; Success, return 0
    xor a
    ret


    ; Sleep for a given amount of milliseconds
    ; Parameters:
    ;   DE - Number of milliseconds to sleep for
    ; Returns:
    ;   None
sleep_ms:
    ld bc, CPU_FREQ / 1000 / 24
_sleep_ms_waste:
    ; 24 T-states for the following, until 'jp nz, _sleep_ms_waste'
    dec bc
    ld a, b
    or c
    jp nz, _sleep_ms_waste
    ; If we are here, a milliseconds has elapsed
    dec de
    ld a, d
    or e
    jp nz, sleep_ms
    ret
