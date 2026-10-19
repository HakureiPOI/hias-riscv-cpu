# 退休 / Trap 契约（P0-02-R1 修订基线）

状态：**修订候选，待管理复审。** 当前没有 DUT 退休记录，也没有 DiffTest。协议版本 `hias-retire/2`；DUT、Spike 派生、合成三种来源边界严格区分。

## 1 正常退休记录

每条正常退休记录对应一条实际退休指令。字段定义见 `rtl/include/core_types_pkg.sv` 的 `retire_record_t` 和 `verification/spec/retire/retire_schema.json`。

| 字段 | 宽度 | 有效性规则 | 说明 |
| --- | --- | --- | --- |
| `valid` | 1 | — | 本槽是否有效 |
| `seq` | 64 | 仅仿真包装 | 全局退休序号；严格递增；不在 `retire_record_t` 中，只存在于 `retire_trace_t` |
| `token_valid` + `token.idx/gen` | 1+5/8 | DUT 必须有效；参考可缺失 | ROB 项号 + 代次；仅 index 不唯一。缺失时必须 `token=null` 且列入 `not_observed_fields` |
| `pc` | 32 | — | 指令 PC |
| `instr` | 32 | — | 原始指令编码 |
| `next_pc_valid` + `next_pc` | 1+32 | DUT 必须有效；参考可缺失 | 架构下一 PC；缺失时 `next_pc=null` 并列入 `not_observed_fields`。Trap 目标用独立 `target_pc` |
| `priv` | 2 | — | 退休时的特权级 U/S/M |
| `rd_we` | 1 | — | 是否写整数寄存器 |
| `rd` | 5 | rd_we=1 | 目标寄存器；`rd=0` 时 `rd_we` 必须为 0 |
| `rd_data` | 32 | rd_we=1，否则 null | 写入值 |
| `csr_valid` | 1 | — | 指令是 CSR 指令 |
| `csr_rd_valid` | 1 | csr_valid=1 | 实际发生 CSR 读（由六种指令规则决定） |
| `csr_wr_valid` | 1 | csr_valid=1 | 实际发生 CSR 写（由 rs1/zimm 编号决定） |
| `csr_addr` | 12 | csr_valid=1，否则 null | CSR 地址 |
| `csr_wdata` | 32 | csr_wr_valid=1 | 写入值；参考模型可能不可观测，须 null + `not_observed_fields` |
| `csr_rdata` | 32 | csr_rd_valid=1 | 读值；参考模型可能不可观测，须 null + `not_observed_fields` |
| `mem_valid` | 1 | — | 是否有架构访存 |
| `mem_we` | 1 | mem_valid=1；load 为 0 | 读/写 |
| `mem_va` | 32 | mem_valid=1，否则 null | 有效地址 |
| `mem_pa` | 34 | mem_valid=1，否则 null | 物理地址 |
| `mem_size` | 2 | mem_valid=1 | byte/half/word/none |
| `mem_mask` | 4 | mem_valid=1，否则 null | 四字节字内 lane；必须等于 `((1<<size)-1) << (va & 3)`，half/word 必须自然对齐 |
| `mem_wdata` | 32 | store，否则 null | 写数据 |
| `mem_rdata` | 32 | load，否则 null | 读数据 |

规则：

- 缺字段必须用显式 valid/null 表示，不能用 0 冒充“已观测到 0”。
- `source=dut`：`token_valid`、`next_pc_valid` 必须为真；DUT load 必须提供 `mem_rdata`；`derived_fields`/`not_observed_fields` 必须为空。
- `source=spike-derived`：不得伪造 Token/next_pc；缺失字段置 null 并列入 `not_observed_fields`；可推导字段列入 `derived_fields`。
- `source=synthetic`：仅格式夹具，不代表任何真实运行。
- `rd=x0` 永不写；CSR 读写的有效性由六种指令规则决定，`csr_wr_valid` 由 rs1/zimm 编号而非值决定。
- 异常指令不产生正常退休记录；只在下一次独立 Trap 事件中记录。正常退休与 Trap 同拍互斥。
- 两槽退休按槽 0、槽 1 程序序输出；`seq` 跨槽严格递增。
- 地址 lane：byte 的 mask 为 `1 << (va & 3)`；half 为 `3 << (va & 3)`（va 必须是 2 的倍数）；word 为 `0xF`（va 必须是 4 的倍数）。LBU/LHU 分别按 byte/half 的 lane 规则。
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

Trap 来源只允许 `dut` 或 `synthetic`；Spike 提交日志不提供 Trap 事件，`source=spike-derived` 的 Trap 记录被检查器拒绝。

Trap 优先级与提交规则见 `docs/architecture/isa-support.md` 与 `docs/interfaces.md`：

- 提交头按槽 0 → 槽 1 检查；槽 0 正常、槽 1 异常时先只退休 S0，下一拍处理 Trap。
- 同一 bundle 中正常退休与 Trap 互斥（slot_valid=0 才能带 trap）；Trap 拍不提交普通指令。
- Store/MMIO 不可取消事务先完成再响应中断。
- bundle 顺序由 `seq_base` 与槽序校验，跨 bundle 的 seq 必须递增；格式夹具见 `bundles.jsonl`。

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

- `verification/spec/retire/retire_schema.json`：v2 字段/类型/有效性规则。
- `verification/spec/retire/examples/synthetic_examples.jsonl`：基础正常/Trap 合成记录。
- `verification/spec/retire/examples/synthetic_csr.jsonl`：六种 CSR 读写规则正例。
- `verification/spec/retire/examples/synthetic_memory.jsonl`：四字节 lane、半字位置、word、LBU/LHU、load x0 正例。
- `verification/spec/retire/examples/bundles.jsonl`：两槽 bundle、S0 正常后 S1 Trap、互斥规则。
- `verification/spec/retire/examples/spike_ok_excerpt.log`：真实 Spike 提交片段（P0-02 运行）。
- `verification/spec/retire/examples/spike_derived_examples.jsonl`：转换结果，`source=spike-derived`，不是 DUT 退休记录。

检查器：`scripts/check_retire_contract.py`

- `--validate-examples`：逐文件按流顺序验证字段、类型、Token/next_pc 有效性、CSR 规则、lane、bundle 互斥与 seq 单调。
- `--self-test`：合法正例与单项非法反例成对，包括 CSR 读/写抑制、四字节 lane、半字位置、LBU/LHU、缺失观测、Token 范围、Trap 字段/来源、seq 重复/倒序、未知权限、bundle 互斥。每条错误必须由预期原因拒绝。
- `--convert-spike FILE`：逐行解析；未知权限、无法解析的行或缺失 rd 值直接报错，不静默丢弃。转换结果明确标记推导字段和未观测字段。

运行证据保存在 `verification/evidence/P0-02/`。合成记录不能作为 DUT 退休或 DiffTest 通过证据。

## 5 P1 可比较范围

| 项目 | P1 |
| --- | --- |
| PC、指令、rd 写值 | 可比较 |
| load/store 地址/数据/宽度/掩码 | 可比较（Bare，PA=VA） |
| 正常退休顺序与计数 | 可比较 |
| CSR 地址/读写有效性 | 可比较（由指令与 CSR 规则推导） |
| CSR 读/写值 | P1 用调试 CSR 快照/独立参考补充，不能整类延期 |
| Trap | 通过独立事件接口比较（P1 需先建立） |
| 中断 | 独立注入与边界测试，不使用提交日志替代 |
| Sv32/Svade | P5 |

## 6 待审决策

1. DUT 退休流是否需要 `next_pc` 独立字段，还是由 DUT 输出的“架构下一 PC”与 Spike 后处理对齐。
2. Trap 与正常退休是否允许同拍输出；当前 P1 规定不允许。
3. `seq` 是否只存在于验证包装层，而不进入 `core_types_pkg`；当前保留在共享包并标注仿真专用。
4. Spike 的 `mem` 地址在 Sv32 下的语义需在 P5 前用实验确认。
