OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

PHDRS
{
  text PT_LOAD FLAGS(5); /* R + X */
  data PT_LOAD FLAGS(6); /* R + W */
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text*)
  } > RAM :text

  .rodata : {
    *(.rodata*)
    *(.srodata*)
  } > RAM :text

  . = ALIGN(16);
  .data : {
    *(.data*)
    *(.sdata*)
  } > RAM :data

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(8);
    tohost = .;
    . += 8;
    fromhost = .;
    . += 8;
    . = ALIGN(8);
    __bss_end = .;
  } > RAM :data

  . = ALIGN(16);
  _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
}
