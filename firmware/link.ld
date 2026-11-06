/* Linker script for tt_um_santhosh_rvsoc.
 * Code and constants execute in place from QSPI flash at 0x0.
 * .data/.bss/stack live in the first 64 KB of PSRAM A (the chip has 8 MB). */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    flash (rx)  : ORIGIN = 0x0000000, LENGTH = 16M
    ram   (rwx) : ORIGIN = 0x1000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        KEEP(*(.vectors))
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > flash

    .data : {
        __data_start = .;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > ram AT > flash
    __data_load = LOADADDR(.data);

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > ram

    /* TinyQV hardwires gp (x3) = 0x1000400 and tp (x4) = 0x8000000 */
    __global_pointer$ = 0x1000400;
    __stack_top = ORIGIN(ram) + LENGTH(ram);
}
