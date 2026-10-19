# P1-A-R1 RAM 边界与验证修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-A-R1 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 原最终交付 | `dcdb54cda060a018212d159dad0cd36fcda8e481` |
| 实际修复基线 | `8dc5f1b169d95005af8550012e3b47eeffe5d699`（`dcdb54c` 合并 `origin/main` 的 `f69887f` 审查/R1 任务单） |
| 分支 | `codex/p1-a-foundation` |
| 被测试实现 Commit | `8e82d69036adbe9904c6aa55556236ad2e0ee4e3` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P1-A-R1-report.md` |
| 证据目录 | `verification/evidence/P1-A-R1/`（128 项，`SHA256SUMS`） |

本轮仅修复 RAM 边界、TB 时序/副作用/统计与负向 runner 保护；保留 P1-A 骨架、Token 联合补测和冻结平台。未实现 CPU 数据通路，未合入 `main`，未进入 P1-B。

## 1 先复现 F01

针对旧实现 `afbb11d15094e234c1c9c1eda78d40dacf83cc2a`，在独立临时目录提取旧 RTL/TB，预置 RAM 尾字 `0xA1B2C3D4` 与相邻保护字 `0x11223344`。证据：`verification/evidence/P1-A-R1/repro/`（`README.log`、`f01_repro.cpp`、`f01-old.log`）。

旧行为（`f01-old.log`）：

```text
TOP_BYTE_READ  accepted=1 error=0 rdata=0x000000a1
TOP_HALF_READ  accepted=1 error=0 rdata=0x0000a1b2
TOP_WORD_READ  accepted=1 error=0 rdata=0xa1b2c3d4
SIZE3_READ     accepted=1 error=1 cause=4
TOP_BYTE_WRITE accepted=1 error=0
TAIL_READ_AFTER_BYTE = 0x5ab2c3d4
TOP_WORD_WRITE accepted=1 error=0
TAIL_READ_AFTER_WORD = 0xdeadbeef
GUARD_READ_AFTER_WORD = 0x11223344
```

即：顶端 34 位 PA 的 byte/half/word 通过范围检查并别名到 RAM 尾字；非法 Store 实际改写 RAM；`size=3` 被报为 misaligned 而非接口 access fault。复现进程退出 0，观察值本身即错误行为。

## 2 修复内容

### F01 / V01：范围与非法编码

- `ram_bridge` 先要求 size 合法，再要求起始 PA 在 RAM 内，并用 `RAM_END - pa >= size_bytes` 的安全剩余空间检查；不再使用会截断的 34 位 `pa + size`。
- 顶端 PA `0x3ffffffff`（byte）、`0x3fffffffe`（half）、`0x3fffffffc`（word）的 Load/Store 均返回 access fault（5/7），ID/代次正确，不进入 RAM 写口。
- `size=3` 按接口非法请求返回 access fault；只有有效宽度的自然对齐失败才返回 misaligned。
- 新增顶端 PA 读/写、`size=3` 正/反检查；预置 RAM 尾字与相邻保护字，非法请求后回读一致。
- 证据：`logs/ram-run.log`、`repro/f01-old.log`。

### F02 / V02：真实边沿监视与数据副作用

- 统一 `low()`/`edge()` 时钟推进；所有仿真边沿（含初始化与事务）计入 `cycles`，运行中达到预算立即非零退出。
- 增加请求接受/完成/实际 RAM 写事件计数；合法 Store 一次实际写、非法请求零写；`accepted_count == completed_count` 与 `write_events == expected_writes` 在末尾核对。
- 响应背压时从首次 valid 起逐拍检查完整 payload 稳定；请求在 `valid=1 && ready=0` 时保持 payload 稳定；握手后有两个空闲观察周期检测无主/重复响应。
- 新增真正的 pipeline stall：A 响应背压期间呈现 B 请求，检查 `req_ready=0`、B payload 稳定，然后同一边沿消费 A 并接受 B。
- 新增已接受 Store + Flush，验证写入保留、响应一次；原有未接受请求 Flush 行为保留。
- 新增受控稳定性反例：TB 包装在 `fault_mode` 下改变 held 响应，逐拍检查器以 `held response changed while backpressured` 失败；输出 `P1-A_RAM_TB_STABILITY_DETECTED`。
- 修复后实际统计：

```text
P1-A_RAM_TB_PASS transactions=1404 legal=629 illegal=773 cycles=43835
```

- 独立模型使用无溢出范围判断与显式 size 合法性，不复刻 RTL 的有限位宽溢出。

### F03 / V03：所有负向路径有界

- `scripts/check_p1_a.sh` 的统一 `run_logged`/`run_expected` 均使用可配置 `P1_A_HOST_TIMEOUT`（默认 120s）与 `P1_A_KILL_AFTER`（默认 5s）的 `timeout -k`；非法/无界配置直接退出 2。
- 比较负向、稳定性负向、专用 timeout、忽略 TERM、比较入口挂起均受主机看门狗约束；超时/构建失败/缺失二进制不会被当作预期比较失败。
- 实际探针：

| 探针 | 预期 | 实际 | 证据 |
| --- | --- | --- | --- |
| 比较负向 | 1 + mismatch 消息 | 1 | `logs/ram-mismatch-probe.log` |
| 稳定性负向 | 1 + `STABILITY_DETECTED` | 1 | `logs/ram-stability-probe.log` |
| 专用 timeout | 124 + timeout 消息 | 124，约 6s | `logs/ram-timeout-probe.log` |
| 忽略 TERM | 137 + ignore-term 消息 | 137，约 7s | `logs/ram-timeout-ignore-term-probe.log` |
| 比较入口挂起 | 124 + comparison-hang 消息 | 124，约 5s | `logs/ram-comparison-hang-probe.log` |

## 3 回归与版本（V04）

实现先提交为 `8e82d69...`；删除 `build/` 与本轮 logs/regression 后，在同一 Commit 上运行：

```sh
P1_A_EVIDENCE=verification/evidence/P1-A-R1 make check-p1-a
```

退出 0，汇总 `logs/summary.log`：

```text
git_head: 8e82d69036adbe9904c6aa55556236ad2e0ee4e3
git_branch: codex/p1-a-foundation
git_status:
  ?? verification/evidence/P1-A-R1/
result: PASS
```

`P1-A_CHECK_ALL_PASS`。回归：

```sh
env P0_02_EVIDENCE=verification/evidence/P1-A-R1/regression/p0-02 make check-p0-02
```

退出 0，`P0-02_CHECK_ALL_PASS`；嵌套 P0-01/R1 日志仍位于本轮 `regression/p0-02/regression/` 下。历史 P0/P1-A 报告与证据未修改。

## 4 F/V 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 | 关闭 | 顶端 PA 回绕、非法 Store 别名、size=3 原因码修复 |
| F02 | 关闭 | 边沿计数、稳定性/守恒/写事件、pipeline stall、Store+Flush、稳定性反例 |
| F03 | 关闭 | 统一主机看门狗 + kill-after，含忽略 TERM 与比较入口挂起 |
| V01 | 通过 | 顶端 PA 读/写反例与 RAM 尾/保护值保持 |
| V02 | 通过 | 1404 事务、629 合法/773 非法、43835 周期，独立记分板 |
| V03 | 通过 | 背压/延迟/恰好一次/取消/回绕联合与所有负向探针 |
| V04 | 通过 | 同 Commit 总入口与 P0 回归 |

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 取指/译码/ALU/LSU/CSR/ROB/Cache/MMU/FPU | 未实现 |
| 真实退休/DiffTest | 未实现；P1-A 不产生伪退休 |
| UART/结果寄存器/中断外设 | 未实现；MMIO 地址返回 access fault |
| FPGA 综合/时序/资源/上板 | 未进行 |
| P1-B | 未开始 |

模块文档已将 P1-B 更正为只做 Fetch/Decode；执行、访存、CSR、真实退休与差分分别由 P1-C—F 推进。课程 FPU/OS/板卡/Benchmark 仍待确认。无环境阻塞。未合入 `main`，未进入 P1-B。

## 6 交付摘要

```text
任务：P1-A-R1
实际修复基线 Commit：8dc5f1b169d95005af8550012e3b47eeffe5d699
分支：codex/p1-a-foundation
被测试实现 Commit：8e82d69036adbe9904c6aa55556236ad2e0ee4e3
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P1-A-R1-report.md
证据目录：verification/evidence/P1-A-R1/
证据数量：128 项
SHA256SUMS：677c17a46b909571907eb7f874346ae7f07d4ba5735ffc5f1fb89033537cf121
F01—F03：关闭
V01—V04：全部通过
未完成项：CPU 数据通路、DiffTest、MMIO/外设、FPGA、P1 实机测试
建议下一步：管理复审通过后下达 P1-B 取指/译码任务
```
