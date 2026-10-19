# P0-01 环境与验证冒烟实施报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P0-01 |
| 执行日期/时区 | 2026-10-19，容器本地 HKT +0800（日志同时记录 UTC） |
| 实际环境 | Ubuntu 24.04.4 LTS；Linux 6.8.0-124-generic x86_64；root；128 vCPU；约 1.0 TiB 内存；`/workspace` 剩余 5.7 TiB |
| 仓库路径 | `/workspace/hias-riscv-cpu` |
| 任务基线 Commit | `6cdc51676e30c8e25f6f4a652f22c8f5ad86a40a`（含任务单的 `main`） |
| 任务分支 | `codex/p0-01-environment-smoke` |
| 被测试实现 Commit | `d22b34a8945a08595cfc2a8cdbd5a1bb9e8024c8` |
| 最终交付 Commit | 由交付消息给出（报告与证据的提交） |
| 证据目录 | `verification/evidence/P0-01/` |

本轮只建立环境与验证冒烟，不实现 CPU。RTL 部分是测试夹具，Spike 运行的是独立参考模型上的 RV32I 软件，不是自主 CPU。

## 1 完成内容

1. 检查容器、工具链、权限、资源和仓库状态，并锁定实际使用的版本与 Spike 源码 Commit。
2. 在 `verification/smoke/rtl/` 增加 4 项、16 位同步 valid/ready FIFO 夹具，覆盖复位、单次/连续传输、背压保持、满时不覆盖、Flush/复位丢弃和同拍进出；使用独立 `std::deque` 记分板，固定种子 `0x5eed1234` 运行 10,000 周期随机激励并检查守恒。
3. 增加断言负向探针、记分板错误负向用例、DUT 周期预算超时探针和主机 `timeout` 探针。
4. 在 `software/smoke/` 增加 freestanding RV32I 启动汇编、链接脚本和自检 C 程序；生成正常、错误结果、死循环三个 ELF 变体，在 Spike 上验证正常/失败/超时三条路径。
5. 增加统一入口 `make env-check`、`make lint-smoke`、`make rtl-smoke`、`make ref-smoke`、`make check-p0-01`。
6. 记录实际执行命令、退出码和原始日志；`docs/verification.md` 只登记实际运行过的入口。

## 2 文件清单

| 路径 | 说明 |
| --- | --- |
| `Makefile` | 统一入口 |
| `.gitignore` | 忽略 `build/`、`obj_dir/`、构建产物 |
| `scripts/toolchain.lock` | 实测工具版本、Spike Commit 与构建方式 |
| `scripts/env_check.sh` | 环境、工具、RV32I/ILP32 编译探针 |
| `scripts/run_rtl_smoke.sh` | Lint、构建、正常与负向探针 |
| `scripts/run_ref_smoke.sh` | ELF 构建/检查、Spike 正常/失败/超时/观察接口 |
| `scripts/check_p0_01.sh` | 总入口与汇总 |
| `verification/smoke/rtl/smoke_buffer.sv` | valid/ready FIFO 夹具（非 CPU RTL） |
| `verification/smoke/rtl/assert_probe.sv` | 故意触发断言的负向探针 |
| `verification/smoke/rtl/tb_smoke.cpp` | 定向 + 随机自检 testbench |
| `verification/smoke/rtl/tb_assert_probe.cpp` | 断言探针驱动 |
| `software/smoke/start.S` | 启动、`.bss` 清零、栈、tohost 结束协议 |
| `software/smoke/main.c` | 自检 C 程序（含失败/挂起编译变体） |
| `software/smoke/link.ld` | `0x80000000`、128 KiB RAM、分离 R-X/RW 段 |
| `docs/verification.md` | 实测入口说明 |
| `README.md` | 增加验证入口与报告链接 |
| `verification/evidence/P0-01/logs/` | 原始小型日志 |

## 3 环境与工具（E01）

工作目录：`/workspace/hias-riscv-cpu`。完整日志：`verification/evidence/P0-01/logs/env-check.log`。

| 工具 | 实际版本/路径 | 状态 |
| --- | --- | --- |
| Git | 2.43.0，`/usr/bin/git` | 可用 |
| Make | GNU Make 4.3，`/usr/bin/make` | 可用 |
| 主机 GCC/G++ | 13.3.0，`/usr/bin/gcc`、`/usr/bin/g++` | 可用 |
| Python | 3.12.3，`/usr/bin/python3` | 可用 |
| Verilator | 5.008 2023-03-04 rev UNKNOWN.REV，`/usr/local/bin/verilator` | 可用，断言经负向探针确认启用 |
| RV32 交叉 GCC | `riscv64-unknown-elf-gcc` 13.2.0，`/usr/bin/` | 可用，实测 `-march=rv32i -mabi=ilp32` |
| RISC-V binutils | `riscv64-unknown-elf-{readelf,objdump,nm}` | 可用 |
| Spike | 1.1.1-dev，`/usr/local/bin/spike` | 由源码构建，见下 |

Spike 处理：

- Ubuntu 24.04 仓库无 `spike` 候选包（`apt-cache policy spike` 无 Candidate），因此从源码构建。
- 源码：`https://github.com/riscv-software-src/riscv-isa-sim.git`，Commit `5a760667bf0d0ab893173b9eeff9c109c8d7dd9a`（2026-10-15）。
- 依赖：`libboost-system-dev 1.83.0.1ubuntu2`、`libboost-regex-dev 1.83.0.1ubuntu2`、`libfdt-dev 1.7.0-2build1`、`device-tree-compiler 1.7.0-2build1`。
- 命令与退出码：clone `0`、checkout `0`、`./configure --prefix=/usr/local` `0`、`make -j128` `0`、`make install` `0`。
- 日志：`spike-clean-clone.log`、`spike-clean-checkout.log`、`spike-clean-configure.log`、`spike-clean-build.log.gz`（构建日志压缩后 51 KB）、`spike-clean-install.log`。
- 安装后 `spike --help` 首行为 `Spike RISC-V ISA Simulator 1.1.1-dev`；`/usr/local/bin/spike` SHA-256 为 `6fcc4b095f398110c3b91ebb7e141a832cec5d9c80dfde837fb3103446342a56`。

RV32I/ILP32 探针（`env-check.log`）：编译退出码 `0`；`readelf -h` 显示 `ELF32`、`RISC-V`、`REL`；`readelf -A` 显示 `Tag_RISCV_arch: "rv32i2p1"`、`Tag_RISCV_stack_align: 16-bytes`。未安装 `riscv32-unknown-elf-gcc`，未使用；`riscv64-linux-gnu-gcc` 也可编译 RV32 对象，但本轮统一使用 `riscv64-unknown-elf-` 前缀。

## 4 RTL 冒烟（E02、E03、E05）

工作目录：`/workspace/hias-riscv-cpu`。入口：`make rtl-smoke`（日志 `rtl-smoke.log`，退出码 `0`）。

夹具语义：同步高有效复位；同步高有效 Flush，优先级高于 push/pop 并清空待发项；仅在 `posedge clk` 且 `valid && ready` 时传输；受阻源必须保持 valid/data。断言覆盖计数不越界、满不 push、空不 pop、输入/输出受阻时保持。

| 用例 | 命令 | 期望 | 实际退出码 | 日志 |
| --- | --- | --- | --- | --- |
| Lint | `verilator --lint-only -Wall --assert --top-module smoke_buffer verification/smoke/rtl/smoke_buffer.sv` | 0，无告警 | 0 | `lint-smoke.log` |
| Lint 探针 | 同上，`--top-module assert_probe` | 0 | 0 | `lint-smoke.log` |
| 正常仿真 | `build/rtl-smoke/smoke_sim/obj/smoke_sim` | 0，打印 `P0-01_RTL_SMOKE_PASS` | 0 | `normal-rtl.log` |
| 记分板错误探针 | `... +checker_probe` | 非 0，打印 `P0-01_CHECKER_PROBE_DETECTED` | 1 | `checker-probe.log` |
| DUT 周期超时 | `... +hang +max_cycles=100` | 非 0，打印 `P0-01_TIMEOUT` | 1 | `timeout-probe.log` |
| 主机超时 | `timeout 5s ... +hang +no_cycle_limit` | 124，打印 `P0-01_TIMEOUT_PROBE` | 124 | `host-timeout-probe.log` |
| 断言负向探针 | `build/rtl-smoke/probe_sim/obj/probe_sim` | 非 0，打印 `P0-01_NEGATIVE_PROBE_ASSERTION_FIRED` | 134（SIGABRT） | `assertion-probe.log` |

正常仿真结果：`cycles=10071 accepted=5890 produced=5768 flush_dropped=120 remaining=0`，固定种子 `0x5eed1234`，随机段 10,000 周期。守恒检查为 `accepted == produced + flush_dropped + reset_dropped`。

断言确已启用：负向探针输出 `Assertion failed ... P0-01_NEGATIVE_PROBE_ASSERTION_FIRED` 并被 `$stop` 终止；脚本同时校验退出码和指定消息，不是仅凭非零退出码判定“预期失败”。

说明：`timeout-probe` 和 `host-timeout-probe` 是两个不同层次；前者由 DUT/testbench 周期预算触发，后者由主机 `timeout` 触发。两者都判为失败。

## 5 软件与参考执行（E04、E05）

工作目录：`/workspace/hias-riscv-cpu`。入口：`make ref-smoke`（日志 `ref-smoke.log`，退出码 `0`）。

编译命令（脚本实际使用绝对路径）：

```sh
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -mcmodel=medany -mno-relax \
  -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2 \
  -T software/smoke/link.ld -Wl,--build-id=none \
  -o build/ref-smoke/ok.elf software/smoke/start.S software/smoke/main.c
```

错误/挂起变体分别追加 `-DSMOKE_FAIL=1`、`-DSMOKE_HANG=1`。三个 ELF 均编译成功（退出码 0，日志 `build-ok.log`、`build-fail.log`、`build-hang.log`）。

ELF 检查（日志 `elf-inspection.log`）：`ELF32`、`Machine: RISC-V`、入口 `0x80000000`、`Tag_RISCV_arch: "rv32i2p1"`；两个 `PT_LOAD` 段分别为 `R E` 与 `RW`；`tohost`、`fromhost`、`_start`、`main` 符号存在；`ok.elf` SHA-256 为 `4852abc4a6572dbe6290861ebe0943db3349e4eb555b1fdb8d94ee6c7550ecfc`。反汇编前 48 行保存在同一日志。

| 用例 | 命令 | 期望 | 实际退出码 | 日志 |
| --- | --- | --- | --- | --- |
| 正常 | `spike --isa=rv32i -m128 --log-commits --log=.../spike-ok-commits.log build/ref-smoke/ok.elf` | 0，提交日志含 `mem ... 0x50415353` | 0 | `spike-ok.log`、`spike-ok-commits.log` |
| 错误结果 | `spike --isa=rv32i -m128 build/ref-smoke/fail.elf` | 非 0，`*** FAILED ***` | 1 | `spike-fail.log` |
| 超时 | `timeout 5s spike --isa=rv32i -m128 build/ref-smoke/hang.elf` | 124 | 124 | `spike-hang.log` |
| 观察接口 | `spike --isa=rv32i -m128 -d --debug-cmd=... build/ref-smoke/ok.elf` | 0，能读寄存器 | 0 | `spike-observe.log` |

结束协议：启动代码把 `main` 返回值编码为 `(code << 1) | 1` 写入 `tohost`，Spike HTIF 以退出码 0 表示成功、1 表示失败。`tohost`/`fromhost` 位于 `.bss` 末尾，启动时清零；未使用 `pk`、libc 或 OS。该宿主协议不代表未来 FPGA 硬件协议。

观察接口：`--log-commits` 输出逐条提交（PC、指令、目标寄存器、内存写入）；`-d --debug-cmd` 使用 `reg 0`、`pc 0`、`until pc 0 <main>` 读取寄存器。日志 `spike-observe.log` 显示到达 `main` 前后的寄存器状态。后续退休差分建议以 `--log-commits` 为主接口，DUT 侧按 `docs/项目设计书.md` 第 8.2 节实现两路退休记录；缺口是尚无 DUT 退休记录、CSR/Trap/Sv32 字段和中断注入对齐。

## 6 统一入口（E06）

总入口：`make check-p0-01`，退出码 `0`。汇总日志 `verification/evidence/P0-01/logs/summary.log`：

```text
steps:
  env-check    exit=0
  rtl-smoke    exit=0
  ref-smoke    exit=0
result: PASS
```

- `make env-check`：退出码 0。
- `make lint-smoke`：退出码 0。
- `make rtl-smoke`：退出码 0。
- `make ref-smoke`：退出码 0。
- 必需工具缺失时 `env_check.sh` 输出 `ENV_CHECK_FAIL` 并返回 1；步骤脚本失败时总入口返回非 0，不会静默跳过。
- 复现：在干净工作区删除 `build/` 与 `verification/evidence/P0-01/logs/` 后重跑 `make check-p0-01` 已实际执行，结果同上（`summary.log` 中 `git_head` 为 `d22b34a...`，`git_status` 仅剩待提交证据）。

## 7 证据对应（E07）

- 被测试实现 Commit：`d22b34a8945a08595cfc2a8cdbd5a1bb9e8024c8`（`test: add P0-01 ...` 与 `docs: link P0-01 ...` 之后）。
- 在该 Commit 上先删除构建产物与旧日志，再运行 `make check-p0-01`；实现提交后未再改动实现。
- 报告与证据作为后续独立提交，不改变被测试实现。
- 分支已推送；未合入 `main`，未进入 P1。
- 证据为 `verification/evidence/P0-01/logs/` 下的原始文本日志和压缩构建日志；`build/` 产物未入库。

## 8 未完成、未验证与阻塞

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 自主 CPU RTL | 未实现 | 本轮只有 FIFO 夹具，不能作为 CPU 成果 |
| DUT 差分（DiffTest） | 未实现 | 仅演示 Spike 观察接口并给出接入建议 |
| ACT4 / Sail / RISCOF | 未运行 | 不在本轮范围 |
| SoftFloat / TestFloat | 未运行 | 不在本轮范围 |
| FPGA / EDA / 上板 | 未运行 | 无板卡与工具 |
| `pk` 与完整 OS | 未使用 | 任务单明确不默认依赖 |
| CSR / Sv32 / Svade / 中断 | 未覆盖 | 留待后续阶段 |
| RV32F / M / C | 未覆盖 | 冒烟目标为 RV32I/ILP32 |
| Verilator 版本选择 | 已锁定 5.008 | 容器 `/usr/local` 预装；Ubuntu 24.04 仓库候选为 5.020，本轮未切换 |
| Spike 版本 | 已锁定 Commit | 源码构建，未提供预编译包 |

未发现网络、权限或依赖阻塞。`make -j128` 构建 Spike 耗时约 1 分钟，日志已压缩保存。

## 9 设计偏离与说明

- 任务单建议的入口名全部保留，未改名。
- 正常 RTL 用例的随机段固定 10,000 周期，总周期 10,071（含复位与定向段），日志分别记录计数。
- `tohost`/`fromhost` 放在 `.bss` 末尾，保证启动清零；`.text` 与 `.data/.bss` 使用不同 `PT_LOAD` 权限，避免链接器 RWX 告警。
- 未使用 `-Wno-fatal` 或全局关闭告警；Lint 使用 `-Wall --assert` 且零告警通过。
- 断言探针的日志包含 shell 的 `Aborted (core dumped)` 行，退出码 134 为 SIGABRT，属于预期行为。

## 10 对阶段门禁的影响与建议

P0-01 只证明工具与验证路径可用，不代表 P0 整体通过，也不代表自主 CPU 已运行。建议管理方：

1. 审查本报告的 E01—E07 与证据对应关系。
2. 通过后安排 P0-02：ISA/CSR/地址图、共享类型、接口时序与测试清单冻结。
3. 在 P0-02 中明确 Spike 退休记录与 DUT 退休接口的字段映射，作为后续 DiffTest 的输入。
4. 板卡、指定 OS 与课程数据仍按设计书风险项单独跟进。

```text
任务：P0-01
任务基线 Commit：6cdc51676e30c8e25f6f4a652f22c8f5ad86a40a
分支：codex/p0-01-environment-smoke
被测试实现 Commit：d22b34a8945a08595cfc2a8cdbd5a1bb9e8024c8
最终交付 Commit：由交付消息给出
报告路径：docs/progress/P0-01-report.md
E01—E07 状态：E01 通过；E02 通过；E03 通过；E04 通过；E05 通过；E06 通过；E07 通过
总入口与退出码：make check-p0-01，0
原始证据目录：verification/evidence/P0-01/
阻塞/未完成项：无环境阻塞；CPU RTL、DiffTest、ACT/Sail、SoftFloat、FPGA 未开展（不在本轮范围）
建议下一步：审查通过后进入 P0-02
```
