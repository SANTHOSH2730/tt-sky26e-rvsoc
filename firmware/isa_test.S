/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-checking instruction test for the supported ISA (RV32E + C + Zicsr +
 * trap/mret), in the style of riscv-tests.
 *
 *   int isa_test(void);   returns 0 on pass, else the number of the first
 *                         failing test (see the numbers below).
 *
 * Only x0..x15 exist (RV32E). TinyQV hardwires gp (x3) and tp (x4), so they
 * are never used as scratch registers here.
 */

    .globl isa_test

.macro CHECK r, e
    beq     \r, \e, 9f
    j       isa_fail
9:
.endm

/* Expected values are always built with 32-bit (uncompressed) instructions */
.macro EXP reg, val
    .option push
    .option norvc
    li      \reg, \val
    .option pop
.endm

.macro TEST_RR n, op, v1, v2, exp
    li      a0, \n
    EXP     t0, \v1
    EXP     t1, \v2
    \op     t2, t0, t1
    EXP     a1, \exp
    CHECK   t2, a1
.endm

.macro TEST_RI n, op, v1, imm, exp
    li      a0, \n
    EXP     t0, \v1
    \op     t2, t0, \imm
    EXP     a1, \exp
    CHECK   t2, a1
.endm

.macro TEST_BR n, op, v1, v2, taken
    li      a0, \n
    EXP     t0, \v1
    EXP     t1, \v2
    \op     t0, t1, 8f
    .if \taken
    j       isa_fail
    .else
    j       7f
    .endif
8:
    .if \taken == 0
    j       isa_fail
    .endif
7:
.endm

/* rd = absolute address of a code label (no auipc involved) */
.macro ADDR reg, label
    .option push
    .option norvc
    lui     \reg, %hi(\label)
    addi    \reg, \reg, %lo(\label)
    .option pop
.endm

    .text
    .align 2
isa_test:
    .option push
    .option norvc
    addi    sp, sp, -32
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    csrci   mstatus, 8              /* no interrupts during the test */

    /* ---- RV32E register-register ---- */
    TEST_RR  1, add,  0x12345678, 0x11111111, 0x23456789
    TEST_RR  2, sub,  5, 7, 0xFFFFFFFE
    TEST_RR  3, sll,  3, 35, 0x18
    TEST_RR  4, slt,  -1, 1, 1
    TEST_RR  5, sltu, -1, 1, 0
    TEST_RR  6, xor,  0xFF00FF00, 0x0F0F0F0F, 0xF00FF00F
    TEST_RR  7, srl,  0x80000000, 4, 0x08000000
    TEST_RR  8, sra,  0x80000000, 4, 0xF8000000
    TEST_RR  9, or,   0xF0F00000, 0x0000F0F0, 0xF0F0F0F0
    TEST_RR 10, and,  0xFF00FF00, 0x0F0F0F0F, 0x0F000F00

    /* ---- RV32E register-immediate ---- */
    TEST_RI 11, addi,  0x7FFFFFFF, 1, 0x80000000
    TEST_RI 12, slti,  -5, -4, 1
    TEST_RI 13, sltiu, 5, -1, 1
    TEST_RI 14, xori,  0x00FF00FF, -1, 0xFF00FF00
    TEST_RI 15, ori,   0x12340000, 0x7FF, 0x123407FF
    TEST_RI 16, andi,  0x12345678, 0x0F0, 0x070
    TEST_RI 17, slli,  1, 31, 0x80000000
    TEST_RI 18, srli,  0xF0000000, 28, 0xF
    TEST_RI 19, srai,  0xF0000000, 28, 0xFFFFFFFF

    /* ---- LUI / AUIPC ---- */
    li      a0, 20
    lui     t2, 0xABCDE
    EXP     a1, 0xABCDE000
    CHECK   t2, a1
    li      a0, 21
1:  auipc   t2, 0
    ADDR    a1, 1b
    CHECK   t2, a1
    li      a0, 22
1:  auipc   t2, 1
    ADDR    a1, (1b + 0x1000)
    CHECK   t2, a1

    /* ---- Branches ---- */
    TEST_BR 23, beq,  5, 5, 1
    TEST_BR 24, bne,  5, 6, 1
    TEST_BR 25, blt,  -1, 0, 1
    TEST_BR 26, bge,  0, -1, 1
    TEST_BR 27, bltu, 0, -1, 1
    TEST_BR 28, bgeu, -1, 0, 1
    TEST_BR 29, beq,  5, 6, 0
    TEST_BR 30, bne,  5, 5, 0
    TEST_BR 31, blt,  0, -1, 0
    TEST_BR 32, bge,  -1, 0, 0
    TEST_BR 33, bltu, -1, 0, 0
    TEST_BR 34, bgeu, 0, -1, 0
    TEST_BR 35, bge,  3, 3, 1
    TEST_BR 36, bgeu, 3, 3, 1

    /* ---- JAL / JALR ---- */
    li      a0, 37
    jal     t0, 1f
2:  j       isa_fail
1:  ADDR    a1, 2b
    CHECK   t0, a1
    li      a0, 38
    ADDR    t1, 1f
    jalr    t0, 0(t1)
2:  j       isa_fail
1:  ADDR    a1, 2b
    CHECK   t0, a1
    li      a0, 39                  /* jalr clears bit 0 of the target */
    ADDR    t1, 1f
    jalr    t0, 1(t1)
    j       isa_fail
1:

    /* ---- Loads and stores (PSRAM) ---- */
    la      s0, isa_buf
    li      a0, 40
    EXP     t0, 0x11223344
    sw      t0, 0(s0)
    lw      t2, 0(s0)
    CHECK   t2, t0
    li      a0, 41
    lbu     t2, 0(s0)
    EXP     a1, 0x44
    CHECK   t2, a1
    lbu     t2, 3(s0)
    EXP     a1, 0x11
    CHECK   t2, a1
    li      a0, 42
    EXP     t0, 0x80
    sb      t0, 4(s0)
    lb      t2, 4(s0)
    EXP     a1, 0xFFFFFF80
    CHECK   t2, a1
    lbu     t2, 4(s0)
    EXP     a1, 0x80
    CHECK   t2, a1
    li      a0, 43
    EXP     t0, 0xFFFF8001
    sh      t0, 6(s0)
    lh      t2, 6(s0)
    CHECK   t2, t0
    lhu     t2, 6(s0)
    EXP     a1, 0x8001
    CHECK   t2, a1
    li      a0, 44
    EXP     t0, 0x11223344
    sw      t0, 8(s0)
    EXP     t1, 0xAA
    sb      t1, 9(s0)
    lw      t2, 8(s0)
    EXP     a1, 0x1122AA44
    CHECK   t2, a1
    li      a0, 45
    sw      t0, 12(s0)
    EXP     t1, 0xBEEF
    sh      t1, 14(s0)
    lw      t2, 12(s0)
    EXP     a1, 0xBEEF3344
    CHECK   t2, a1
    li      a0, 46                  /* negative offsets */
    addi    s1, s0, 32
    EXP     t0, 0x5A5AA5A5
    sw      t0, -4(s1)
    lw      t2, -4(s1)
    CHECK   t2, t0
    li      a0, 47                  /* data reads from flash */
    la      t1, isa_const
    lw      t2, 0(t1)
    EXP     a1, 0xCAFEF00D
    CHECK   t2, a1
    lh      t2, 2(t1)
    EXP     a1, 0xFFFFCAFE
    CHECK   t2, a1
    lbu     t2, 1(t1)
    EXP     a1, 0xF0
    CHECK   t2, a1

    /* ---- FENCE, x0, hardwired gp/tp ---- */
    li      a0, 48
    EXP     t0, 48
    fence
    CHECK   a0, t0
    li      a0, 49
    addi    x0, x0, 5
    CHECK   x0, zero
    li      a0, 50
    EXP     a1, 0x1000400
    CHECK   gp, a1
    EXP     a1, 0x8000000
    CHECK   tp, a1

    /* ---- Zicsr ---- */
    li      a0, 51                  /* csrrw / csrr on mepc */
    EXP     t1, 0x123456
    csrrw   t0, mepc, t1
    csrr    t2, mepc
    CHECK   t2, t1
    li      a0, 52                  /* csrrs on mie */
    csrw    mie, zero
    EXP     t1, 0x30000
    csrrs   t0, mie, t1
    CHECK   t0, zero
    csrr    t2, mie
    CHECK   t2, t1
    li      a0, 53                  /* csrrc on mie */
    EXP     t1, 0x10000
    csrrc   t0, mie, t1
    EXP     a1, 0x30000
    CHECK   t0, a1
    csrr    t2, mie
    EXP     a1, 0x20000
    CHECK   t2, a1
    csrw    mie, zero
    li      a0, 54                  /* csrrsi / csrrci / csrrwi on mstatus.MIE */
    EXP     a1, 8
    csrrsi  zero, mstatus, 8
    csrr    t2, mstatus
    andi    t2, t2, 8
    CHECK   t2, a1
    csrrci  t0, mstatus, 8
    andi    t0, t0, 8
    CHECK   t0, a1
    csrr    t2, mstatus
    andi    t2, t2, 8
    CHECK   t2, zero
    csrrwi  t0, mstatus, 8
    andi    t0, t0, 8
    CHECK   t0, zero
    csrr    t2, mstatus
    andi    t2, t2, 8
    CHECK   t2, a1
    csrrwi  zero, mstatus, 0
    li      a0, 55                  /* misa = RV32 + C + E */
    csrr    t2, misa
    EXP     a1, 0x40000014
    CHECK   t2, a1

    /* ---- Traps: ecall / ebreak / mret, mcause, mepc ---- */
    la      s1, trap_info
    li      a0, 56
    lw      t0, 0(s1)
1:  ecall
    lw      t1, 0(s1)
    addi    t0, t0, 1
    CHECK   t1, t0
    lw      t2, 4(s1)               /* trap_cause */
    EXP     a1, 11
    CHECK   t2, a1
    lw      t2, 8(s1)               /* trap_epc */
    ADDR    a1, 1b
    CHECK   t2, a1
    li      a0, 57
    lw      t0, 0(s1)
    ebreak
    lw      t1, 0(s1)
    addi    t0, t0, 1
    CHECK   t1, t0
    lw      t2, 4(s1)
    EXP     a1, 3
    CHECK   t2, a1

    /* Zicntr (rdcycle/rdtime/rdinstret) is not implemented in this SoC (area). */
    .option pop

    /* ---- C extension (RV32EC) ---- */
    .option push
    .option rvc
    li      a0, 70
    c.li    a1, -7
    EXP     a2, -7
    CHECK   a1, a2
    li      a0, 71
    EXP     a1, 100
    c.addi  a1, -3
    EXP     a2, 97
    CHECK   a1, a2
    li      a0, 72
    c.lui   a1, 0x1f
    EXP     a2, 0x1F000
    CHECK   a1, a2
    c.lui   a1, 0xfffe0
    EXP     a2, 0xFFFE0000
    CHECK   a1, a2
    li      a0, 73
    EXP     a1, 0x12345678
    c.mv    a2, a1
    CHECK   a2, a1
    li      a0, 74
    EXP     a1, 0x10000
    EXP     a2, 0x234
    c.add   a1, a2
    EXP     a3, 0x10234
    CHECK   a1, a3
    li      a0, 75
    EXP     s0, 10
    EXP     s1, 3
    c.sub   s0, s1
    EXP     a1, 7
    CHECK   s0, a1
    li      a0, 76
    EXP     s0, 0xF0F0
    EXP     s1, 0xFF00
    c.xor   s0, s1
    EXP     a1, 0x0FF0
    CHECK   s0, a1
    li      a0, 77
    EXP     s0, 0xF000
    EXP     s1, 0x000F
    c.or    s0, s1
    EXP     a1, 0xF00F
    CHECK   s0, a1
    li      a0, 78
    EXP     s0, 0xF0F0
    EXP     s1, 0xFF00
    c.and   s0, s1
    EXP     a1, 0xF000
    CHECK   s0, a1
    li      a0, 79
    EXP     s0, 0x1234
    c.andi  s0, 15
    EXP     a1, 4
    CHECK   s0, a1
    EXP     s0, 0x1234
    c.andi  s0, -16
    EXP     a1, 0x1230
    CHECK   s0, a1
    li      a0, 80
    EXP     a1, 3
    c.slli  a1, 4
    EXP     a2, 0x30
    CHECK   a1, a2
    li      a0, 81
    EXP     s0, 0x80000000
    c.srli  s0, 31
    EXP     a1, 1
    CHECK   s0, a1
    li      a0, 82
    EXP     s0, 0x80000000
    c.srai  s0, 31
    EXP     a1, 0xFFFFFFFF
    CHECK   s0, a1
    li      a0, 83
    .option push
    .option norvc
    addi    t0, sp, 0
    addi    t1, sp, -64
    .option pop
    c.addi16sp sp, -64
    CHECK   sp, t1
    c.addi16sp sp, 64
    CHECK   sp, t0
    li      a0, 84
    c.addi4spn s0, sp, 8
    .option push
    .option norvc
    addi    t1, sp, 8
    .option pop
    CHECK   s0, t1
    li      a0, 85
    la      s1, isa_buf
    EXP     a1, 0xDEADBEEF
    c.sw    a1, 16(s1)
    c.lw    a2, 16(s1)
    CHECK   a2, a1
    li      a0, 86
    EXP     a1, 0x0BADF00D
    c.swsp  a1, 16(sp)
    c.lwsp  a3, 16(sp)
    CHECK   a3, a1
    li      a0, 87
    EXP     s0, 0
    c.beqz  s0, 1f
    j       isa_fail
1:  EXP     s0, 1
    c.beqz  s0, 2f
    j       3f
2:  j       isa_fail
3:  li      a0, 88
    EXP     s0, 1
    c.bnez  s0, 1f
    j       isa_fail
1:  EXP     s0, 0
    c.bnez  s0, 2f
    j       3f
2:  j       isa_fail
3:  li      a0, 89
    c.j     1f
    j       isa_fail
1:  li      a0, 90
    c.jal   1f
2:  j       isa_fail
1:  ADDR    a1, 2b
    CHECK   ra, a1
    li      a0, 91
    ADDR    t0, 1f
    c.jr    t0
    j       isa_fail
1:  li      a0, 92
    ADDR    t0, 1f
    c.jalr  t0
2:  j       isa_fail
1:  ADDR    a1, 2b
    CHECK   ra, a1
    li      a0, 93
    c.nop
    li      a0, 94
    la      s1, trap_info
    lw      t0, 0(s1)
    c.ebreak
    lw      t1, 0(s1)
    addi    t0, t0, 1
    CHECK   t1, t0
    lw      t2, 4(s1)
    EXP     a1, 3
    CHECK   t2, a1
    .option pop

    li      a0, 0                   /* all passed */
isa_fail:
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    addi    sp, sp, 32
    csrsi   mstatus, 8
    ret

    .section .rodata
    .align 2
isa_const:
    .word   0xCAFEF00D

    .bss
    .align 2
isa_buf:
    .space  32
