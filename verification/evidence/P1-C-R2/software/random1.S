# AUTO-GENERATED P1-C random integer program
# seed=1584364171 loops=40 body=28
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
    li x30, 40
.Lloop:
    sub x20, x9, x13
    ori x23, x16, 245
    sltu x14, x10, x19
    sra x9, x9, x4
    slli x6, x9, 12
    srli x20, x10, 17
    sub x8, x18, x7
    srl x22, x20, x23
    lui x25, 0xaf3d7
    srli x28, x20, 1
    auipc x6, 0x2a6b2
    sltu x15, x3, x29
    srl x4, x27, x17
    and x28, x18, x21
    andi x26, x4, -1659
    slt x4, x25, x23
    xori x29, x12, -1225
    and x25, x4, x22
    addi x11, x17, 662
    slti x12, x4, -2018
    sll x16, x29, x17
    addi x14, x25, 1882
    sub x21, x9, x6
    addi x5, x29, -1649
    auipc x16, 0x427c6
    auipc x16, 0xc5505
    lui x27, 0xe0952
    sltu x29, x21, x28
    addi x30, x30, -1
    bne x30, x0, .Lloop
    sub x16, x16, x19
    xori x8, x19, 688
    or x19, x4, x23
    srl x13, x9, x23
    xori x14, x29, -859
    addi x12, x29, 1514
    and x28, x24, x19
    slt x21, x3, x18
    slti x25, x2, 797
    slt x7, x3, x3
    xori x28, x25, 873
    sltiu x6, x25, 723
    sltu x29, x9, x7
    srli x10, x17, 25
    andi x7, x14, -400
    sll x18, x29, x19
    jal x0, end
end:
    jal x0, end
