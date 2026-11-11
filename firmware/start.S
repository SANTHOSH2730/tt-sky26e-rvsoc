/*
 * Copyright (c) 2026 Santhosh and Dr. O. Vignesh
 * SPDX-License-Identifier: Apache-2.0
 *
 * Startup for tt_um_santhosh_rvsoc. TinyQV fixed vectors:
 *   0x0 reset (and double fault), 0x4 trap (ecall/ebreak), 0x8 interrupt.
 */
    .section .vectors, "ax"
    .option push
    .option norvc
    .globl _start
_start:
    j   reset_handler
    j   trap_entry
    j   irq_entry
    .option pop

    .text
reset_handler:
    la      sp, __stack_top
    la      a0, __data_load
    la      a1, __data_start
    la      a2, __data_end
1:  bgeu    a1, a2, 2f
    lw      a3, 0(a0)
    sw      a3, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    j       1b
2:  la      a1, __bss_start
    la      a2, __bss_end
3:  bgeu    a1, a2, 4f
    sw      zero, 0(a1)
    addi    a1, a1, 4
    j       3b
4:  call    main
5:  j       5b

.macro SAVE_CALLER
    addi    sp, sp, -40
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
.endm

.macro RESTORE_CALLER
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    addi    sp, sp, 40
.endm

/* uint32_t trap_handler(uint32_t mcause, uint32_t mepc) returns the resume address */
trap_entry:
    SAVE_CALLER
    csrr    a0, mcause
    csrr    a1, mepc
    call    trap_handler
    csrw    mepc, a0
    RESTORE_CALLER
    mret

/* void irq_handler(uint32_t mcause) */
irq_entry:
    SAVE_CALLER
    csrr    a0, mcause
    call    irq_handler
    RESTORE_CALLER
    mret
