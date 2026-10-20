# P1-C directed integer/control subset. No loads, stores, CSR, M/A/C/F, or
# compressed instructions. Every architectural register used for final
# comparison is initialized explicitly. `end` is the DUT/Spike endpoint.
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li x1, 0x12345678
    li x2, 0x80000000
    li x3, 0x7fffffff
    li x4, -1
    li x5, 0
    li x6, 1
    li x7, 31
    li x8, -2048
    li x9, 2047
    li x10, 0x55555555
    li x11, 0xaaaaaaa
    li x12, 0x0000000f
    li x13, 0xfffffff0
    li x14, 0x1000
    li x15, 0x100
    li x16, 0x80000000
    li x17, 7
    li x18, 3
    li x19, -7
    li x20, -3
    li x21, 0xffff
    li x22, 0x8000
    li x23, 0x7fff
    li x24, 0xdeadbeef
    li x25, 0x12345678
    li x26, 0x0f0f0f0f
    li x27, 0xf0f0f0f0
    li x28, 0x7fffffff
    li x29, 0x80000000
    li x30, 6
    li x31, 0x55

# Bounded backward branch loop and RAW/WAW.
.Lloop:
    addi x5, x5, 3
    xor  x6, x6, x5
    addi x30, x30, -1
    bne  x30, x0, .Lloop

    add  x1, x5, x6
    sub  x2, x5, x6
    sll  x3, x5, x17
    slt  x4, x19, x20
    sltu x5, x19, x20
    xor  x6, x10, x11
    srl  x7, x24, x18
    sra  x8, x24, x18
    or   x9, x10, x11
    and  x10, x10, x11

    addi  x11, x11, -2048
    slti  x12, x19, -3
    sltiu x13, x19, -3
    xori  x14, x14, 0x7ff
    ori   x15, x15, 0x700
    andi  x16, x16, 0xff
    slli  x17, x17, 31
    srli  x18, x24, 0
    srai  x19, x24, 31
    lui   x21, 0xabcde
    auipc x22, 0x1

    addi x23, x1, 1
    add  x23, x23, x23
    addi x0, x23, 99

    li x24, 5
    li x25, 5
    beq  x24, x25, .Lb1
    addi x26, x26, 0x111
.Lb1:
    bne  x24, x25, .Lbad
    addi x26, x26, 1
    blt  x19, x20, .Lb2
    addi x26, x26, 0x222
.Lb2:
    bge  x20, x19, .Lb3
    addi x26, x26, 0x333
.Lb3:
    li   x27, 0xffffffff
    li   x28, 1
    bltu x28, x27, .Lb4
    addi x26, x26, 0x444
.Lb4:
    bgeu x27, x28, .Lb5
    addi x26, x26, 0x555
.Lb5:
    beq  x0, x0, .Lb6
    addi x26, x26, 0x666
.Lb6:
    bne  x0, x0, .Lbad
    # Taken-vs-untaken alignment distinction: this +6 target is not taken.
    beq  x0, x1, . + 6

    # Taken BLT/BGE anchors with x31=0x55 and x20=-3.
    blt  x20, x31, .Lbt1
    addi x26, x26, 0x7f
.Lbt1:
    bge  x31, x20, .Lbt2
    addi x26, x26, 0x7f
.Lbt2:

    # Untaken direction matrix after x19 was changed to -1 by SRAI.
    blt  x19, x20, .Lbad       # -1 < -3 is false
    bge  x20, x19, .Lbad       # -3 >= -1 is false
    bltu x27, x28, .Lbad       # 0xffffffff < 1 is false
    bgeu x28, x27, .Lbad       # 1 >= 0xffffffff is false

    jal  x1, .Ljal1
    addi x26, x26, 0x777
.Ljal1:
    jal  x0, .Ljal2
    addi x26, x26, 0x88
.Ljal2:
    la   x2, .Ljalr1
    jalr x2, x2, 0
    addi x26, x26, 0x99
.Ljalr1:
    la   x3, .Ljalr2
    addi x3, x3, 1
    jalr x4, x3, 0
    addi x26, x26, 0xaa
.Ljalr2:
    jal  x5, .Ljal3
    addi x26, x26, 0xbb
.Ljal3:
    j    end

.Lbad:
    addi x26, x26, 0x7f
end:
    j    end
