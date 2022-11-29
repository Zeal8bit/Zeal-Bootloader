; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0
        INCLUDE "uart_h.asm"
        INCLUDE "pio_h.asm"
        INCLUDE "mmu_h.asm"
        INCLUDE "video_h.asm"

        DEFC PINS_DEFAULT_STATE = IO_PIO_SYSTEM_VAL & ~(1 << IO_UART_TX_PIN)
        DEFC UART_FIFO_SIZE = 16

        EXTERN int_handlers_table

        SECTION BOOTLOADER
        ; Initialize the PIO and the UART
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   A
        PUBLIC uart_initialize
uart_initialize:
        ; Set the default baudrate
        ld a, UART_BAUDRATE_DEFAULT
        ld (baudrate), a
        ; Init the FIFO
        ld hl, uart_fifo
        ld (uart_fifo_wr), hl
        ld (uart_fifo_rd), hl
        call pio_init_ports
        ret


        ; Initialize the PIO system and user port
pio_init_ports:
        ; Set system port as bit-control
        ld a, IO_PIO_BITCTRL
        out (IO_PIO_SYSTEM_CTRL), a
        ; Set the proper direction for each pin
        ld a, IO_PIO_SYSTEM_DIR
        out (IO_PIO_SYSTEM_CTRL), a
        ; Set default value for all the (output) pins
        ld a, IO_PIO_SYSTEM_VAL
        out (IO_PIO_SYSTEM_DATA), a
        ; Set interrupt vector to 2
        ld a, 2
        out (IO_PIO_SYSTEM_CTRL), a
        ; Enable the interrupts globally for the system port
        ld a, IO_PIO_ENABLE_INT
        out (IO_PIO_SYSTEM_CTRL), a
        ; Enable interrupts, for the required pins only
        ld a, IO_PIO_SYSTEM_INT_CTRL
        out (IO_PIO_SYSTEM_CTRL), a
        ; Mask must follow
        ld a, IO_PIO_SYSTEM_INT_MASK
        out (IO_PIO_SYSTEM_CTRL), a
        ; Initalize user port as input
        ld a, IO_PIO_INPUT
        out (IO_PIO_USER_CTRL), a
        ld a, IO_PIO_DISABLE_INT
        out (IO_PIO_USER_CTRL), a

        ; Enable interrupts
        ld a, int_handlers_table >> 8
        ld i, a
        im 2
        ei
        ret


        PUBLIC default_handler
default_handler:
        ex af, af'
        exx
        ; Triggered by UART RX pin
        ld a, (baudrate)
        ld d, a
        ld e, 8
        ld b, 0
        call uart_receive_wait_start_bit_anybaud
        call uart_enqueue
        exx
        ex af, af'
        ei
        reti

        ; Enqueue the value A inside the UART software FIFO
uart_enqueue:
        ; A contains the received byte, enqueue it
        ld hl, (uart_fifo_wr)
        ld (hl), a
        ; Increment HL. We know that HL is aligned on UART_FIFO_SIZE.
        ; So L can be incremented alone, but keep the upper bit like
        ; they are in the FIFO address
        inc l
        ld a, l
        ; And A with the upper bits of L that shall not change
        ; For example, when HL is aligned on 16, L upper nibble
        ; must not change, thus we should have A AND 0xNF where
        ; N = L upper nibble
        and UART_FIFO_SIZE - 1
        add uart_fifo & 0xff
        ld (uart_fifo_wr), a
        ; Check if the size needs update (i.e. FIFO not full)
        ld a, (uart_fifo_size)
        cp UART_FIFO_SIZE
        ; In case the FIFO is full, we need to push read cursor forward
        jr z, _uart_queue_next_read
        ; Else, simply increment the size
        inc a
        ld (uart_fifo_size), a
        ret
_uart_queue_next_read:
        ld a, l
        ld (uart_fifo_rd), a
        ret

        ; Dequeue a value from the UART FIFO, if empty, wait for a character
        ; Parameters:
        ;       None
        ; Returns:
        ;       A - Character received
        ; Alters:
        ;       A
uart_dequeue:
        push hl
        ld hl, uart_fifo_size
        xor a
_uart_dequeue_wait:
        or (hl)
        jr nz, _uart_dequeue_available
        halt
        jr _uart_dequeue_wait
_uart_dequeue_available:
        di
        ; Decrement the FIFO size
        dec (hl)
        ; Get the read pointer
        ld hl, (uart_fifo_rd)
        ; Get the oldest value
        ld h, (hl)
        ; Increment L, the same way we did in enqueue
        inc l
        ld a, l
        and UART_FIFO_SIZE - 1
        add uart_fifo & 0xff
        ld (uart_fifo_rd), a
        ; Re-enable the interrupts
        ei
        ; Popped value in A and restore HL
        ld a, h
        pop hl
        ret

        PUBLIc uart_disable_fifo
uart_disable_fifo:
        ld a, IO_PIO_DISABLE_INT
        out (IO_PIO_SYSTEM_CTRL), a
        ret

        ; Reset the UART FIFO
        ; Parameters:
        ;       None
        ; Returns:
        ;       None
        ; Alters:
        ;       A, HL
        PUBLIC uart_fifo_reset
uart_fifo_reset:
        xor a
        ld hl, uart_fifo
        di
        ld (uart_fifo_size), a
        ld (uart_fifo_wr), hl
        ld (uart_fifo_rd), hl
        ei
        ret

        ; Number of characters received on the UART
        ; Parameters:
        ;   None
        ; Returns:
        ;   A - Number of characters available to read
        ; Alters:
        ;   None
        PUBLIC uart_available_read
uart_available_read:
        ld a, (uart_fifo_size)
        ret

        ; Set the baudrate for the UART
        ; Parameters:
        ;   D - New baudrate
        ; Returns:
        ;   None
        ; Alters:
        ;   None
        PUBLIC uart_set_baudrate
uart_set_baudrate:
        ld a, d
        ld (baudrate), a
        ret

        ; Small helper to print a newline
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   A, BC, D
        PUBLIC newline
newline:
        ; Print \r\n
        ld a, '\r'
        call uart_send_one_byte
        ld a, '\n'
        jp uart_send_one_byte


        ; Send a sequences of bytes on the UART, with default baudrate
        ; Parameters:
        ;   HL - Pointer to the sequence of bytes
        ;   BC - Size of the sequence
        ; Returns:
        ;   A - 0 on success, not zero else
        ;   HL - HL + BC
        ; Alters:
        ;   A, D, BC, HL
        PUBLIC uart_send_bytes
uart_send_bytes:
        ; Check that the length is not 0
        ld a, b
        or c
        ret z
        ; Set the baudrate in D
        ld a, (baudrate)
        ld d, a
_uart_send_next_byte:
        ld a, (hl)
        push bc
        ; Enter a critical section (disable interrupts) only when sending a byte.
        di
        call uart_send_byte
        ei
        pop bc
        inc hl
        dec bc
        ld a, b
        or c
        jp nz, _uart_send_next_byte
        ret

        ; Send a single byte on the UART with default baudrate
        ; Parameters:
        ;   A - ASCII byte to send on the UART
        ; Alters:
        ;   A, BC ,D
        PUBLIc uart_send_one_byte
uart_send_one_byte:
        ld b, a
        ; Set the baudrate in D
        ld a, (baudrate)
        ld d, a
        ld a, b
        jp uart_send_byte


        ; Receive a single byte from the UART with default baudrate
        ; Parameters:
        ;       None
        ; Returns:
        ;       A - ASCII byte received
        ; Alters:
        ;       A, B, DE
        PUBLIC uart_receive_one_byte
uart_receive_one_byte:
        ld a, (baudrate)
        ld d, a
        jp uart_receive_byte

        ; Receive a sequences of bytes on the UART.
        ; Parameters:
        ;   HL - Pointer to the sequence of bytes
        ;   BC - Size of the sequence (NOT 0!)
        ; Returns:
        ;   A - 0 on success, not zero else
        ; Alters:
        ;   A, BC, D, HL
        PUBLIC uart_receive_bytes
uart_receive_bytes:
        ld a, (baudrate)
        ld d, a
        ; di
_uart_receive_next_byte:
        push bc
        call uart_receive_byte
        pop bc
        ; ei
        ld (hl), a
        inc hl
        dec bc
        ld a, b
        or c
        jp nz, _uart_receive_next_byte
        ret

        ; Receive a big file on the UART and save it to RAM.
        ; Parameters:
        ;       CDE - Size of the file to receive (maximum 496KB)
        ; Returns:
        ;       None
        ; Alters:
        ;       A
        PUBLIC uart_receive_big_file
uart_receive_big_file:
        push hl
        push bc
        push de
        ; Determine how many times we will have to loop, in other words, we have to divide
        ; CDE by 32KB to know how many times we will have to call uart_receive_bytes
        ; The maximum is 15, store this count in B, remainder in HL.
        ; For example: 496/32 = 15.5, so B = 15 and HL = 16KB
        ld l, e
        ld a, d
        and 0x7f
        ld h, a
        ; Move D's MSB to C LSB
        rl d
        rl c
        ld b, c
        ; That's it! Save HL on the stack
        push hl
        ; Use page 1 and page 2 to store the file. Map RAM to these pages.
        ld a, 0x80000 >> 14
        out (MMU_PAGE_1), a
        inc a
        out (MMU_PAGE_2), a
        inc a
        ld c, a
        ; Check if we have to loop 0 time!
        ld a, b
        or a
        jr z, uart_receive_big_file_no_loop
uart_receive_big_file_loop:
        ; Save C (RAM mapped pages), and B (loop count)
        push bc
        ; Receive bytes to the page 1
        ld hl, 0x4000
        ld bc, 0x8000
        call uart_receive_bytes
        ; 32KB received, map the next 32KB of RAM
        pop bc
        ld a, c
        out (MMU_PAGE_1), a
        inc a
        out (MMU_PAGE_2), a
        inc a
        ld c, a
        djnz uart_receive_big_file_loop
uart_receive_big_file_no_loop:
        pop bc
        ; If BC is not 0, we have to receive some bytes still
        ld a, b
        or c
        jr z, uart_receive_big_file_end
        ; Receive BC bytes in page 1
        ld hl, 0x4000
        call uart_receive_bytes
uart_receive_big_file_end:
        pop de
        pop bc
        pop hl
        ret


        ; Send a single byte on the UART
        ; Parameters:
        ;   A - Byte to send
        ;   D - Baudrate
        ; Alters:
        ;   A, BC
uart_send_byte:
        ; Shift B to match TX pin
        ASSERT(IO_UART_TX_PIN <= 7)
        REPT IO_UART_TX_PIN
        rlca
        ENDR
        ; Byte to send in C
        ld c, a
        ; 8 bits in B
        ld b, 8
        ; Start bit, set TX pin to 0
        ld a, PINS_DEFAULT_STATE
        out (IO_PIO_SYSTEM_DATA), a
        ; The loop considers that all bits went through the "final"
        ; dec b + jp nz, which takes 14 T-states, but coming from here, we
        ; haven't been through these, so we are a bit too early, let's wait
        ; 14 T-states too.
        jp $+3
        nop
        ; For each baudrate, we have to wait N T-states in TOTAL:
        ; Baudrate 57600 => (D = 0)  => 173.6  T-states (~173 +  0 * 87)
        ; Baudrate 38400 => (D = 1)  => 260.4  T-states (~173 +  1 * 87)
        ; Baudrate 19200 => (D = 4)  => 520.8  T-states (~173 +  4 * 87)
        ; Baudrate 9600  => (D = 10) => 1041.7 T-states (~173 + 10 * 87)
        ; Wait N-X T-States inside the routine called, before sending next bit, where X is:
        ;            17 (`call` T-states)
        ;          + 4 (`ld` T-states)
        ;          + 8 (`rrc b` T-states)
        ;          + 7 (`and` T-states)
        ;          + 7 (`or` T-states)
        ;          + 12 (`out (c), a` T-states)
        ;          + 14 (dec + jp)
        ;          = 69 T-states
        ; Inside the routine, we have to wait (173 - 69) + D * 87 T-states = 104 + D * 87
uart_send_byte_next_bit:
        call wait_104_d_87_tstates
        ; Put the byte to send in A
        ld a, c
        ; Shift B to prepare next bit
        rrc c
        ; Isolate the bit to send
        and 1 << IO_UART_TX_PIN
        ; Or with the default pin value to not modify I2C
        or PINS_DEFAULT_STATE
        ; Output the bit
        out (IO_PIO_SYSTEM_DATA), a
        ; Check if we still have some bits to send. Do not use djnz,
        ; it adds complexity to the calculation, use jp which always uses 10 T-states
        dec b
        jp nz, uart_send_byte_next_bit
        ; Output the stop bit, but before, for the same reasons as the start, we have to wait the same
        ; amount of T-states that is present before the "out" from the loop: 43 T-states
        call wait_104_d_87_tstates
        ld a, IO_PIO_SYSTEM_VAL
        ; Wait 19 T-states now
        jr $+2
        ld c, 0
        ; Output the bit
        out (IO_PIO_SYSTEM_DATA), a
        ; Output some delay after the stop bit too
        call wait_104_d_87_tstates
        ret

        ; Receive a byte on the UART with a given baudrate.
        ; Parameters:
        ;   D - Baudrate
        ; Returns:
        ;   A - Byte received
        ; Alters:
        ;   A, B, E
uart_receive_byte:
        ld e, 8
        ; A will contain the data read from PIO
        xor a
        ; B will contain the final value
        ld b, a
        ; RX pin must be high (=1), before receiving
        ; the start bit, check this state.
        ; If the line is not high, then a transfer is ocurring
        ; or a problem is happening on the line
uart_receive_wait_for_idle_anybaud:
        ; in a, (IO_PIO_SYSTEM_DATA)
        ; bit IO_UART_RX_PIN, a
        ; jp z, uart_receive_wait_for_idle_anybaud
        ; ; Delay the reception
        ; jp $+3
        ; bit 0, a
uart_receive_wait_start_bit_anybaud:
        in a, (IO_PIO_SYSTEM_DATA)
        ; We can use AND and save one T-cycle, but this needs to be time accurate
        ; So let's keep BIT.
        bit IO_UART_RX_PIN, a
        jp nz, uart_receive_wait_start_bit_anybaud
        ; Delay the reception
        ld a, r     ; For timing
        ld a, r     ; For timing
        ; Add 44 T-States (for 57600 baudrate)
        ; This will let us read the bits incoming at the middle of their period
        jr $+2      ; For timing
        ld a, (hl)  ; For timing
        ld a, (hl)  ; For timing
        ; Check baudrate, if 0 (57600)
        ; Skip the wait_tstates_after_start routine
        ld a, d
        or a
        jp z, uart_receive_wait_next_bit_anybaud
        ; In case we are not in baudrate 57600,
        ; BAUDRATE * 86 - 17 (CALL)
        call wait_tstates_after_start
uart_receive_wait_next_bit_anybaud:
        ; Wait for bit 0
        ; Wait 174 T-states in total for 57600
        ; Where X = 174
        ;           - 17 (CALL T-States)
        ;           - 12 (IN b, (c) T-states)
        ;           - 8 (BIT)
        ;           - 8 (RRC B)
        ;           - 4 (DEC)
        ;           - 10 (JP)
        ;           - 18 (DEBUG/PADDING instructions)
        ;           - 10 (JP)
        ;       X = 105 - 18 = 87 T-states
        ; For any baudrate, wait 87 + baudrate * 86
        call wait_tstates_next_bit
        in a, (IO_PIO_SYSTEM_DATA)
        jp $+3      ; For timing
        bit 0, a    ; For timing
        bit IO_UART_RX_PIN, a
        jp z, uart_received_no_next_bit_anybaud
        inc b
uart_received_no_next_bit_anybaud:
        rrc b
        dec e
        jp nz, uart_receive_wait_next_bit_anybaud
        ; Set the return value in A
        ld a, b
        ret

        ; In case we are not in baudrate 57600, we have to wait about BAUDRATE * 86 - 17
        ; Parameters:
        ;   A - Baudrate
        ;   D - Baudrate
wait_tstates_after_start:
        ; For timing (50 T-states)
        ex (sp), hl
        ex (sp), hl
        bit 0, a
        nop
        ; Really needed
        dec a
        jp nz, wait_tstates_after_start
        ; 10 T-States
        ret

        ; Routine to wait 104 + D * 87 T-states
        ; A can be altered
wait_104_d_87_tstates:
        ; We need to wait 17 T-states more than in the routine below, let's wait and fall-through
        ld a, i
        bit 0, a
        ; After receiving a bit, we have to wait:
        ; 87 + baudrate * 86
        ; Parameters:
        ;   D - Baudrate
wait_tstates_next_bit:
        ld a, d
        or a
        jp z, wait_tstates_next_bit_87_tstates
wait_tstates_next_bit_loop:
        ; This loop shall be 86 T-states long
        ex (sp), hl
        ex (sp), hl
        push af
        ld a, (0)
        pop af
        ; 4 T-states
        dec a
        ; 10 T-states
        jp nz, wait_tstates_next_bit_loop
        ; Total = 2 * 19 + 11 + 13 + 10 + 4 + 10 = 86 T-states
wait_tstates_next_bit_87_tstates:
        ex (sp), hl
        ex (sp), hl
        push hl
        pop hl
        ret

        SECTION BSS
        ALIGN 16
uart_fifo: DEFS UART_FIFO_SIZE
uart_fifo_wr: DEFS 2
uart_fifo_rd: DEFS 2
uart_fifo_size: DEFS 1
baudrate: DEFS 1
