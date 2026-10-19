OUTPUT_ARCH(riscv)
ENTRY(_start)

/* Platform constants come from config/platform.json via
 * software/generated/platform.ld. Regenerate with:
 *   python3 scripts/gen_platform.py
 */
INCLUDE software/generated/platform.ld

MEMORY
{
  RAM (rwx) : ORIGIN = PLATFORM_RAM_BASE, LENGTH = PLATFORM_RAM_SIZE
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

  /* Reserved regions are computed by the platform generator and checked here.
   * Code/data must end before the signature reserve; the stack grows down from
   * PLATFORM_STACK_TOP. */
  _stack_top = PLATFORM_STACK_TOP;
  __stack_limit = PLATFORM_STACK_LIMIT;
  __signature_start = PLATFORM_SIGNATURE_BASE;
  __signature_end = PLATFORM_PAGE_TABLE_BASE;
  __page_table_start = PLATFORM_PAGE_TABLE_BASE;
  __page_table_end = PLATFORM_PAGE_TABLE_END;
  __layout_gap_start = PLATFORM_LAYOUT_GAP_START;
  __layout_gap_end = PLATFORM_LAYOUT_GAP_END;

  ASSERT(__bss_end <= __signature_start,
         "platform config: program/data overlaps signature reserve")
  ASSERT(__signature_end <= __page_table_start,
         "platform config: signature reserve overlaps page tables")
  ASSERT((__page_table_end - __page_table_start) == PLATFORM_PAGE_TABLE_RESERVE,
         "platform config: page table size does not match reserve")
  ASSERT(__page_table_start % 4096 == 0,
         "platform config: page table base not 4 KiB aligned")
  ASSERT(__page_table_end == PLATFORM_LAYOUT_GAP_START,
         "platform config: page table end does not match layout gap")
  ASSERT(__layout_gap_end == __stack_limit,
         "platform config: layout gap does not meet stack limit")
  ASSERT(__page_table_end <= __stack_limit,
         "platform config: page tables overlap stack reserve")
  ASSERT(__stack_limit >= PLATFORM_RAM_BASE,
         "platform config: stack reserve exceeds RAM")
  ASSERT(ADDR(.text) == PLATFORM_RESET_VECTOR,
         "platform config: reset vector must be the start of .text")
}
