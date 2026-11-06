/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * Register map of tt_um_santhosh_rvsoc (TinyQV-based RV32EC SoC).
 */
#ifndef RVSOC_H
#define RVSOC_H

#include <stdint.h>

#define REG32(a) (*(volatile uint32_t *)(a))

/* Memory map */
#define FLASH_BASE   0x0000000u   /* 16 MB QSPI flash, execute in place */
#define PSRAM_A_BASE 0x1000000u   /*  8 MB QSPI PSRAM A */
#define PSRAM_B_BASE 0x1800000u   /*  8 MB QSPI PSRAM B */
#define PERI_BASE    0x8000000u

/* Peripherals (all word registers) */
#define GPIO_OUT     REG32(PERI_BASE + 0x00)  /* R/W: uo_out (read returns the pins) */
#define GPIO_IN      REG32(PERI_BASE + 0x04)  /* R:   ui_in */
#define GPIO_SEL     REG32(PERI_BASE + 0x0C)  /* R/W: bit0/1 = uo[0]/uo[1] driven by GPIO_OUT instead of UART TX/RTS */
#define UART_DATA    REG32(PERI_BASE + 0x10)  /* W: transmit byte, R: received byte */
#define UART_STATUS  REG32(PERI_BASE + 0x14)  /* R: bit0 TX busy, bit1 RX byte valid */
#define TIMER_COUNT  REG32(PERI_BASE + 0x28)  /* R/W: 32-bit counter, +1 every 8 clocks */
#define TIMER_CMP    REG32(PERI_BASE + 0x2C)  /* R/W: compare; IRQ while COUNT==CMP, cleared by writing CMP */
#define UART_DIV     REG32(PERI_BASE + 0x34)  /* R/W: clocks per UART bit - 1 (13 bits), reset 555 = 115200 @ 64 MHz */

#define UART_STATUS_TX_BUSY  1u
#define UART_STATUS_RX_VALID 2u

/* Interrupts: mcause = 0x80000010 + n, enable bit (16 + n) in mie */
#define IRQ_IN0    16   /* rising edge on ui_in[0] */
#define IRQ_IN1    17   /* rising edge on ui_in[1] */
#define IRQ_UART   18   /* UART byte received (level) */
#define IRQ_TIMER  19   /* timer compare (level, cleared by writing TIMER_CMP) */

#define csr_read(csr) ({ uint32_t __v; __asm__ volatile ("csrr %0, " #csr : "=r"(__v)); __v; })
#define csr_set(csr, v)   __asm__ volatile ("csrs " #csr ", %0" :: "r"(v))
#define csr_clear(csr, v) __asm__ volatile ("csrc " #csr ", %0" :: "r"(v))

#endif
