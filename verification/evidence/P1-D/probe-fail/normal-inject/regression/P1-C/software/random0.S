# AUTO-GENERATED P1-C random integer program
# seed=439041101 loops=40 body=28
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li x1, 0xf18f536d
    li x2, 0xb585eced
    li x3, 0x29555e96
    li x4, 0x50564b58
    li x5, 0x5b75c2f8
    li x6, 0xb4771d9a
    li x7, 0x8048fc90
    li x8, 0x70ebfd72
    li x9, 0xcea1c897
    li x10, 0xfb8b3081
    li x11, 0x40341cf6
    li x12, 0x56e9799b
    li x13, 0x05d2d0a8
    li x14, 0x4663940e
    li x15, 0xf3c2984e
    li x16, 0xbc49a9aa
    li x17, 0x9bdd1569
    li x18, 0x45397d82
    li x19, 0x75fe7865
    li x20, 0xa7f723a4
    li x21, 0x2a09161f
    li x22, 0x42ecb9ea
    li x23, 0xbb4e15fd
    li x24, 0x88bbbfb8
    li x25, 0x93596396
    li x26, 0x1e410163
    li x27, 0xf82082c5
    li x28, 0x199e97c6
    li x29, 0x0e24650e
    li x30, 0x0e3d49c5
    li x31, 0x047620d5
    li x30, 40
.Lloop:
    or x7, x2, x8
    srai x27, x8, 30
    sra x3, x9, x8
    ori x11, x2, 1243
    add x24, x12, x20
    sltiu x4, x9, -1282
    slt x21, x4, x25
    auipc x14, 0x259cc
    srli x8, x17, 2
    ori x9, x10, -1046
    srl x29, x1, x8
    or x11, x25, x25
    slli x14, x20, 8
    lui x4, 0x02c5d
    sll x23, x8, x27
    lui x4, 0x5bbdc
    sltiu x20, x25, 1547
    auipc x16, 0xa3be3
    sltu x3, x10, x12
    xor x18, x13, x28
    add x13, x23, x14
    and x4, x28, x11
    sll x20, x3, x25
    bgeu x17, x16, .Lskip0
    sll x4, x3, x6
.Lskip0:
    sra x29, x25, x11
    sub x14, x11, x17
    andi x1, x3, 2025
    bgeu x15, x5, .Lskip1
    srl x27, x22, x25
.Lskip1:
    addi x30, x30, -1
    bne x30, x0, .Lloop
    srl x17, x14, x16
    srl x4, x22, x17
    sltiu x6, x19, 1736
    lui x27, 0x778d3
    srl x14, x8, x10
    addi x15, x10, 606
    xori x5, x1, 871
    slli x5, x11, 13
    slt x29, x19, x6
    sra x2, x13, x13
    lui x1, 0x2d82b
    srli x27, x25, 2
    slli x5, x27, 16
    or x16, x19, x8
    slti x9, x9, 1726
    and x3, x11, x5
    jal x0, end
end:
    jal x0, end
