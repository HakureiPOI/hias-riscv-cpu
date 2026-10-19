# P1-A-R2 验证收尾报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-A-R2 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 原最终交付 | `6905b9ec40db42e4e113db19261478e35de6f873` |
| 实际修复基线 | `350d03ff0b8b7e3f2abc722a0d2b91166bf386b5`（`6905b9e` 合并 `origin/main` 的 `538c87a` 复审/R2 任务单） |
| 分支 | `codex/p1-a-foundation` |
| 被测试实现 Commit | `cacf71aaa2e3f80bd53ba1be9ae8d4ab67f66e1b` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P1-A-R2-report.md` |
| 证据目录 | `verification/evidence/P1-A-R2/`（254 项，`SHA256SUMS`） |

本轮只做验证收尾：探针错误绑定、物理回读与统一边沿监视、意外挂起总入口失败证据。未重写已接受的 RAM 地址修复，未重开 Token 联合用例，未实现 CPU 数据通路；未合入 `main`，未进入 P1-B。

## 1 G01：探针只因指定错误通过

- 稳定性探针 ID 从 `0x52` 改为合法 6 位 `0x12`；比较挂起探针从 `0x62` 改为 `0x22`；`mk()` 对 ID > 0x3f 直接报错，避免静默截断。
- 稳定性探针先以 `fault_mode=0` 运行相同请求作为正常对照，要求零错误；再注入 held 响应变化。
- 新增 `stability_errors` 与 `comparison_errors` 分类；稳定性成功标记必须满足 `stability_errors>0` 且 `errors == stability_errors`，其他 ID/数据/超时错误会使探针失败。
- 比较负向必须满足 `comparison_errors>0` 且 `errors == comparison_errors`，并输出 `P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED comparison_errors=1`。
- 新增 final-handshake 受控反例：在 `resp_ready=1` 的最终握手拍改变载荷，由同一稳定性监视器报告；成功条件明确允许该注入导致的 stability + comparison + reference 三类预期错误之和。
- 证据：`logs/ram-stability-probe.log`（`stability_errors=1`，exit 1）、`logs/ram-mismatch-probe.log`（`comparison_errors=1`，exit 1）、`logs/ram-final-handshake-probe.log`（`stability_errors=1 comparison_errors=1`，exit 1）。

## 2 G02：物理观察与统一边沿监视

- 非法顶端 PA / `size=3` 请求后，通过 DUT 总线正常 Load 回读 RAM 尾字与相邻保护字，并与独立预置期望比较；日志明确输出地址、DUT 值、期望和结果：
  - `P1-A_RAM_DUT_READBACK tail_after_illegal pa=0x8001fffc got=0x01020304 expected=0x01020304 result=PASS`
  - `P1-A_RAM_DUT_READBACK guard_after_illegal pa=0x8001fff8 got=0x522d08e3 expected=0x522d08e3 result=PASS`
- 响应监视：从首次 valid 起逐拍比较完整字段；`ready=1` 的最终握手拍也必须与 held payload 相同；valid 提前消失、payload 变化均记入 `stability_errors`。
- 请求监视：`valid=1 && ready=0` 时保存 payload；ready 变高的最终握手拍仍要求与保存值一致；Flush 只用于未接受请求的例外路径。
- 串行 `transact` 与 `pipeline_stall` 共用 `note_request`/`note_accept`/`note_complete` 和按序 `pending_resp` 参考队列；每个接受/完成来自真实 valid/ready 边沿，删除手动 `completed_count += 2`。
- 正常结束核对：事务分类合计 = 接受数 = 完成数 = 参考队列出队数，队列为空；实际 RAM 写事件 = 合法 Store 预期写事件。Pipeline 的两笔请求也进入同一分类与队列。
- 统一 `low()`/`edge()` 覆盖初始化、预载、全部事务和 pipeline；周期预算 200000，运行中到限立即失败。
- 实际正常统计：

```text
P1-A_RAM_TB_PASS transactions=1406 legal=633 illegal=773
  accepted=1406 completed=1406 writes=319 expected_writes=319 cycles=43847
```

- 保留无主/重复响应空闲窗口、非法零写、合法 Store 一次写、Store/Load+Flush、三个固定种子与原定向项；Token 联合用例保持通过。

## 3 G03：意外比较挂起使实际总入口失败

- `scripts/check_p1_a.sh` 增加 `P1_A_INJECT_MISMATCH_HANG=1`：仅把原 `ram-mismatch-probe` 命令替换为 `timeout -k 2s 3s <ram_tb> +mismatch_hang`，其成功判据仍为 exit 1 + `P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED`。
- 注入运行仍先产生真实比较错误 `read data mismatch`，随后挂起；3 秒后被 `timeout` 以 124 终止，预期 1 不匹配，`ram-mismatch-probe` 步骤失败，汇总 `result: FAIL`，`make check-p1-a` 实际退出 2。
- 外层 `timeout 180s` 未触发；总入口自行失败，不是外层超时冒充传播。
- 完整运行、步骤日志与结果：
  - `verification/evidence/P1-A-R2/injected/total.log`
  - `verification/evidence/P1-A-R2/injected/logs/summary.log`
  - `verification/evidence/P1-A-R2/injected/logs/ram-mismatch-probe.log`
  - `verification/evidence/P1-A-R2/injected/result.log`（`injected_rc=2 elapsed=143s`）

## 4 V01—V04 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| V01 | 通过 | 6 位 ID、正常对照、稳定性/比较专用错误绑定 |
| V02 | 通过 | DUT 物理回读、最终握手稳定、统一队列/计数/写事件、pipeline 同路径 |
| V03 | 通过 | 原比较步骤注入挂起后，实际总入口有界 FAIL（exit 2，143s） |
| V04 | 通过 | 正常 `make check-p1-a` 在同一 Commit 上 exit 0；P0-02/P0-01/R1 回归通过 |

正常回归命令与结果：

```sh
P1_A_EVIDENCE=verification/evidence/P1-A-R2 make check-p1-a
```

退出 0；`P1-A_CHECK_ALL_PASS`；`P0-02_CHECK_ALL_PASS`。嵌套 P0-01/R1 日志位于本轮 `regression/p0-02/regression/`。

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 取指/译码/ALU/LSU/CSR/ROB/Cache/MMU/FPU | 未实现 |
| 真实退休/DiffTest | 未实现 |
| UART/结果寄存器/中断外设、FPGA | 未实现/未进行 |
| P1-B | 未开始 |

模块/验证说明已同步 G01—G03 的探针与观察要求；P1-B 仍只做 Fetch/Decode。课程 FPU/OS/板卡/Benchmark 待确认。无环境阻塞。未合入 `main`，未进入 P1-B。

## 6 交付摘要

```text
任务：P1-A-R2
实际修复基线 Commit：350d03ff0b8b7e3f2abc722a0d2b91166bf386b5
分支：codex/p1-a-foundation
被测试实现 Commit：cacf71aaa2e3f80bd53ba1be9ae8d4ab67f66e1b
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P1-A-R2-report.md
证据目录：verification/evidence/P1-A-R2/
证据数量：254 项
SHA256SUMS：b10f824b84a79527be5467d2df8c2212dd7895090517212e494bff0577125223
G01—G03：关闭
V01—V04：全部通过
未完成项：CPU 数据通路、DiffTest、MMIO/外设、FPGA、P1 实机测试
建议下一步：管理复审通过后结束 P1-A 并下达 P1-B 取指/译码任务
```
