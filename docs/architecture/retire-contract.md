# 退休 / Trap 契约（P0-02 候选基线）

状态：**候选冻结，待管理审查。** 当前没有 DUT 退休记录，也没有 DiffTest。本文定义目标契约、Spike 现有观察能力映射和格式夹具；合成记录不称为 DUT 结果。

## 1 正常退休记录

每条正常退休记录对应一条实际退休指令。字段定义见 `rtl/include/core_types_pkg.sv` 的 `retire_record_t` 和 `verification/spec/retire/retire_schema.json`。

| 字段 | 宽度 | 有效性规则 | 说明 |
| --- | --- | --- | --- |
| `valid` | 1 | — | 本槽是否有效 |
| `seq` | 64 | 仅仿真 | 全局退休序号；严格递增；不进入可综合关键路径 |
| `token.idx/gen` | 5/8 | — | ROB 项号 + 代次；仅 index 不唯一 |
| `pc` | 32 | — | 指令 PC |
| `instr` | 32 | — | 原始指令编码 |
| `next_pc` | 32 | — | 架构下一 PC（trap 时为 trap 目标或指令的正确下一 PC，按事件区分） |
| `priv` | 2 | — | 退休时的特权级 U/S/M |
| `rd_we` | 1 | — | 是否写整数寄存器 |
| `rd` | 5 | rd_we=1 | 目标寄存器；`rd=0` 时 `rd_we` 必须为 0 |
| `rd_data` | 32 | rd_we=1，否则 null | 写入值 |
| `csr_we` | 1 | — | 是否写 CSR |
| `csr_addr` | 12 | csr_we=1，否则 null | CSR 地址 |
| `csr_wdata` | 32 | csr_we=1，否则 null | 写入值（用于追踪，不建议作为唯一架构证据） |
| `csr_rdata` | 32 | 有 CSR 读时，否则 null | 读值 |
| `mem_valid` | 1 | — | 是否有架构访存 |
| `mem_we` | 1 | mem_valid=1；load 为 0 | 读/写 |
| `mem_va` | 32 | mem_valid=1，否则 null | 有效地址 |
| `mem_pa` | 34 | mem_valid=1，否则 null | 物理地址 |
| `mem_size` | 2 | mem_valid=1 | byte/half/word/none |
| `mem_mask` | 4 | mem_valid=1，否则 null | 字节使能，非零且不超出 size |
| `mem_wdata` | 32 | store，否则 null | 写数据 |
| `mem_rdata` | 32 | load，否则 null | 读数据 |

规则：

- 缺字段必须用显式 valid/null 表示，不能用 0 冒充“已观测到 0”。
- `rd=x0` 永不写；正常退休必须满足。
- 异常指令不产生正常退休记录；只在下一次独立 Trap 事件中记录。
- 两槽退休按槽 0、槽 1 程序序输出；`seq` 跨槽严格递增。
- Store/MMIO 的 `mem_pa` 是架构可见的最终物理地址；错误路径不产生退休记录。

## 2 Trap 事件

Trap 是独立事件，字段见 `trap_event_t` / `retire_schema.json`：

| 字段 | 说明 |
| --- | --- |
| `pc` | 触发指令 PC；异步中断为被打断的首条未退休 PC |
| `epc` | 写入 mepc/sepc 的值 |
| `target_pc` | trap 向量目标（Direct 模式为 mtvec/stvec 基址） |
| `cause` | 5 位异常/中断 cause 码 |
| `is_interrupt` | 0=同步异常，1=异步中断 |
| `tval` | mtval/stval 值 |
| `from_priv`/`to_priv` | 特权切换前后 |
| `mstatus_before/after` | 完整 CSR 值，便于核对 MIE/MPIE/MPP |
| `cause_csr_before/after` | mcause/scause 前后值 |
| `epc_csr_before/after` | mepc/sepc 前后值 |

Trap 优先级与提交规则见 `docs/architecture/isa-support.md` 与 `docs/interfaces.md`：

- 提交头按槽 0 → 槽 1 检查；槽 0 正常、槽 1 异常可先提交槽 0，异常项下一拍处理。
- 同一拍不同时输出正常退休与 Trap（P1 首版）；Trap 拍不提交普通指令。
- Store/MMIO 不可取消事务先完成再响应中断。

## 3 Spike `--log-commits` 字段映射

Spike 1.1.1-dev 的提交行格式（实测）：

```text
core   0: 3 0x80000110 (0x00f72a23) mem 0x80000120 0x50415353
core   0: 3 0x800000a4 (0x00c12503) x10 0x00000091 mem 0x8001ffdc
```

| 契约字段 | Spike 是否直接提供 | 来源/推导 | P1 可比较性 |
| --- | --- | --- | --- |
| hart/core | 是 | 行首 `core N` | 是 |
| priv | 是 | 行内数字（3=M, 1=S, 0=U） | 是 |
| pc | 是 | 第 3 个字段 | 是 |
| instr | 是 | 括号内 | 是 |
| rd_we/rd/rd_data | 是 | `xN value`；无 `xN` 表示不写 | 是 |
| mem_valid/mem_we | 可推导 | opcode 0x03/0x23；行内 `mem` | 是（需译码） |
| mem_pa | 是（Bare） | `mem 0x...`；Sv32 后为 PA 还是 VA 需核对 | P1 Bare 可比较 |
| mem_wdata | 是 | store 的第二个 `mem` 值 | 是 |
| mem_rdata | 可推导 | load 的目的寄存器值 + `mem` 地址 | 是（需关联） |
| mem_size/mask | 可推导 | 指令 funct3 + 地址低 2 位 | 是（需译码） |
| next_pc | 否（不直接打印） | 下一条提交行 PC，或按指令语义推导 | P1 需后处理 |
| csr_addr/wdata/rdata | 否 | 需额外接口或反汇编 CSR 指令 | 否（P1 不比较 CSR 值） |
| token idx/gen | 否 | DUT 内部状态 | 否（仅 DUT 侧断言） |
| seq | 否 | Spy 日志行号可作替代 | 仅格式夹具 |
| Trap 事件 | 否 | Spike `-d` 可读 CSR；提交日志不含 Trap 记录 | P1 不比较 Trap；P5 需新增接口 |

已实现观察方式：

- `--log-commits`：逐条提交（PC/指令/寄存器写/内存地址与值）。
- `-d --debug-cmd`：`reg`、`pc`、`until pc` 可读寄存器和控制运行。
- DTS：`--dump-dts` 可核对 ISA、Sv32、内存范围。

缺口：

- 无结构化退休流/Trap 流；需要 P1 验证环境解析或扩展。
- `next_pc`、CSR 写读值、Trap 事件、精确中断边界不能直接从提交日志得到。
- `mem` 行在 Sv32 下表示 VA 还是 PA 需 P5 前确认。

## 4 格式夹具与检查

文件：

- `verification/spec/retire/retire_schema.json`：字段/类型/有效性规则。
- `verification/spec/retire/examples/synthetic_examples.jsonl`：合成记录，明确标注 `source=synthetic`，只验证格式。
- `verification/spec/retire/examples/spike_ok_excerpt.log`：真实 Spike 提交片段（来自本轮 P0-02 运行）。
- `verification/spec/retire/examples/spike_derived_examples.jsonl`：由上述片段转换，`source=spike-derived`，不是 DUT 退休记录。

检查器：`scripts/check_retire_contract.py`

- `--validate-examples`：逐条验证字段、类型、`rd=x0`、null/valid 关系、bundle 顺序、访存 mask、trap 字段。
- `--self-test`：对故意错误的记录要求拒绝，证明检查器不是无条件通过。
- `--convert-spike FILE`：将真实 Spike 行转换为契约形状并保留来源标记。

运行证据保存在 `verification/evidence/P0-02/`。合成记录不能作为 DUT 退休或 DiffTest 通过证据。

## 5 P1 可比较范围

| 项目 | P1 |
| --- | --- |
| PC、指令、rd 写值 | 可比较 |
| load/store 地址/数据/宽度/掩码 | 可比较（Bare，PA=VA） |
| 正常退休顺序与计数 | 可比较 |
| CSR 值 | 记录但不作为 P1 DiffTest 主判据 |
| Trap | 通过独立事件接口比较（P1 需先建立） |
| 中断 | 独立注入与边界测试，不使用提交日志替代 |
| Sv32/Svade | P5 |

## 6 待审决策

1. DUT 退休流是否需要 `next_pc` 独立字段，还是由 DUT 输出的“架构下一 PC”与 Spike 后处理对齐。
2. Trap 与正常退休是否允许同拍输出；当前 P1 规定不允许。
3. `seq` 是否只存在于验证包装层，而不进入 `core_types_pkg`；当前保留在共享包并标注仿真专用。
4. Spike 的 `mem` 地址在 Sv32 下的语义需在 P5 前用实验确认。
