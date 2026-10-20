# AUTO-GENERATED P1-D random integer+Load/Store program
# seed=2618105391 loops=80 body=16
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
    beq x6, x12, .Lskip0
    add x14, x24, x20
.Lskip0:
    slt x18, x9, x5
    or x24, x23, x8
    andi x7, x23, -1300
    andi x27, x20, 1561
    xor x2, x1, x26
    xori x21, x6, 1895
    xori x6, x12, -365
    slli x1, x13, 7
    bne x7, x3, .Lskip1
    sub x29, x28, x27
.Lskip1:
    add x27, x4, x20
    bltu x27, x6, .Lskip2
    sll x3, x1, x12
.Lskip2:
    xori x25, x27, 1159
    andi x28, x19, 1579
    ori x28, x12, -197
    slli x12, x13, 12
    lhu x29, 252(x31)
    sb x22, 9(x31)
    addi x30, x30, -1
    bne x30, x0, .Lloop
    andi x23, x28, -889
    lbu x2, 156(x31)
    sh x25, 70(x31)
    or x20, x18, x10
    lhu x19, 162(x31)
    sb x6, 207(x31)
    and x24, x11, x21
    lh x29, 54(x31)
    sh x11, 244(x31)
    sltu x15, x9, x23
    lb x2, 102(x31)
    sh x20, 212(x31)
    srai x10, x11, 24
    lw x2, 216(x31)
    sw x15, 72(x31)
    ori x24, x9, -166
    lh x2, 130(x31)
    sb x18, 128(x31)
    ori x21, x10, 550
    lb x20, 196(x31)
    sh x19, 154(x31)
    andi x10, x29, 1284
    lbu x18, 211(x31)
    sb x3, 245(x31)
    or x18, x14, x16
    lh x26, 132(x31)
    sw x19, 92(x31)
    slti x29, x8, -201
    lbu x23, 175(x31)
    sw x23, 180(x31)
    sltiu x14, x19, 337
    lh x6, 190(x31)
    sh x21, 160(x31)
    and x27, x8, x13
    lbu x13, 199(x31)
    sb x24, 172(x31)
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
