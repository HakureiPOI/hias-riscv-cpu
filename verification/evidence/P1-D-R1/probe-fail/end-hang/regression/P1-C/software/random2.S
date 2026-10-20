# AUTO-GENERATED P1-C random integer program
# seed=2618105391 loops=40 body=28
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li x1, 0xc7692edf
    li x2, 0xf9a1f6e9
    li x3, 0x9121c20b
    li x4, 0x3cd82031
    li x5, 0x056dfef3
    li x6, 0xe5efac65
    li x7, 0xd9c826aa
    li x8, 0x235cc1d2
    li x9, 0x41c3e2d5
    li x10, 0x216e722a
    li x11, 0x27a8d718
    li x12, 0xb8da9663
    li x13, 0x8ca38455
    li x14, 0x6b78af52
    li x15, 0x51fc938a
    li x16, 0x5247fbad
    li x17, 0xb19e4fcd
    li x18, 0x21bca2c5
    li x19, 0x54d7490f
    li x20, 0x1c1356a8
    li x21, 0xba9b9c62
    li x22, 0x6620af63
    li x23, 0x12793e9a
    li x24, 0xbef48be0
    li x25, 0x44878b92
    li x26, 0x242faf53
    li x27, 0x77376a28
    li x28, 0xf4060519
    li x29, 0xdb3c3dcd
    li x30, 0x0c37a17f
    li x31, 0xad02c020
    li x30, 40
.Lloop:
    lui x2, 0x5dc58
    addi x14, x24, -1942
    or x9, x5, x1
    andi x23, x8, -426
    lui x3, 0xcc6c7
    srai x15, x7, 21
    add x26, x18, x13
    slli x16, x29, 27
    slti x12, x23, -365
    slli x1, x13, 7
    auipc x29, 0x46cf2
    sub x3, x29, x28
    add x27, x4, x20
    srai x27, x6, 11
    add x12, x28, x12
    xori x17, x27, 1579
    ori x28, x12, -197
    slli x12, x13, 12
    srli x4, x22, 1
    andi x23, x28, -889
    addi x23, x10, 235
    bne x5, x17, .Lskip0
    and x18, x10, x18
.Lskip0:
    andi x26, x29, 548
    sll x13, x6, x28
    srai x11, x21, 15
    srl x11, x16, x7
    sra x9, x23, x2
    slt x25, x16, x20
    addi x30, x30, -1
    bne x30, x0, .Lloop
    ori x25, x22, 493
    xori x10, x2, 1412
    xori x5, x14, 87
    sll x2, x22, x9
    or x9, x12, x17
    srli x19, x27, 20
    and x13, x9, x19
    sra x22, x10, x29
    xori x18, x14, -139
    sra x6, x26, x27
    ori x14, x16, -654
    blt x18, x19, .Lskip1
    sll x12, x6, x29
.Lskip1:
    slt x16, x23, x11
    bgeu x23, x12, .Lskip2
    srl x10, x14, x19
.Lskip2:
    sll x6, x12, x12
    srli x6, x21, 15
    jal x0, end
end:
    jal x0, end
