# P1-B 取指与译码报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-B |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 任务基线 | `2dfdcd7254ca00c93f06c31d121399992ea625b2`（含 P1-A-R2 管理验收与 P1-B 任务单） |
| 分支 | `codex/p1-b-fetch-decode` |
| 被测试实现 Commit | `278f6f7e13eb423952c1119a28d1900f3ac57356` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-B-report.md` |
| 证据目录 | `verification/evidence/P1-B/`（139 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `ebffbb8ed8e96a1b68e0e9b9ff5dc22139ad2039de01e041812f9e26d53a6630` |

本轮交付可复用单活动槽取指、RV32I/Zicsr/Zifencei 组合译码和真实 128 KiB RAM/桥前端集成。未执行指令，未更新 CSR，未产生真实退休/Trap；未合入 `main`，未进入 P1-C。

## 1 完成内容

### B01 单活动槽取指

- `rtl/frontend/p1_fetch.sv`：复位 PC=`RESET_VECTOR`，M/Bare，无 C，顺序候选 PC+4；请求固定为 4 字节 word 读，PA 零扩展，`byte_mask=4'b1111`、`is_store=0`、`wdata=0`。
- 最多一个外部请求在途；只有 `valid && req_ready` 边沿接受。未接受请求保持 valid/payload；redirect 取消尚未接受的请求。
- 已接受的读必须收尾。redirect 后旧响应被消费但不产生新译码事件；请求原 PC、ID、代次单独保存，不把响应归到重定向后的 PC。
- 译码结果由保持寄存器保存 PC、指令、预测占位、取指异常和 `fetch_gen`，直到消费者返回 `prefix_accept_t` 的 S0 接受。预测占位为 `pred_taken=0`、`pred_target=PC+4`、`pred_index=0`。
- redirect 优先于同拍正常输出与接受；覆盖请求等待、响应等待、译码背压、恰逢响应同拍和连续 redirect。代次回绕前阻塞新分配，待旧响应排空后再放开；集成构建用 `GEN_W=2` 强制覆盖。
- 不匹配 ID/代次的响应被消费但不写结果，随后真正匹配的响应仍可完成；一次性错误响应由独立 TB 包装注入，不修改生产桥。
- 取指访问错误转换为 `fetch_exc_valid=1`、instruction access fault(1)、tval=原取指 PC，且不置 `illegal`。异常结果稳定保持、交付一次，之后等待 redirect。
- 非 4 字节对齐 redirect 只报告 `redirect_error_o`，不改 PC、不伪造带错误 EPC 的 Trap。
- 输出活动槽仅 S0：`slot_valid=2'b01`，S1 恒无效；S1 接受请求会置 `accept_error_o`，并有单槽断言保护。

### B02 译码

- `rtl/frontend/p1_decode.sv`：组合覆盖 RV32I 40 条（含 FENCE/ECALL/EBREAK）、Zicsr 六种、Zifencei、MRET、WFI。
- 明确生成 rd/rs1/rs2、uses_rs1/uses_rs2、rd_we、立即数、访存宽度、CSR 操作/地址/五位立即数、系统/Fence/异常标志。
- I/S/B/U/J 立即数按语义扩展；移位立即数只把 `shamt[4:0]` 作为运算量。
- `rd=x0` 清 `rd_we`；Load x0 保留 `is_load`；合法 HINT 不因无写回被判非法；CSRRS/CSRRC 的读不由 `rd_we=0` 抑制。
- 非法 opcode/funct3/funct7、RV32M、A/C/F、SRET/SFENCE.VMA 等按冻结范围标非法，保留原 32 位编码到 `illegal_tval`。FENCE/FENCE.I 未用字段按基线忽略。
- 任意输入预测元数据原样传递，不因译码覆盖。取指异常优先于编码非法判断。
- 共享类型扩展：`decoded_slot_t` 与 `renamed_slot_t` 增加 `fetch_gen`，使代次从取指经译码保存到后端接口。调用者为 P1-B 前端与未来 P1-C 消费者；原因是任务要求逐字段保留代次；影响是 packed struct 宽度变化，当前无 P1-C 消费者。`docs/interfaces.md` 已同步说明。

### B03 集成与测试观察

- `rtl/frontend/p1_frontend_top.sv` 直接实例化已验收的 `ram_bridge`/`ram_128k`；`commit_o` 恒为 `slot_valid=0`、`trap_valid=0`，并有断言防止伪造退休/Trap。
- `verification/p1b/tb/frontend_tb_top.sv` 把冻结 struct 展开为标量端口，并提供测试专用请求门控和一次性错误 ID/代次响应注入；生产桥未改动。
- 镜像在取指启动前通过 RAM load 端口静默载入；期望表来自独立 `verification/p1b/gen_decode_cases.py`，不从 DUT 输出生成。
- P1-C 接入位置：消费 `decoded_o`/`decoded_valid_o`，按 `decoded_accept_i` 接收 S0；把执行产生的 redirect 接到 `redirect_i`。P1-B 不产生执行、CSR 状态、Trap 或退休事件。

## 2 验证结果（V01—V05）

总入口：`make check-p1-b`，在实现 Commit `278f6f7e13eb423952c1119a28d1900f3ac57356` 上退出 `0`，输出 `P1-B_CHECK_ALL_PASS`。完整日志在 `verification/evidence/P1-B/logs/`。

### V01 结构/译码

- `verilator --lint-only -Wall --assert -Irtl/include --top-module p1_frontend_top -f rtl/p1_b.f`：退出 0，无未解释告警（`logs/lint.log`）。
- 集成 TB 包装 lint：退出 0（`logs/lint-tb.log`）。
- 独立译码表 76 项：40 条 RV32I、CSR 六种及 zimm=0/31、HINT/FENCE 保留字段、x0、正负立即数与移位边界、非法 funct3/funct7、M/A/C/F、SRET/SFENCE.VMA、非法 opcode；逐字段比较。
- 结果：`P1-B_DECODE_PASS cases=76`（`logs/decode-run.log`）。

### V02 取指/集成

- 从复位向量顺序取到 76 条独立镜像指令，再重定向读取 RAM 末字 `0x8001fffc`；首字和末字均由 TB 镜像期望比较。统计：`P1-B_FRONTEND_BASIC_PASS cases=76 accepted=77`。
- 越界取指 `0x80020000` 返回 `fetch_exc_valid=1`、cause=1、tval=原 PC，且 `illegal=0`；错误结果交付一次后等待 redirect。
- 非法编码与取指异常分开检查；非法编码保留原指令，取指异常不被重分类。
- 单活动槽、`fetch_gen`、预测占位、PC/指令/异常元数据逐字段检查；请求/响应/译码接受分别计数。每个随机种子结束排空后 `requests == responses`；最终种子为 `requests=453 responses=453 redirects=121 cycles=2814`。
- 结果：`P1-B_FRONTEND_PASS ...`（`logs/frontend-run.log`）。

### V03 时序/恢复

- 定向覆盖：请求门控阻塞、响应延迟 0—3、连续译码背压、请求等待 redirect、响应等待 redirect、恰逢响应同拍 redirect、连续 redirect、旧 ID/代次错误响应后恢复、取指异常恢复、对齐/非对齐 redirect。
- 强制回绕：`GEN_W=2` 集成构建；`P1-B_FRONTEND_WRAP_PASS gen_w=2`。
- 随机：三个固定种子 `0x1a2b3c4d`、`0x5e6f7a8b`、`0x9c0d1e2f`，每种子 340 次译码接受，合计 `1020` 次；随机混合 redirect、请求门控、接受背压和 0—3 拍响应延迟。
- 结果：`P1-B_FRONTEND_RANDOM_PASS seeds=3 accepted=1020`。

### V04 检测/回归

- 正常对照：上述 decode/frontend 正常运行均退出 0 并输出 PASS。
- 译码负向：`decode_tb +mismatch` 只改一个期望字段，真实字段比较退出 1 并输出 `P1-B_DECODE_NEGATIVE_MISMATCH_DETECTED`（`logs/decode-mismatch-probe.log`）。
- 前端负向：`frontend_tb +mismatch` 在镜像已载入后只改一个期望 `op`，真实 PC/指令/字段比较退出 1 并输出 `P1-B_FRONTEND_NEGATIVE_MISMATCH_DETECTED`（`logs/frontend-mismatch-probe.log`）。
- 挂起探针：`+hang` 由 `timeout -k 2s 3s` 结束，退出 124；`+hang_ignore_term` 忽略 TERM，由 kill-after 结束，退出 137；两者均保留 `P1-B_FRONTEND_TIMEOUT_PROBE`（`logs/frontend-timeout-*.log`）。
- 预算：前端 `max_cycles=300000`，比较错误上限 30；桥和 RAM 沿用 P1-A 事务/周期检查。构建命令、运行退出码均由总入口检查。

### V05 追溯

- 实现先提交为 `278f6f7e13eb423952c1119a28d1900f3ac57356`；全套检查在该 Commit 上运行，证据 `logs/summary.log` 记录同一 `git_head`。
- `make check-p1-b` 退出 0，外层 `summary.log` 为 `result: PASS`。
- 回归：`P1_A_EVIDENCE=verification/evidence/P1-B/regression/P1-A make check-p1-a` 退出 0；P1-A 总入口输出 `P1-A_CHECK_ALL_PASS`，其中嵌套 `P0-02_CHECK_ALL_PASS`。嵌套日志全部落在 P1-B 证据目录，未覆盖历史 P1-A/P0 证据。
- 证据共 139 个文件（138 个日志/数据文件 + `SHA256SUMS`）；`sha256sum -c SHA256SUMS` 全部通过。

## 3 文件清单

| 路径 | 说明 |
| --- | --- |
| `rtl/frontend/p1_fetch.sv` | 单活动槽取指、取消/排空、保持、代次回绕 |
| `rtl/frontend/p1_decode.sv` | RV32I/Zicsr/Zifencei 组合译码 |
| `rtl/frontend/p1_frontend_core.sv` | Fetch + Decode + 结果保持 |
| `rtl/frontend/p1_frontend_top.sv` | 前端 + 真实 RAM/桥集成顶层 |
| `rtl/p1_b.f` | P1-B RTL 文件清单 |
| `rtl/include/core_types_pkg.sv` | `decoded_slot_t`/`renamed_slot_t` 增加 `fetch_gen` |
| `verification/p1b/gen_decode_cases.py` | 独立译码表生成器 |
| `verification/p1b/decode_expected.h` | 76 项独立期望表 |
| `verification/p1b/tb/decode_tb_top.sv` | 译码单元标量包装 |
| `verification/p1b/tb/tb_decode.cpp` | 译码单元与负向探针 |
| `verification/p1b/tb/frontend_tb_top.sv` | 集成 TB 包装、门控与故障注入 |
| `verification/p1b/tb/tb_frontend.cpp` | 集成/时序/负向/挂起测试 |
| `scripts/check_p1_b.sh` | P1-B 总入口 |
| `Makefile` | 新增 `check-p1-b` |
| `docs/architecture/p1-b-modules.md` | 模块端口、契约与 P1-C 接入位置 |

## 4 V01—V05 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| V01 | 通过 | 生产前端与 TB 包装 lint；76 项独立译码表 |
| V02 | 通过 | 首/末 RAM 字、越界异常、单活动槽、元数据与计数 |
| V03 | 通过 | 背压/延迟/请求取消/响应重定向/回绕/1020 次随机接受 |
| V04 | 通过 | 真实比较路径负向、124/137 看门狗、构建退出码 |
| V05 | 通过 | 实现 Commit 上检查、P1-A（含 P0）回归、证据哈希 |

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 指令执行、ALU、分支解析、LSU 执行 | 未实现 |
| CSR 状态更新、Trap/中断/真实退休 | 未实现；前端不产生 commit/Trap |
| ROB/IQ、BPU、Cache、MMU、FPU、DiffTest | 未实现 |
| P1-C 后端接入 | 未开始；只提供 `decoded_o`/`redirect_i` 接口 |
| SoC 顶层替换空闲骨架 | 未进行；保留原 P1-A 空闲测试含义 |
| FPGA 综合/时序/上板 | 未进行 |

FENCE/FENCE.I 只做保守分类，不承诺 Cache/特殊扩展语义。CSR 地址权限与写合法化留待 P1-E。未合入 `main`，未进入 P1-C。

## 6 交付摘要

```text
任务：P1-B
任务基线 Commit：2dfdcd7254ca00c93f06c31d121399992ea625b2
分支：codex/p1-b-fetch-decode
被测试实现 Commit：278f6f7e13eb423952c1119a28d1900f3ac57356
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-B-report.md
证据目录：verification/evidence/P1-B/
证据数量：139 项（含 SHA256SUMS）
SHA256SUMS：ebffbb8ed8e96a1b68e0e9b9ff5dc22139ad2039de01e041812f9e26d53a6630
V01—V05：全部通过
```
