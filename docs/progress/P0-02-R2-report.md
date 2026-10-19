# P0-02-R2 剩余问题修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P0-02-R2 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 原交付 | `49d8d9602947f1a7702e16fe1dbe79dd6b8e5870` |
| 实际修复基线 | `9d7c3c652c65f4b0dcfb67805561c9a97e517b10`（`49d8d96` 合并 `origin/main` 的 `76f3900` 复审/R2 任务单） |
| 分支 | `codex/p0-02-spec-interfaces` |
| 被测试实现 Commit | `c6e2e4335d11b0befbe28ce03565161f01075378` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P0-02-R2-report.md` |
| 证据目录 | `verification/evidence/P0-02-R2/`（116 项，`SHA256SUMS`） |

本轮只关闭 B01—B03；未重做已关闭的平台工作，未实现 CPU 数据通路，未合入 `main`，未进入 P1。历史 P0-01、P0-01-R1、P0-02、P0-02-R1 报告和证据未修改。

## 1 先复现旧实现反例

复现针对旧实现 Commit `cdc6238417aaa8a069de9c2cae6dd50ea68145fd`，使用独立临时目录，不修改旧证据。证据：`verification/evidence/P0-02-R2/repro/`。

| 反例 | 旧行为 | 证据 |
| --- | --- | --- |
| B01 中断方向/misa | 旧文写“当前权限低于目标权限时不响应”；`misa`/`mstatush` 标为 RO 或写忽略 | `repro/README.log` 的 Git 对象 grep |
| B02 分配→Flush→重分配→旧响应 | 旧夹具返回 `{idx=0,gen=0}` 两次，旧响应被接受（`old_response_accepted=1`） | `repro/b02-old-fixture.log` |
| B02 同拍分配/完成 | 4 个活动项后仍 `alloc_ready=1`，允许额外分配/覆盖 | `repro/b02-old-fixture.log` |
| B02 非队头完成 | 释放 idx1 后 `alloc_ready=1` 且目标 idx0 仍活动 | `repro/b02-old-fixture.log` |
| B03 隐藏 CSR 指令 | `instr=0x30002073`、`csr_valid=false` 被接受 | `repro/b03-old-checker.log` |
| B03 重复非空 bundle | 两个 `seq_base=1` 的 bundle 被接受 | `repro/b03-old-checker.log` |
| B03 错误布尔类型 | `token_valid=1`（整数）被当作真值接受 | `repro/b03-old-checker.log` |

复现源：`repro/b02_repro.cpp`、`repro/b03_repro.py`。旧实现检查退出码为 0，但输出的观察值即错误行为；新实现用例必须拒绝/阻止这些结果。

## 2 修复内容

### F01 / B01：规则修正

- `docs/architecture/isa-support.md` 与 `docs/architecture/csr-support.md` 改为先委托、再比较当前权限与目标级：
  - 当前权限低于目标级：pending + individual enable 满足时响应，不受当前级 xIE 限制；
  - 当前权限等于目标级：还需该级 xIE=1；
  - 当前权限高于目标级：不响应该目标级；
  - M-mode 不接收已委托给 S 的 S 中断，不因 MIE/SIE 开启转入 S；
  - 同步异常委托同理，M-mode 异常不能因委托进入 S。
- 增加 U/S/M × 目标 S/M × 委托 × xIE 的边界示例表。
- `misa` 改为合法可访问 RW/WARL 固定能力字段：P1 读 `0x40000100`，合法写完成但保持值，不 Trap；`mstatush` 合法写保持零，不 Trap。明确区分整只只读身份 CSR（`mvendorid` 等写尝试 Trap）与可写 CSR 内固定字段。
- 删除已决定事项的陈旧“待审”文字；PLIC/CLINT 按 D09 表述为能力要求而非完整设备兼容必交项。D05/D06 的 Trap 互斥、seq 隔离在退休契约中改为已冻结规则。
- 本轮只有文档/规则检查，无 CSR RTL 或 DUT 运行。

### F02 / B02：Token 与通道夹具

- `interface_fixture.sv` 重写：
  - 代次在**每次分配**时递增，释放索引复用时身份必然变化；
  - Flush 把活动项标记为“已取消但在途”，保持 `active_count` 与身份保留，直到匹配响应到达；不提前重用；
  - 分配目标必须是空闲项；下一项活跃时保守停顿，不覆盖活动项；
  - 同拍分配/完成使用一次净计数更新，避免两个非阻塞赋值相互覆盖；
  - 回绕前停止分配，所有在途（含取消）事务排空后才恢复；缩小 `GEN_W` 可强制回绕；
  - 增加 `active_count`/`cancelled_count` 观察输出。
  - 复位契约明确为“外部请求已排空”；模块不能证明外部事务消失。
- `tb_interface.cpp` 重写：
  - 发送端待发送队列 + 接收端记分板，在时钟边沿检查 0/1/2 槽、部分资源、连续背压、Flush、S0/S1 恰好一次与顺序；
  - 覆盖分配→Flush→重分配→旧响应、同拍分配/完成净计数、非队头完成、Flush+完成同拍、回绕前排空、重复/迟到响应。
- 新增 `retire_event_fixture.sv` + `tb_retire_event.cpp`：S0 正常先退休、S1 异常下一拍 Trap、同拍互斥、cause/tval/PC 保持、非连续输入不退休 S1。
- 证据：`logs/interface-run.log`（`P0-02_INTERFACE_FIXTURE_PASS`）、`logs/retire-event-run.log`（`P0-02_RETIRE_EVENT_FIXTURE_PASS`）。

### F03 / B03：退休检查器

- `check_csr(record)` 现在无论 `csr_valid` 真假都会执行：真实 CSR 指令关闭 `csr_valid` 会被拒绝；非 CSR 指令错误置位也会被拒绝。
- 跨 normal/bundle/Trap 统一严格递增：bundle 的每个事件 seq 必须 `> last`；重复/相邻重复包被拒绝；空 bundle 定义为不推进 seq 的占位。
- `token_valid`/`next_pc_valid` 严格布尔；列表字段先检查类型和字段名；有值却列入 `not_observed_fields`、无值却列入 `derived_fields` 均拒绝；未知字段名拒绝。
- 访存 trace 语义写清：`mem_wdata` 为按 lane 对齐、未用高位为零的架构值；`mem_rdata` 为符号/零扩展后的 32 位值；store 数据必须适配访问宽度；到 `mem_req_t` 保持同一映射。
- 自测新增隐藏 CSR、错误布尔/列表、列表矛盾、重复 bundle、相邻 bundle 重复 seq、空 bundle 正例等。实际输出：`RETIRE_CONTRACT_SELFTEST_PASS positives=18 negatives=27`。
- R1 计数更正：R1 报告交付消息写“16 正例/19 反例”，实际源码与日志为 **16 正例/18 反例**；本轮报告与日志以实际计数为准，不回写历史报告/证据。

## 3 验证结果（V01—V04）

### V01 规则修正

- 文档边界表覆盖：S 下 MIE=0 的 M 目标中断（响应）、S 下 SIE=0/1 的已委托 S 中断（不响应/响应）、U 下 SIE=0 的已委托 S 中断（响应）、M 下已委托 S 中断（不响应）、M 下 MIE=0 的 M 中断（不响应）。
- `misa` 合法写保持值、`mvendorid` 写尝试 Trap 的规则分列；`mstatush` 与整只只读身份 CSR 分开。
- 证据：`docs/architecture/isa-support.md`、`docs/architecture/csr-support.md`、`repro/README.log`（旧文本）。

### V02 接口

- `P0-02_INTERFACE_FIXTURE_PASS`：S0/S1 恰好一次、背压、Flush 后身份不复用、同拍净计数、非队头完成、回绕排空。
- `P0-02_RETIRE_EVENT_FIXTURE_PASS`：S0 先退休、S1 下一拍 Trap、同拍互斥、元数据保持。
- 证据：`logs/interface-*.log`、`logs/retire-event-*.log`。

### V03 退休

- `RETIRE_CONTRACT_SELFTEST_PASS positives=18 negatives=27`；所有反例按指定原因拒绝。
- 5 个示例文件、45 条记录通过；Spike 转换 19 行通过；隐藏 CSR、布尔/列表、bundle 顺序等新增反例均拒绝。
- 证据：`logs/retire-*.log`、`verification/spec/retire/`。

### V04 回归与可追溯

- 先提交实现 `c6e2e4...`，删除 `build/` 与本轮 logs/regression，再在同一 Commit 上运行 `make check-p0-02`；测试后未修改实现。
- `make check-p0-02` 退出 0，全部步骤 `P0-02_STEP_PASS`（见 `logs/summary.log`）。
- 回归显式使用本轮目录：
  - `P0_01_LOG_DIR=verification/evidence/P0-02-R2/regression/p0-01/logs make check-p0-01`，三步骤 exit=0、`result: PASS`；
  - `P0_01_R1_PROBE_DIR=verification/evidence/P0-02-R2/regression/p0-01-r1 make r1-probes`，11 项探针全部通过。
- 平台检查保持 R04 已关闭状态：页表 `[0x8001a000,0x8001e000)`、gap、128 KiB Spike 运行、8 类负向配置与 drift 检查均通过。
- 证据 116 个文件，清单 `verification/evidence/P0-02-R2/SHA256SUMS`，SHA-256 为 `e087da55d874fcad720e7eb9d5140e7347aac1a170447879a6d31ef343ae5f40`。

## 4 B/V 状态汇总

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| B01 | 关闭 | 中断方向/委托、misa/mstatush 属性、陈旧文字修正 |
| B02 | 关闭 | Flush 身份保留、同拍净计数、非队头安全、回绕/背压/事件夹具 |
| B03 | 关闭 | CSR 分类不可绕过、严格布尔/列表、跨事件 seq、数据宽度语义 |
| V01 | 通过 | 文档规则与边界示例 |
| V02 | 通过 | 接口/事件夹具实际运行 |
| V03 | 通过 | 18 正例/27 反例与示例校验 |
| V04 | 通过 | 同 Commit 总入口与回归通过 |

## 5 未完成项与剩余问题

| 项目 | 状态 |
| --- | --- |
| CPU 数据通路、DiffTest、ACT/Sail、SoftFloat、FPGA | 未实现/未运行 |
| P1 CSR/计数器/Trap 实机测试 | 计划已列，未执行 |
| Sv32/Svade 完整缺页闭环 | 未验证；仅参数/规则准备 |
| 课程 FPU/OS/板卡/Benchmark | 仍待课程确认（D11） |

本轮没有环境阻塞。未合入 `main`，未进入 P1。

## 6 交付摘要

```text
任务：P0-02-R2
修复基线 Commit：9d7c3c652c65f4b0dcfb67805561c9a97e517b10
分支：codex/p0-02-spec-interfaces
被测试实现 Commit：c6e2e4335d11b0befbe28ce03565161f01075378
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P0-02-R2-report.md
证据目录：verification/evidence/P0-02-R2/
证据数量：116 项
SHA256SUMS：e087da55d874fcad720e7eb9d5140e7347aac1a170447879a6d31ef343ae5f40
B01—B03：关闭
V01—V04：全部通过
未完成项：CPU RTL、DiffTest、ACT/Sail、SoftFloat、FPGA、P1 实机测试
建议下一步：管理复审冻结 P0-02 后下达 P1 首个实现任务
```
