# CSR 支持表（P0-02 候选基线）

状态：**规格候选，未冻结；当前 CPU 未实现任何 CSR。** 本表覆盖 P1 最小核与最终 M/S/U + Sv32 目标。规范依据为技术调研记录锁定的 `v20260120` 文档集合：

- [Machine 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [Supervisor 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/supervisor.html)
- [Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)

## 1 通用规则

- 地址为 12 位。未列出的地址按“未实现 CSR”处理：读返回 0、写忽略，或按实现选择产生非法指令；本基线统一为**读返回 0、写忽略**，但不得伪装成已支持功能。
- 读写权限由 `[11:10]` 编码：`11` 只读、`01`/`10`/`00` 读写。P1 只在 M-mode 运行；S/U 访问越权 CSR 产生非法指令。
- WARL 字段写入非法值后必须读回合法值；WPRI 位读 0、写忽略；只读位写忽略。
- `misa` 的扩展位只反映实际实现；P1 只置 I，P3 加 M，P5 视实现加 S/U。
- CSR 指令的读写抑制规则按 Zicsr：`csrrw` 总是写；`csrrs/csrrc` 在 `rs1=x0` 时不写；立即数形式 `zimm=0` 时不写。读抑制在 `rd=x0` 时仍允许发生副作用，但实现可以选择不读；本基线规定 **rd=x0 时不读 CSR，但写仍发生**。
- CSR/Trap/返回/Fence 在提交头串行执行，完成架构更新后清除年轻指令并重取。
- 计数器在 P1 为只读零或按平台实现的确定性递增；若实现递增，必须提供 `mcycle`/`minstret` 及 `mcycleh`/`minstreth`。本基线 P1 固定为**只读零**，避免不确定值进入差分；P3 再决定是否启用真实计数。

## 2 P1 最小集合

| 地址 | 名称 | 权限 | 复位值 | 实现位 | WARL/WPRI/只读 | P1 | 最终 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `0x300` | mstatus | RW | `0x0000_0000` | MIE(3)、MPIE(7)、MPP[12:11]、MPRV(17)、SUM(18)、MXR(19)、FS[14:13]、SD(31) 见下 | MPP WARL 仅 M（P1）；FS 只读 0（无 F）；SD 由 FS/XS 决定 | 是 | 是 |
| `0x301` | misa | RW | `0x4000_0000`（MXL=1, I） | MXL[31:30]、扩展位 I/M/S/U | 扩展位只读实际支持；写只能清除允许清除的位 | 是 | 是 |
| `0x305` | mtvec | RW | `0x0000_0000` | BASE[31:2]、MODE[1:0] | MODE WARL：仅 Direct(0)；其他值回读 0 | 是 | 是 |
| `0x341` | mepc | RW | `0x0000_0000` | [31:0] | 低 2 位读 0（无 C）；写入忽略低 2 位 | 是 | 是 |
| `0x342` | mcause | RW | `0x0000_0000` | Interrupt(31)、Exception Code[30:0] | 只实现已列 cause；写入其他值按 WARL 保留或回读合法值 | 是 | 是 |
| `0x343` | mtval | RW | `0x0000_0000` | [31:0] | 无 C 时低 2 位对地址类异常有效 | 是 | 是 |
| `0x340` | mscratch | RW | `0x0000_0000` | [31:0] | — | 是 | 是 |
| `0x304` | mie | RW | `0x0000_0000` | MSIE(3)、MTIE(7)、MEIE(11) | 未实现位只读 0；P1 可写但无中断源 | 是 | 是 |
| `0x344` | mip | RW | `0x0000_0000` | MSIP(3)、MTIP(7)、MEIP(11) | 只读或由硬件置位；软件写按规范 | 是 | 是 |
| `0x30a` | menvcfg | RW | `0x0000_0000` | 见下 | P1 无 U 模式，保持 0 | 否（P5） | 是 |
| `0x31a` | menvcfgh | RW | `0x0000_0000` | 高 32 位 | RV32 别名 | 否（P5） | 是 |
| `0x747` | mhpmevent3 | RW | `0x0000_0000` | 事件选择 | 未实现计数时为 0 | 否 | 是 |
| `0xb00` | mcycle | RW | `0x0000_0000` | [31:0] | P1 只读零；P3 决定 | 是（只读零） | 是 |
| `0xb02` | minstret | RW | `0x0000_0000` | [31:0] | 同上 | 是（只读零） | 是 |
| `0xb80` | mcycleh | RW | `0x0000_0000` | [63:32] | 同上 | 是（只读零） | 是 |
| `0xb82` | minstreth | RW | `0x0000_0000` | [63:32] | 同上 | 是（只读零） | 是 |
| `0xf11` | mvendorid | RO | `0x0000_0000` | [31:0] | 只读；0 表示非商业实现 | 是 | 是 |
| `0xf12` | marchid | RO | `0x0000_0000` | [31:0] | 只读 | 是 | 是 |
| `0xf13` | mimpid | RO | `0x0000_0000` | [31:0] | 只读 | 是 | 是 |
| `0xf14` | mhartid | RO | `0x0000_0000` | [31:0] | 只读；单核恒 0 | 是 | 是 |
| `0x306` | mcounteren | RW | `0x0000_0000` | CY(0)、TM(1)、IR(2) | P1 无 S/U，保持 0 | 是 | 是 |

P1 说明：

- `mstatus` 在 P1 只使用 MIE/MPIE/MPP。MPP 写入非 M 值按 WARL 回读 M 或 0，实现需固定并在测试中记录。本基线选择 **MPP 只支持 M(11)，其他写入回读 11**。
- `misa` 的 `MXL` 必须为 1（32 位）；I 位固定 1；M 位 P3 置位。
- `menvcfg`/`menvcfgh` 在 P1 未实现，读 0、写忽略；P5 引入 Sv32 时按规范实现 PBMT/ADUE 等必要位，`ADUE` 固定 0（Svade）。
- `mip` 的 MSIP/MTIP/MEIP 由平台输入驱动；P1 无 CLINT/PLIC，软件可读，硬件保持 0。
- `mhpmevent3` 及 `mhpmcounter*` 在 P1 读 0、写忽略；不宣称性能计数器。

## 3 最终（P5 起）M/S/U 集合

| 地址 | 名称 | 权限 | 复位值 | 关键实现位 | 阶段 |
| --- | --- | --- | --- | --- | --- |
| `0x100` | sstatus | RW | 见 mstatus 别名 | SIE(1)、SPIE(5)、SPP(8)、SUM(18)、MXR(19)、FS/SD | P5 |
| `0x104` | sie | RW | 0 | SSIE(1)、STIE(5)、SEIE(9) | P5 |
| `0x105` | stvec | RW | 0 | BASE、MODE（Direct） | P5 |
| `0x106` | scounteren | RW | 0 | CY/TM/IR | P5 |
| `0x10a` | senvcfg | RW | 0 | 必要位 | P5 |
| `0x140` | sscratch | RW | 0 | [31:0] | P5 |
| `0x141` | sepc | RW | 0 | 低 2 位读 0 | P5 |
| `0x142` | scause | RW | 0 | 与 mcause 相同编码 | P5 |
| `0x143` | stval | RW | 0 | [31:0] | P5 |
| `0x144` | sip | RW | 0 | SSIP(1)、STIP(5)、SEIP(9) | P5 |
| `0x180` | satp | RW | 0 | MODE(31) WARL：Bare(0)/Sv32(1)；ASID[30:22] 只读 0；PPN[21:0] | P5 |
| `0x200` | vsstatus | — | — | 不实现 H | — |
| `0x300` | mstatus | RW | 见上 | 增加 SPP、SIE、MPRV 等 | 是 |
| `0x302` | medeleg | RW | 0 | 可委托异常位 | P5 |
| `0x303` | mideleg | RW | 0 | 可委托中断位 | P5 |
| `0x310` | mstatush | RW | 0 | RV32 高位别名（MPRV 等） | P5 |
| `0x30a` | menvcfg | RW | 0 | ADUE=0（Svade）、PBMT=0 | P5 |
| `0x31a` | menvcfgh | RW | 0 | RV32 高位 | P5 |
| `0x3a0` | pmpcfg0 | RW | 0 | P1—P5 零项；读 0、写忽略 | 是（零项） |
| `0x3b0`–`0x3bf` | pmpaddr0–15 | RW | 0 | 零项；读 0、写忽略 | 是（零项） |

别名与掩码：

- `sstatus` 是 `mstatus` 的受限视图：可写位由规范固定；P5 实现时列出准确掩码并测试。
- `sie/sip` 是 `mie/mip` 的受限视图；委托后 S 级可见。
- `mstatush` 在 RV32 只包含 mstatus 高半部分字段（如 MPRV 的高位不存在时读 0）。
- `satp` ASIDLEN=0：ASID 写入按 WARL 读回 0；MODE 仅 Bare/Sv32；PPN 在 Bare 时忽略。
- `medeleg/mideleg` 对未实现异常/中断位只读 0。
- `mcounteren/scounteren` 在无 S/U 时保持 0；P5 按计数器是否启用决定。

## 4 读写抑制与副作用

| 指令 | rd=x0 | rs1=x0 / zimm=0 | 写 | 读 |
| --- | --- | --- | --- | --- |
| csrrw rd, csr, rs1 | 允许 | — | 总是 | rd≠x0 时读 |
| csrrs rd, csr, rs1 | 允许 | 不写 | rs1≠x0 时写 | rd≠x0 时读 |
| csrrc rd, csr, rs1 | 允许 | 不写 | rs1≠x0 时写 | rd≠x0 时读 |
| csrrwi rd, csr, zimm | 允许 | zimm=0 不写 | zimm≠0 时写 | rd≠x0 时读 |
| csrrsi rd, csr, zimm | 允许 | zimm=0 不写 | zimm≠0 时写 | rd≠x0 时读 |
| csrrci rd, csr, zimm | 允许 | zimm=0 不写 | zimm≠0 时写 | rd≠x0 时读 |

- 非法/只读 CSR 写入产生非法指令，且不改变 CSR 状态。
- 越权访问（P1 在 M-mode 访问 S/U CSR）产生非法指令。
- CSR 指令在 ROB 头串行执行；结果与 CSR 状态共同提交。完成架构更新后清除年轻指令并重取，避免旧权限/旧 satp 下的年轻访存继续提交。
- `FENCE` 保守等待先前访存完成；`FENCE.I` 按 Zifencei 全流程同步。
- `MRET`/`SRET` 恢复 MPP/SPP、MPIE/SPIE、MIE/SIE 与特权，目标 PC 为 mepc/sepc；返回后年轻指令全部重取。

## 5 待审问题

1. `mstatus.MPP` 的 WARL 行为（本基线只支持 M）需与 P1 测试对齐。
2. P1 计数器固定只读零是否影响课程 Benchmark 口径；P3 需重新决定。
3. `menvcfg` 的 PBMT/ADUE 位在 P5 的确切取值需与 Svade 配置一致。
4. 课程是否要求 `misa` 反映 S/U（取决于是否要求用户态演示）。
