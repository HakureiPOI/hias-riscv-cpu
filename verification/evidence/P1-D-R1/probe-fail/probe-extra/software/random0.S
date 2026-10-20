# AUTO-GENERATED P1-D random integer+Load/Store program
# seed=439041101 loops=80 body=16
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
    li x31, 0x80018000
    li x30, 64
    li x5, 0x10203040
.Linit:
    sw x5, 0(x31)
    addi x5, x5, 0x111
    addi x31, x31, 4
    addi x30, x30, -1
    bne x30, x0, .Linit
    li x31, 0x80018000
    li x30, 80
.Lloop:
    or x7, x2, x8
    bltu x27, x8, .Lskip0
    sra x1, x15, x3
.Lskip0:
    slt x27, x18, x29
    sltiu x2, x27, 1243
    add x24, x12, x20
    sltiu x4, x9, -1282
    slt x21, x4, x25
    bge x3, x22, .Lskip1
    xor x8, x17, x23
.Lskip1:
    srl x18, x9, x10
    sltu x14, x29, x1
    sll x24, x18, x11
    bltu x6, x14, .Lskip2
    and x5, x24, x4
.Lskip2:
    sltu x24, x6, x23
    sub x6, x17, x12
    srli x24, x16, 20
    sltu x3, x10, x12
    lh x12, 206(x31)
    sh x2, 202(x31)
    addi x30, x30, -1
    bne x30, x0, .Lloop
    bge x7, x19, .Lskip3
    sub x28, x11, x1
.Lskip3:
    lh x20, 40(x31)
    sw x17, 240(x31)
    sub x3, x6, x6
    lbu x29, 164(x31)
    sb x27, 61(x31)
    sltiu x17, x14, -1962
    lb x16, 224(x31)
    sb x22, 204(x31)
    blt x21, x14, .Lskip4
    or x14, x16, x7
.Lskip4:
    lbu x4, 152(x31)
    sb x19, 236(x31)
    bne x4, x24, .Lskip5
    srl x14, x8, x10
.Lskip5:
    lhu x4, 228(x31)
    sh x27, 164(x31)
    xori x5, x1, 871
    lh x5, 168(x31)
    sb x26, 60(x31)
    bne x29, x19, .Lskip6
    sll x9, x16, x2
.Lskip6:
    lbu x13, 8(x31)
    sw x3, 156(x31)
    beq x22, x4, .Lskip7
    sll x27, x22, x9
.Lskip7:
    lw x18, 240(x31)
    sw x8, 108(x31)
    sltu x19, x15, x29
    lw x19, 40(x31)
    sh x5, 152(x31)
    andi x6, x8, -116
    lh x5, 20(x31)
    sb x3, 119(x31)
    bgeu x28, x12, .Lskip8
    slt x29, x26, x27
.Lskip8:
    lh x6, 2(x31)
    sb x15, 26(x31)
    slli x14, x2, 23
    lhu x21, 66(x31)
    sb x13, 232(x31)
    li x31, 0x80018000
    lw x1, 0(x31)
    lw x2, 4(x31)
    lw x3, 8(x31)
    lw x4, 12(x31)
    lw x5, 16(x31)
    lw x6, 20(x31)
    lw x7, 24(x31)
    lw x8, 28(x31)
    lw x9, 32(x31)
    lw x10, 36(x31)
    lw x11, 40(x31)
    lw x12, 44(x31)
    lw x13, 48(x31)
    lw x14, 52(x31)
    lw x15, 56(x31)
    lw x16, 60(x31)
end:
    jal x0, end
