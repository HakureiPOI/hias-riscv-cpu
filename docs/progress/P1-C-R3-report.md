# P1-C-R3 fault 探针失败传播报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-C-R3 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `592dbabe2a20848494cbb4d875170b5797505b69` |
| 修复起点（代码变更前） | `ac827066925c6b71ad8ffe8fb0949c24d0f33ffb` |
| 被测试实现 Commit | `aa4272c8c3d64f3319650ec60c12dcb98ebe9587`（`3875710` 修复 + `592dbab` 管理文档合并） |
| 分支 | `codex/p1-c-integer-execute` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-C-R3-report.md` |
| 证据目录 | `verification/evidence/P1-C-R3/`（1008 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `ba8a19a8f2251e0a6dec6b0568bcc497d2926ee3339190513daf881ae88b6e05` |

本轮仅关闭 H01，保留整数执行、ARF/ALU、单项顺序提交、格式门禁、独立提交镜像、Spike 子集差分和恢复成果。未实现 Load/Store、CSR/Trap、M/A/C/F、OoO/Cache/MMU/FPU、完整 DiffTest、SoC 替换或 FPGA；未合入 `main`，未进入 P1-D/E。

## 1 H01：统一正常与负向监视路径

- `tb_faults.cpp` 不再在 `initial_arf`/`hold_change` 分支重新做局部 `same_regs` 后直接打印 DETECTED 返回。正常与两类注入都把观察值送入同一个 `compare_arf` 监视器，并统一累计：
  - `target_errors`：指定注入的 ARF/保持差异；
  - `other_errors`：提交 PC/指令/写入、独立镜像、fault kind/PC/instr/cause/tval、Token/fetch_gen、禁止 commit/Trap/RAM 写、16 边沿保持、fault 前缀数量等全部其他失败。
- 只有 `target_errors>0`、`other_errors==0`、`scenario_ok`（fault 到达且实际提交数等于 `commit_pcs.size()`）同时成立，才输出对应 DETECTED 并返回负向退出码 1。
- 目标未检出返回 NOT_DETECTED（2）；目标存在但另有错误返回 EXTRA_ERRORS（3）；场景未完成返回 SCENARIO_FAIL（4）。所有路径先打印 `P1C_FAULT_PROBE_STATS target_errors=... other_errors=... scenario=...`，不提前返回忽略已有错误。
- 故障分支新增 `commits == commit_pcs.size()` 明示检查；Token gen 与预期前缀提交数交叉核对。
- 额外错误通过同一 metadata 检查器制造：在故障 cause 观察上注入 `cause^1`，不是直接调用 fail；目标寄存器/保持注入仍由真实 ARF 监视器检出。

## 2 针对性证据

| 探针 | target_errors | other_errors | 结果 |
| --- | ---: | ---: | --- |
| `initial_arf` 正常对照 | 0 | 0 | `P1C_FAULT_PASS` |
| `initial_arf` 仅目标错误 | 1 | 0 | `INITIAL_ARF_DETECTED`, exit 1 |
| `initial_arf_extra` 目标 + cause 错误 | 1 | 1 | `INITIAL_ARF_EXTRA_ERRORS`, exit 3 |
| `initial_arf_missing` 目标未检出 | 0 | 0 | `INITIAL_ARF_NOT_DETECTED`, exit 2 |
| `hold_change` 仅目标错误 | 1 | 0 | `HOLD_CHANGE_DETECTED`, exit 1 |
| `hold_change_extra` 目标 + cause 错误 | 1 | 1 | `HOLD_CHANGE_EXTRA_ERRORS`, exit 3 |
| 正常 fault 场景 | 0 | 0 | PASS，16 边沿保持 |

正常关闭注入的 fault 场景全部通过；目标加额外错误不再获得 DETECTED。

## 3 实际总入口失败

- `P1_C_INJECT=probe_initial_extra make check-p1-c`：原 `fault-negative-initial` 预期检出步骤被运行成 `initial_arf_extra`，返回 3/EXTRA_ERRORS，runner 仍按 rc1+DETECTED 判据拒绝，步骤 FAIL、汇总 `result: FAIL`、make 非零。
- `P1_C_INJECT=probe_hold_extra make check-p1-c`：同样使原 `fault-negative-hold` 步骤失败、总入口 FAIL。
- 既有 `P1_C_INJECT=fault_initial`/`fault_hold` 对正常 fault 步骤的失败证据保留在 P1-C-R2 证据中；正常探针判据未放宽。

## 4 旧版复现（3ed8ec9）

使用原 `tb_faults.cpp` 和独立 observation wrapper：在 fault 时把观察到的 `fault_cause` 改为错误值，同时原 TB 的 `initial_arf` 注入仍执行。原 TB 先累计 cause mismatch，随后在局部 x1 比较处直接 `DETECTED` 并 exit 1，掩盖已有错误。

证据 `old-repro-r3/run.log`：

```text
P1C_FAULT_TRACE ... phase=fault_first kind=3 cause=1 ...
P1C_FAULT_NEGATIVE_INITIAL_ARF_DETECTED
exit: 1
OLD_H01_EARLY_RETURN_MASKED_ERROR_REPRODUCED
```

修复后的同一额外错误判据输出 `PROBE_STATS target_errors=1 other_errors=1` 与 EXTRA_ERRORS，退出 3，不再得到 DETECTED。

## 5 正常回归

`make check-p1-c` 在被测试 Commit `aa4272c` 上退出 0：

| 项目 | 结果 |
| --- | --- |
| 定向程序 | 124 条退休，Spike diff PASS |
| random 0x1a2b3c4d / 0x5e6f7a8b / 0x9c0d1e2f | 1281 / 1281 / 1282，合计 3844 |
| 六分支矩阵 | 六种分支 taken/untaken |
| 四类恢复 | req_wait=28、resp_wait=28、held=28、resp_same=1 |
| 正常 fault/停止 | illegal/unsupported/unaligned/JALR bit1/fetch/branch_untaken/JALR clear |
| 负向 | 差分七类、格式门禁、fault initial/hold/extra/missing |
| 回归 | `P1-B-R2_CHECK_ALL_PASS`、`P1-A_CHECK_ALL_PASS`、`P0-02_CHECK_ALL_PASS` |

历史 P1-C/P1-C-R1/P1-C-R2 证据未改写。主机看门狗/kill-after、周期/退休预算、构建退出码传播保留；正常与预期失败运行分目录。

## 6 文件清单

| 路径 | 说明 |
| --- | --- |
| `verification/p1c/tb/tb_faults.cpp` | 统一监视、target/other 分类、场景/额外错误判定、H01 回归 |
| `verification/p1c/old_repro/integer_tb_top_old_repro_r3.sv` | 旧 TB cause 错误观察夹具 |
| `scripts/repro_p1_c_r3.sh` | 3ed8ec9 旧版 H01 复现 |
| `scripts/check_p1_c.sh` | R3 总入口、fault extra/missing 探针、probe 注入失败 |
| `docs/architecture/p1-c-modules.md` | H01 当前验证说明 |

## 7 H01 / V01—V03 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| H01 | 关闭 | 正常/注入统一监视；target/other 分离；提前 DETECTED 路径移除 |
| V01 | 通过 | 统一 ARF/保持监视、全失败路径累计、场景/前缀检查 |
| V02 | 通过 | initial/hold 目标、额外错误、未检出对照；实际总入口 FAIL |
| V03 | 通过 | 同 Commit 正常 exit 0；3844 随机退休；P1-B/P1-A/P0；证据哈希 |

## 8 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| Load/Store、LSU、访存退休 | 未实现（P1-D） |
| CSR 状态、Trap/MRET/WFI/Fence、完整异常处理 | 未实现（P1-E/F） |
| M/A/C/F、FPU | 未实现 |
| OoO/ROB/IQ/BPU/Cache/MMU、完整 DiffTest | 未实现 |
| SoC 替换、FPGA | 未进行 |

29 条子集差分通过不等于完整 RV32I/P1 门禁通过。未合入 `main`，未进入 P1-D/E。

## 9 交付摘要

```text
任务：P1-C-R3
修复起点 Commit：ac827066925c6b71ad8ffe8fb0949c24d0f33ffb
分支：codex/p1-c-integer-execute
被测试实现 Commit：aa4272c8c3d64f3319650ec60c12dcb98ebe9587
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-C-R3-report.md
证据目录：verification/evidence/P1-C-R3/
证据数量：1008 项（含 SHA256SUMS）
SHA256SUMS：ba8a19a8f2251e0a6dec6b0568bcc497d2926ee3339190513daf881ae88b6e05
H01 / V01—V03：全部通过
```
