# AUTO-GENERATED P1-D random integer+Load/Store program
# seed=1584364171 loops=80 body=16
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li x1, 0xb5b93174
    li x2, 0x96cde651
    li x3, 0x45b4fc12
    li x4, 0x9c3275ba
    li x5, 0xec5687dc
    li x6, 0x2c94dde1
    li x7, 0x4157a050
    li x8, 0x3c55239c
    li x9, 0x40d43d83
    li x10, 0x6961b12b
    li x11, 0xd959374f
    li x12, 0xbc8ab569
    li x13, 0x6fa5f5dc
    li x14, 0xdcf514e7
    li x15, 0x2039604b
    li x16, 0x5cc43528
    li x17, 0x4ef6032b
    li x18, 0xf43e368a
    li x19, 0x27871c5c
    li x20, 0x1defd4c2
    li x21, 0x03f5c855
    li x22, 0xcf10598c
    li x23, 0x0efc890a
    li x24, 0x42ba8fd4
    li x25, 0x05eefb0f
    li x26, 0x98cef54f
    li x27, 0x81f8a252
    li x28, 0x510049c0
    li x29, 0xd4e2b776
    li x30, 0xff6226f0
    li x31, 0x9f96c213
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
    addi x20, x9, 1138
    ori x23, x16, 245
    sltu x14, x10, x19
    sra x9, x9, x4
    slli x6, x9, 12
    bge x20, x10, .Lskip0
    and x9, x5, x29
.Lskip0:
    slt x18, x7, x8
    andi x20, x23, 755
    bge x28, x20, .Lskip1
    add x25, x6, x3
.Lskip1:
    sltu x15, x3, x29
    srl x4, x27, x17
    and x28, x18, x21
    andi x26, x4, -1659
    slt x4, x25, x23
    xori x29, x12, -1225
    and x25, x4, x22
    lhu x4, 168(x31)
    sw x29, 168(x31)
    addi x30, x30, -1
    bne x30, x0, .Lloop
    slti x12, x4, -2018
    lh x6, 240(x31)
    sw x13, 32(x31)
    ori x25, x16, -1212
    lb x21, 130(x31)
    sb x28, 21(x31)
    add x24, x16, x24
    lh x24, 244(x31)
    sw x17, 196(x31)
    bge x3, x10, .Lskip2
    slt x26, x3, x16
.Lskip2:
    lbu x19, 219(x31)
    sh x8, 170(x31)
    or x19, x4, x23
    lh x13, 206(x31)
    sh x23, 192(x31)
    slti x15, x4, 837
    lbu x2, 78(x31)
    sb x21, 47(x31)
    sltiu x28, x5, -1636
    lw x8, 112(x31)
    sb x3, 41(x31)
    xori x28, x25, 873
    lhu x29, 138(x31)
    sb x25, 173(x31)
    sltu x29, x9, x7
    lhu x13, 154(x31)
    sw x22, 204(x31)
    andi x7, x14, -400
    lw x6, 244(x31)
    sh x13, 122(x31)
    addi x7, x25, 525
    lh x28, 218(x31)
    sb x3, 192(x31)
    and x17, x4, x28
    lbu x18, 39(x31)
    sb x18, 63(x31)
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
