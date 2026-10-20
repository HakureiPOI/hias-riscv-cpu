# P1-C-R2 验证收尾报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-C-R2 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `f648b06acea43249d9eacd1e72ec74424b1dc4ba` |
| 原 P1-C-R1 交付 | `50221625c6038c843382130acb111877298f396d` |
| 实际修复基线 | `3ed8ec9cc70a4145e08d3ebdda41dc805c98d9a7`（`5022162` 合并管理提交后的分支顶端） |
| 分支 | `codex/p1-c-integer-execute` |
| 被测试实现 Commit | `3ed8ec9cc70a4145e08d3ebdda41dc805c98d9a7` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-C-R2-report.md` |
| 证据目录 | `verification/evidence/P1-C-R2/`（987 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `70dd499a8a93898f2c183270a3f5b7081062000da2efd8c45b7fcf2ebcc7a6b8` |

本轮只关闭 G01/G02，保留已接受的整数执行、ARF/ALU、单项顺序提交、Spike 子集差分和四类恢复成果。未实现 Load/Store、CSR/Trap、M/A/C/F、OoO/Cache/MMU/FPU、完整 DiffTest、SoC 替换或 FPGA；未合入 `main`，未进入 P1-D/E。

## 1 G01：差分公共入口复用完整格式校验

- `scripts/p1c_diff.py` 现在在读取 DUT JSONL 后统一调用 `scripts/check_retire_contract.py` 的 `validate_stream`，再执行 P1-C 子集检查。正常、七类 `--inject`、`pc_extra` 和格式变体都走同一入口，不再维护较弱的手工格式子集。
- 冻结规则由共用校验器覆盖：seq 严格递增、必需字段、严格布尔/数值类型、Token/next_pc 有效性、valid/null、derived/not_observed 来源列表等。
- 直接从真实正常 trace 构造并验证的代表性反例：
  - seq 重复/倒退：`format: stream:N: seq not strictly increasing`
  - seq/字段缺失：`format: normal: missing fields [...]`
  - `token_valid` 用字符串：`format: token_valid: expected boolean, got str`
  - PC 用字符串：`format: pc: expected integer ...`
  - 尾记录/坏行/priv/末条 next_pc/脏基线仍按原规则拒绝。
- 格式非法 trace 直接运行差分器返回 `P1C_DIFF_BASELINE_FAIL`（退出 4），不依赖外层格式命令；`seq_dup + --inject rd` 也先返回基线格式失败，不产生 `RD_DETECTED`。
- 旧 d8d7cab 检查器对 seq 重复 trace 仍 `P1C_DIFF_PASS`、exit 0；证据 `old-repro-r2/g01-seq-dup.log`。

## 2 G02：独立已提交镜像与 fault 初值

- `tb_faults.cpp` 从复位零建立独立 32 寄存器镜像，仅用**预期的正常提交写**在该实际提交边沿更新；x0 恒零。每个提交 PC/原指令/rd_we/rd/data 与用例预期逐项核对，不从 DUT 回读整套寄存器作为期望。
- 零前缀与非零前缀覆盖：
  - illegal/unsupported/JAL 未对齐/taken branch 未对齐：0 次提交。
  - `jalr_unaligned`：提交 `x1=0x55`、`x5=7`；故障 JALR PC=0x80000008、cause=0、tval=6、instr=0x000280e7；x1 仍为 0x55。
  - fetch：提交 `x5=0x10000000` 后进入 kind=0 停止。
  - branch_untaken：`x1=1`、三次正常提交；JALR bit0 清除：`x5=5`、`x1=0x80000008`。
- 首次 fault 时立即核对完整 ARF 与独立镜像、kind/PC/instr/cause/tval、Token（idx=0，gen=已提交数）、fetch_gen（由已接受请求 PC→gen 记录按 fault PC 查得）；之后继续 16 个实际边沿，逐拍比较镜像、元数据和无 commit/Trap/RAM 写。
- 正常提交日志、fault_first 和 16 个 hold 边沿均以 `P1C_FAULT_TRACE` 可追溯输出。

## 3 V03：监视器受控负向

- 观察夹具在首次 fault 将 x1 伪造成 JALR 链接值 `0x8000_000c`，随后保持稳定；独立镜像在首次比较即拒绝，输出 `P1C_FAULT_NEGATIVE_INITIAL_ARF_DETECTED`、退出 1。
- 保持期间把 x5 改变一次；真实保持监视输出 `P1C_FAULT_NEGATIVE_HOLD_CHANGE_DETECTED`、退出 1。
- 正常关闭注入时所有 fault 场景 PASS；失败类别与正常错误分开，探针只在指定检测发生且其他错误为零时认可。
- 实际总入口注入：
  - `P1_C_INJECT=fault_initial make check-p1-c`：jalr_unaligned fault 步骤失败，summary FAIL，退出非零。
  - `P1_C_INJECT=fault_hold make check-p1-c`：保持变化探针失败，summary FAIL，退出非零。
  - `pc`/`pc_extra` 的既有差分失败验证仍在正常探针和 R1 证据中保留。
- 旧 d8d7cab fault TB 使用同一观察夹具（fault 时 x1 错为链接值、随后稳定）仍 `P1C_FAULT_PASS`、exit 0；证据 `old-repro-r2/g02-initial-arf.log`。

## 4 完整正常回归

`make check-p1-c` 在被测试 Commit `3ed8ec9` 上退出 0：

| 项目 | 结果 |
| --- | --- |
| 定向程序 | 124 条退休，SPIKE diff PASS |
| random 0x1a2b3c4d | 1281 条，PASS |
| random 0x5e6f7a8b | 1281 条，PASS |
| random 0x9c0d1e2f | 1282 条，PASS |
| 随机合计 | 3844 条，每种子 >1000 |
| 六分支矩阵 | BEQ/BNE/BLT/BGE/BLTU/BGEU 均 taken/untaken |
| 四类恢复 | req_wait=28、resp_wait=28、held=28、resp_same=1 |
| 停止场景 | illegal/unsupported/unaligned/JALR bit1/fetch/branch_untaken/JALR clear |

P1-B（含 P1-A/P0）回归：

```sh
P1_B_EVIDENCE=verification/evidence/P1-C-R2/regression/P1-B make check-p1-b
```

退出 0，`P1-B-R2_CHECK_ALL_PASS`；嵌套 `P1-A_CHECK_ALL_PASS`、`P0-02_CHECK_ALL_PASS`。历史 P1-C/P1-C-R1 证据未改写。

## 5 旧版复现（d8d7cab）

| 项目 | 预期 | 实际 |
| --- | --- | --- |
| G01 seq 重复 | 原差分器错误接受 | `P1C_DIFF_PASS`、exit 0 |
| G02 首次 fault ARF 错值 | 原 TB 快照吸收后仍 PASS | `P1C_FAULT_PASS`、exit 0 |

旧 G02 复现使用独立 observation wrapper，在 fault 时把输出 x1 改为链接值并保持；原 TB 的快照逻辑接受该错误。当前 RTL 本身写入正确前缀值，报告不声称发现真实 RTL 缺陷。

## 6 文件清单

| 路径 | 说明 |
| --- | --- |
| `scripts/p1c_diff.py` | 公共格式门禁、差分与注入原因绑定 |
| `scripts/p1c_make_trace_variant.py` | 格式/尾记录/priv/next_pc/脏基线变体 |
| `scripts/repro_p1_c_r2.sh` | d8d7cab G01/G02 旧版复现 |
| `scripts/check_p1_c.sh` | R2 总入口、格式变体、fault 负向、回归 |
| `verification/p1c/tb/tb_faults.cpp` | 独立 ARF 镜像、fault 初值/16 边沿、监视负向 |
| `verification/p1c/tb/integer_tb_top.sv` | 请求 PC/gen 观察 |
| `verification/p1c/old_repro/integer_tb_top_old_repro.sv` | 旧 TB 观察夹具 |
| `rtl/core/p1_integer_top.sv` | 请求 PC/gen 观察端口 |
| `docs/architecture/p1-c-modules.md` | R2 当前验证说明 |

## 7 G01/G02 / V01—V04 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| G01 | 关闭 | 公共入口复用 validate_stream；seq/字段/类型/来源反例直接拒绝 |
| G02 | 关闭 | 独立提交镜像、首次 fault 元数据/ARF/fetch_gen、16 边沿保持、监视负向 |
| V01 | 通过 | 正常/注入/格式变体统一格式门禁 |
| V02 | 通过 | 独立已提交镜像与非零前缀 fault 初值 |
| V03 | 通过 | 首次错值/保持变化监视负向、实际总入口 FAIL |
| V04 | 通过 | 正常 exit 0、随机 3844、恢复/矩阵/停止、P1-B/P1-A/P0、证据哈希 |

## 8 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| Load/Store、LSU、访存退休 | 未实现（P1-D） |
| CSR 状态、Trap/MRET/WFI/Fence、完整异常处理 | 未实现（P1-E/F）；held fault 不等于 Trap |
| M/A/C/F、FPU | 未实现 |
| OoO/ROB/IQ/BPU/Cache/MMU、完整 DiffTest | 未实现 |
| SoC 替换、FPGA | 未进行 |

29 条子集差分通过不等于完整 RV32I/P1 门禁通过。未合入 `main`，未进入 P1-D/E。

## 9 交付摘要

```text
任务：P1-C-R2
实际修复基线 Commit：3ed8ec9cc70a4145e08d3ebdda41dc805c98d9a7
分支：codex/p1-c-integer-execute
被测试实现 Commit：3ed8ec9cc70a4145e08d3ebdda41dc805c98d9a7
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-C-R2-report.md
证据目录：verification/evidence/P1-C-R2/
证据数量：987 项（含 SHA256SUMS）
SHA256SUMS：70dd499a8a93898f2c183270a3f5b7081062000da2efd8c45b7fcf2ebcc7a6b8
G01/G02 / V01—V04：全部通过
```
