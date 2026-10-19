# P1-A 基础框架与 RAM/总线报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-A |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 任务基线 | `9acbd20dddb80a23171a1ab1858c26eb0bd80ba0`（含 P0-02-R2 验收、冻结澄清与 P1-A 任务单） |
| 分支 | `codex/p1-a-foundation` |
| 被测试实现 Commit | `afbb11d15094e234c1c9c1eda78d40dacf83cc2a` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P1-A-report.md` |
| 证据目录 | `verification/evidence/P1-A/`（122 项，`SHA256SUMS`） |

本轮建立可接 P1-B 的 RTL 顶层、共享接口、128 KiB RAM、单事务存储桥与验证入口。未实现指令执行，未制造退休记录；未合入 `main`，未进入 P1-B。

## 1 完成内容

### A01 核心/SoC 骨架

- `rtl/core/p1_core_skeleton.sv`：
  - 导入冻结的 `core_config_pkg`/`core_types_pkg`；结构保留双槽类型，P1 活动宽度使用 `ACTIVE_SLOTS_P1=1`。
  - `mem_req_o.valid` 恒 0，`commit_o.slot_valid=0`、`trap_valid=0`、`idle_o=1`；内部断言防止骨架发起事务或伪造退休/Trap。
  - 端口保留 `mem_req_t`/`mem_resp_t`/`redirect_t`/`commit_bundle_t`，P1-B 只需替换内部实现，不改 SoC/验证接口。
- `rtl/soc/p1_soc_top.sv`：骨架 + RAM 桥 + RAM 的 SoC 包装，用于结构 Lint 与空闲验证。
- `rtl/p1_a.f`：本轮 RTL 文件清单。

### A02 RAM 与单事务桥

- `rtl/soc/ram_128k.sv`：128 KiB 小端字节阵列；同步读写；测试专用 `load_valid/load_word_addr/load_data` 镜像加载端口；复位不清数据阵列。
- `rtl/soc/ram_bridge.sv`：
  - 完整 34 位 PA 检查，严格 `[0x80000000,0x80020000)`；高 PA、越界、MMIO 地址返回 access fault，不截断高位。
  - byte/half/word 自然对齐；mask 与 size/lane 精确匹配；store 高位数据必须为零；所有非法请求在写 RAM 前拒绝。
  - 请求 wdata 为低标量，桥按 lane 转换后写入；响应 rdata 按宽度提取、低位零扩展，符号扩展留给未来 LSU。
  - 单事务在途；ID/代次原样返回；响应在 `resp_ready` 背压下保持；同一请求只产生一个响应。
  - `flush_i` 只阻止未接受请求；已接受 Store 为不可取消事务，已接受 Load 可返回并由调用者按 ID/代次丢弃。
  - `resp_delay_i` 提供可控访问延迟（测试/调试输入，SoC 默认 0）。
- 复位/初始化契约：复位仅清控制状态，环境需先静默/排空；RAM 内容由 TB load 端口或未来镜像加载提供，未初始化位置不冒充确定值。

### A03 验证

- 新增 `verification/p1a/tb/`：
  - `ram_bridge_tb_top.sv`：冻结 struct 到标量 TB 端口的包装。
  - `soc_idle_tb_top.sv`：暴露骨架 retire/trap/request 状态。
  - `tb_ram_bridge.cpp`：独立 128 KiB 字节数组记分板；定向边界 + 3 个固定种子随机事务；响应背压、请求停顿、访问延迟、未接受 Flush、已接受 Flush、ID/代次与恰好一次检查。
  - `tb_soc_idle.cpp`：16 周期空闲检查。
  - `tb_token_joint.cpp`：P0 取消项 + 回绕联合补测（缩小代次到 `GEN_W=3`）。
- 新增 `scripts/check_p1_a.sh` 与 `make check-p1-a`。

## 2 验证结果（V01—V05）

### V01 结构

命令：`make check-p1-a`，退出码 `0`。

- `verilator --lint-only -Wall --assert -Irtl/include --top-module p1_soc_top -f rtl/p1_a.f`：退出 0，无未解释告警（`logs/lint.log`）。
- 空闲骨架：`P1-A_CORE_IDLE_PASS cycles=16 retire=0 trap=0 mem_req=0`（`logs/soc-run.log`）。
- 证据：`logs/soc-build.log`、`logs/soc-run.log`。

### V02 RAM

- 定向覆盖：RAM 首/末字节、首/末字、四种 byte lane、两种 half lane、word、部分写保持邻接字节、连续同址读写、响应低位零扩展。
- 非法请求：高 PA、低于/超过 RAM、MMIO 地址、half/word 非对齐、错误 mask、size/mask 不匹配、store 高位数据非零；均返回明确错误且内存不变。
- 随机：3 个固定种子（`0x1a2b3c4d`、`0x5e6f7a8b`、`0x9c0d1e2f`）各 450 笔合法/非法混合事务，加定向共：

```text
P1-A_RAM_TB_PASS transactions=1392 legal=627 illegal=765 cycles=34124
```

- 记分板为独立字节数组，不使用 DUT 读出值生成期望。RAM 在测试前通过 load 端口写入与模型一致的确定模式。
- 证据：`logs/ram-build.log`、`logs/ram-run.log`。

### V03 时序

- 响应连续背压：held 期间响应 payload 稳定，释放后恰好消费一次。
- 请求停顿/延迟：`req_delay` 与 `resp_delay` 覆盖；请求仅在 `valid && ready` 边沿接受。
- 已接受 load 遇上游 Flush：响应仍返回；Store 接受后不可取消。
- Token 联合补测：`P1-A_TOKEN_JOINT_PASS flush_wrap_drain=ok`。回绕前存在已取消匹配响应时新分配持续阻塞，真正收尾后恢复；active/cancelled 计数归零后下一 Token 代次回到 0。
- 证据：`logs/token-build.log`、`logs/token-run.log`。

### V04 失败检测

- 比较路径负向探针：`ram_tb +mismatch`，真实读值比较发现一次注入错误，退出 1 并输出 `P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED`（`logs/ram-mismatch-probe.log`）。
- 受控挂起：`timeout 5s ram_tb +hang`，退出 124 并输出 `P1-A_RAM_TB_TIMEOUT_PROBE`（`logs/ram-timeout-probe.log`）。
- 正常路径由 `timeout -k 5s` 主机看门狗执行；构建使用真实退出码，构建失败不会被忽略。
- 事务/周期预算：总事务 ≥1000、总周期不超过 200000；正常运行 1392/34124。

### V05 回归/追溯

`make check-p1-a` 退出 0，汇总 `verification/evidence/P1-A/logs/summary.log`：

```text
git_head: afbb11d15094e234c1c9c1eda78d40dacf83cc2a
git_branch: codex/p1-a-foundation
git_status:
  ?? verification/evidence/P1-A/
result: PASS
```

回归：

```sh
env P0_02_EVIDENCE=verification/evidence/P1-A/regression/p0-02 make check-p0-02
```

退出 0；`P0-02_CHECK_ALL_PASS`。其中嵌套 `make check-p0-01` 与 `make r1-probes` 的日志分别写入：

- `verification/evidence/P1-A/regression/p0-02/regression/p0-01/logs/`
- `verification/evidence/P1-A/regression/p0-02/regression/p0-01-r1/`

历史 P0-01/P0-02/R1/R2 报告与证据未修改。

## 3 文件清单

| 路径 | 说明 |
| --- | --- |
| `rtl/core/p1_core_skeleton.sv` | 核心接口骨架（空闲） |
| `rtl/soc/ram_128k.sv` | 128 KiB RAM |
| `rtl/soc/ram_bridge.sv` | 单事务存储桥 |
| `rtl/soc/p1_soc_top.sv` | SoC 包装 |
| `rtl/p1_a.f` | RTL 文件清单 |
| `verification/p1a/tb/*` | RAM/桥、空闲 SoC、Token 联合 TB |
| `scripts/check_p1_a.sh` | P1-A 总入口 |
| `docs/architecture/p1-a-modules.md` | 模块端口、契约、P1-B 插入点 |
| `Makefile` | 新增 `check-p1-a` |

## 4 V01—V05 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| V01 | 通过 | Lint、空闲骨架、无伪请求/退休 |
| V02 | 通过 | 定向边界、错误无副作用、1392 笔混合事务与固定种子 |
| V03 | 通过 | 背压/延迟/ID/代次/取消/回绕联合 |
| V04 | 通过 | 比较负向、挂起超时、构建退出码传播 |
| V05 | 通过 | 总入口与 P0-02/P0-01/R1 回归、证据追溯 |

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 取指/译码/ALU/LSU/CSR/ROB/Cache/MMU/FPU | 未实现 |
| 真实退休记录/DiffTest | 未实现；本轮明确不产生伪退休 |
| UART/结果寄存器/中断外设 | 未实现；MMIO 地址当前返回 access fault |
| FPGA 综合/时序/资源/上板 | 未进行 |
| P1-B | 未开始 |

课程 FPU/OS/板卡/Benchmark 仍待确认。无环境阻塞。未合入 `main`，未进入 P1-B。

## 6 交付摘要

```text
任务：P1-A
任务基线 Commit：9acbd20dddb80a23171a1ab1858c26eb0bd80ba0
分支：codex/p1-a-foundation
被测试实现 Commit：afbb11d15094e234c1c9c1eda78d40dacf83cc2a
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P1-A-report.md
证据目录：verification/evidence/P1-A/
证据数量：122 项
SHA256SUMS：f0051dda28df51755e47e304c3a8c1c5d4c64dcb4c4d519e6bb37933e617d6e8
V01—V05：全部通过
未完成项：CPU 数据通路、DiffTest、MMIO/外设、FPGA、P1 实机测试
建议下一步：管理审查通过后下达 P1-B 取指/译码任务
```
