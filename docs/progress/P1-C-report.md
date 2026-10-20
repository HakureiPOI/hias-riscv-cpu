# P1-C 整数执行与顺序提交报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-C |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 任务基线 | `9156a0b5edc83995521653ce8508b7d43c3fd92a`（P1-B 验收与 P1-C 任务单） |
| 分支 | `codex/p1-c-integer-execute` |
| 被测试实现 Commit | `7643d36c7b4cd590e7b62226f08931b736d9ab7d` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-C-report.md` |
| 证据目录 | `verification/evidence/P1-C/`（519 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `2a70e44f9c49a4f9d4a3b27e22d2bc4f7010b89fc9a29e099d5f315808ac0e03` |

本轮复用已验收 P1-B 前端和 P1-A RAM/桥，新增真实 ARF、整数 ALU、29 条整数/控制流执行、单项顺序提交、真实 DUT 退休记录和 29 条子集 Spike 差分。未实现 Load/Store、CSR 状态/Trap、真实 Trap 处理、M/A/C/F、OoO、Cache/MMU/FPU、完整 DiffTest 或 SoC 替换；未合入 `main`，未进入 P1-D/E。

## 1 完成内容

### C01 ARF 与单项顺序后端

- `rtl/core/p1_arf.sv`：32×32 ARF，双组合读、提交写；复位清零；x0 恒读 0、写 x0 抑制。测试覆盖 reset、x0、双重读、写后读与 WAW。
- `rtl/core/p1_integer_core.sv`：单指令在途，状态 `IDLE → EXEC → EXEC2 → COMMIT → IDLE`；接受后在 COMMIT 拍更新 ARF、输出 S0 正常退休并产生控制转移 redirect。`accept_stall_i` 可保持前端译码结果。
- 每次接受分配真实 `rob_token_t{idx=0, gen=next_gen}`；gen 每次接受递增，单在途保证回绕前旧项已提交/停止。Token 随真实提交或 fault 输出；测试断言 idx=0、gen 序列及 8 位回绕。
- 正常项每项恰好一次提交；rd=x0、非写回分支也提交但不写 ARF。TB 在每个提交边沿后检查 `arf_debug_o[rd]` 与提交 `rd_data` 一致。

### C02 整数 ALU 与控制转移

- `rtl/core/p1_alu.sv` 覆盖 10 条 OP、9 条 OP-IMM、LUI/AUIPC、JAL/JALR、6 条分支。
- 32 位加减模运算；有/无符号比较分离；移位取低 5 位，SRA/SRAI 算术右移；SLTIU 对符号扩展后的立即数做无符号比较；LUI/AUIPC/JAL/JALR 链接和原 PC 基数正确。
- JALR 使用旧 rs1+imm 后清 bit0；`rd=rs1`、JAL x0、JAL 链接、前后向分支和有限循环均覆盖。
- 目标对齐：JAL/taken 分支检查 bit1:0；JALR 清 bit0 后检查 bit1。未对齐 taken 目标进入 fault kind=3、cause=0、tval=错误目标；同一目标 untaken 不 fault。
- 控制转移提交时同时向 P1-B 前端输出真实 redirect；该条自身提交/链接写入保留，年轻前端项被清除。定向统计覆盖 redirect 时请求等待 10、响应等待 2、译码保持 3、后端 accept 停顿 5；三个随机种子也分别覆盖这四类（见 `logs/dut-random*.log`）。

### C03 提交、错误停止与边界

- `commit_bundle_t` 只 S0 有效，slot1/Trap 恒空；`priv=M`，csr/mem 字段全部无效。所有正常项（含 x0/分支）各一次。
- TB 从真实提交载荷记录 source=dut 正常记录，`seq` 只由 TB 按事件递增；Token/next_pc 来自 DUT，不用 seq 伪造身份。
- 停止 fault 接口区分：
  - kind=0：fetch instruction access fault；kind=1：非法编码 cause=2；kind=2：合法但本阶段未实现（Load/Store/CSR/System/Fence 等）；kind=3：控制目标未对齐。
- fault 不写 ARF、不产生正常退休/commit、不产生访存副作用；当前不更新 mepc/mcause/mtval/mstatus，不声称 Trap 已实现。
- 定向 fault 证据：illegal kind=1、unsupported kind=2、unaligned JAL/分支 kind=3、fetch kind=0；untaken 未对齐分支不 fault 且正常提交；JALR bit0 清除后对齐目标正常提交。

### C04 前端/RAM 集成与 Spike 子集差分

- `rtl/core/p1_integer_top.sv` 实例化 P1-B `p1_frontend_core`、真实 `ram_bridge`/`ram_128k` 和整数后端；镜像在复位时静默载入；TB 可设置响应延迟和后端 accept 停顿。
- `software/p1c/directed.S` 为纯寄存器 rv32i 程序，初始化全部架构寄存器，覆盖 29 条、边界/符号、RAW/WAW、x0、前后向控制流、JAL/JALR 链接和 bit0 清除、对齐差别；结束于 `end: jal x0,end`。
- `scripts/gen_p1c_random.py` 生成三个固定种子程序（0x1a2b3c4d、0x5e6f7a8b、0x9c0d1e2f），每个含初始化、40 次有界循环、随机算术/前向分支/跳转和尾部。
- Spike 使用平台 `config/platform.spike.args`、`--pc=0x80000000` 直接进入 ELF、`--instructions=5000` 有限运行、`--log-commits` 记录。脚本在第一个 `end` PC 截断参考流，明确无启动 ROM 指令进入比较；不丢弃任何 DUT 退休。
- `scripts/p1c_diff.py` 逐项比较 PC、原指令、priv、rd_we/rd/rd_data；DUT next_pc 与相邻参考 PC 比较，最后一条用 end PC 快照补足（参考 next_pc 标记 derived）；最终比较全部 32 个 ARF 寄存器和退休数量。参考 Token 不可观测，只断言 DUT 内部 idx=0 与 gen 递增/回绕。
- 证据包含 ELF/BIN/S 源、objdump、nm、Spike 原始提交、DUT JSONL、寄存器快照和差分日志。

## 2 验证结果（V01—V05）

总入口：`make check-p1-c`，在被测试实现 Commit `7643d36c7b4cd590e7b62226f08931b736d9ab7d` 上退出 0，输出 `P1-C_CHECK_ALL_PASS`。

### V01 ALU/ARF

- `p1_alu` 单元：29 个 exec op 的定向 2900 组边界组合 + 20000 随机组；独立 C++ 语义期望；`P1C_ALU_PASS`。
- `p1_arf` 单元：reset 全零、双读、x0 抑制、写后读/WAW；`P1C_ARF_PASS`。
- 真实程序覆盖 29 条、全部寄存器、x0、RAW/WAW、rd/源重叠、边界立即数和移位。

### V02 控制流/错误

- 六种分支 taken/untaken、前后向、JAL x0/链接、JALR bit0 清除/rd=rs1、未对齐 taken/untaken 差别均通过（定向程序 + fault 探针）。
- 前端 redirect 覆盖四类等待位置，定向计数
  `redirect_pending=10 redirect_resp=2 redirect_dec=3 redirect_stall=5`；三个随机种子也分别非零。
- fault/unsupported 不写 ARF、不提交、无 RAM 写；fetch/illegal/unsupported/unaligned 分别区分。

### V03 提交/差分

| 程序 | 退休数 | 差分结果 |
| --- | ---: | --- |
| directed | 118 | `P1C_DIFF_PASS` |
| random seed 0x1a2b3c4d | 1281 | `P1C_DIFF_PASS` |
| random seed 0x5e6f7a8b | 1281 | `P1C_DIFF_PASS` |
| random seed 0x9c0d1e2f | 1282 | `P1C_DIFF_PASS` |

随机合计 3844 条正常退休，每种子 >1000。DUT/Spike 的 PC、指令、priv、rd 写/值、DUT next_pc（参考为 derived）和最终 32 个 ARF 寄存器/退休数全部一致。DUT JSONL 通过 `check_retire_contract.py --validate-file`；Token idx/gen 和提交时 ARF 边沿断言通过。

### V04 检测/入口

- 正常对照：上述差分全部通过。
- 负向：`--inject pc`、`instr`、`rd`、`next_pc`、`missing`、`duplicate`、`token` 均产生可区分的 `P1C_DIFF_NEGATIVE_*_DETECTED`，退出 1；首差异报告序号/字段/两侧值。
- 实际总入口注入：`P1_C_EVIDENCE=verification/evidence/P1-C/probe-fail/retire P1_C_INJECT=pc make check-p1-c` 退出非零，`summary.log` 为 `result: FAIL`，`diff-directed.log` 记录 `P1C_DIFF_NEGATIVE_PC_DETECTED`；原正常步骤未被改成成功。
- 主机看门狗/kill-after、周期/退休预算、真实构建退出码传播保留。

### V05 回归/追溯

- 实现先提交 `7643d36`；全套正常和注入运行均在同一 Commit 上。
- `P1_B_EVIDENCE=verification/evidence/P1-C/regression/P1-B make check-p1-b` 退出 0，`P1-B-R2_CHECK_ALL_PASS`；内部 P1-A/P0 日志落在本轮 regression 子目录。
- 证据 519 个文件（518 个日志/源码/ELF/BIN/JSONL + `SHA256SUMS`）；`sha256sum -c` 通过。

## 3 文件清单

| 路径 | 说明 |
| --- | --- |
| `rtl/core/p1_arf.sv` | 32×32 ARF |
| `rtl/core/p1_alu.sv` | 29 条整数/控制 ALU |
| `rtl/core/p1_integer_core.sv` | 单指令顺序后端、Token、提交、redirect、fault |
| `rtl/core/p1_integer_top.sv` | P1-B 前端 + RAM/桥 + 整数后端 |
| `rtl/p1_c.f` | P1-C RTL 文件清单 |
| `software/p1c/directed.S` | 定向汇编程序 |
| `verification/p1c/tb/*` | ALU/ARF、DUT 退休/ARF、fault/控制边界 TB |
| `scripts/gen_p1c_random.py` | 三个固定种子随机程序生成器 |
| `scripts/p1c_diff.py` | DUT/Spike 子集差分与负向注入 |
| `scripts/check_p1_c.sh` | P1-C 总入口 |
| `docs/architecture/p1-c-modules.md` | 模块/边界/差分说明 |

## 4 V01—V05 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| V01 | 通过 | ALU 29 类、边界/随机、ARF；真实程序覆盖 |
| V02 | 通过 | 分支/JAL/JALR、对齐、fault、前端四类 redirect 恢复 |
| V03 | 通过 | 单项提交/ARF 边沿/Token、118+3844 条 Spike 差分、最终寄存器 |
| V04 | 通过 | 正常对照、七类差分负向、实际总入口 FAIL、看门狗/预算 |
| V05 | 通过 | 同 Commit 正常 exit 0、P1-B/P1-A/P0 回归、证据哈希 |

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| Load/Store、LSU 与访存退休 | 未实现（P1-D） |
| CSR 状态、Trap/MRET/WFI/Fence、完整异常处理 | 未实现（P1-E/F）；当前只说 held fault |
| M/A/C/F、FPU | 未实现 |
| OoO/双发射、ROB/IQ/BPU/Cache/MMU | 未实现 |
| 完整启动/终止协议、完整 DiffTest、SoC 替换 | 未实现 |
| FPGA 综合/时序/上板 | 未进行 |

P1-C 的“29 条子集差分通过”不等于完整 RV32I/P1 门禁通过；fault 停止不等于 Trap 已实现。未合入 `main`，未进入 P1-D/E。

## 6 交付摘要

```text
任务：P1-C
任务基线 Commit：9156a0b5edc83995521653ce8508b7d43c3fd92a
分支：codex/p1-c-integer-execute
被测试实现 Commit：7643d36c7b4cd590e7b62226f08931b736d9ab7d
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-C-report.md
证据目录：verification/evidence/P1-C/
证据数量：519 项（含 SHA256SUMS）
SHA256SUMS：2a70e44f9c49a4f9d4a3b27e22d2bc4f7010b89fc9a29e099d5f315808ac0e03
V01—V05：全部通过
```
