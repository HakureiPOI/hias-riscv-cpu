# P0-02-R1 管理复审

审查日期：2026-10-19。结论：**R04 关闭；R01—R03 部分修复，仍不具备冻结条件。暂不合入实施分支，不进入 P1，执行 [P0-02-R2](../tasks/P0-02-R2-剩余问题修复.md)。** R2 只处理下述剩余问题，不重做已经接受的平台工作，不扩大 CPU 实现范围。

## 1 交付与证据

| 项目 | 核对结果 |
| --- | --- |
| 修复基线 | `3c56bfbb49a5680ae0d8536cd015239ec7d07eb7`，包含原实施与 `4024f86` 管理文档 |
| 被测试实现 | `cdc6238417aaa8a069de9c2cae6dd50ea68145fd` |
| 最终交付 | `49d8d9602947f1a7702e16fe1dbe79dd6b8e5870` |
| 分支 | `codex/p0-02-spec-interfaces` |
| 报告 | [交付版本报告](https://github.com/HakureiPOI/hias-riscv-cpu/blob/49d8d9602947f1a7702e16fe1dbe79dd6b8e5870/docs/progress/P0-02-R1-report.md) |
| 证据 | `verification/evidence/P0-02-R1/SHA256SUMS` 所列 109 项逐项哈希一致 |
| 清单 SHA-256 | `02cb72c1e2a29aad0f3a1406dd10d43f1791700e115bfea44d760cf2b2cf3652`，与交付消息一致 |
| 测试后变更 | 被测试实现至最终交付只有本轮报告、证据和 README 文档链接变更；没有功能实现修改 |
| 历史保护 | P0-02、P0-01、P0-01-R1 的原始证据没有改动 |

Windows 侧仅阅读提交对象、规格、代码、夹具和原始日志，并重算哈希；未运行 RTL、Spike、提交的 Python 检查器或 Linux 总入口。下列失败场景为代码路径推演，交由 Ubuntu 侧实际重现和验证。

日志记录 `git_head=cdc6238...`、工作区只有本轮未跟踪证据、总入口 PASS；平台 ELF/Spike 和历史回归有相应成功日志。退休格式示例为 5 文件、45 条顶层记录（含 bundle）；自测实际有 **16 条 POSITIVE_OK、18 条 NEGATIVE_OK**，源码也只有 18 次 negative 调用，报告与交付消息中的 19 应在后续更正说明，不回写历史日志。

## 2 已接受的修复

- R01：六类 CSR 读写条件、五位立即数、misa I 位、MPP 与复位、计数器方案、EBREAK 和跳转对齐等已有实质修正。仍有下面 B01 的规则错误。
- R02：执行子操作、原指令、异常/预测元数据、反向接收类型与 seq 隔离已加入。公共字段修复接受；夹具尚不能证明其宣称的 Token/并发行为，见 B02。
- R03：v2 已去除伪造的参考 Token/next_pc，新增 CSR 读写有效性、lane、LBU/LHU、Token/Trap 范围和来源检查。仍有 B03 的可绕过路径。
- **R04 关闭**：页表范围精确为 `[0x8001a000,0x8001e000)`、大小 0x4000；单列到栈底的空隙，链接脚本检查大小与端点。配置语义校验与漂移检查分开，负向用例核对 exit 2 与指定原因，独立漂移用例 exit 3；MMIO 寄存器表已有补充。当前固定基线常量的独立断言可以保留；以后改变配置要同步审查，不能把该断言当成第二份可编辑配置。

## 3 剩余问题与具体反例

定位均基于 `49d8d96`，并非 main 当前文件。

### B01（高，延续 R01）：中断权限判断写反，固定 CSR 被误当成整只只读

定位：`docs/architecture/isa-support.md:88–89`；`docs/architecture/csr-support.md:46,64,77,122`。

两份文档均写“当前权限低于目标权限时不响应”，且称委托后的 S 中断可以在 M-mode 响应。这会阻止低权限程序被高权限中断抢占，并错误地下调 Trap 权限。

正确边界：先由委托确定目标级；在对应 pending/individual enable 满足时，当前权限低于目标级，目标级全局中断不受其 xIE 限制；相等时检查该级 xIE；当前权限高于目标级时不响应该目标级中断。已委托给 S 的中断在 M-mode 被屏蔽，不能因 MIE/SIE 开启而转入 S。同步 Trap 的委托也不能使 M-mode 异常进入 S。

`misa` 被标为“RO（本项目）”“整只只读”，同时通用规则要求任何整只只读 CSR 写尝试 Trap。这与其 RW/WARL 属性及 D04 的固定能力写入不改变方案冲突。固定返回 `0x40000100` 可以通过 WARL/固定字段实现，合法 CSR 写应完成而保持值，不应套用 `mvendorid` 等整只只读 CSR 的非法写策略。`mstatush` 的“RO”与“写忽略”也须统一为可合法写、实现字段固定零的行为。明确区分地址权限与字段可变性。

依据：[Machine ISA 的 misa、全局中断、委托和 mip/mie 条件](https://docs.riscv.org/reference/isa/priv/machine.html)，[Supervisor 的中断条件](https://docs.riscv.org/reference/isa/priv/supervisor.html)，[CSR 权限与字段属性](https://docs.riscv.org/reference/isa/priv/priv-csrs.html)。官方当前入口对应 v20260120；实施方按项目锁定版本核对。这是对原 D04 的澄清，不新增扩展或实现任务。

修正表/正文/计划中的同一规则，并消除 D09 已决定后仍把完整 PLIC/CLINT 列为必交、D05/D06 已决定后仍在退休契约列为待审的陈旧文字。

### B02（高，延续 R02）：Token 夹具会复用在途身份，并发计数和分配也不安全

定位：`verification/spec/interface/interface_fixture.sv:64–120`；`verification/spec/interface/tb_interface.cpp:135–175`。

1. **Flush 身份复用**：先分配 `{idx=0,gen=0}` 并保留其外部响应；Flush 将 next_idx、next_gen、所有 valid 和 busy 清零；下一次分配立即再次得到 `{0,0}`。这时旧响应满足 valid+gen 匹配，会被接收为新事务。仅清 valid 只能在重新分配之前挡住旧响应。夹具还没有取消请求的在途记账，busy 清零不能证明外部事务排空。
2. **同拍分配和完成**：两个独立 if 对 busy 分别做 `+1`、`-1`，后一个非阻塞赋值覆盖前一个。同拍一分配一完成，本应净变化零，实际减一；从两项在途开始连续两次这样操作，可得到 busy=0，但仍有两项有效。计数错误还会使回绕过早解锁。
3. **非队头完成后覆写活项**：分配 0/1/2/3 后，先完成 idx=1；busy<DEPTH，但 next_idx=0 仍活着，alloc_ready 没有检查目标项，会覆写 idx=0 的身份。若夹具选择 ROB 顺序回收模型，就必须另行表达完成与回收，不能把任意响应当回收；若选择通用事务槽模型，则必须确保目标槽可分配。

现有 TB 总是分配后立刻释放，Flush 发生在 Token 测试前，因此避开了上述场景。回绕夹具也只看当前 valid/busy，未证明 D06 要求的已取消但仍可返回的事务排空。

修复夹具和说明；可以保守停顿/串行处理冲突，但必须准确保持所有权和净计数。加入独立观察在途集合的记分板，不要求实现 ROB 或 CPU。反向接收路径明确 `valid/ready/accept_count` 的唯一接受条件并按时钟边沿检查；保留未接收槽，不以人工设置几个组合输出代替“恰好一次”检查。第二槽异常与 Flush 同拍响应的原要求继续补足最小契约用例。

### B03（中，延续 R03）：CSR 分类和跨 bundle 序号可以漏检

定位：`scripts/check_retire_contract.py:108–121,178–204,302–311`。

- `check_csr()` 只在 `csr_valid=true` 的分支调用，因此其中“CSR instruction missing csr_valid”的拒绝路径无法覆盖 `csr_valid=false`。以现有正常模板为基础，令 instr=`0x30002073`（CSRRS x0,mstatus,x0）、rd=0、rd_we=false、rd_data=null，其余 CSR 字段全部 false/null，代码会接受，将 CSR 指令隐藏为普通指令。指令分类一致性必须在两个分支外检查。
- `validate_stream()` 对 bundle 使用 `min(seqs) < last`，单条事件却用 `<=`。上一个事件 seq=1，下一 bundle 的 seq_base=1、首槽 seq=1 会通过；重复同一非空 bundle 也可能通过。这违背严格递增契约，应统一跨单条/bundle/Trap 的判据，明确空 bundle 的语义。
- token_valid/next_pc_valid 用真值判断，却没有 need_bool；例如 1 或非空字符串会被当作有效位。按 schema 拒绝错误类型。来源/缺失列表应先验证类型再用于成员查询，避免畸形输入落到非受控 Python 异常；列表字段名和“有值却声明未观测”的矛盾也应一致检查。

补成对正反例，特别是合法零值与未观测的区别。当前自测的正例/反例数量不能代替这些边界检查。用一处明确约定访存 trace 数据是原始总线字还是扩展后的架构值、Store 数据如何对齐，并给出到 `mem_req_t` 的映射，避免 mask 修复后数据语义仍由各模块猜测。

## 4 下一步与边界

继续原分支，从 `49d8d96` 纳入包含本复审和 R2 任务的最新 main；只关闭 B01—B03，已有 D01—D11 保持。新增独立 R2 报告与证据，历史 R1 报告保留，在新报告说明自测计数修正。仍未实现 CPU、DiffTest、ACT/Sail、SoftFloat 或 FPGA。

本次 main 仅提交管理文档；不合入实施分支。B01—B03 的预期行为已明确，无需逐项等待再次批准。关闭后复审冻结 P0-02，再开始 P1 首个实现任务。
