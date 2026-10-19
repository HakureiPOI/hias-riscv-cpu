# ISA 支持表（P0-02 候选基线）

状态：**规格候选，未冻结；当前 CPU 未实现任何指令。** 本表是 P1 最小核、后续阶段与最终承诺的计划能力，不是已验收结果。冻结需管理方审查。规范基线为技术调研记录锁定的 `v20260120` 文档集合。

## 1 阶段定义

| 标签 | 含义 |
| --- | --- |
| P1 | 最小顺序核：RV32I + 最小 M-mode Trap/CSR，单发射活动宽度 |
| P2/P3 | OoO 与双发射集成；ISA 面不扩大，只增加执行与提交能力 |
| P5 | Sv32、Svade、M/S/U 与页故障软件闭环 |
| P6 | 独立 FP32 部件与 MMIO 演示（不等于 RV32F） |
| 最终承诺 | 项目对外声明的 ISA/特权范围，须全部有证据 |
| 暂不支持 | 明确不进入当前范围 |

## 2 基础 ISA

| 扩展/特性 | P1 | 后续 | 最终承诺 | 暂不支持 | 依据与说明 |
| --- | --- | --- | --- | --- | --- |
| RV32I 全部 40 条（含 FENCE/ECALL/EBREAK，不含 FENCE.I） | 是 | 保持 | 是 | — | [RV32I 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)；无 C 时 4 字节对齐 |
| RV32M（mul/div/rem 共 8 条） | 否 | P3 | 是 | — | [M 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/m-st-ext.html)；含除零、有符号溢出、余数符号规则 |
| Zicsr（csrrw/s/c 及立即数形式） | 是（最小集合） | 扩展 | 是 | — | [Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)；读写抑制规则见 CSR 表 |
| Zifencei（fence.i） | 是（保守实现） | 保持 | 是 | — | [Zifencei 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zifencei.html)；排空数据访存、写回脏数据、失效 ICache 后重取 |
| RV32A | 否 | 否 | 否 | 是 | 单核演示不需要原子扩展；若课程新增要求另立任务 |
| RV32C（压缩） | 否 | 否 | 否 | 是 | 避免指令长度与取指拼接复杂度 |
| RV32F/D/Q | 否 | P6 独立部件 | 否（除非课程澄清） | 完整 F/D/Q | 浮点以独立 binary32 Add/Sub/Mul/Div + MMIO 演示交付；不等于 RV32F |
| H 扩展 | 否 | 否 | 否 | 是 | 不实现虚拟化 |
| 调试规范 / Trigger | 否 | 否 | 否 | 是 | 不在课程要求内 |
| 非对齐 Load/Store | 否（产生异常） | 否 | 否 | 是 | 自然对齐的 byte/half/word 支持；非对齐产生 load/store misaligned |
| 非对齐跳转目标 | 否（产生异常） | 否 | 否 | 是 | branch 仅在实际跳转时检查目标；JALR 先清 bit0 再检查 bit1；JAL/branch 目标必须 4 字节对齐；EPC=跳转指令 PC，tval=错误目标 |

## 3 特权与系统

| 特性 | P1 | 后续 | 最终承诺 | 暂不支持 | 说明 |
| --- | --- | --- | --- | --- | --- |
| M-mode | 是 | 保持 | 是 | — | 复位后处于 M-mode |
| S-mode | 否 | P5 | 是 | — | CSR/Trap 委托与 satp 在 P5 前完成规格 |
| U-mode | 否 | P5 | 是 | — | 权限测试使用 |
| Sv32（Bare + Sv32） | 否（P1 为 Bare） | P5 | 是 | — | [Supervisor 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/supervisor.html)；34 位 PA |
| Svade（A/D 软件管理） | 否 | P5 | 是 | — | A=0 或写入且 D=0 时产生 Page Fault，由软件更新 PTE 后重试 |
| Svadu（硬件 A/D 更新） | 否 | 否 | 否 | 是 | 显式选择 Svade |
| 硬件 PTW | 否 | P5 | 是 | — | 共享 PTW，经 DCache 物理入口读 PTE |
| 分离 ITLB/DTLB | 否 | P5 | 是 | — | 各 8 项全相联，ASIDLEN=0 |
| PMP | 否（零项） | 保持零项 | 零项 | PMP 编程 | 平台地址限制由固定 PMA 承担；CSR 存在但按只读零项行为实现 |
| 中断控制器（PLIC/CLINT） | 否（P1 仅软件中断可选） | P5 | 是 | — | P1 外部中断输入保留，不实现 PLIC |
| WFI | 是（按权限检查后 NOP） | 保持 | 是 | — | [Machine 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html) 允许 NOP 实现 |
| MRET/SRET | 是（MRET）；否（SRET） | P5（SRET） | 是 | — | P1 只需 MRET |
| SFENCE.VMA | 否 | P5 | 是 | — | P1 Bare 下若译码则按非法指令或 NOP 需在 P1 任务中固定；本基线定为非法指令 |
| ECALL/EBREAK | 是 | 保持 | 是 | — | ECALL cause 8/9/11；EBREAK cause 3，tval=0，EPC=指令 PC；P1 仅 M-mode ECALL |

## 4 异常与中断

### 4.1 同步异常

| 异常 | cause | tval | 处理阶段 | P1 | 最终 |
| --- | --- | --- | --- | --- | --- |
| Instruction address misaligned | 0 | 错误目标地址 | 取指/提交 | 是 | 是 |
| Instruction access fault | 1 | 出错取指地址 | 取指/提交 | 是 | 是 |
| Illegal instruction | 2 | 指令编码 | 译码/提交 | 是 | 是 |
| Breakpoint | 3 | 0 | 提交 | 是 | 是 |
| Load address misaligned | 4 | 出错有效地址 | 执行/提交 | 是 | 是 |
| Load access fault | 5 | 出错有效地址 | 执行/提交 | 是 | 是 |
| Store/AMO address misaligned | 6 | 出错有效地址 | 执行/提交 | 是 | 是 |
| Store/AMO access fault | 7 | 出错有效地址 | 执行/提交 | 是 | 是 |
| ECALL from U/S/M | 8/9/11 | 0 | 提交 | 仅 M（11） | 是 |
| Instruction page fault | 12 | 出错取指地址 | 取指/提交 | 否 | 是 |
| Load page fault | 13 | 出错有效地址 | 执行/提交 | 否 | 是 |
| Store/AMO page fault | 15 | 出错有效地址 | 执行/提交 | 否 | 是 |

说明：

- 异常在提交头处理；异常指令不写 ARF、不产生正常退休记录，年轻指令不产生架构副作用。
- 异常优先级（同一指令）：取指异常 > 非法指令 > 断点 > 访存地址/访问/页故障 > ECALL。实现必须在 `docs/interfaces.md` 的提交槽优先级中体现。
- 页故障在 Sv32 阶段启用；P1 只产生 0/1/2/3/4/5/6/7/11。
- `tval` 在 ECALL/EBREAK 时为 0；非法指令时为完整 32 位指令；地址类异常时为出错地址；跳转目标异常时为错误目标地址，EPC 为跳转指令 PC。

### 4.2 异步中断

| 中断 | cause | P1 | 最终 | 说明 |
| --- | --- | --- | --- | --- |
| Machine software | 3 | 预留输入，不实现 CLINT | 是 | MSIP |
| Machine timer | 7 | 预留输入，不实现 CLINT | 是 | MTIP |
| Machine external | 11 | 预留输入，不实现 PLIC | 是 | MEIP |
| Supervisor software/timer/external | 1/5/9 | 否 | 是（委托后） | 经 mideleg |

中断在提交边界评估，不能只用“目标级全局使能位为 1”一个条件：

- 当前权限低于目标权限时不响应；等于或高于目标权限时，按委托（mideleg）与目标级使能决定。
- M-mode 响应 M 中断需 `mstatus.MIE=1`；S 中断在 M-mode 下仅在委托且相应条件满足时响应。
- 优先级固定为 MEI > MSI > MTI > SEI > SSI > STI；P1 只开放 M 级。
- 中断 EPC 指向首条未退休指令；ROB 为空时使用记录的架构下一 PC。响应拍不提交普通指令。
- 不可取消 Store/MMIO 事务先完成再响应。

## 5 阶段门禁（计划）

| 阶段 | ISA 出口 |
| --- | --- |
| P1 | RV32I 全部指令、Zicsr 最小集合、Zifencei、MRET、M-mode 同步异常；单发射活动宽度 |
| P3 | RV32M 全边界；双发射/双提交不改变 ISA 语义 |
| P5 | S/U、Sv32、Svade、页故障修复重执行、SFENCE.VMA、中断委托 |
| P6 | 独立 FP32 部件；不宣称 RV32F |

## 6 待审问题

1. 课程是否要求完整 RV32F，还是接受独立 FP32 + MMIO 演示（Q01）。
2. 指定 OS/监控程序与 Page Fault 演示口径（Q02）。
3. P1 中 `SFENCE.VMA` 的临时行为：本基线定为非法指令，待审查确认。
4. D01 已决定 M 扩展仍在 P3；P1 软件构建不得隐含 M/A/F 运行库依赖。若课程要求 M 更早，需管理方变更决策。
