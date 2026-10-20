# P1-B-R2 管理验收

审查日期：2026-10-20（Asia/Shanghai）。结论：**G01—G03 关闭，结合 R1 已接受的 JAL、redirect/取消身份和错误累计修复，P1-B 取指/译码验收通过。实施已快进合入 main，允许进入 [P1-C 整数执行与顺序提交](../tasks/P1-C-整数执行与顺序提交.md)。**

验收对象是前端和真实 RAM 集成取字，不是已能执行程序的 CPU。执行、CSR 状态、Trap/真实退休、后端/ROB/BPU/Cache/MMU/FPU、DiffTest、SoC 顶层替换及 FPGA 仍未实现。

## 1 版本与证据

| 项目 | 核对结果 |
| --- | --- |
| 实际修复基线 | `37524bdc8f894e294e5581685379d410e55d14d8`，包含管理提交 `51ecc1c` |
| 被测试实现 | `c14c2befd5483f9ce5b542db32912e453c789add` |
| 最终交付/合入实现 | `3df13084c23d41d1a3ad5e3c08640fb5ea3d85ba` |
| 报告 | [P1-B-R2 报告](P1-B-R2-report.md) |
| 证据 | `verification/evidence/P1-B-R2/`；816 个清单条目逐个重算一致，无重复或遗漏，连同清单共 817 个文件 |
| 清单 SHA-256 | `8d7636e74558c0cf90d638341e29556d05d5919868895b04608ce1d5403b148f` |
| 测试后差异 | 实现提交到交付提交仅新增报告/证据，没有功能变化 |
| 历史保护 | 未改写历史证据；生产 RTL 相对 R1 无修改 |

Windows 管理侧读取 Git 对象、实现差异、TB/观察包装、入口、报告与原始日志并重算哈希；未运行提交的程序、RTL、Spike 或 Linux 总入口。容器实际执行由 opencode 负责。

## 2 问题闭环

| 项目 | 实现与证据 | 结论 |
| --- | --- | --- |
| G01 构建传播 | 两次 build_frontend 返回值立即检查，失败配置不运行，依赖该配置的负向也不运行。default/wrap 分别在真实构建成功、二进制存在后受控返回 3，构建日志 real_rc=0、exit=3；对应 run 日志不存在，实际 make.log 与 summary 均 FAIL | 关闭 |
| G02 独立 PC | next_req_pc 独立来自复位、有效 redirect 和请求接受后的 +4，不由 DUT 当前地址反推；每请求核对 VA/34 位 PA。一次改写独立 PC 期望得到两个 cat=pc 错误，无其他错误，退出 1 | 关闭 |
| G02 请求载荷 | 观察/采样 mem_req_t 的全部有效载荷，检查 word 只读契约；held 检查覆盖最终握手拍。观察夹具只改 byte_mask，真实 held 比较与 mask 契约检查各拒绝一次，exit 1，不改生产请求或 RAM | 关闭 |
| G03 错误原因 | decode/frontend 的指定 op 与其他错误分别计数；PC/请求错误亦计入 other。正常 op 负向 exit 1；仅 imm 错误无 op 时 exit 2；op+imm 时 exit 3。完整定向/首种子注入走完后仍保留失败，指定 op 且 other=0 才有成功标记 | 关闭 |
| G03 实际入口 | directed_other 与 directed_extra 注入原正常运行步骤，输出 WRONG_REASON / EXTRA_ERRORS，不产生指定 op 成功标记；实际总入口汇总 FAIL，make 非零 | 关闭 |

原始请求稳定性反例的两个错误都由同一次 byte_mask 观察变化引起；它证明当前完整请求监视器拒绝该变化，不将其解读为只由稳定性单一检查器检出。PC 反例改变独立期望而非生产 RTL，证明新增地址比较路径有效。

正常 `make check-p1-b` exit 0、summary 为 PASS，P1-A/P0 嵌套回归通过；92 项译码、JAL 工具链锚点、默认/缩小代次、取消/错误响应联合边界、旧版反例与 124/137 探针保留。正常统计：

| 配置 | accepted | requests/matched | responses | orphan | redirects | cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| GEN_W=8 | 1405 | 1777/1777 | 1780 | 3 | 420 | 10182 |
| GEN_W=2 | 1196 | 1571/1571 | 1577 | 6 | 423 | 9460 |

每配置三个固定种子各 340 次随机接受，合计 1020；drain 额外接受另计，因此阶段 accepted=341 的说明成立。异常结果仍是取指异常元数据，不是 CSR/Trap 事件；前端 commit 端口恒空。

## 3 下一步与使用边界

- 已通过的有界定向/固定种子验证不是任意时序的形式化证明；后端接入仍须验证真实 redirect、背压、提交与旧项抑制，不能只复用前端 TB 的 PASS。
- P1-C 复用已验收前端与 RAM，新增 ARF、ALU/分支、单项顺序提交和支持子集的真实 DUT 退休/Spike 对照。P1-F 继续负责含 LSU/CSR/Trap 的完整差分与平台协议，不能把 P1-C 子集结果称为 P1 全通过。
- 现有 p1_soc_top 空闲测试含义保留；P1-C 可新增独立整数核集成顶层。不提前声称 SoC 已替换、FPGA 已验证或 OoO 已实现。
- FPU/OS/板卡/EDA/Benchmark 课程口径仍待确认，不阻止 P1-C；P1-G 实机门禁保持未完成。

原报告/日志的未合入状态保留作为交付时快照。下一轮从包含本验收及任务单的最新 main 新建 `codex/p1-c-integer-execute`，由用户手动转交 opencode。
