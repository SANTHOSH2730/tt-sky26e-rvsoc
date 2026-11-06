/*
 * Copyright (c) 2026 Santhosh
 * SPDX-License-Identifier: Apache-2.0
 *
 * Demo + self-test firmware for tt_um_santhosh_rvsoc.
 *
 * Pins sampled once at boot (ui_in):
 *   ui[3:2] = 00  DEMO   : banner, self-test, LED chaser on uo[7:2] driven by the
 *                          timer interrupt, "tick N" every 10 ticks, UART echo,
 *                          "IRQ0"/"IRQ1" on a rising edge of ui[0]/ui[1].
 *   ui[3:2] = 01  MIRROR : banner, GPIO self-test, then uo[7:2] = ui[7:2] forever.
 *   ui[4]   = 1   FAST   : simulation speed-up. From boot the UART runs at
 *                          2 Mbaud (UART_DIV=31) and the timer tick is 250 us.
 *                          Leave ui[4]=0 on real hardware: 115200 baud, 100 ms tick.
 *
 * Self-test lines printed (each "PASS" or "FAIL <n>"):
 *   ISA, PSRAM, TIMER, GPIO, then "SELFTEST PASS" or "SELFTEST FAIL".
 */
#include <stdint.h>
#include "rvsoc.h"

extern int isa_test(void);

/* Shared with isa_test.S: [0] trap count, [1] last mcause, [2] last mepc */
volatile uint32_t trap_info[3];
volatile uint32_t irq_count;
volatile uint32_t irq_last_cause;
volatile uint32_t tick_count;
volatile uint32_t tick_period;
volatile uint32_t ext_irq_flags;      /* bit0: ui_in[0] rising edge, bit1: ui_in[1] */

/* Freestanding helpers the compiler may call */
void *memset(void *d, int c, unsigned n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, unsigned n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }

/* ------------------------------------------------------------------ UART */
static void uart_wait_idle(void) { while (UART_STATUS & UART_STATUS_TX_BUSY) {} }
static void uart_putc(char c) { uart_wait_idle(); UART_DATA = (uint8_t)c; }
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

static void uart_putdec(uint32_t v)
{
    static const uint32_t pow10[] = {1000000000u, 100000000u, 10000000u, 1000000u,
                                     100000u, 10000u, 1000u, 100u, 10u, 1u};
    int started = 0;
    for (unsigned i = 0; i < sizeof(pow10) / sizeof(pow10[0]); i++) {
        char d = '0';
        while (v >= pow10[i]) { v -= pow10[i]; d++; }
        if (d != '0' || started || i == 9) { uart_putc(d); started = 1; }
    }
}

static int report(const char *name, int result)
{
    uart_puts(name);
    if (result == 0) {
        uart_puts(" PASS\r\n");
    } else {
        uart_puts(" FAIL ");
        uart_putdec((uint32_t)result);
        uart_puts("\r\n");
    }
    return result != 0;
}

/* ---------------------------------------------------------- trap / IRQ */
uint32_t trap_handler(uint32_t cause, uint32_t epc)
{
    trap_info[0]++;
    trap_info[1] = cause;
    trap_info[2] = epc;
    uint16_t insn = *(volatile uint16_t *)epc;      /* fetched from flash */
    return epc + (((insn & 3u) == 3u) ? 4u : 2u);   /* skip ecall/ebreak */
}

void irq_handler(uint32_t cause)
{
    irq_count++;
    irq_last_cause = cause;
    switch (cause & 0x1fu) {
    case IRQ_TIMER:
        TIMER_CMP = TIMER_CMP + tick_period;   /* writing CMP acknowledges */
        tick_count++;
        break;
    case IRQ_IN0:
        csr_clear(mip, 1u << IRQ_IN0);          /* edge interrupts are cleared in mip */
        ext_irq_flags |= 1u;
        break;
    case IRQ_IN1:
        csr_clear(mip, 1u << IRQ_IN1);
        ext_irq_flags |= 2u;
        break;
    default:
        csr_clear(mie, 1u << (cause & 0x1fu));  /* unexpected: mask it */
        break;
    }
}

/* ------------------------------------------------------------ self-tests */
#define PSRAM_A_TEST (PSRAM_A_BASE + 0x8000u)
#define PSRAM_B_TEST (PSRAM_B_BASE + 0x0100u)

static int psram_test(void)
{
    volatile uint32_t *a = (volatile uint32_t *)PSRAM_A_TEST;
    volatile uint32_t *b = (volatile uint32_t *)PSRAM_B_TEST;
    uint32_t pa = 0x12345678u, pb = 0xA5A55A5Au;
    for (int i = 0; i < 16; i++) { a[i] = pa; b[i] = pb; pa += 0x11111111u; pb ^= 0x0F0F0F0Fu; pb += 0x01010101u; }
    pa = 0x12345678u; pb = 0xA5A55A5Au;
    for (int i = 0; i < 16; i++) {
        if (a[i] != pa) return 1 + i;
        if (b[i] != pb) return 17 + i;
        pa += 0x11111111u; pb ^= 0x0F0F0F0Fu; pb += 0x01010101u;
    }
    /* byte and halfword accesses on both chips */
    volatile uint8_t  *a8  = (volatile uint8_t *)(PSRAM_A_TEST + 0x40u);
    volatile uint16_t *b16 = (volatile uint16_t *)(PSRAM_B_TEST + 0x40u);
    for (int i = 0; i < 8; i++) { a8[i] = (uint8_t)(0xC0u + i); b16[i] = (uint16_t)(0xBEE0u + i); }
    for (int i = 0; i < 8; i++) {
        if (a8[i] != (uint8_t)(0xC0u + i)) return 33 + i;
        if (b16[i] != (uint16_t)(0xBEE0u + i)) return 41 + i;
    }
    if (*(volatile uint32_t *)(PSRAM_A_TEST + 0x40u) != 0xC3C2C1C0u) return 49;
    return 0;
}

static int timer_test(void)
{
    uint32_t c0 = TIMER_COUNT;
    for (volatile int i = 0; i < 20; i++) {}
    if (TIMER_COUNT == c0) return 1;               /* counter not running */

    TIMER_COUNT = 0x100;                           /* counter is writable */
    if (TIMER_COUNT - 0x100u > 0x1000u) return 2;

    uint32_t saved_period = tick_period;
    tick_period = 2000;    /* 2000 ticks = 16000 clocks: well above the ~2400-clock ISR time (code runs from QSPI flash) */
    tick_count = 0;
    irq_count = 0;
    TIMER_CMP = TIMER_COUNT + tick_period;
    csr_set(mie, 1u << IRQ_TIMER);
    for (uint32_t t = 0; tick_count < 3; t++) {
        if (t > 200000u) break;
    }
    csr_clear(mie, 1u << IRQ_TIMER);
    tick_period = saved_period;
    if (tick_count < 3) return 3;                  /* interrupt did not fire */
    if (irq_last_cause != 0x80000013u) return 4;   /* wrong mcause */
    if (irq_count != tick_count) return 5;
    return 0;
}

static int gpio_test(void)
{
    uart_wait_idle();
    GPIO_OUT = 0xA4;
    if ((GPIO_OUT & 0xFCu) != 0xA4u) return 1;
    GPIO_OUT = 0x58;
    if ((GPIO_OUT & 0xFCu) != 0x58u) return 2;
    /* Set out0 high BEFORE handing uo[0] to GPIO, so the UART TX line never
       dips low (a low pulse would look like a start bit to the receiver). */
    GPIO_OUT = 0x5B;
    GPIO_SEL = 3;                                  /* uo[1:0] become GPIO too */
    if (GPIO_SEL != 0xFFu) return 3;
    if (GPIO_OUT != 0x5Bu) return 4;
    GPIO_OUT = 0xA5;                               /* bit 0 kept high: UART TX idles high */
    if (GPIO_OUT != 0xA5u) return 5;
    GPIO_SEL = 0;
    if (GPIO_SEL != 0xFCu) return 6;
    GPIO_OUT = 0;
    if ((GPIO_OUT & 0xFCu) != 0) return 7;
    return 0;
}

static int selftest(void)
{
    int fails = 0;
    fails += report("ISA", isa_test());
    fails += report("PSRAM", psram_test());
    fails += report("TIMER", timer_test());
    fails += report("GPIO", gpio_test());
    uart_puts(fails ? "SELFTEST FAIL\r\n" : "SELFTEST PASS\r\n");
    return fails;
}

/* ------------------------------------------------------------------ modes */
static void mirror_mode(void)
{
    report("GPIO", gpio_test());
    uart_puts("MIRROR\r\n");
    uart_wait_idle();
    for (;;) GPIO_OUT = GPIO_IN & 0xFCu;
}

static void demo_mode(void)
{
    uint32_t last = 0, pos = 0, every10 = 0;
    int dir = 1;
    tick_count = 0;
    ext_irq_flags = 0;
    TIMER_CMP = TIMER_COUNT + tick_period;
    csr_clear(mip, (1u << IRQ_IN0) | (1u << IRQ_IN1));   /* forget edges seen during boot */
    csr_set(mie, (1u << IRQ_TIMER) | (1u << IRQ_IN0) | (1u << IRQ_IN1));
    for (;;) {
        if (ext_irq_flags) {                       /* rising edge on ui_in[0] / ui_in[1] */
            uint32_t f = ext_irq_flags;
            ext_irq_flags = 0;
            if (f & 1u) uart_puts("IRQ0\r\n");
            if (f & 2u) uart_puts("IRQ1\r\n");
        }
        if (tick_count != last) {
            last = tick_count;
            GPIO_OUT = 4u << pos;                  /* LED chaser on uo[7:2] */
            if (pos == 5) dir = -1;
            if (pos == 0) dir = 1;
            pos += dir;
            if (++every10 == 10) {
                every10 = 0;
                uart_puts("tick ");
                uart_putdec(last);
                uart_puts("\r\n");
            }
        }
        if (UART_STATUS & UART_STATUS_RX_VALID) {  /* echo received characters */
            char c = (char)UART_DATA;
            uart_putc(c);
            if (c == '\r') uart_putc('\n');
        }
    }
}

int main(void)
{
    uint32_t in = GPIO_IN;
    uint32_t mode = (in >> 2) & 3u;
    int fast = (in >> 4) & 1u;

    GPIO_OUT = 0;
    if (fast) {
        UART_DIV = 31;                 /* 64 MHz / 32 = 2 Mbaud */
        tick_period = 2000;            /* 2000 x 8 clocks = 250 us */
    } else {
        tick_period = 800000;          /* 800000 x 8 clocks = 100 ms at 64 MHz */
    }
    uart_puts("Hello, TT!\r\n");

    if (mode == 1) mirror_mode();
    selftest();
    demo_mode();
    return 0;
}
