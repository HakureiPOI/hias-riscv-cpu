# P1-D directed Load/Store program. Data area: 0x80018000..0x8001803f.
# All accesses are naturally aligned except byte accesses, and remain in RAM.
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li x31, 0x80018000
    li x30, 16
    li x5, 0x10203040
.Linit:
    sw x5, 0(x31)
    addi x5, x5, 0x111
    addi x31, x31, 4
    addi x30, x30, -1
    bne x30, x0, .Linit

    li x31, 0x80018000
    li x5, 0x80
    sb x5, 0(x31)
    li x5, 0x7f
    sb x5, 1(x31)
    li x5, 0xff
    sb x5, 2(x31)
    li x5, 0x00
    sb x5, 3(x31)
    lb x6, 0(x31)
    lbu x7, 0(x31)
    lb x8, 1(x31)
    lbu x9, 2(x31)

    li x5, 0x8000
    sh x5, 4(x31)
    lh x10, 4(x31)
    lhu x11, 4(x31)

    li x5, 0xdeadbeef
    sw x5, 8(x31)
    lw x12, 8(x31)

    li x5, 0x11223344
    sw x5, 16(x31)
    li x5, 0xaa
    sb x5, 17(x31)
    lw x13, 16(x31)

    li x5, 0x11
    sb x5, 20(x31)
    li x5, 0x22
    sb x5, 21(x31)
    li x5, 0x33
    sb x5, 22(x31)
    li x5, 0x44
    sb x5, 23(x31)
    lb x14, 23(x31)
    lbu x15, 20(x31)

    li x5, 0x5566
    sh x5, 24(x31)
    lh x16, 24(x31)
    li x5, 0x7788
    sh x5, 26(x31)
    lhu x17, 26(x31)

    li x5, 0x80018010
    lw x18, -4(x5)

    li x5, 0x7ffffffc
    lw x19, 4(x5)          # EA wraps to 0x80000000, within RAM

    lw x0, 0(x31)          # x0 load still performs the access
    sw x0, 28(x31)         # store zero
    li x5, 0x80018000
    lw x5, 0(x5)           # rd = rs1: old address used for EA

    # Wrong-path store/load after a taken branch must not issue data traffic.
    li x5, 0xaaaaaaaa
    beq x0, x0, .Lwrong_done
    sw x5, 32(x31)
    lw x6, 32(x31)
.Lwrong_done:

    li x20, 0x80018000
    lw x1, 0(x20)
    lw x2, 4(x20)
    lw x3, 8(x20)
    lw x4, 12(x20)
    lw x5, 16(x20)
    lw x6, 20(x20)
    lw x7, 24(x20)
    lw x8, 28(x20)
    lw x9, 32(x20)
    lw x10, 36(x20)
    lw x11, 40(x20)
    lw x12, 44(x20)
    lw x13, 48(x20)
    lw x14, 52(x20)
    lw x15, 56(x20)
    lw x16, 60(x20)
end:
    j end
