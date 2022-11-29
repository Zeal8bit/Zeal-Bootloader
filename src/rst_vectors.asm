; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

        SECTION RST_VECTORS
        ORG 0

        EXTERN bootloader_entry

rst_vector_0:
        di
        jp bootloader_entry
        ; 4 random bytes
        DEFM 0x42, 0x7d, 0xb1, 0xaa
rst_vector_8:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_10:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_18:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_20:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_28:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_30:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
rst_vector_38:
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop

        ; Make the BOOTLOADER section follow this one directly
        SECTION BOOTLOADER


        SECTION INT_HANDLERS
        ALIGN 256

        EXTERN default_handler

        PUBLIC int_handlers_table
int_handlers_table:
        DEFW default_handler
        DEFW default_handler

        ; Section containing the list of systems registered that we can boot
        ; It must be aligned on 4KB as the SST39SF0x0 NOR Flashes can only erase
        ; sectors of 4KB.
        ; Thus the sections above (code) must not be bigger than 4KB. If more space
        ; is needed, move this section further and adapt the code.
        SECTION SYS_TABLE
        ORG 0x2000