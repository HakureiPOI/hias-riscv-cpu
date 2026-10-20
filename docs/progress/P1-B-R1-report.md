# P1-B-R1 译码与恢复修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-B-R1 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `087f21f2ae6baefdc86ac3c3ae45a9f879b3e79c` |
| 原 P1-B 交付 | `a7862559674f9ac52f1acb60cf4e49cd3a59c8fa` |
| 实际修复基线 | `f4101e0deb2ef726c0782a9cf4567e20da3a6e32`（合并管理提交后的分支顶端） |
| 分支 | `codex/p1-b-fetch-decode` |
| 被测试实现 Commit | `f9f501514ddf39ae64e30f73565ec88c65c068ce`（RTL 修复 `8fc743a`，探针补强 `6a9f060`，构建目录修正 `f9f5015`） |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-B-R1-report.md` |
| 证据目录 | `verification/evidence/P1-B-R1/`（315 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `51c3ceb045e9f2e83c7813456b15fde54f27c4771a156989f391fedace7a6e17` |

本轮只关闭 F01—F03。前端仍不执行指令、不更新 CSR、不产生真实 Trap/退休；未合入 `main`，未进入 P1-C。

## 1 修复内容

### F01：JAL 与独立期望

- `rtl/frontend/p1_decode.sv` 删除 JAL 对 `instr[14:12]` 的 funct3 检查；JAL 按 J-type 取立即数，JALR 的功能码检查保留。
- `0x000010ef`、`0x000012ef` 现在分别译码为 JAL x1/x5、imm=+4096、`is_jump=1`、`rd_we=1`。
- 生成器同步修正，移除错误的 `ILL_JAL_F3`；新增 JAL 正负/边界立即数、rd=x0/x1/x5/x31、全部 8 种 `instr[14:12]` 值。期望表从 76 项增至 92 项。
- 增加固定字段断言 `check_jal_anchors()`，不依赖表生成结果；新增 `verification/p1b/spec/jal_anchor.s`，由锁定工具链 `riscv64-unknown-elf-as`/`objdump`/`objcopy` 生成编码与反汇编证据（`logs/jal-anchor-*.log`）。反汇编确认 `0x000010ef` 为 `jal ra,0x1000`，`0x000012ef` 为 `jal t0,0x1004`，并覆盖 +2、-4、最小/最大立即数及 `instr[14:12]=0..7`。

### F02：生效重定向与响应身份闭环

- 统一“有效 redirect”条件为 `redirect_i.valid && target_pc[1:0]==0`：
  - `p1_frontend_core` 组合输出改为 `decoded_o.valid = decoded_valid_o = out_valid_q && !redirect_effective`；生效 redirect 同拍抑制外部 valid 与接受，消费者保持 `accept=1` 也不会接受旧项。
  - `p1_fetch` 只在生效 redirect 时取消请求、清 held 结果和置 discard；非对齐目标只报告 `redirect_error_o`，不更新 PC、不取消在途项、不伪造 Trap。
- 响应身份处理改为先比较 ID/代次：
  - 不匹配响应可以消费并计入无主响应，但不释放真正在途请求、不解除回绕屏障、不生成结果。
  - 取消项保留原 PC/ID/代次；只有匹配的终结响应才释放身份，且取消项不生成译码结果。
  - 连续 redirect 只更新目标 PC，不覆盖在途身份。
- 定向覆盖：held 输出 + redirect + accept 同拍；redirect 与匹配响应同拍；请求等待/响应等待 redirect；连续 redirect；非法目标与在途响应同拍；取消后错误 ID、错误代次、错误 ID+代次分别先到且真响应延迟 4 拍；缩小 `GEN_W=2` 下最后代次取消、错误响应到达、真响应排空后才回绕；默认 `GEN_W=8` 与强制回绕配置均运行。

### F03：累计失败、统一监视与正常入口拒绝反例

- 全局错误计数不再在阶段、复位或种子切换时清零；阶段 PASS 只由该阶段错误增量决定，总 PASS/exit 0 由全局错误决定。
- 所有工作边沿（包括同拍 redirect、故障注入、非法目标）统一走 `begin_cycle`/`commit`；手动路径不再绕过请求/响应/译码接受计数。
- 新增独立请求所有权队列与结果队列：
  - 请求记录 PA/PC、ID、代次、期望字/异常；匹配响应核对返回字、异常和预测占位。
  - 结果队列核对译码接受时的 PC、指令、`fetch_gen` 与预测占位；取消请求不进入结果队列。
  - 区分 `matched`（真实事务完成）与 `orphan`（无主故障响应）；每个阶段检查 `requests==matched`、`matched+orphan==responses`。
- 请求与译码 payload 在 held 期间逐字段稳定比较；译码正常路径比较全部有效字段。非法指令只比较 PC/指令/illegal cause/tval 并要求副作用标志为 0；取指异常只比较异常元数据并要求 `illegal=0`；这明确了无效字段的比较例外。
- 复位前统一门控停止新请求并排空已接受事务/结果，队列为空后才复位；复位不清理全局统计或错误。
- 受控注入：
  - `+inject_directed` 在定向 backpressure 阶段改一个真实期望 `op`，随后恢复，继续完整流程；退出 1，错误为 `op` 比较。
  - `+inject_random0` 在首个随机种子第一次接受时改真实期望，随后恢复；退出 1，错误为 `op` 比较。
  - 正常无注入完整流程退出 0；`P1_B_INJECT=directed make check-p1-b` 实际运行汇总 `result: FAIL`、退出非零（`injection-make/logs/`）。
- 原有 `+mismatch` 真实字段负向、124/137 看门狗、周期/事务预算和构建退出码传播保留。

## 2 阶段统计

以下为默认 `GEN_W=8` 正常运行的实际日志统计（`logs/frontend-default-run.log`）。`accepted` 包含 drain 期间消费的 held 结果；`matched` 是真实完成请求，`orphan` 是故障包装注入的无主响应。

| 阶段 | accepted | requests | responses | matched | orphan | redirects | decode | fetch_exc | errors |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| basic-image | 93 | 95 | 95 | 95 | 0 | 2 | 93 | 0 | 0 |
| directed-backpressure | 2 | 2 | 2 | 2 | 0 | 1 | 2 | 0 | 0 |
| directed-held-redirect-accept | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-request-stall | 2 | 2 | 2 | 2 | 0 | 2 | 2 | 0 | 0 |
| directed-response-redirect | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-same-cycle-redirect | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-fault-id-gen | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fault-id | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fault-gen | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fetch-error | 3 | 3 | 3 | 3 | 0 | 2 | 3 | 1 | 0 |
| directed-illegal-target-pending | 3 | 4 | 4 | 4 | 0 | 2 | 3 | 0 | 0 |
| directed-continuous-redirect | 2 | 2 | 2 | 2 | 0 | 3 | 2 | 0 | 0 |
| directed-wrap | 265 | 265 | 265 | 265 | 0 | 0 | 265 | 0 | 0 |
| random-0 | 341 | 471 | 471 | 471 | 0 | 136 | 341 | 0 | 0 |
| random-1 | 341 | 466 | 466 | 466 | 0 | 142 | 341 | 0 | 0 |
| random-2 | 341 | 452 | 452 | 452 | 0 | 121 | 341 | 0 | 0 |

默认配置总计：`accepted=1405 requests=1777 responses=1780 matched=1777 orphan=3 decode=1405 fetch_exc=1 redirects=420 cycles=10182`。

强制 `GEN_W=2` 配置额外运行三个取消/错误响应阶段：

| 阶段 | accepted | requests | responses | matched | orphan | redirects | decode | fetch_exc | errors |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| directed-cancel-wrong-wrap-id-gen | 5 | 6 | 7 | 6 | 1 | 1 | 5 | 0 | 0 |
| directed-cancel-wrong-wrap-id | 5 | 6 | 7 | 6 | 1 | 1 | 5 | 0 | 0 |
| directed-cancel-wrong-wrap-gen | 5 | 6 | 7 | 6 | 1 | 1 | 5 | 0 | 0 |
| directed-wrap | 41 | 41 | 41 | 41 | 0 | 0 | 41 | 0 | 0 |

强制配置总计：`accepted=1196 requests=1571 responses=1577 matched=1571 orphan=6 decode=1196 fetch_exc=1 redirects=423 cycles=9460`。三个随机种子分别为 340 次随机接受，打印合计 `1020`；每种子 drain 后额外消费的 held 结果计入该阶段 `accepted`。

## 3 旧版复现（278f6f7）

证据在 `verification/evidence/P1-B-R1/old-repro/`，使用独立 worktree 检出原 Commit；原 RTL/原检查器保持原版本，夹具来源与差异见 `verification/p1b/old_repro/README.md`。

| 编号 | 原缺陷证据 |
| --- | --- |
| F01 | `OLD_F01 instr=0x000010ef illegal=1`、`0x000012ef illegal=1`；原 JAL 合法字被拒绝 |
| F02a | `OLD_F02A old_pc=0x80000008 dec_valid=1 ... leak=1`；redirect+accept 同拍仍暴露旧结果 |
| F02b | `OLD_F02B saw_wrong=1 pending_after_wrong=0 early_release=1`；错误 ID/代次响应提前释放取消项 |
| F03 | 原 TB `+mismatch` 注错后继续正常流程，随机种子清空错误，最终 `P1-B_FRONTEND_PASS`、退出 0，`OLD_F03_ERROR_CLEARED` |

F03 夹具只删除原 `+mismatch` 的立即 return，并在基础镜像后恢复期望；原每种子 `tb.errors=0` 清空逻辑保持不变。补丁源码与 diff 在 `old-repro/source/`。

## 4 验证结果（V01—V04）

总入口：`make check-p1-b`，在被测试实现 Commit `f9f501514ddf39ae64e30f73565ec88c65c068ce` 上退出 0，输出 `P1-B-R1_CHECK_ALL_PASS`；`logs/summary.log` 记录同一 `git_head`。

### V01 结构/译码

- 生产前端和 TB 包装 `verilator --lint-only -Wall --assert` 通过（`logs/lint.log`、`logs/lint-tb.log`）。
- JAL assembler/objdump 锚点通过（`logs/jal-anchor-*.log`）。
- 独立译码表 92 项通过：`P1-B_DECODE_PASS cases=92`；固定 JAL 锚点、全部 8 种 `instr[14:12]`、正负/边界立即数、rd=x0/x1/x5/x31 均逐字段检查。
- 真实字段负向：`decode_tb +mismatch` 退出 1，`P1-B_DECODE_NEGATIVE_MISMATCH_DETECTED`（`injection/`）。

### V02 取指/恢复

- 默认和强制回绕配置均通过：镜像 92 条、RAM 末字、越界取指异常、held redirect+accept、请求/响应等待 redirect、同拍响应 redirect、非法目标同拍、连续 redirect、错误 ID/代次后恢复、取消后真响应延迟、回绕屏障。
- 每阶段统计见第 2 节；`requests==matched`、`matched+orphan==responses` 均通过。
- `P1-B_FRONTEND_PASS` 默认与强制配置分别记录实际请求/响应/匹配/无主/译码/异常/redirect/周期计数。

### V03 检测/回归

- 正常完整流程退出 0；三个固定种子分别完成 340 次随机接受，合计 1020。
- 定向阶段注入：`+inject_directed` 退出 1，首个错误为 `op got=0x2 want=0x3`，恢复后后续阶段继续；`+inject_random0` 退出 1，首个错误为 `op got=0x0 want=0x1`。
- 实际总入口注入：`P1_B_EVIDENCE=verification/evidence/P1-B-R1/injection-make P1_B_INJECT=directed make check-p1-b` 退出非零，`summary.log` 为 `result: FAIL`；未把预期失败改写成成功。
- `+mismatch`、`+hang`（124）、`+hang_ignore_term`（137）通过；周期预算与真实构建退出码传播保留。
- 旧版 F01/F02/F03 复现通过。

### V04 追溯/回归

- 实现先提交 `8fc743a`，探针补强提交 `6a9f060`，旧版复现构建目录修正提交 `f9f5015`；全套正常检查与注入检查均在同一被测试 Commit `f9f501514ddf39ae64e30f73565ec88c65c068ce` 上运行。
- `P1_A_EVIDENCE=verification/evidence/P1-B-R1/regression/P1-A make check-p1-a` 退出 0，`P1-A_CHECK_ALL_PASS`，嵌套 `P0-02_CHECK_ALL_PASS`；历史证据未修改。
- 证据 315 个文件（314 个日志/源码/数据 + `SHA256SUMS`）；`sha256sum -c SHA256SUMS` 通过。

## 5 文件清单

| 路径 | 说明 |
| --- | --- |
| `rtl/frontend/p1_decode.sv` | JAL J-type 修复与 92 项覆盖对应译码 |
| `rtl/frontend/p1_fetch.sv` | 有效 redirect、匹配响应释放、取消身份/回绕屏障 |
| `rtl/frontend/p1_frontend_core.sv` | redirect 同拍输出抑制 |
| `verification/p1b/gen_decode_cases.py` | JAL/边界/全部 `instr[14:12]` 期望 |
| `verification/p1b/decode_expected.h` | 92 项独立期望表 |
| `verification/p1b/spec/jal_anchor.s` | assembler/objdump 规范锚点 |
| `verification/p1b/tb/tb_decode.cpp` | 固定 JAL 字段断言与译码负向 |
| `verification/p1b/tb/frontend_tb_top.sv` | 全字段观察、可延迟故障响应注入 |
| `verification/p1b/tb/tb_frontend.cpp` | 统一边沿监视、所有权队列、阶段统计、注入/取消测试 |
| `verification/p1b/old_repro/*` | 旧版 F01/F02 夹具与说明 |
| `scripts/repro_p1_b_r1.sh` | 旧版复现入口 |
| `scripts/check_p1_b.sh` | R1 总入口 |
| `docs/architecture/p1-b-modules.md` | 更新后的模块/验证说明 |

## 6 F01—F03 / V01—V04 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 | 关闭 | JAL 合法字/全部立即数边界/8 种 `instr[14:12]` 通过，工具链锚点留证 |
| F02 | 关闭 | 同拍输出抑制、取消身份闭环、错误响应不提前释放、非法目标不取消、默认/强制回绕均通过 |
| F03 | 关闭 | 全局错误不清零、统一边沿监视、所有权队列/全字段稳定、两个注入反例和实际 FAIL 入口留证 |
| V01 | 通过 | lint、JAL 锚点、92 项译码、JAL 负向 |
| V02 | 通过 | 恢复/取消/回绕/非法目标定向与阶段守恒 |
| V03 | 通过 | 1020 随机接受、旧版复现、注入/看门狗/正常对照 |
| V04 | 通过 | 实现先提交、同 Commit 正常检查 exit 0、P1-A/P0 回归、证据哈希 |

## 7 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 指令执行、ALU、分支解析、LSU 执行 | 未实现 |
| CSR 状态更新、Trap/中断/真实退休 | 未实现；前端不产生 commit/Trap |
| ROB/IQ、BPU、Cache、MMU、FPU、DiffTest | 未实现 |
| P1-C 后端接入 | 未开始；只提供 `decoded_o`/`redirect_i` 接口 |
| SoC 顶层替换空闲骨架 | 未进行 |
| FPGA 综合/时序/上板 | 未进行 |

FENCE/FENCE.I 仍只做保守分类；CSR 地址权限/写合法化留待 P1-E。未合入 `main`，未进入 P1-C。

## 8 交付摘要

```text
任务：P1-B-R1
实际修复基线 Commit：f4101e0deb2ef726c0782a9cf4567e20da3a6e32
分支：codex/p1-b-fetch-decode
被测试实现 Commit：f9f501514ddf39ae64e30f73565ec88c65c068ce
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-B-R1-report.md
证据目录：verification/evidence/P1-B-R1/
证据数量：315 项（含 SHA256SUMS）
SHA256SUMS：51c3ceb045e9f2e83c7813456b15fde54f27c4771a156989f391fedace7a6e17
F01—F03 / V01—V04：全部通过
```
