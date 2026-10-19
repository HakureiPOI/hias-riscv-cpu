# P0-02-R1 规格与接口修订报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P0-02-R1 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 原最终交付 | `ade9e81e27ab318fefaf88bdf1425b969bbf6c6b` |
| 实际修复基线 | `3c56bfbb49a5680ae0d8536cd015239ec7d07eb7`（`ade9e81` 合并 `origin/main` 的 `4024f86` 管理审查/R1 任务单） |
| 分支 | `codex/p0-02-spec-interfaces` |
| 被测试实现 Commit | `cdc6238417aaa8a069de9c2cae6dd50ea68145fd` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P0-02-R1-report.md` |
| 证据目录 | `verification/evidence/P0-02-R1/`（109 项，`SHA256SUMS`） |

本轮只修正规格、共享接口、平台生成/检查与契约夹具；未实现 CPU 数据通路，未合入 `main`，未进入 P1。历史 P0-02 报告与证据未修改。

## 1 修复内容（F01—F04）

### F01 / R01：ISA/CSR 规则

- 重写 `docs/architecture/csr-support.md`：
  - 六种 CSR 读写条件按编号而非“值是否为零”：CSRRW/CSRRWI 仅 `rd=x0` 抑制读；CSRRS/CSRRC/CSRRSI/CSRRCI 总是读；CSRRW/CSRRWI 总是写（含 zimm=0）；CSRRS/CSRRC 写由 `rs1≠x0` 决定，CSRRSI/CSRRCI 由 `zimm≠0` 决定。
  - 5 位 `csr_uimm[4:0]`，不截断。
  - P1 `misa=0x40000100`（I 位），写不改变能力；`mstatus` 复位 `0x1800`，MPP 只支持 M；MIE/MPIE=0。
  - 修正 `mhpmevent3=0x323`、`0x747=mseccfg`、MPRV 在 `mstatus[17]` 而非 mstatush。
  - 区分整只只读 CSR 非法写、可写 CSR 内只读位忽略、未实现 CSR 默认非法指令（D04）。
  - P1 计数器：64 位 `mcycle/minstret` + RV32 高低半、复位 0、可写；CSR 写优先于同周期自增；异常/Flush 指令不计 minstret；`mcountinhibit.CY/IR` 可写。
  - EBREAK `tval=0`、EPC=指令 PC；JALR 先清 bit0 再查 bit1；分支仅实际跳转时检查目标；中断按当前/目标权限与委托判断。
- 修正 `docs/architecture/isa-support.md` 的 RV32I 数量（40 条含 FENCE/ECALL/EBREAK）、EBREAK、跳转对齐、中断条件与 M 扩展 P3 口径。
- 退休检查器新增 CSR 规则推导：从指令编码计算 `csr_rd_valid`/`csr_wr_valid`，并拒绝不匹配的记录；自测覆盖五种指令形式，示例文件覆盖六种指令。

### F02 / R02：共享类型与接口

- `core_types_pkg.sv`：
  - 新增 `exec_op_e`（ADD/SUB、BEQ/BNE、LB/LBU、M 扩展等），`issue_slot_t`/`decoded_slot_t`/`renamed_slot_t` 携带 `exec_op` 与原指令；CSR 立即数为 5 位。
  - Fetch 异常 cause/tval、`pred_index`、非法指令信息进入 Decode/Rename/Issue/commit 元数据链。
  - 双槽接收改为反向 `prefix_accept_t`（`fetch_accept_t`/`decode_accept_t`/`dispatch_accept_t`）；`dispatch_bundle_t` 不再携带前向 `accept_count`。
  - 正常退休与 Trap 在契约中同拍互斥；`retire_record_t` 移除 `seq`，仅 `retire_trace_t` 保留。
  - 退休记录新增 `csr_rd_valid`/`csr_wr_valid`，替代无法表达只读/抑制读的单一 `csr_we`。
- `docs/interfaces.md`：更新方向/稳定性、元数据路径、T04/T12 时序，加入生产者→存储/通道→消费者表与已冻结接口决策。
- 新增 `verification/spec/interface/interface_fixture.sv` + C++ TB：
  - 0/1/2 槽、资源不足只收 S0、S1 下一拍再收、连续 4 拍零资源背压、Flush 抑制接收。
  - Token 分配/释放、旧代次响应拒绝、`GEN_W=1` 强制回绕、排空后恢复、重复/迟到响应拒绝。
  - 日志：`logs/interface-run.log`，输出 `P0-02_INTERFACE_FIXTURE_PASS`。

### F03 / R03：退休 schema/转换/检查器

- 协议升级为 `hias-retire/2`：
  - 参考记录不得伪造 `token`/`next_pc`；缺失字段必须 null 并列入 `not_observed_fields`；可推导字段列入 `derived_fields`。
  - CSR 用 `csr_valid`/`csr_rd_valid`/`csr_wr_valid` 区分 CSR 指令、实际读、实际写；参考模型缺失 CSR 值时显式标记不可观测。
  - 地址 lane 规则：mask 必须等于 `((1<<size)-1) << (va & 3)`；half/word 必须自然对齐；覆盖 byte 偏移 0—3、half 偏移 0/2、word。
  - LBU/LHU 的 funct3=4/5 正确映射为 byte/half；load x0 的不可观测数据显式列出。
  - Token 类型/范围、Trap 字段/来源、seq 单调、bundle 互斥与顺序逐项校验。
- 转换器对未知权限、损坏行、缺失 rd 值直接报错，不静默丢弃。
- 示例：`synthetic_examples.jsonl`、`synthetic_csr.jsonl`、`synthetic_memory.jsonl`、`bundles.jsonl`、真实 Spike 派生的 `spike_derived_examples.jsonl`。
- 自测：16 个合法正例 + 19 个单项非法反例，均按预期原因拒绝；日志 `logs/retire-selftest.log`。

### F04 / R04：平台页表与负向检查

- 生成器精确计算并输出页表端点：`PLATFORM_PAGE_TABLE_BASE=0x8001a000`、`PLATFORM_PAGE_TABLE_END=0x8001e000`，大小正好 `0x4000`；另列 `PLATFORM_LAYOUT_GAP_START/END=[0x8001e000,0x8001eff0]`。
- 链接脚本/ELF 检查要求精确端点与大小；不再把 `0x8001eff0` 当页表终点。
- 配置校验要求页表保留为 4 KiB 的整数倍；新增非页粒度负向用例。
- `--validate-only` 只做语义校验（非法配置 exit 2）；`--check` 单独检测生成物漂移（exit 3）。负向检查现在核对退出码 2 与具体原因，另有独立漂移用例。
- MMIO 寄存器契约写入 `config/platform.json` 并生成宏：UART DATA/STATUS、test_result RESULT；`test_result` 统一为 RW（读返回最近写入值，无读副作用），解决“只写/RW”冲突。

## 2 验证结果（V01—V06）

### V01 规则一致

- CSR 六种读写条件在 `docs/architecture/csr-support.md` 真值表、退休 schema/检查器、`synthetic_csr.jsonl` 与自测中一致。
- 自测正例包含：CSRRW rd=x0 抑制读、CSRRS rs1=x0 抑制写、CSRRS rs1=x1 值零仍写、CSRRWI zimm=0 仍写、CSRRSI zimm=0 不写；反例包含读/写抑制错误。
- `misa` 读例为 `0x40000100`；只读 CSR 写尝试以 Trap cause 2 表示。
- 计数器读写优先级、异常不计数等为规格/规则检查；本轮没有 DUT 运行测试。
- 证据：`logs/retire-selftest.log`、`verification/spec/retire/examples/synthetic_csr.jsonl`。

### V02 接口

- 类型 Lint/构建/运行通过：`P0-02_TYPE_SELFCHECK_PASS bits: ...`（`logs/types-run.log`）。
- 自检覆盖 5 位 CSR 立即数、`exec_op`/原指令、取指异常、预测索引、反向接收类型、`retire_trace_t` seq 隔离。
- 接口夹具通过：`P0-02_INTERFACE_FIXTURE_PASS`（`logs/interface-run.log`）。
- 证据：`logs/types-*.log`、`logs/interface-*.log`、`verification/spec/interface/`。

### V03 退休

- 检查器自测：`RETIRE_CONTRACT_SELFTEST_PASS positives=16`，反例覆盖 CSR 抑制、错误 lane、半字未对齐、缺失观测、Token 范围、Trap 字段/来源、seq 重复/倒序、未知权限、bundle 互斥。
- 示例校验：5 个文件、45 条记录通过（`logs/retire-validate.log`）。
- Spike 转换：19 行真实提交日志转换，未知/未观测字段显式标记（`logs/retire-convert.log`）。
- 证据：`logs/retire-*.log`、`verification/spec/retire/`。

### V04 平台

- `PLATFORM_CHECK_ELF_OK ... page_tables=[0x8001a000,0x8001e000) gap=[0x8001e000,0x8001eff0) ...`（`logs/platform-check.log`）。
- 128 KiB Spike 执行 `PLATFORM_CHECK_SPIKE_RUN_OK`；最终 ISA/Svade 参数探测通过（`logs/spike-features.log`）。
- 负向：8 类语义错误全部 exit 2 且带指定原因；生成物漂移单独 exit 3（`logs/platform-negative.log`）。
- 证据：`logs/platform-*.log`、`config/`、`software/generated/`。

### V05 回归

`make check-p0-02` 退出 0，全部步骤 `P0-02_STEP_PASS`；其中：

- `env P0_01_LOG_DIR=verification/evidence/P0-02-R1/regression/p0-01/logs make check-p0-01`，三步骤 exit 0、`result: PASS`。
- `env P0_01_R1_PROBE_DIR=verification/evidence/P0-02-R1/regression/p0-01-r1 make r1-probes`，11 项探针全部通过、总 `P0-01_R1_PROBES_ALL_PASS`。
- 正常 RTL 仍为固定种子 10,000 周期；Spike 参数为 128 KiB 配置；看门狗与失败传播未弱化。
- 证据：`logs/regression-*.log`、`logs/summary.log`。

### V06 可追溯

- 被测试实现 Commit：`cdc6238417aaa8a069de9c2cae6dd50ea68145fd`。
- 先提交实现，再删除 `build/` 与 `P0-02-R1` 证据目录，在该 Commit 上运行 `make check-p0-02`；测试后未修改实现。
- 证据 109 个文件，清单 `verification/evidence/P0-02-R1/SHA256SUMS`，SHA-256 为 `02cb72c1e2a29aad0f3a1406dd10d43f1791700e115bfea44d760cf2b2cf3652`。
- 历史 `verification/evidence/P0-02/` 与 P0-01/R1 证据未修改。

## 3 F/V 状态汇总

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 / R01 | 完成 | CSR/ISA/计数器/Trap 规则修正并由检查器验证 |
| F02 / R02 | 完成 | 细粒度执行操作、端到端元数据、反向接收、接口夹具 |
| F03 / R03 | 完成 | schema v2、CSR 有效性、lane、来源/顺序与正反例 |
| F04 / R04 | 完成 | 页表精确端点/空隙、负向语义与漂移分离、MMIO 契约 |
| V01 | 通过 | 规则一致；仅规则/夹具验证，非 DUT 运行 |
| V02 | 通过 | 类型与接口夹具通过；不称 CPU 完成 |
| V03 | 通过 | 退休契约正反例通过；不是 DiffTest |
| V04 | 通过 | 128 KiB 执行与负向/漂移检查通过 |
| V05 | 通过 | `check-p0-02`、`check-p0-01`、`r1-probes` 均通过 |
| V06 | 通过 | 实现/命令/退出码/日志/哈希对应 |

## 4 未完成项与待审问题

### 未完成/未验证

| 项目 | 状态 |
| --- | --- |
| CPU 数据通路（Fetch/Decode/ALU/ROB/Cache/MMU/FPU） | 未实现 |
| DiffTest、ACT/Sail、SoftFloat | 未运行 |
| FPGA / 板卡 / EDA | 未进行 |
| P1 指令/CSR/Trap 实机测试 | 计划已列，未执行 |
| Sv32/Svade 完整缺页闭环 | 未验证；仅参数探测 |
| CSR 值比较 | 参考模型提交日志不可见；P1 需调试 CSR 快照/独立参考 |

### 仍待管理/课程决定（D11）

1. 课程是否要求完整 RV32F；独立 FP32 + MMIO 是否可接受（Q01）。
2. 指定 OS/Page Fault 演示口径（Q02）。
3. 板卡型号/可用存储/EDA 许可（Q03）。
4. 指定 Benchmark 与给定浮点数据（Q05）。
5. P5 前需确认 Spike 的 `svade` ISA 字符串与 DUT A/D 软件管理行为的一致性表达。
6. 页表预算 16 KiB 仅用于演示，不宣称足以承载未确定的 OS。

### 对设计书的建议

建议管理方在冻结时同步更新设计书的 CSR/Trap、退休字段和页表保留区条目；本轮未直接改设计书。

## 5 交付摘要

```text
任务：P0-02-R1
修复基线 Commit：3c56bfbb49a5680ae0d8536cd015239ec7d07eb7
分支：codex/p0-02-spec-interfaces
被测试实现 Commit：cdc6238417aaa8a069de9c2cae6dd50ea68145fd
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P0-02-R1-report.md
证据目录：verification/evidence/P0-02-R1/
证据数量：109 项
SHA256SUMS：02cb72c1e2a29aad0f3a1406dd10d43f1791700e115bfea44d760cf2b2cf3652
F01—F04：完成
V01—V06：全部通过
未完成项：CPU RTL、DiffTest、ACT/Sail、SoftFloat、FPGA 未开展；P1 测试未执行
建议下一步：管理复审冻结 P0-02 后下达 P1 首个实现任务
```
