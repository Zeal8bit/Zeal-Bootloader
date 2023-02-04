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
        ;   A, DE
i2c_send_byte:
        push bc
        ld b, 8
        ld c, PINS_DEFAULT_STATE
        ; Prepare the byte to send
        REPT IO_I2C_SDA_OUT_PIN
        rlca
        ENDR
        ld e, a
        ; D represent the mask to retrieve the SDA line output data
        ld d, 1 << IO_I2C_SDA_OUT_PIN
        ; A represent the current value of SDA, 0 to begin with
        xor a
_i2c_send_byte_loop:
        rlc e

        ; Set SCL low, keep SDA to the current value
        or c
        out (IO_PIO_SYSTEM_DATA), a

        ; Prepare the next bit to send in the PINS_STATE
        ld a, e
        and d
        or c    ; or with PINS_DEFAULT_STATE

        IFNDEF I2C_NO_LIMIT
        ; In order to achieve a duty cycle of 50% with a period of 5us, let's add the following
        bit 0, a
        ENDIF

        ; Set SDA state in PIO, set SCL to low at the same time
        ; SCL is already 0 because PINS_DEFAULT_STATE sets it to 0
        out (IO_PIO_SYSTEM_DATA), a

        ; Set SCL back to high: SDA must not change.
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a

        ; Save only the current SDA value in A
        and d

        IFNDEF I2C_NO_LIMIT
        ; In order to achieve a duty cycle of 50% with a period of 5us, let's add the following
        jp $+3
        ENDIF

        ; SDA is not allowed to change here as SCL is high
        djnz _i2c_send_byte_loop
        ; End of byte transmission, A contains the last value sent

        ; Need to check ACK: set SCL to low, do not modify SDA (A)
        ; We could use `or c`, but we want to operation to last a bit longer
        or PINS_DEFAULT_STATE
        out (IO_PIO_SYSTEM_DATA), a

        ; SDA MUST be set to 1 to activate the open-drain output!
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a

        ; Wait a bit to have a 5us period
        IFNDEF I2C_NO_LIMIT
        jr $+2
        ENDIF

        ; Put SCL high again
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN) | (1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a

        ; Read the reply from the device
        in a, (IO_PIO_SYSTEM_DATA)
        and SDA_INPUT_MASK

        pop bc
        ret


        ; Receive a byte on the bus (perform ACK if needed)
        ; Parameters:
        ;   A - 0: ACK, 1: NACK
        ; Returns:
        ;   A - Byte received
i2c_receive_byte:
        push bc
        push hl
        ld b, 8
        ld c, IO_PIO_SYSTEM_DATA
        ; Contains ACK or NACK
        ld d, a
        ; Contains the result
        xor a
        ld h, SDA_INPUT_MASK
        ld l, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
_i2c_receive_byte_loop:
        ; A contains the future content of E, which needs to be shifted once
        ; to allow a new bit to come.
        rlca

        ; Set SCL low, and SDA high (high impedance)
        out (c), l

        ld e, a

        IFNDEF I2C_NO_LIMIT
        ; Without a delay, SCL will stay low during less than 5us. Let's balance it by delaying a bit.
        push af
        pop af
        nop
        ENDIF

        ; Set SCL back to high
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN) | (1 << IO_I2C_SCL_OUT_PIN)
        out (c), a

        ; SDA is not allowed to change here as SCL is high
        ; Get the value of SDA here
        in a, (c)
        and h
        add e
        ; Loop again until we don't have any remaining bit
        djnz _i2c_receive_byte_loop

        ; End of byte transmission, set result in E
        ld e, a

        ; SDA is in high-impedance here, set clock to low first
        out (c), l

        ; Check if we need to ACK. D is either 0, ACK, either 1, NACK.
        ld a, d
        REPT IO_I2C_SDA_OUT_PIN
        rlca
        ENDR

        ; Output value of SDA first, while SCL is still low
        or PINS_DEFAULT_STATE
        out (c), a

        ; Add the flag to put SCL to 1
        or 1 << IO_I2C_SCL_OUT_PIN
        out (c), a

        ; Return the byte received, needs to be shifted
        ld a, e
        REPT IO_I2C_SDA_IN_PIN
        rrca
        ENDR

        pop hl
        pop bc
        ret


        ; Perform a START on the bus. SCL MUST be high when calling this routine
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   C
i2c_perform_start:
        ld c, a
        ; Output a start bit by setting SDA to LOW. SCL must remain HIGH.
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SCL_OUT_PIN) | (0 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ld a, c
        ret
i2c_perform_repeated_start:
        ; Set SCL to low, set SDA to high
        ld c, a
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SDA_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ; Set SCL to high, without modifying SDA
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ; Issue a regular start
        ; Output a start bit by setting SDA to LOW. SCL must remain HIGH.
        ld a, PINS_DEFAULT_STATE | (1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ld a, c
        ret

        ; Perform a STOP on the bus. SCL MUST be high when calling this routine
        ; Parameters:
        ;   None
        ; Returns:
        ;   None
        ; Alters:
        ;   C
i2c_perform_stop:
        ld c, a
        in a, (IO_PIO_SYSTEM_DATA)
        ; Set SCL to low while keeping SDA value
        and  ~(1 << IO_I2C_SCL_OUT_PIN)
        out (IO_PIO_SYSTEM_DATA), a
        ; Put both SCL and SDA to low
        ld a, PINS_DEFAULT_STATE
        out (IO_PIO_SYSTEM_DATA), a
        ; Set SCL to high
        or 1 << IO_I2C_SCL_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ; Set SDA to high
        or 1 << IO_I2C_SDA_OUT_PIN
        out (IO_PIO_SYSTEM_DATA), a
        ld a, c
        ret

        ; Write bytes on the bus to the specified device
        ; Parameters:
        ;   A - 7-bit device address
        ;   HL - Buffer to write on the bus
        ;   B - Size of the buffer
        ; Returns:
        ;   A - 0: Success
        ;       -1: No device responded
        ;       positive value: Device stopped responding during transmission (NACK received)
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

        ; Start signal and send address
        call i2c_perform_start
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        ld a, 0xff
        jp nz, _i2c_write_device_nack

        ; Start reading and sending the bytes
_i2c_write_device_byte:
        ld a, (hl)
        inc hl
        ; BC are both preserved across this function call
        call i2c_send_byte
        ; If not zero, NACK was received, abort.
        jr nz, _i2c_write_device_nack
        djnz _i2c_write_device_byte

        ; A should be 0 at the end to show success
        xor a
_i2c_write_device_nack:
        ; Send stop signal in ANY case
        call i2c_perform_stop
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
        ;       -1: No device responded
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

        ; Start signal and send address
        call i2c_perform_start
        ; Send the device address
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        ld a, 0xff
        jr nz, _i2c_read_device_address_nack

        ; Run the following loop for B - 1 (sending an ACK at the end)
        dec b
        jp z, _i2c_read_device_byte_end
_i2c_read_device_byte:
        ; Set A to 0 (ACK)
        xor a
        ; BC and HL are both preserved across this function call
        call i2c_receive_byte
        ld (hl), a
        inc hl
        djnz _i2c_read_device_byte
_i2c_read_device_byte_end:
        ; Set A to 1 (NACK)
        ld a, 1
        call i2c_receive_byte
        ld (hl), a

        ; Success, set A to 0
        xor a
_i2c_read_device_address_nack:
        ; Send stop signal in ANY case
        call i2c_perform_stop
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
        ;       -1: No device responded
        ; Alters:
        ;   A, HL
        PUBLIC i2c_write_read_device
i2c_write_read_device:
        ; In order to optimize the size of this routine, C will be used as a
        ; temporary storage for device address and error code
        push bc
        push de

        ; Making the write device address in A (left shift + 0)
        sla a
        ; Save AF for the device address
        push af

        ; Start signal and send address
        call i2c_perform_start
        ; Send the device address
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jr nz, _i2c_write_read_device_address_nack

        ; Start sending the bytes
_i2c_write_read_write_device_byte:
        ld a, (hl)
        inc hl
        ; BC are both preserved across this function call
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jr nz, _i2c_write_read_device_address_nack
        djnz _i2c_write_read_write_device_byte

        ; Bytes were sent successfully. Issue a repeated start with the read address.
        pop af

        ; Making the read device address in A. A has already been shifted left.
        inc a

        ; Start signal and send address
        call i2c_perform_repeated_start
        ; Send the (read) device address
        call i2c_send_byte
        ; If not zero, NACK was received, abort
        jp nz, _i2c_write_read_device_address_nack_no_pop

        ; Before reading the bytes, retrieve DE and BC from the stack.
        ; Put DE in HL. Both HL and BC shall be saved back on the stack.
        pop hl
        pop bc
        push bc
        push hl
        ; Argument (DE) is in HL, put C (read size) argument in B
        ld b, c
        ; Run the following loop for B - 1 (sending an ACK at the end)
        dec b
        jp z, _i2c_write_read_read_device_byte_end
_i2c_write_read_read_device_byte:
        ; Set A to 0 (ACK)
        xor a
        ; B and HL are both preserved across this function call
        call i2c_receive_byte
        ld (hl), a
        inc hl
        djnz _i2c_write_read_read_device_byte
_i2c_write_read_read_device_byte_end:
        ; Set A to 1 (NACK)
        ld a, 1
        call i2c_receive_byte
        ld (hl), a

        ; Everything went well, stop signal
        xor a
        jp _i2c_write_read_device_end
_i2c_write_read_device_address_nack:
        pop af
_i2c_write_read_device_address_nack_no_pop:
        ld a, 0xff
_i2c_write_read_device_end:
        call i2c_perform_stop
        pop de
        pop bc
        ret
