# P0-01-R1 验证入口修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P0-01-R1 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 修复基线 | `741733d35f1e3a3e550ee45e831ccd0c4a4a414a`（首轮交付 `4f4580f` 与 `origin/main` 审查文档 `bc9de2d` 的普通合并提交） |
| 分支 | `codex/p0-01-environment-smoke` |
| 被测试实现 Commit | `251c151e5684dd2751cdb4fe27f557621b34e144` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P0-01-R1-report.md` |
| 证据目录 | `verification/evidence/P0-01-R1/`（`logs/` 正常复测，`probes/` 受控故障注入） |
| 首轮证据 | `verification/evidence/P0-01/` 仍由首轮 Commit `4f4580f` 追溯，不用作本轮结果 |

本轮继续在任务分支修复 F01—F03，不重做环境，不实现 CPU，不进入 P0-02。被测试实现提交后未再修改任何实现文件；报告与证据为后续独立提交。

## 1 修复内容

### F01 正常路径看门狗

- 新增 `scripts/lib/watchdog.sh`。所有实际执行路径统一经 `run_guarded` 调用 `timeout -k 5s`，超时返回 `124/137`，并在日志写入 `P0-01_WATCHDOG_TIMEOUT`、实际退出码、耗时和命令。
- 覆盖范围：RTL 正常仿真、断言探针、记分板负向探针、DUT 周期超时探针、Verilator Lint/构建、Spike 正常/错误/观察运行。
- 保留 RTL 自身 `+max_cycles` 周期预算；主机看门狗与其相互独立。
- 可配置变量：`P0_01_HOST_TIMEOUT`（默认 60）、`P0_01_NORMAL_TIMEOUT`、`P0_01_SPIKE_NORMAL_TIMEOUT`、`P0_01_OBSERVE_TIMEOUT`、`P0_01_STEP_TIMEOUT`（总入口每步骤默认 600）。
- 正常目标挂起时由看门狗判失败，不会等待到外层超时；专用超时探针使用预期 124 + `P0-01_WATCHDOG_TIMEOUT` 双重判定，普通路径超时不会被误记为探针成功。

### F02 构建返回码传播

- `scripts/run_rtl_smoke.sh` 的 `build_sim` 现在立即保存 Verilator 的真实退出码；只有“本次构建返回 0 且目标产物存在”才返回成功。
- `rm -rf` 清理或 `mkdir -p` 目录准备失败会直接记录并返回失败，不使用旧产物。
- 新增隔离包装器 `scripts/probes/verilator_build_fail.sh`：调用真实 Verilator 完成构建后强制返回 3，用于覆盖“二进制存在但构建非零”。
- 构建失败会把失败传播到 `rtl-smoke` 步骤和 `make check-p0-01` 总入口，日志保留真实退出码 3 及失败步骤名。

### F03 真正的记分板负向检测

- 正常模式不变：仍使用独立 `std::deque` 记分板和原有功能判断。
- 负向模式只改写一次队列期望值（`corrupt_next_expected`），然后走正常输出传输比较路径；由该路径报告 `P0-01_SCOREBOARD_MISMATCH: output got 0x1111 expected 0xeeee`。
- 不再依赖 `pop_one` 的额外人工不相等检查来制造“检测成功”。
- 若该比较未报错，探针输出 `P0-01_CHECKER_PROBE_NOT_DETECTED`，验收失败。

## 2 复测结果（V01—V06）

### V01 正常总入口

```sh
rm -rf build verification/evidence/P0-01-R1
make check-p0-01
```

退出码 `0`。日志：`verification/evidence/P0-01-R1/logs/summary.log`。汇总：

```text
host_timeout_seconds: 60
step_timeout_seconds: 600
steps:
  env-check    exit=0
  rtl-smoke    exit=0
  ref-smoke    exit=0
result: PASS
```

原有 E01—E07 正常项仍成立：

- RTL 正常：`P0-01_RTL_SMOKE_PASS cycles=10071 accepted=5890 produced=5768 flush_dropped=120 remaining=0`，固定种子 `0x5eed1234`，随机段 10,000 周期（`logs/normal-rtl.log`）。
- 断言负向：指定断言消息 + 退出码 134（`logs/assertion-probe.log`）。
- 参考程序：RV32I ELF、Spike 正常退出 0 且提交日志写入 `0x50415353`；错误结果退出 1；专用挂起由看门狗以 124 结束（`logs/spike-*.log`）。
- Spike 观察接口正常完成（`logs/spike-observe.log`）。
- 该次运行 `git_head` 为 `251c151...`，工作区除未提交证据外无修改（见 `logs/summary.log`）。

### V02 正常 RTL/Spike 路径受控挂起

```sh
make r1-probes
```

退出码 `0`，仅表示全部预期故障均按预期出现。各子探针真实结果：

| 探针 | 命令要点 | 实际结果 | 证据 |
| --- | --- | --- | --- |
| RTL 正常挂起 | `P0_01_NORMAL_HANG=1 P0_01_NORMAL_TIMEOUT=2 ./scripts/run_rtl_smoke.sh` | `normal-rtl` 退出 124，`P0-01_WATCHDOG_TIMEOUT`，runner 退出 1 | `probes/rtl-normal-hang/run.log` |
| 总入口 RTL 挂起 | 同上环境 + `./scripts/check_p0_01.sh` | 20 秒内结束；`rtl-smoke exit=1`；`result: FAIL`；无外层次级超时 | `probes/total-entry-rtl-hang/` |
| Spike 正常挂起 | `P0_01_SPIKE_NORMAL_HANG=1 P0_01_SPIKE_NORMAL_TIMEOUT=2 ./scripts/run_ref_smoke.sh` | `Spike normal run` 退出 124，`P0-01_WATCHDOG_TIMEOUT`，runner 退出 1 | `probes/spike-normal-hang/` |

总入口探针没有被外层吞掉后冒称 0：日志中的 `outer_exit` 为 1，`summary.log` 的 `result: FAIL` 为真实结果。外层 `timeout 120s` 仅作最后保险，未触发。

### V03 观察命令看门狗

- 正常观察：`logs/spike-observe.log` 退出 0，读到 `zero:` 与 `pc`。
- 受控挂起：`P0_01_OBSERVE_HANG=1 P0_01_OBSERVE_TIMEOUT=2 ./scripts/run_ref_smoke.sh`；`until pc` 目标不可达，Spike 观察进程在 2 秒被终止，退出 124，记录 `P0-01_WATCHDOG_TIMEOUT`，runner 退出 1。
- 证据：`probes/observe-hang/run.log`、`probes/observe-hang/logs/spike-observe.log`。

### V04 构建非零且二进制存在

- 包装器真实构建成功（日志内 `real verilator exit=0`）后强制返回 3。
- `build_sim` 记录 `exit: 3` 并返回失败；不运行后续正常用例。
- 直接 runner：`P0_01_BUILD_FAULT=1 ./scripts/run_rtl_smoke.sh` 退出 1，日志同时出现 `P0-01_BUILD_FAIL: smoke_buffer build returned exit=3` 与 `P0-01_RTL_STEP_FAIL: build smoke_buffer simulator`；此时 `build/rtl-smoke/smoke_sim/obj/smoke_sim` 确实存在。
- 总入口：`P0_01_BUILD_FAULT=1 ./scripts/check_p0_01.sh` 退出 1，`rtl-smoke exit=1`，`result: FAIL`，`rtl-smoke.log` 含上述构建失败行。
- 证据：`probes/build-fault-runner/`、`probes/total-entry-build-fault/`。

### V05 真正的记分板比较

`logs/checker-probe.log` 原始输出：

```text
P0-01_CHECKER_PROBE: injecting one wrong expected value
P0-01_RTL_SMOKE_FAIL: P0-01_SCOREBOARD_MISMATCH: output got 0x1111 expected 0xeeee (cycle=70)
P0-01_CHECKER_PROBE_DETECTED errors=1
exit: 1
```

该消息来自 `tick()` 中正常的队列期望值与实际输出比较，不是 `pop_one` 的人工检查。独立探针 `probes/checker-scoreboard/run.log` 同样通过。正常固定种子 10,000 周期测试继续通过。

### V06 证据与实现对应

- 被测试实现 Commit：`251c151e5684dd2751cdb4fe27f557621b34e144`。
- 先提交实现，再删除 `build/` 与 `P0-01-R1` 旧日志，在干净实现版本上依次运行 `make check-p0-01`、`make r1-probes`。
- 证据共 93 个文件，清单 `verification/evidence/P0-01-R1/SHA256SUMS`，SHA-256 为 `73100cab51dfef0d674bfbfa9958d5ba3a258534587312a3e38dca7e6a81aaf3`。
- 大体积 Spike 提交轨迹不再出现在挂起探针中（挂起探针关闭 `--log-commits` 或使用不可达目标），证据总量约 1.1 MB。
- 未提交 `build/` 产物。

## 3 范围偏离与容量说明

- 管理审查已接受四项 FIFO 作为 P0-01 的小范围偏离，本轮未重写为一项深度缓存。该夹具只是验证环境，不是 CPU 公共模块，不能作为已验收的 CPU 成果。
- Spike 使用 `-m128`（128 MiB 物理内存），链接脚本只声明 128 KiB RAM。当前程序访问均在链接区域内，但这不等于最终系统地址图；P0-02 必须统一 DUT 与参考模型的物理内存/PMA 约定。

## 4 F/V 状态汇总

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 | 完成 | 全部实际执行路径统一主机看门狗；受控挂起在 runner 与总入口均有界失败 |
| F02 | 完成 | 构建真实退出码传播；二进制存在但返回 3 仍使步骤和总入口失败 |
| F03 | 完成 | 负向探针经真实队列比较报告 got/expected |
| V01 | 通过 | `make check-p0-01` 退出 0，正常项保持 |
| V02 | 通过 | RTL/Spike 正常挂起被看门狗终止；总入口有界非零 |
| V03 | 通过 | 观察命令受保护，正常观察仍完成 |
| V04 | 通过 | 构建退出 3 且二进制存在时步骤与总入口失败 |
| V05 | 通过 | 记分板真实比较报错；正常 10,000 周期继续通过 |
| V06 | 通过 | 实现 Commit、命令、退出码、日志与哈希对应 |

## 5 未完成项与下一步

- 未实现 CPU、DiffTest、ACT/Sail、SoftFloat、FPGA；均不在本轮范围。
- 未发现新的环境或权限阻塞。
- 建议管理方审查 F01—F03 与 V01—V06 证据；通过后再安排 P0-02。未自行合入 `main`，未进入 P0-02。

```text
任务：P0-01-R1
修复基线 Commit：741733d35f1e3a3e550ee45e831ccd0c4a4a414a
分支：codex/p0-01-environment-smoke
被测试实现 Commit：251c151e5684dd2751cdb4fe27f557621b34e144
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P0-01-R1-report.md
F01—F03：完成
V01—V06：全部通过
日志目录：verification/evidence/P0-01-R1/
未完成项：CPU RTL、DiffTest、ACT/Sail、SoftFloat、FPGA 未开展（不在本轮范围）
建议下一步：审查通过后进入 P0-02
```
