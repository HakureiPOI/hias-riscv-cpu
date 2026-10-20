# P1-B-R1 F01 spec anchor: locked RV32I J-type has no funct3 field.
# Assemble with: riscv64-unknown-elf-as -march=rv32i -mabi=ilp32
# Disassemble with: riscv64-unknown-elf-objdump -d -M no-aliases
    .option norvc
    .text
    .globl _start
_start:
    jal x1,  . + 4096       # canonical reviewed example: 0x000010ef
    jal x5,  . + 4096       # canonical reviewed example: 0x000012ef
    jal x0,  . + 2          # +2 is a legal J-type encoding
    jal x31, . - 4          # negative
    jal x31, . + 1048574    # maximum positive
    jal x5,  . - 1048576    # minimum negative

    # Raw J-type words with instr[14:12] = 0..7. All are legal JAL.
    .word 0x000000ef
    .word 0x0000116f
    .word 0x000021ef
    .word 0x0000326f
    .word 0x000042ef
    .word 0x0000536f
    .word 0x000063ef
    .word 0x0000f46f
