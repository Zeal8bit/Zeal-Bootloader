; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

        INCLUDE "pio_h.asm"

        ; Mask used to get the value from SDA input pin
        DEFC SDA_INPUT_MASK = 1 << IO_I2C_SDA_IN_PIN

        ; Default value for other pins than I2C ones. This is used to output a
        ; value on the I2C without sending garbage on the other lines (mainly UART)
        DEFC PINS_DEFAULT_STATE = IO_PIO_SYSTEM_VAL & ~(1 << IO_I2C_SDA_OUT_PIN | 1 << IO_I2C_SCL_OUT_PIN)

        SECTION BOOTLOADER

        ; Send a single byte on the bus (and check ACK)
        ; Parameters:
        ;   A - Byte to send
        ; Returns:
        ;   A - SDA Pin state
        ;   NZ Flag - NACK
        ;   Z Flag - ACK received
        ; Alters:
        ;   A, D
i2c_send_byte:
        push bc
        ld b, 8
        ld c, a
        ld d, PINS_DEFAULT_STATE
_i2c_send_byte_loop:
        ; Set SCL low, keep SDA low
        ld a, d
        out (IO_PIO_SYSTEM_DATA), a

        xor a
        ; Send next bit on SDA wire
        rlc c
        ; A is 0 so this will become A = Carry
        adc a, a
        ; If SDA is bit 0, no need to shift, else, it is needed
        IF IO_I2C_SDA_OUT_PIN != 0
        jr z, _i2c_send_byte_no_shift
        ld a, 1 << IO_I2C_SDA_OUT_PIN
_i2c_send_byte_no_shift:
        ENDIF
        ; Do not modify other pins' state
        or PINS_DEFAULT_STATE
        ; In D, SCL is low, but SDA is set or reset
        ld d, a

        ; Set SDA state in PIO, set SCL to low at the same time
        ; SCL is already 0 because PINS_DEFAULT_STATE sets it to 0
        out (IO_PIO_SYSTEM_DATA), a

        ; Set SCL back to high: SDA must not change.
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ; SDA is not allowed to change here as SCL is high
        djnz _i2c_send_byte_loop
        ; End of byte transmission

        ; Need to check ACK: set SCL to low.
        ld a, d
        out (IO_PIO_SYSTEM_DATA), a

        ; SDA MUST be set to 1 to activate the open-drain
        ; output!
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a

        ; Put SCL high again
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a

        ; Read the reply from the device
        in a, (IO_PIO_SYSTEM_DATA)
        and SDA_INPUT_MASK

        pop bc
        ret


        ; Receive a byte on the bus (perform ACK if needed)
        ; Parameters:
        ;   A - 0: No ACK, 1: ACK
        ; Returns:
        ;   A - Byte received
i2c_receive_byte:
        push bc
        ld b, 8
        ; Contains the result
        ld c, 0
        ; Contains ACK or NACK
        ld d, a

_i2c_receive_byte_loop:
        ; Shift C to allow a new bit to come
        rlc c

        ; Set SCL low, and SDA high (high impedance)
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a

        ; Set SCL back to high
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a

        ; SDA is not allowed to change here as SCL is high
        ; Get the value of SDA here
        in a, (IO_PIO_SYSTEM_DATA)
        and SDA_INPUT_MASK
        jp z, _i2c_receive_byte_no_inc
        inc c
_i2c_receive_byte_no_inc:
        djnz _i2c_receive_byte_loop
        ; End of byte transmission

        ; Check if the caller needs to send ACK or NACK
        bit 0, d
        ; Prepare SDA to high-impedance (high)
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        jr z, _i2c_receive_byte_no_ack
        ld a, PINS_DEFAULT_STATE
_i2c_receive_byte_no_ack:

        ; Set SCL to low (set because of PINS_DEFAULT_STATE
        out (IO_PIO_SYSTEM_DATA), a

        ; Put SCL high again
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a

        ; Return the byte received
        ld a, c

        pop bc
        ret


        ; Perform a START on the bus. SCL MUST be high when calling this routine
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   A
i2c_perform_start:
        ; Output a start bit by setting SDA to LOW. SCL must remain HIGH.
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ret

i2c_perform_repeated_start:
        ; Set SCL to low, set SDA to high
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ; Set SCL to high, without modifying SDA
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ; Issue a regular start
        ; Output a start bit by setting SDA to LOW. SCL must remain HIGH.
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ret

        ; Perform a STOP on the bus. SCL MUST be high when calling this routine
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   A
i2c_perform_stop:
        ; Stop bit, put SCL low, put SDA high
        ; then SCL high, finally SDA high
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ; Put SCL high, save time by making SDA low here
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ; Finally, put SDA high
        or 1 << IO_I2C_SDA_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ret

        ; Write bytes on the bus to the specified device
        ; Parameters:
        ;   A - 7-bit device address
        ;   HL - Buffer to write on the bus
        ;   B - Size of the buffer
        ; Returns:
        ;   A - 0: Success
        ;       1: No device responded
        ;       2: Device stopped responding during transmission (NACK received)
        ; Alters:
        ;   A, HL
        PUBLIC i2c_write_device
i2c_write_device:
        ; In order to optimize the size of this routine, C will be used as a
        ; temporary storage for device address and error code
        push bc
        push de

        ; Making the write device address in A (left shift + 0)
        sla a
        ld c, a

        ; Start signal and send address
        call i2c_perform_start
        ld a, c
        call i2c_send_byte
        ld c, 0
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_device_address_nack

        ; Start reading and sending the bytes
_i2c_write_device_byte:
        ld a, (hl)
        inc hl
        ; BC are both preserved across this function call
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_device_nack
        djnz _i2c_write_device_byte

        ; C should be 0 at the end, so put -2 inside.
        ld c, -2
_i2c_write_device_nack:
        inc c
_i2c_write_device_address_nack:
        inc c
_i2c_write_device_end:
        ; Send stop signal in ANY case
        call i2c_perform_stop
        ; Restore error code
        ld a, c
        pop de
        pop bc
        ret

        ; Read bytes from a device on the bus
        ; Parameters:
        ;   A - 7-bit device address
        ;   HL - Buffer to store the bytes read
        ;   B - Size of the buffer
        ; Returns:
        ;   A - 0: Success
        ;       1: No device responded
        ; Alters:
        ;   A, HL
        PUBLIC i2c_read_device
i2c_read_device:
        ; In order to optimize the size of this routine, C will be used as a
        ; temporary storage for device address and error code
        push bc
        push de

        ; Making the read device address in A (left shift + 1)
        scf
        rla
        ld c, a

        ; Start signal and send address
        call i2c_perform_start
        ld a, c
        call i2c_send_byte
        ld c, 0
        ; If not zero, NACK was received, abort
        jp nz, _i2c_read_device_address_nack

_i2c_read_device_byte:
        ; If B is 1, the last byte needs to be read, NACK shall be passed on the bus.
        ; Else, ACK shall be performed (0 = NACK, 1 = ACK)
        ld a, b
        dec a
        ; If A is 0, do nothing, it is already representing NACK
        ; Else, add 1
        jr z, _i2c_read_device_perform_nack
        ld a, 1
_i2c_read_device_perform_nack:
        ; BC are both preserved across this function call
        call i2c_receive_byte
        ld (hl), a
        inc hl
        djnz _i2c_read_device_byte

        ; C should be 0 at the end, so put -1 inside.
        ld c, -1
_i2c_read_device_address_nack:
        inc c
        ; Send stop signal in ANY case
        call i2c_perform_stop
        ; Restore error code
        ld a, c
        pop de
        pop bc
        ret

        ; Perform a write followed by a read on the bus
        ; Parameters:
        ;   A - 7-bit device address
        ;   HL - Write buffer (bytes to write)
        ;   DE - Read buffer (bytes read from the bus)
        ;   B - Size of the write buffer
        ;   C - Size of the read buffer
        ; Returns:
        ;   A - 0: Success
        ;       1: No device responded
        ; Alters:
        ;   A, HL
        PUBLIC i2c_write_read_device
i2c_write_read_device:
        ; In order to optimize the size of this routine, C will be used as a
        ; temporary storage for device address and error code
        push bc
        push de
        ; Save AF for the device address
        push af

        ; Making the write device address in A (left shift + 0)
        sla a
        ld c, a

        ; Start signal and send address
        call i2c_perform_start
        ld a, c
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_read_device_address_nack

        ; Start sending the bytes
_i2c_write_read_write_device_byte:
        ld a, (hl)
        inc hl
        ; BC are both preserved across this function call
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_read_device_address_nack
        djnz _i2c_write_read_write_device_byte

        ; Bytes were sent successfully. Issue a repeated start with
        ; the read address.
        pop af

        ; Making the read device address in A (left shift + 1)
        scf
        rla
        ld c, a

        ; Start signal and send address
        call i2c_perform_repeated_start
        ld a, c
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_read_device_address_nack_no_pop

        ; Before reading the bytes, retrieve DE and BC from the stack.
        ; Put DE in HL. Both HL and BC shall be saved it back on the stack
        pop hl
        pop bc
        push bc
        push hl
        ; Argument (DE) is in HL, BC (argument) is in BC
        ld b, c
_i2c_write_read_read_device_byte:
        ; If B is 1, the last byte needs to be read, NACK shall be passed on the bus.
        ; Else, ACK shall be performed (0 = NACK, 1 = ACK)
        ld a, b
        dec a
        ; If A is 0, do nothing, it is already representing NACK
        ; Else, add 1
        jr z, _i2c_write_read_device_perform_nack
        ld a, 1
_i2c_write_read_device_perform_nack:
        ; BC are both preserved across this function call
        call i2c_receive_byte
        ld (hl), a
        inc hl
        djnz _i2c_write_read_read_device_byte

        ; Everything went well, stop signal
        call i2c_perform_stop
        xor a
        pop de
        pop bc
        ret
_i2c_write_read_device_address_nack:
        pop af
_i2c_write_read_device_address_nack_no_pop:
        call i2c_perform_stop
        ld a, 1
        pop de
        pop bc
        ret