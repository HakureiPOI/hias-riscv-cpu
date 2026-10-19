# P0-01 freestanding RV32I startup.
# Contract:
#   - RAM base 0x80000000, entry _start
#   - zero .bss (which also contains tohost/fromhost)
#   - call main() with a valid stack
#   - publish the return value through the HTIF tohost word and park
#   - no libc, no OS, no compressed/M/F instructions

.section .text.init, "ax", @progbits
.globl _start
_start:
    la      sp, _stack_top

    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main

    # tohost encoding: (exit_code << 1) | 1
    la      t0, tohost
    slli    t1, a0, 1
    ori     t1, t1, 1
    sw      t1, 0(t0)
    sw      zero, 4(t0)

3:
    j       3b

.size _start, . - _start
