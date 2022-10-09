; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    IFNDEF SYS_TABLE_H
    DEFINE SYS_TABLE_H

    ; The system table contains a lsit of all the systems that can be booted
    ; from the bootloader.
    ; It is organized as follows:
    DEFVARS 0 {
        sys_name_t          DS.B 32  ; System/OS name, filled with \0 when smaller than 32
        sys_phys_addr_t     DS.B 3   ; System/OS 24-bit physical address (aligned on 16KB)
        sys_virt_addr_t     DS.B 2   ; System/OS entry address
        sys_flags_t         DS.B 1   ; Future use?
        sys_end_t           DS.B 0 
    }

    ; Length of the names in the table
    DEFC SYS_NAME_MAX_LENGTH = sys_phys_addr_t - sys_name_t
    ; Size of a single entry in the table
    DEFC SYS_TABLE_ENTRY_SIZE  = sys_end_t
    ; Maximum 7 entries
    DEFC SYS_TABLE_ENTRY_COUNT = 7
    ; Size of the whole table
    DEFC SYS_TABLE_SIZE = SYS_TABLE_ENTRY_COUNT * SYS_TABLE_ENTRY_SIZE


    ; Public routines
    EXTERN sys_table_init
    EXTERN sys_table_get_first
    EXTERN sys_table_boot_entry
    EXTERN sys_table_delete
    EXTERN sys_table_add_entry
    EXTERN sys_table_ram
    EXTERN sys_table_save_flash
    EXTERN sys_boot_from_ram

    ENDIF