# P0-02 规格与接口基线实施报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P0-02 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800 |
| 任务基线 | `b89be08da8fe7dc45697e13c0900548d8cafc783`（含 P0-01 验收与 P0-02 任务单的最新 main） |
| 分支 | `codex/p0-02-spec-interfaces` |
| 被测试实现 Commit | `ae3784f45996cd2400ad88a380dc8ec764bbb012` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 报告路径 | `docs/progress/P0-02-report.md` |
| 证据目录 | `verification/evidence/P0-02/`（106 项，`SHA256SUMS`） |

本轮完成细化规格、平台单一配置、共享类型、双槽接口、退休/Trap 契约与 P1 验证计划，并在容器内实际运行配置、类型与契约检查。**未实现任何 CPU 数据通路，未进入 P1。**

## 1 完成内容

- ISA/CSR/异常范围：`docs/architecture/isa-support.md`、`docs/architecture/csr-support.md`。
- 平台地址图与参考模型：`docs/architecture/memory-map.md`、`config/platform.json`。
- 单一事实来源生成/检查：`scripts/gen_platform.py`、`scripts/check_platform.py`。
- 共享类型与接口：`rtl/include/core_config_pkg.sv`、`rtl/include/core_types_pkg.sv`、`docs/interfaces.md`。
- 退休/Trap 契约与 Spike 映射：`docs/architecture/retire-contract.md`、`verification/spec/retire/`、`scripts/check_retire_contract.py`。
- P1 与后续阶段测试计划：`docs/verification-plan.md`。
- 统一入口：`make check-p0-02`（并保留 `make check-p0-01`、`make r1-probes`）。

## 2 ISA、CSR 与异常（S01）

状态：**通过（文档规格候选，待管理冻结）。**

交付内容：

- P1 最小核：RV32I + Zicsr 最小集合 + Zifencei + M-mode 同步异常/MRET；活动宽度 1。
- 最终：RV32IM + Zicsr + Zifencei + M/S/U + Sv32 + Svade；独立 FP32 部件不等于 RV32F。
- 暂不支持：A/C/F/D/H、调试/Trigger、非对齐访存、硬件事务性 A/D 更新等。
- 异常表逐项列出 cause、tval、EPC、处理阶段与 P1/最终阶段；区分同步异常与异步中断。
- CSR 表覆盖设计书第 6.4 节所列寄存器、计数器、身份 CSR、PMP 零项、satp/ASIDLEN=0、WARL/WPRI/只读位与读写抑制规则。
- 规范链接指向 `v20260120` 的 RV32I、M、Zicsr、Zifencei、Machine、Supervisor 章节。

未实现行为只标为“计划/规格待实现”，没有写成已支持。

## 3 平台配置与参考执行（S02）

状态：**通过。**

单一事实来源为 `config/platform.json`。生成文件：

- `software/generated/platform.h`
- `software/generated/platform.ld`
- `config/platform.spike.args`
- `config/platform.generated.json`

命令与结果：

| 检查 | 命令 | 退出码 | 证据 |
| --- | --- | --- | --- |
| 生成一致性 | `python3 scripts/gen_platform.py --check` | 0 | `logs/platform-check.log` |
| 链接/ELF/Spike 一致性 | `python3 scripts/check_platform.py` | 0 | `logs/platform-check.log` |
| 负向配置 | `python3 scripts/check_platform.py --negative` | 0 | `logs/platform-negative.log` |

实际结果（`logs/platform-check.log`）：

```text
PLATFORM_CHECK_GENERATED_OK
PLATFORM_CHECK_LINKER_OK
PLATFORM_CHECK_HEADER_OK
PLATFORM_CHECK_RTL_PACKAGE_OK
PLATFORM_CHECK_SPIKE_ARGS_OK
PLATFORM_CHECK_ELF_OK entry=0x80000000 bss_end=0x80000138
  signature=[0x80019f00,0x8001a000)
  page_tables=[0x8001a000,0x8001eff0)
  stack_limit=0x8001eff0 stack_top=0x8001fff0
PLATFORM_CHECK_SPIKE_RUN_OK
PLATFORM_CHECK_SPIKE_FEATURES_OK: isa=rv32im_zicsr_zifencei_svade priv=msu
  memory=0x80000000:0x20000 mmu=sv32
```

- 软件链接区域、`platform.h` 常量、RTL 包中的 `RAM_BASE/RAM_SIZE` 与 Spike 的 `-m0x80000000:0x20000` 由同一配置驱动。
- 已移除 P0-01 的 `-m128`；128 KiB 参考执行正常退出 0。
- 负向检查实际拒绝 7 类配置：MMIO 与 RAM 重叠、错误 RAM 大小、MMIO 未对齐、Spike 内存不一致、错误 PA 位宽、保留区超出 RAM、MMIO 重名。日志含具体原因。
- Spike 最终 ISA/特权/Svade 探测：`--isa=rv32im_zicsr_zifencei_svade --priv=msu` 被接受，`--dump-dts` 显示 `riscv,isa`、`mmu-type = "riscv,sv32"`、`memory@80000000`；这仅证明参数被接受，不证明完整缺页/特权功能已验证。证据 `logs/spike-features.log`。
- Spike 无 `pk`、无独立 Svade 运行时开关；`svade` 作为 ISA 扩展字符串接受，A/D 行为需 P5 与参考模型适配任务一起冻结。

## 4 共享类型与接口（S03）

状态：**通过。**

交付：

- `core_config_pkg`：XLEN/VA/PA、2 槽、ROB 32、IQ 16、访存 FIFO 8、Token 项号/代次、请求 ID、FPU 事务 ID、RAM 常量。
- `core_types_pkg`：Fetch/Decode、Rename/Dispatch、Issue/FU、WB、Commit/Trap、存储请求响应、Redirect/Flush、独立 FPU 的 packed struct/枚举。
- `docs/interfaces.md`：通用 valid/ready 规则、逐槽字段、T01—T18 时序表（0/1/2 槽、只剩一项、RAW/WAW/WAR、同拍广播、Flush 与完成/外部响应、第二槽异常、不可取消事务遇中断、Token 回绕、FPU 背压等）。

命令与结果：

| 检查 | 命令 | 退出码 | 证据 |
| --- | --- | --- | --- |
| Lint | `verilator --lint-only -Wall --assert -Irtl/include --top-module type_selfcheck ...` | 0 | `logs/types-lint.log` |
| 编译+运行自检 | Verilator 构建 `type_selfcheck` 并运行 | 0 | `logs/types-build.log`、`logs/types-run.log` |
| 非法参数 | 构建 `-GINJECT_INVALID=1` 的 `invalid_probe` 并运行 | 构建 0；运行 134 | `logs/types-invalid-build.log`、`logs/types-invalid-run.log` |

自检输出（`logs/types-run.log`）：

```text
P0-02_TYPE_SELFCHECK_PASS bits: fetch_slot=152 decoded_slot=284
  renamed_slot=344 issue_slot=269 retire=429 trap=331 commit=1192 mem_req=123
```

非法参数探针输出 `P0-02_INVALID_PARAM_DETECTED: ROB_ENTRIES=33` 并以 134 结束。自检还校验 `RAM_BASE=0x80000000`、`RAM_SIZE=0x20000`、`RAM_END=0x80020000` 与 Token 位宽。

说明：包内少量预留常量与布局探针变量使用了**文件内、按告警类别**的 Verilator lint waiver，理由是该夹具仅做类型/位宽检查；功能 runner 未全局关闭告警。

## 5 退休/Trap 契约（S04）

状态：**通过（格式与映射夹具；无 DUT 退休记录）。**

交付：

- `docs/architecture/retire-contract.md`：正常退休与 Trap 字段、有效性规则、两槽顺序、rd=x0、访存地址/掩码/数据、CSR 与特权、Spike 字段能力表和缺口。
- `verification/spec/retire/retire_schema.json`：机器可读字段与有效性规则。
- `verification/spec/retire/examples/synthetic_examples.jsonl`：4 条合成夹具，明确 `source=synthetic`。
- `verification/spec/retire/examples/spike_ok_excerpt.log`：本轮 P0-02 回归运行的真实 Spike 提交片段。
- `verification/spec/retire/examples/spike_derived_examples.jsonl`：由上述真实片段转换，`source=spike-derived`。
- `scripts/check_retire_contract.py`：格式校验、负向自测与 Spike 转换。

| 检查 | 命令 | 退出码 | 结果 |
| --- | --- | --- | --- |
| 检查器负向自测 | `python3 scripts/check_retire_contract.py --self-test` | 0 | 8 类坏记录全部拒绝 |
| 示例校验 | `python3 scripts/check_retire_contract.py --validate-examples` | 0 | 23 条记录（19 Spike 派生 + 4 合成） |
| Spike 转换 | `python3 scripts/check_retire_contract.py --convert-spike verification/spec/retire/examples/spike_ok_excerpt.log` | 0 | 19 行转换 |

证据：`logs/retire-selftest.log`、`logs/retire-validate.log`、`verification/spec/retire/examples/`。

映射要点：

- Spike 直接提供：PC、指令、priv、rd 写值、store 地址/数据；load 地址与目的寄存器值可推导。
- 需后处理：`next_pc`、访存 size/mask、部分 load 数据关联。
- 不提供：CSR 读写值、Trap 事件、Token、精确中断边界；P1 不比较 CSR/Trap，P5 需新增接口。
- 合成记录与 Spike 派生记录都不是 DUT 退休证据，也未运行 DiffTest。

## 6 测试计划与 P1 拆分（S05）

状态：**通过（计划文档，未执行）。**

`docs/verification-plan.md` 提供：

- C01—C17 到 P1—P7 测试/证据的映射表，并区分“已执行”与“计划”。
- P1 每类指令、Trap、停顿/握手、启动/终止的输入与预期结果。
- P1-A—P1-G 任务拆分、依赖、集成顺序与验收标准，供下一轮审查后启动。
- 板卡未定时 P1-G 保持“受阻”，不写成通过。

## 7 统一入口与回归（S06）

状态：**通过。**

命令：`make check-p0-02`，退出码 `0`，汇总 `verification/evidence/P0-02/logs/summary.log`：

```text
git_head: ae3784f45996cd2400ad88a380dc8ec764bbb012
git_branch: codex/p0-02-spec-interfaces
git_status:
  (only regenerated verification/evidence/P0-02 files; no implementation changes)
result: PASS
```

步骤全部为 `P0-02_STEP_PASS`：

```text
platform config, generated files, linker, ELF and Spike agree
negative platform configs rejected
Spike accepts final ISA/Svade/priv and runs the smoke ELF
shared type lint
shared type build
shared type width/layout self-check
invalid shared parameters rejected
retire contract validator rejects malformed records
retire contract examples validate
make check-p0-01 regression
make r1-probes regression
```

回归日志没有覆盖历史证据：

- `P0_01_LOG_DIR=verification/evidence/P0-02/regression/p0-01/logs`，`summary.log` 三步骤 exit=0、`result: PASS`。
- `P0_01_R1_PROBE_DIR=verification/evidence/P0-02/regression/p0-01-r1`，11 项探针全部 `P0-01_R1_PROBE_PASS`，总 `P0-01_R1_PROBES_ALL_PASS`。
- 回归中的正常 RTL 仍为固定种子 `0x5eed1234`、随机段 10,000 周期、总周期 10,071；记分板负向仍报 `got 0x1111 expected 0xeeee`。
- 回归 Spike 参数已为 `--isa=rv32i --priv=m --disable-dtb -m0x80000000:0x20000`。

## 8 证据对应（S07）

- 被测试实现 Commit：`ae3784f45996cd2400ad88a380dc8ec764bbb012`。
- 先提交实现（`aae064d`、`cec5af9`、`ae3784f`），再删除 `build/` 与 `verification/evidence/P0-02/`，在 `ae3784f` 上运行 `make check-p0-02`；测试后未修改实现。
- 证据 106 个文件，清单 `verification/evidence/P0-02/SHA256SUMS`，SHA-256 为 `9e0542c097177b654fa7e90fa431b3ee1286d322deedec0dc04e94d6f8ea02af`。
- 产物 `build/` 未入库；生成文件已提交并由 `--check` 验证无漂移。
- `platform_check.elf` 未入库；哈希与布局在日志中。

## 9 偏离、未完成与待审问题

### 已接受偏离

- 四项 FIFO 继续作为 P0-01 验证夹具，不重写为一项深度缓存，不作为 CPU 公共模块（管理审查已接受）。
- P0-01 的 Spike `-m128` 已替换为平台配置的 `-m0x80000000:0x20000`；历史日志保留原参数。

### 未完成/未验证

| 项目 | 状态 |
| --- | --- |
| CPU 数据通路、Fetch/Decode/ALU/ROB/Cache/MMU/FPU | 未实现 |
| DiffTest、ACT/Sail、SoftFloat | 未运行 |
| FPGA / 板卡 / EDA | 未进行 |
| 真实 Trap/CSR/中断退休流 | 规格已定义，接口未实现 |
| Sv32/Svade 完整缺页闭环 | 未验证；仅探测 Spike 接受 ISA 字符串 |
| P1 指令测试 | 计划已列出，未执行 |

### 待审决策

1. P1 是否必须包含 RV32M 才能运行课程 C 程序；当前计划 P3。
2. P1 的 `SFENCE.VMA` 行为：当前定为非法指令。
3. P1 计数器固定只读零是否满足课程/差分要求。
4. `mstatus.MPP` 的 WARL 行为（当前只支持 M）。
5. Trap 与正常退休是否允许同拍；当前 P1 不允许。
6. Token 代次回绕策略与 `retire_trace_t.seq` 是否留在共享包。
7. Spike 无独立 Svade 开关；P5 需确认 `svade` ISA 字符串与 DUT 的 A/D 软件管理行为一致。
8. P5 页表保留区实际大小（当前约 20 KiB）与 Sv32 页表数量需求。
9. 板卡 RAM/BRAM 容量与 128 KiB 基线的关系。

### 课程疑问（继续跟进）

- Q01 FPU 接入形式与是否要求完整 RV32F（影响 P6）。
- Q02 指定 OS/Page Fault 演示口径（影响 P5 软件）。
- Q03 板卡型号/领取时间（影响 P1-G、P7）。
- Q05 指定 Benchmark 与给定浮点数据。

## 10 交付摘要

```text
任务：P0-02
任务基线 Commit：b89be08da8fe7dc45697e13c0900548d8cafc783
分支：codex/p0-02-spec-interfaces
被测试实现 Commit：ae3784f45996cd2400ad88a380dc8ec764bbb012
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P0-02-report.md
证据目录：verification/evidence/P0-02/
S01—S07：全部通过
总入口与退出码：make check-p0-02，0
未完成项：CPU RTL、DiffTest、ACT/Sail、SoftFloat、FPGA 未开展；P1 指令测试未执行
待审问题：见第 9 节
建议下一步：管理审查规格/接口后冻结，再下达 P1 最小顺序核任务
```
