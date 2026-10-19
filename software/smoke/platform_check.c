/* P0-02 compile-time platform consistency check.
 *
 * Includes the generated platform header and verifies the values the smoke
 * program relies on. This is a build-time check, not a CPU feature test.
 */

#include "../generated/platform.h"

#define STATIC_ASSERT(cond, name) typedef char static_assert_##name[(cond) ? 1 : -1]

STATIC_ASSERT(PLATFORM_XLEN == 32, xlen_is_32);
STATIC_ASSERT(PLATFORM_VA_BITS == 32, va_is_32);
STATIC_ASSERT(PLATFORM_PA_BITS == 34, pa_is_34);
STATIC_ASSERT(PLATFORM_RAM_BASE == PLATFORM_RESET_VECTOR, reset_at_ram_base);
STATIC_ASSERT((PLATFORM_RAM_BASE & 0xfffu) == 0, ram_base_aligned);
STATIC_ASSERT((PLATFORM_RAM_SIZE & 0xfffu) == 0, ram_size_aligned);
STATIC_ASSERT(PLATFORM_RAM_END == PLATFORM_RAM_BASE + PLATFORM_RAM_SIZE,
              ram_end_consistent);
STATIC_ASSERT(PLATFORM_MMIO_UART0_BASE >= PLATFORM_RAM_END ||
              PLATFORM_MMIO_UART0_BASE + PLATFORM_MMIO_UART0_SIZE <= PLATFORM_RAM_BASE,
              uart_outside_ram);
STATIC_ASSERT(PLATFORM_MMIO_TEST_RESULT_BASE >= PLATFORM_RAM_END ||
              PLATFORM_MMIO_TEST_RESULT_BASE + PLATFORM_MMIO_TEST_RESULT_SIZE <= PLATFORM_RAM_BASE,
              test_result_outside_ram);
STATIC_ASSERT(PLATFORM_PAGE_TABLE_END == PLATFORM_PAGE_TABLE_BASE + PLATFORM_PAGE_TABLE_RESERVE,
              page_table_end_consistent);
STATIC_ASSERT(PLATFORM_PAGE_TABLE_BASE == 0x8001a000u, page_table_base_frozen);
STATIC_ASSERT(PLATFORM_PAGE_TABLE_END == 0x8001e000u, page_table_end_frozen);
STATIC_ASSERT(PLATFORM_LAYOUT_GAP_START == PLATFORM_PAGE_TABLE_END, layout_gap_start_frozen);
STATIC_ASSERT(PLATFORM_LAYOUT_GAP_END == PLATFORM_STACK_LIMIT, layout_gap_end_frozen);

/* Keep a symbol so the object is non-empty and actually linked. */
const unsigned int platform_check_signature = PLATFORM_RAM_BASE;
