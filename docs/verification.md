# 验证入口（P0-01 / P0-01-R1 / P0-02 / P0-02-R1 / P0-02-R2 实测）

本文只记录仓库中实际存在并执行过的入口。P0-01 的夹具不是 CPU 实现，参考执行也不代表自主 CPU 已运行。

## 环境

锁定值见 `scripts/toolchain.lock`。本次实测环境：

- Ubuntu 24.04.4 LTS，Linux 6.8.0-124-generic x86_64，root 容器。
- Verilator 5.008（`/usr/local/bin/verilator`）。
- `riscv64-unknown-elf-gcc` 13.2.0，`-march=rv32i -mabi=ilp32`。
- Spike 1.1.1-dev，源码 Commit `5a760667bf0d0ab893173b9eeff9c109c8d7dd9a`，安装到 `/usr/local/bin/spike`。Ubuntu 24.04 无 `spike` 软件包，需源码构建。

## 总入口

```sh
make check-p0-01
```

依次执行 `env-check`、`rtl-smoke`、`ref-smoke`；任一步骤缺少工具、超时、未运行或出现非预期失败时整体非零返回。每个步骤另有 `P0_01_STEP_TIMEOUT`（默认 600 秒）主机级时限。预期失败探针由步骤脚本按“退出码 + 指定消息”双重判定，不吞掉任意非零退出码。

## 分项入口

| 目标 | 内容 |
| --- | --- |
| `make env-check` | OS/内核/资源、工具路径与版本、RV32I/ILP32 编译探针、ELF 属性 |
| `make lint-smoke` | `verilator --lint-only -Wall --assert` 检查夹具与断言探针 |
| `make rtl-smoke` | 构建并运行 valid/ready 夹具；正常、记分板错误、周期超时、看门狗、断言负向探针 |
| `make ref-smoke` | 构建 RV32I ELF 三个变体，检查 ELF/反汇编，Spike 正常/错误/超时运行及观察接口 |
| `make r1-probes` | P0-01-R1 受控故障注入：正常路径挂起、观察挂起、构建非零、记分板比较 |
| `make platform-generate` | 从 `config/platform.json` 生成平台头文件、链接片段、Spike 参数 |
| `make platform-check` | 校验配置、生成文件漂移、链接/ELF 布局与 Spike 参数一致 |
| `make check-p0-02` | 平台正/负向/漂移、共享类型、接口/事件夹具、退休契约检查 + P0-01/R1 回归（R2 默认日志写入 P0-02-R2 目录） |
| `make clean` | 删除 `build/`，不删除证据 |

## P0-02 平台配置

单一事实来源是 `config/platform.json`；`scripts/gen_platform.py` 生成 `software/generated/platform.h`、`software/generated/platform.ld`、`config/platform.spike.args`、`config/platform.generated.json`。`--validate-only` 只做语义校验（非法配置退出 2），`--check` 另比较生成内容并拒绝漂移（退出 3）。`scripts/check_platform.py` 校验链接常量、ELF 段与保留区域、Spike 参数；页表区精确为 `[0x8001a000,0x8001e000)`、大小 `0x4000`，栈前空隙单独输出。负向检查保留 7 类语义错误并增加非页粒度页表，另有独立的生成物漂移用例。

`scripts/run_ref_smoke.sh` 不再使用 `-m128`，而是读取 `config/platform.spike.args`，因此软件链接区域与 Spike 参考内存统一为 `0x80000000`、`0x20000`（128 KiB）。

## P0-02 共享类型

`rtl/include/core_config_pkg.sv` 与 `rtl/include/core_types_pkg.sv` 由 Verilator `--lint-only -Wall --assert` 检查；`verification/spec/types/type_selfcheck.sv` 编译运行并校验关键位宽、5 位 CSR 立即数、`exec_op_e`、异常/预测元数据、`prefix_accept_t` 与 `retire_trace_t` 的 seq 隔离；`type_invalid_probe` 用非法参数证明自检会失败。`verification/spec/interface/interface_fixture.sv` 是最小双槽/资源/Token 通道夹具：发送端队列 + 接收端记分板在时钟边沿检查 S0/S1 恰好一次；Flush 后身份保留到外部响应；同拍分配/完成使用净计数；非队头完成不覆盖活动项；缩小编号/代次宽度强制回绕并排空。`retire_event_fixture.sv` 验证 S0 正常先退休、S1 异常下一拍 Trap、同拍互斥和异常元数据保持。它们不是 CPU 模块。

## P0-02 退休契约

`verification/spec/retire/retire_schema.json`（`hias-retire/2`）定义字段与有效性规则；`scripts/check_retire_contract.py --self-test` 用合法正例与单项非法反例成对验证 CSR 分类不可绕过、六种读写条件、四字节 lane、半字位置、LBU/LHU、缺失观测、Token 布尔/范围、Trap 字段/来源、跨 normal/bundle/Trap 的严格 seq、空 bundle 语义与 bundle 互斥；`--validate-examples` 校验基础、CSR、内存、bundle 合成夹具与由真实 Spike 提交日志转换的样例（`source=spike-derived`，不是 DUT 退休记录）。转换器对未知权限、损坏行或缺失 rd 值直接报错，不静默丢弃。转换命令与字段映射见 `docs/architecture/retire-contract.md`。

## 主机看门狗与可配置变量

`scripts/lib/watchdog.sh` 的 `run_guarded` 为每次 RTL 仿真、断言探针、构建、Spike 正常/错误/观察运行加 `timeout -k 5s`。超时返回 124/137，日志写入 `P0-01_WATCHDOG_TIMEOUT` 和实际退出码，并明确判为失败。

| 变量 | 默认 | 用途 |
| --- | --- | --- |
| `P0_01_HOST_TIMEOUT` | 60 | 通用主机时限（秒） |
| `P0_01_STEP_TIMEOUT` | 600 | 总入口每个步骤的时限 |
| `P0_01_NORMAL_TIMEOUT` | 继承通用值 | RTL 正常仿真 |
| `P0_01_SPIKE_NORMAL_TIMEOUT` | 继承通用值 | Spike 正常运行 |
| `P0_01_SPIKE_HANG_TIMEOUT` | 5 | 专用 Spike 超时探针 |
| `P0_01_OBSERVE_TIMEOUT` | 5 | Spike 观察命令 |
| `P0_01_LOG_DIR` | `verification/evidence/P0-01-R1/logs` | 日志输出目录 |

故障注入开关仅用于探针：`P0_01_NORMAL_HANG`、`P0_01_SPIKE_NORMAL_HANG`、`P0_01_OBSERVE_HANG`、`P0_01_BUILD_FAULT`。`P0_01_BUILD_FAULT=1` 时通过 `scripts/probes/verilator_build_fail.sh` 调用真实 Verilator，并在其返回 0 后强制返回 3，用来证明“二进制存在但构建非零”不会被当成成功。

## RTL 夹具

`verification/smoke/rtl/smoke_buffer.sv` 是 4 项、16 位的同步 valid/ready FIFO，仅用于验证构建、复位、握手、Flush、断言与退出机制。管理审查已接受“四项 FIFO 而非一项深度缓存”的范围偏离；该夹具不是 CPU 公共模块，也不代表 CPU 已验收。

定向测试后使用固定种子 `0x5eed1234` 运行 10,000 周期随机激励，并以独立 `std::deque` 记分板核对接收、输出、Flush/复位丢弃与守恒。断言负向探针位于 `verification/smoke/rtl/assert_probe.sv`，必须产生 `P0-01_NEGATIVE_PROBE_ASSERTION_FIRED` 且非零退出。记分板负向模式只改写一次期望值，由正常输出比较路径报告 `P0-01_SCOREBOARD_MISMATCH`。

## 软件与参考执行

`software/smoke/` 提供 freestanding RV32I 程序：启动汇编清零 `.bss`、建立栈、调用 C 函数，通过 `tohost` 的 `(code << 1) | 1` 编码结束。链接脚本使用 `0x80000000`、128 KiB RAM，未使用 libc、pk 或 OS。Spike 使用 `-m128`，即 128 MiB 参考内存；两者容量不同，当前程序只访问链接区域内地址。P0-02 必须统一 DUT 与参考模型的内存/PMA 约定。

`SMOKE_FAIL=1` 反转判定作为错误结果负向用例；`SMOKE_HANG=1` 进入死循环作为超时负向用例。Spike 观察接口使用 `--log-commits` 与 `-d --debug-cmd`（`reg`/`until pc`），为后续退休差分提供基础；本轮不实现 DiffTest。

## 证据

原始小型日志位于 `verification/evidence/P0-01/`、`P0-01-R1/`、`P0-02/`、`P0-02-R1/`、`P0-02-R2/`，与对应报告的 Commit、命令和退出码对应。`build/` 产物不入库。R2 运行使用 `P0_02_EVIDENCE=verification/evidence/P0-02-R2`，回归的 `P0_01_LOG_DIR`/`P0_01_R1_PROBE_DIR` 指向其 `regression/` 子目录。
