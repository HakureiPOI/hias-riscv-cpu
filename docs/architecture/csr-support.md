# CSR 支持表（P0-02-R1 修订基线）

状态：**规格候选，待管理复审冻结；当前 CPU 未实现任何 CSR。** 本文落实 P0-02 管理审查的 D01—D11，规范依据为锁定的 `v20260120`：

- [Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [CSR 权限与地址表](https://docs.riscv.org/reference/isa/priv/priv-csrs.html)
- [Machine 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [Supervisor 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/supervisor.html)

## 1 通用规则

- 地址 12 位；权限编码 `[11:10]`，最低特权编码 `[9:8]`。M-mode 访问已实现、低权限的 CSR 不构成越权；S/U 访问更高权限 CSR 才产生非法指令。
- 整只只读 CSR：读允许，任何写尝试（CSRRW/CSRRWI 总是写；CSRRS/CSRRC/CSRRSI/CSRRCI 仅在 rs1≠x0/zimm≠0 时写）产生非法指令。
- 可写 CSR 内的只读位/WPRI：写入被忽略，读回固定值；不产生异常。
- 未实现且未列为本项目零项 CSR 的地址：**非法指令**（D04）。明确列出的零项 CSR 按其规则读 0、写忽略。
- WARL 字段写入非法值后必须读回合法值；实现不得只写“忽略或保留”而不固定行为。
- CSR 指令在提交头串行执行；完成架构更新后清除年轻指令并重取。

## 2 六种 CSR 指令的读写条件（修正版）

`rd` 抑制读、`rs1` 抑制写；两者不能混用“值是否为零”。

| 指令 | 读 CSR？ | 写 CSR？ | 说明 |
| --- | --- | --- | --- |
| CSRRW rd, csr, rs1 | `rd != x0` | 总是写 | rd=x0 时抑制读（含读副作用），但写仍发生 |
| CSRRS rd, csr, rs1 | 总是读 | `rs1 != x0` | rs1=x0 抑制写；rs1 编号非零但值为零仍写 |
| CSRRC rd, csr, rs1 | 总是读 | `rs1 != x0` | 同上 |
| CSRRWI rd, csr, zimm | `rd != x0` | 总是写 | zimm=0 也执行写（写入 0） |
| CSRRSI rd, csr, zimm | 总是读 | `zimm != 0` | zimm=0 抑制写 |
| CSRRCI rd, csr, zimm | 总是读 | `zimm != 0` | zimm=0 抑制写 |

补充：

- `CSRRW rd=x0, csr, rs1` 不读 CSR；若该 CSR 读有副作用，不得触发。
- `CSRRWI rd=x0, csr, 0` 仍然写 0。
- `CSRRS/CSRRC rd=x0` 仍读 CSR（因为指令需要读值来计算写值），但写抑制由 rs1 决定。
- `csr_uimm` 为完整 5 位，范围 0—31，不得截断。

## 3 P1 最小集合（D01/D03/D04）

P1 = RV32I（40 条，含 FENCE/ECALL/EBREAK）+ 六种 Zicsr + 保守 Zifencei + 最小 M-mode Trap/CSR。M 扩展仍在 P3。

| 地址 | 名称 | 权限 | 复位值 | 实现与写规则 | P1 | 最终 |
| --- | --- | --- | --- | --- | --- | --- |
| `0x300` | mstatus | RW | **`0x0000_1800`** | MIE(3)、MPIE(7)、MPP[12:11] 可写；MPP 仅 M(11)，其他写入回读 11；MIE/MPIE 复位 0；其余位读 0、写忽略 | 是 | 是 |
| `0x301` | misa | RW/WARL | **`0x4000_0100`** | MXL=1、I=1；P1 固定报告 RV32I；合法写完成但字段保持固定值，不 Trap；P3/P5 启用 M/S/U 时只读/固定能力位相应扩展 | 是 | 是 |
| `0x305` | mtvec | RW | `0x0000_0000` | BASE[31:2]；MODE 仅 Direct(0)，其他写入回读 0 | 是 | 是 |
| `0x341` | mepc | RW | `0x0000_0000` | 低 2 位读 0（无 C）；写入忽略低 2 位 | 是 | 是 |
| `0x342` | mcause | RW | `0x0000_0000` | Interrupt(31)+Code；只接受已实现 cause，其他 WARL 回读 0 | 是 | 是 |
| `0x343` | mtval | RW | `0x0000_0000` | 32 位；按异常规则写 | 是 | 是 |
| `0x340` | mscratch | RW | `0x0000_0000` | 32 位读写 | 是 | 是 |
| `0x304` | mie | RW | `0x0000_0000` | MSIE(3)、MTIE(7)、MEIE(11)；未实现位只读 0 | 是 | 是 |
| `0x344` | mip | RW | `0x0000_0000` | MSIP(3) 可写；MTIP(7)/MEIP(11) 由平台输入驱动，软件写忽略 | 是 | 是 |
| `0x320` | mcountinhibit | RW | `0x0000_0000` | CY(0)、IR(2) 可写；TM(1) 只读 0；写在下一条指令生效 | 是 | 是 |
| `0x306` | mcounteren | RW | `0x0000_0000` | CY(0)、TM(1)、IR(2)；P1 无 S/U，仅保存值 | 是 | 是 |
| `0xb00` | mcycle | RW | `0x0000_0000` | 64 位计数器低半；可读写；正常每周期加 1 | 是 | 是 |
| `0xb80` | mcycleh | RW | `0x0000_0000` | 64 位高半；可读写 | 是 | 是 |
| `0xb02` | minstret | RW | `0x0000_0000` | 64 位退休指令计数低半；可读写；异常指令不计 | 是 | 是 |
| `0xb82` | minstreth | RW | `0x0000_0000` | 高半；可读写 | 是 | 是 |
| `0xf11` | mvendorid | RO | `0x0000_0000` | 只读零 | 是 | 是 |
| `0xf12` | marchid | RO | `0x0000_0000` | 只读零 | 是 | 是 |
| `0xf13` | mimpid | RO | `0x0000_0000` | 只读零 | 是 | 是 |
| `0xf14` | mhartid | RO | `0x0000_0000` | 只读零；单核 | 是 | 是 |
| `0x310` | mstatush | RW/WARL | `0x0000_0000` | RV32 高半实现位均为 0；合法写完成但保持 0，不 Trap。MPRV 在 `mstatus[17]`，不在高半 | 是 | 是 |

计数器规则（D03）：

- `mcycle`/`minstret` 为 64 位，RV32 通过低/高半 CSR 访问；复位为 0，允许软件写。
- CSR 写在提交头生效；同一周期“写 vs 自增”冲突时，**写优先**，该周期不自增。`mcycle` 写入值从下一周期继续递增。
- 写入 `minstret` 的指令本身不增加计数（写优先）；后续退休指令恢复计数。
- 异常指令、被 Flush 的年轻指令不计入 `minstret`。
- `mcountinhibit.CY/IR` 分别停止 `mcycle`/`minstret` 自增；软件写 CSR 仍可修改计数值。
- 不与 Spike 的周期数直接比较；P1 用受控计数/相对关系自检。

其他 P1 规则：

- `misa` 读固定 `0x40000100`；它是 RW/WARL 固定能力字段，合法写完成但值保持不变，不 Trap。
- `mstatus` 复位 `0x00001800`；MPP=3，MIE/MPIE=0；未实现位读 0。
- P1 没有 U/S，M-mode 访问已实现 CSR 不越权。
- 未实现地址（如 `satp`、`medeleg`、`mideleg`、`mhpmevent3=0x323`、`mseccfg=0x747`、PMP 等）在 P1 产生非法指令；若未来定义为零项，必须在本表明确。
- `mhpmevent3` 地址是 `0x323`；`0x747` 是 `mseccfg`，当前不实现。
- MPRV 位于 `mstatus[17]`；`mstatush` 不含 MPRV。

## 4 最终 M/S/U 集合（P5 起）

| 地址 | 名称 | 权限 | 复位 | 关键规则 |
| --- | --- | --- | --- | --- |
| `0x100` | sstatus | RW | `0x0000_0000` | mstatus 受限视图；SIE(1)、SPIE(5)、SPP(8)、SUM(18)、MXR(19) |
| `0x104` | sie | RW | 0 | SSIE(1)、STIE(5)、SEIE(9)；mie 视图 |
| `0x105` | stvec | RW | 0 | 同 mtvec，Direct |
| `0x106` | scounteren | RW | 0 | CY/TM/IR |
| `0x10a` | senvcfg | RW | 0 | 实现位按最终配置 |
| `0x140` | sscratch | RW | 0 | 32 位 |
| `0x141` | sepc | RW | 0 | 低 2 位读 0 |
| `0x142` | scause | RW | 0 | 同 mcause 编码 |
| `0x143` | stval | RW | 0 | 32 位 |
| `0x144` | sip | RW | 0 | SSIP(1) 可写；STIP/SEIP 由平台/委托驱动 |
| `0x180` | satp | RW | 0 | MODE Bare/Sv32；ASIDLEN=0，ASID 回读 0；PPN[21:0] |
| `0x302` | medeleg | RW | 0 | 仅可委托异常位；未实现位只读 0 |
| `0x303` | mideleg | RW | 0 | 仅可委托中断位；未实现位只读 0 |
| `0x30a` | menvcfg | RW | 0 | ADUE=0（Svade）、PBMT=0；不承诺 Svpbmt/Svadu |
| `0x31a` | menvcfgh | RW | 0 | RV32 高半 |
| `0x3a0` | pmpcfg0 | RW | 0 | 零项；读 0、写忽略 |
| `0x3b0`–`0x3bf` | pmpaddr0–15 | RW | 0 | 零项；读 0、写忽略 |

`misa` 在最终配置启用 M/S/U 后只读报告相应位；写仍不改变能力。`medeleg/mideleg` 的有效位随已实现异常/中断集合固定。

## 5 Trap 与返回规则

| 事件 | cause | tval | EPC | 说明 |
| --- | --- | --- | --- | --- |
| ECALL U/S/M | 8/9/11 | 0 | ECALL 指令 PC | P1 仅 M |
| EBREAK | 3 | **0** | EBREAK 指令 PC | 正文与表统一为 0 |
| 非法指令 | 2 | 指令编码（32 位） | 指令 PC | 不写 rd/CSR |
| 取指/跳转目标非对齐 | 0 | 错误目标地址 | 跳转/分支指令 PC | 分支仅在实际跳转时检查 |
| 非对齐 load/store | 4/6 | 有效地址 | 指令 PC | — |
| 访问故障 | 1/5/7 | 出错地址 | 指令 PC | PMA 拒绝 |
| Page Fault | 12/13/15 | 出错 VA | 指令 PC | P5/Svade |

- JALR 先清 `target[0]`，再要求 `target[1]==0`；JAL/branch 目标必须 4 字节对齐。
- MRET 从 mepc 返回；P1 只返回 M。SRET 与 SFENCE.VMA 在 P1 产生非法指令（D02）。
- 中断判据（与 `docs/architecture/isa-support.md` 一致）：
  1. 先由 `mideleg` 决定目标级；
  2. 目标级 pending 与 individual enable 满足；
  3. 当前权限低于目标级时响应，不受当前级 xIE 限制；
  4. 当前权限等于目标级时还需该级 `xIE=1`；
  5. 当前权限高于目标级时不响应。
- 已委托给 S 的中断在 M-mode 被屏蔽，不能因 MIE/SIE 开启而转入 S；同步异常委托也不能使 M-mode 异常进入 S。
- 边界例：S 下 MIE=0 的 M 目标中断响应；S 下 SIE=0 的已委托 S 中断不响应、SIE=1 响应；U 下 SIE=0 的已委托 S 中断响应；M 下已委托 S 中断不响应；M 下 MIE=0 的 M 中断不响应。
- 中断优先级 MEI > MSI > MTI > SEI > SSI > STI；在提交边界评估，异常指令不退休，EPC 指向首条未退休指令。

## 6 依据与阶段

- 六种 CSR 读写条件、CSR 地址/权限、mstatus/misa 字段依据 Zicsr/Machine 规范；本项目选择非法指令/零项策略处已标为项目决策（D04）。
- P1 计数器/Trap/返回/精确副作用列入 P1 验证（D10）；Spike 提交日志不能表达 CSR 快照时，使用调试 CSR 快照或独立参考测试。
- M 扩展在 P3；P1 软件构建不得隐含 M/A/F 运行库依赖。
