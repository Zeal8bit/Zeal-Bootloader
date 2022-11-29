; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    IFNDEF MMU_MACROS
    DEFINE MMU_MACROS

    ; MMU Pages
    DEFC MMU_PAGE_0 = 0xF0
    DEFC MMU_PAGE_1 = 0xF1
    DEFC MMU_PAGE_2 = 0xF2
    DEFC MMU_PAGE_3 = 0xF3

    ; Virtual Pages Addresses
    DEFC PAGE0_VIRT_ADDR = 0x0000
    DEFC PAGE1_VIRT_ADDR = 0x4000
    DEFC PAGE2_VIRT_ADDR = 0x8000
    DEFC PAGE3_VIRT_ADDR = 0xC000

    MACRO MAP_PHYS_ADDR page, address
        ld a, address >> 14
        out (page), a
    ENDM

    MACRO MMU_GET_PAGE_NUMBER page
        ASSERT(page >= MMU_PAGE_0 && page <= MMU_PAGE_3)
        ld a, page << 6 & 0xff
        in a, (page)
    ENDM

    MACRO MMU_SET_PAGE_NUMBER page
        ASSERT(page >= MMU_PAGE_0 && page <= MMU_PAGE_3)
        out (page), a
    ENDM

    ENDIF