# P1-C-R3 管理验收

审查日期：2026-10-20（Asia/Shanghai）。结论：**H01 关闭，V01—V03 通过；P1-C 整体验收通过，交付 `96510ec` 快进合入 main。** 允许按 [P1-D 任务单](../tasks/P1-D-LoadStore与访存仲裁.md)开始 RAM 访存集成；不等于完整 RV32I/P1 或完整 DiffTest 已通过。

## 1 版本和证据

| 项目 | 核对结果 |
| --- | --- |
| 代码变更前起点 | `ac827066925c6b71ad8ffe8fb0949c24d0f33ffb` |
| 修复提交 | `3875710`，随后纳入管理提交 `592dbab` |
| 被测试实现 | `aa4272c8c3d64f3319650ec60c12dcb98ebe9587` |
| 最终交付 | `96510ecf90f3f25f103db6a578c719a79e34144b` |
| 报告 | [P1-C-R3-report.md](P1-C-R3-report.md) |
| 证据 | `verification/evidence/P1-C-R3/`，1007 条清单逐个重算一致，含清单共 1008 个文件，无重复/遗漏 |
| 清单 SHA-256 | `ba8a19a8f2251e0a6dec6b0568bcc497d2926ee3339190513daf881ae88b6e05` |
| 测试后变化 | 仅新增本轮报告/证据；历史证据未修改 |

Windows 管理侧读取 Git 对象、代码/脚本、报告及原始日志，独立重算清单哈希并核对 DUT 记录数量/seq；未运行提交的程序、RTL、Spike 或 Linux 总入口。实际执行结果来自 Ubuntu 容器的本轮证据。

## 2 H01 关闭依据

`verification/p1c/tb/tb_faults.cpp` 的正常、initial_arf 和 hold_change 路径都使用同一 compare_arf；目标观察差异与其余提交、镜像、metadata、Token、禁止副作用和保持错误分别累计为 target_errors/other_errors。注入后不再提前返回，而是继续完成保持检查，再统一判定。

仅 target_errors>0、other_errors=0 且 fault/预期提交前缀场景完成时允许 DETECTED/exit 1。提交数量有独立预期，Token 与该前缀交叉检查；其他错误不会被归零或因目标命中被忽略。

| 证据 | 实际结果 | 结论 |
| --- | --- | --- |
| initial / hold 仅目标 | 各 target=1、other=0、scenario=complete，DETECTED/exit 1 | 指定错误由公共监视器检出 |
| initial / hold 加 cause 观察错误 | 各 target=1、other=1，EXTRA_ERRORS/exit 3 | metadata 错误经真实 check_meta 累计，不认可探针成功 |
| initial_missing | target=0、other=0，NOT_DETECTED/exit 2 | 没有目标错误不能冒充检出 |
| 普通 fault | 初始独立镜像、metadata 和 16 个真实保持边沿通过 | 正常对照保留 |
| 旧 3ed8ec9 复现 | metadata mismatch 后仍 DETECTED/exit 1；旧源和独立 cause 观察夹具已保存 | 原失效路径成立，修复对应 |

`scripts/check_p1_c.sh` 保留原 fault-negative-initial/hold 的 exit 1 + 指定 DETECTED 判据。两次 probe_initial_extra/probe_hold_extra 总入口分别只出现对应原步骤失败（exit 3，expected 1），普通 fault 场景均通过，汇总 result: FAIL、make 非零。不是放宽判据后将额外错误当成功，也不是用普通 fault 步骤失败替代探针验证。

## 3 正常回归及验收边界

- 同 aa4272c 的正常 make check-p1-c 汇总 PASS；定向 124、随机 1281/1281/1282（3844），DUT 文件数量与 seq 核对一致，逐字段/最终寄存器差分日志通过。
- ALU/ARF、六分支双向矩阵、四类真实恢复、格式/差分负向、停止场景和 P1-B/P1-A/P0 嵌套回归通过。主机看门狗、kill-after、预算和真实构建退出码保留。
- R1/R2 已接受的整数执行、真实单项提交、格式门禁和独立镜像不重开；本轮完成剩余探针失败传播。

验收覆盖 29 条整数/控制流、ARF、临时单项顺序提交槽、真实 Token/next_pc 退休及该子集的 Spike 差分。fault 只是保持停止结果，没有 CSR 状态更新和 Trap 处理。Load/Store、CSR/Trap、M/A/C/F、OoO/32 项 ROB/IQ/BPU/Cache/MMU/FPU、完整 DiffTest、SoC 顶层替换及 FPGA 仍未完成。

## 4 后续路线

P1-D 仅加入 RAM 的 5 种 Load/3 种 Store、前端/数据请求仲裁、访存故障停止和访存退休证据。实际 UART/test_result 外设与启动终止协议集中到 P1-F，仍是 P1 必做项；P1-D 中未实现 MMIO 必须明确 access fault，禁止假成功。CSR/同步 Trap 在 P1-E，完整平台差分在 P1-F，板卡待落实的 P1-G 不记为通过。
