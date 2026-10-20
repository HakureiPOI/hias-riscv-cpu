# P1-C-R1 差分与边界验证修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-C-R1 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `01bf883b48025d4a9ae05fa5821a05c6c62bbe15` |
| 原 P1-C 交付 | `e73c8641a7a27ef9822fc8ab6ddbb12a43f76ecd` |
| 实际修复基线 | `4f0992b374b9b4cfde7e61e2fadd206768ff82e0`（合并管理提交后的分支顶端） |
| 分支 | `codex/p1-c-integer-execute` |
| 被测试实现 Commit | `d8d7cabe9cad2b967ce7146feed6313848945ef9` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-C-R1-report.md` |
| 证据目录 | `verification/evidence/P1-C-R1/`（919 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `7c48f0677f3e58d854cbd4523b1755b154cddd27cfd6973a0577fbf2e762a9d5` |

本轮只关闭 F01—F03，保留现有 ARF/ALU/单项顺序提交和真实退休链路。未实现 Load/Store、CSR/Trap、M/A/C/F、OoO/Cache/MMU/FPU、完整 DiffTest、SoC 替换或 FPGA；未合入 `main`，未进入 P1-D/E。

## 1 F01：完整消费 DUT 与实际字段

- `scripts/p1c_diff.py` 现在读取并校验整个 DUT JSONL：所有记录必须是 `hias-retire/2`、`kind=normal`、`source=dut`、Token/next_pc 有效、Token idx=0/gen 按序、无 CSR/mem/x0 写；恰好一个 `end_pc` 退休且必须是最后一条，任何额外正常记录/Trap/坏行/重复终点均拒绝。
- `priv` 比较来自实际 DUT 记录的 `priv` 字段；不再用常量代替。最终 `retire_count` 等于全部输入记录数。
- 稀疏 Spike 有限运行允许在终点自循环后退出；脚本验证终点后的参考后缀只有同一 PC/指令自循环，并用实际后继参考 PC 推导最后一条 DUT `next_pc`（标记 derived），不把命令行 `end_pc` 参数称为快照。最终提交终点 PC、提交后 next_pc、退休数分别校验；最终寄存器由完整参考提交写日志重建，报告明确说明来源。
- 负向尾记录/坏行/priv/末条 next_pc 变体全部被新差分器以 `P1C_DIFF_BASELINE_FAIL` 拒绝（`injection/variant-*.log`）。

## 2 F02：干净基线与指定错误原因

- 所有 `--inject` 模式先完整验证未修改基线（全量 DUT、参考、终点、最终寄存器、数量、Token）；基线坏时返回 `P1C_DIFF_BASELINE_FAIL`，不打印注入成功标记。
- 注入后收集全部差异，只有唯一指定字段/位置（或 missing/duplicate 的计数关系）差异才产生 `P1C_DIFF_NEGATIVE_<KIND>_DETECTED`。目标错误伴随额外错误返回 `P1C_DIFF_INJECTION_EXTRA_ERRORS`，原因不符返回 `P1C_DIFF_INJECTION_WRONG_REASON`；均不得计为该类检出成功。
- 七类 `pc/instr/rd/next_pc/missing/duplicate/token` 均纳入总入口，日志分别保存；`pc_extra` 作为“目标错误 + 无关 rd 错误”的受控反例，返回 EXTRA_ERRORS。
- 实际总入口注入：
  - `P1_C_INJECT=pc` 使原正常差分步骤失败，总入口退出 2，`diff-directed.log` 记录 `P1C_DIFF_NEGATIVE_PC_DETECTED`。
  - `P1_C_INJECT=pc_extra` 使总入口 FAIL，记录 `P1C_DIFF_INJECTION_EXTRA_ERRORS`，未产生 PC 成功标记。
- 脏基线 `dirty_pc + --inject rd` 返回基线失败且不出现 `RD_DETECTED`。

## 3 F03：真实恢复、停止与边界

### 3.1 控制流恢复

- 集成顶层新增测试专用请求门控 `req_gate_i`：核心侧看到真实请求 `valid=1, ready=0`，桥侧看到同一请求 `valid=0`；生产 RAM/桥功能不变。
- 定向程序新增六分支 taken/untaken 矩阵锚点。真实 Spike 日志统计（`logs/branch-matrix.log`）：

```text
beq  untaken=1 taken=2
bne  untaken=3 taken=5
blt  untaken=2 taken=1
bge  untaken=2 taken=1
bltu untaken=1 taken=1
bgeu untaken=1 taken=1
P1C_BRANCH_MATRIX_PASS six_branches_both_directions
```

- 使用真实后端控制流提交触发的四次定向恢复运行（均同时通过 DUT/Spike 差分）：

| 场景 | 参数 | 实际计数 |
| --- | --- | ---: |
| 请求 valid=1/ready=0 未接受 | `recovery=0 resp_delay=0` | `redirect_req_wait=28` |
| 已接受响应在途 | `recovery=1 resp_delay=2` | `redirect_resp_wait=28` |
| 译码结果 held | `recovery=2 resp_delay=0` | `redirect_dec=28` |
| redirect 与匹配响应同拍 | `recovery=3 resp_delay=0` | `redirect_resp_same=1` |
| 后端 accept_stall（另一统计） | 正常定向 `+stall` | `redirect_stall=7` |

  每次恢复运行都核对原控制流自身正常退休/链接写和旧路径不退休（差分全量通过），没有使用外部人工 redirect。

### 3.2 停止状态与边界

- `tb_faults` 在首次 fault 后继续 16 个实际时钟边沿，逐拍核对 fault kind/PC/instr/cause/tval/Token/fetch_gen 保持，无正常 commit/Trap/RAM 写，且完整 ARF 与 fault 前快照一致。
- 证据：
  - illegal kind=1、unsupported kind=2、JAL taken 未对齐 kind=3、taken branch 未对齐 kind=3、fetch kind=0（有两条已提交前缀）。
  - `jalr_unaligned`（x1 旧值非零、前缀已提交、清 bit0 后 bit1 仍置位）kind=3、cause=0、tval=6、fault PC=JALR PC；链接寄存器不变。
  - untaken 未对齐分支不 fault 并正常提交；JALR bit0 清除后对齐目标正常提交、链接写保留。
- ALU 单元增加显式 `imm12=-2048/-1/0/2047` 符号扩展、LUI/AUIPC 高位/回绕、移位 0/31/63 锚点；分支方向矩阵由真实集成执行留证，不用 ALU 单元替代。

## 4 正常回归与统计

正常 `make check-p1-c` 在被测试 Commit `d8d7cab` 上退出 0：

| 程序 | 退休数 | 差分 |
| --- | ---: | --- |
| directed | 124 | PASS |
| random 0x1a2b3c4d | 1281 | PASS |
| random 0x5e6f7a8b | 1281 | PASS |
| random 0x9c0d1e2f | 1282 | PASS |

随机合计 3844 条正常退休，每种子 >1000。DUT 全量 trace 通过 `check_retire_contract.py --validate-file`；逐条 PC/指令/priv/rd 写/next_pc 与最终 32 个 ARF 寄存器一致。Token/P1-C 内部身份、提交边沿 ARF 一致性、四类恢复和所有停止边界均通过。

P1-B（含 P1-A/P0）回归：

```sh
P1_B_EVIDENCE=verification/evidence/P1-C-R1/regression/P1-B make check-p1-b
```

退出 0，`P1-B-R2_CHECK_ALL_PASS`；嵌套 `P1-A_CHECK_ALL_PASS`、`P0-02_CHECK_ALL_PASS`。历史 P1-C/P1-B 证据未被改写；本轮所有正常、旧版复现、注入失败和回归日志均在 `verification/evidence/P1-C-R1/`。

## 5 旧版复现（原检查器 7643d36）

使用原 `scripts/p1c_diff.py` 和独立数据副本，证据在 `old-repro/`：

| 项目 | 预期 | 实际 |
| --- | --- | --- |
| F01 尾记录 | 原检查器错误接受 | `P1C_DIFF_PASS`、exit 0，`f01-extra-endpoint.log` |
| F01 priv=S | 原检查器错误接受 | `P1C_DIFF_PASS`、exit 0，`f01-priv-s.log` |
| F02 脏基线 + `--inject rd` | 原检查器错贴 RD 原因 | `P1C_DIFF_NEGATIVE_RD_DETECTED` 但首差异 field=pc，exit 1 |

修复后的差分器对同样变体分别以完整消费/真实 priv/基线失败拒绝。

## 6 文件清单

| 路径 | 说明 |
| --- | --- |
| `scripts/p1c_diff.py` | 全量 DUT、真实字段、基线/原因绑定、七类注入 |
| `scripts/p1c_make_trace_variant.py` | 尾记录/坏行/priv/next_pc/脏基线变体 |
| `scripts/p1c_branch_matrix.py` | 六分支 taken/untaken 真实矩阵 |
| `scripts/repro_p1_c_r1.sh` | 原检查器 F01/F02 针对性复现 |
| `scripts/check_p1_c.sh` | R1 总入口、恢复/停止/负向/回归 |
| `rtl/frontend/p1_frontend_core.sv` | 暴露 raw held decoded 观察 |
| `rtl/core/p1_integer_top.sv` | 测试请求门控、raw held/前端观察 |
| `verification/p1c/tb/tb_integer.cpp` | 四类真实恢复、ARF 边沿、全量 trace |
| `verification/p1c/tb/tb_faults.cpp` | 16 边沿 fault 保持、JALR 非对齐 |
| `software/p1c/directed.S` | 六分支双向矩阵与恢复程序 |
| `docs/architecture/p1-c-modules.md` | R1 更新说明 |

## 7 F01—F03 / V01—V04 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 | 关闭 | DUT 全量消费、唯一末尾终点、真实 priv、实际后继 next_pc/最终字段 |
| F02 | 关闭 | 干净基线、唯一目标差异、七类注入、extra/wrong-reason 拒绝、实际 FAIL |
| F03 | 关闭 | 四类真实恢复、六分支矩阵、16 边沿 fault 保持、JALR bit1 非对齐、ALU 锚点 |
| V01 | 通过 | 完整消费、实际字段、最终寄存器/终点/数量 |
| V02 | 通过 | 基线/原因隔离、七类注入、实际总入口失败 |
| V03 | 通过 | 真实控制流恢复、停止保持、分支矩阵、边界 |
| V04 | 通过 | 同 Commit 正常 exit 0、随机 3844、P1-B/P1-A/P0、证据哈希 |

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
任务：P1-C-R1
实际修复基线 Commit：4f0992b374b9b4cfde7e61e2fadd206768ff82e0
分支：codex/p1-c-integer-execute
被测试实现 Commit：d8d7cabe9cad2b967ce7146feed6313848945ef9
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-C-R1-report.md
证据目录：verification/evidence/P1-C-R1/
证据数量：919 项（含 SHA256SUMS）
SHA256SUMS：7c48f0677f3e58d854cbd4523b1755b154cddd27cfd6973a0577fbf2e762a9d5
F01—F03 / V01—V04：全部通过
```
