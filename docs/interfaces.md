# 共享类型与模块接口（P0-02 候选基线）

状态：**候选冻结版本，待管理审查。** 对应 RTL 类型包：

- `rtl/include/core_config_pkg.sv`：参数与位宽。
- `rtl/include/core_types_pkg.sv`：packed struct/枚举。

自检夹具：`verification/spec/types/type_selfcheck.sv`（Verilator 编译并运行）。该夹具只验证类型与位宽，不是处理器模块。

## 1 通用握手与时序

| 规则 | 约定 |
| --- | --- |
| 时钟/复位 | 单时钟；`posedge clk` 采样；同步高有效 `reset`（`RESET_ACTIVE_LEVEL=1`） |
| 传输 | 仅在 `valid && ready` 的上升沿发生 |
| 背压 | 发送方在未接收时保持 `valid` 与全部 payload 稳定；不得以单拍脉冲表示可背压事务 |
| 双槽 | `slot_valid` 必须是程序序连续前缀；消费者用反向 `prefix_accept_t.accept_count`（0/1/2）确认实际接收数量；不允许跳过槽 0 接受槽 1。发送方在收到 accept_count 前保持完整 bundle 稳定 |
| 资源预留 | Rename/Dispatch 必须原子预留 ROB 与目标队列空间；空间不足时保持输入稳定，不改变 RAT |
| 同拍优先级 | reset > redirect/flush > 常规完成/入队；被清除项不得被同拍事件复活 |
| 在途响应 | 每个请求携带 `req_id`/`gen`；只有标识匹配且项仍有效才能更新状态；过期响应丢弃 |
| 不可取消事务 | Store/MMIO 提交事务一旦发出不可取消，必须先完成再处理中断/Flush |

不是所有接口都用同一种握手：

- Fetch→Decode、Decode→Rename、Rename→Dispatch 使用 valid/ready + 双槽 bundle；接收数量由反向 `fetch_accept_t`/`decode_accept_t`/`dispatch_accept_t` 返回，不在前向 payload 中。
- Issue→FU 使用 per-FU valid/ready；一个周期全核最多发射 2 条，LSU 与整数共用配额。
- FU→WB 使用带保持的结果端口；两路完成仲裁，结果保持到被接收。
- Commit/Trap 是单向事件（无 ready），由验证环境按序采样。
- FPU 独立接口使用 valid/ready，一次一个运算在途。

## 2 位宽与标识

| 项 | 值 | 类型/来源 |
| --- | --- | --- |
| XLEN/VA/PA | 32/32/34 | `core_config_pkg` |
| 槽数 | 2（P1 活动宽度 1） | `NUM_SLOTS`/`ACTIVE_SLOTS_P1` |
| ROB | 32 项，索引 5 位，代次 8 位 | `rob_token_t {idx, gen}` |
| 整数 IQ / 访存 FIFO | 16 / 8 项 | `IQ_ENTRIES`/`MEM_FIFO_ENTRIES` |
| 取指缓冲 | 8 项，代次 8 位 | `FETCH_BUF_ENTRIES`/`FETCH_GEN_W` |
| 请求 ID | 6 位 | `REQ_ID_W` |
| 字节掩码 | 4 位 | `BYTE_MASK_W` |
| FPU 事务 ID / flags | 6 / 5 位 | `FPU_TXN_ID_W`/`FPU_FLAGS_W` |

Token 身份 = `{idx, gen}`。代次在 ROB 项重新分配时递增；回绕前必须停止分配并等待所有旧请求排空。仅比较 `idx` 不允许。全局 64 位退休序号 `seq` 只用于仿真追踪，不在可综合关键路径。

## 3 接口清单

| 接口 | 方向 | 类型 | 说明 |
| --- | --- | --- | --- |
| Fetch→Decode | 前向 | `fetch_bundle_t` | 逐槽 PC/指令/预测元数据/取指异常/fetch_gen |
| Fetch→Decode 接收 | 反向 | `fetch_accept_t` | 0/1/2 连续前缀接收数量 |
| Decode→Rename | 前向 | `decoded_bundle_t` | 操作/执行子操作、源/目标、CSR 5 位立即数、访存宽度、非法指令、取指异常 |
| Decode→Rename 接收 | 反向 | `decode_accept_t` | 0/1/2 连续前缀接收数量 |
| Rename→Dispatch | 前向 | `dispatch_bundle_t` | Token、源值/源 Tag、rd、PC、预测、异常、预测索引 |
| Rename→Dispatch 接收 | 反向 | `dispatch_accept_t` | 0/1/2 连续前缀接收数量 |
| Issue→FU | 前向 | `issue_bundle_t`/`issue_slot_t` | 全核最多 2 条；FU ready 后出队 |
| FU→WB | 后向 | `wb_bundle_t` | Token、结果、异常、真实下一 PC、访存结果 |
| Commit/Trap | 事件 | `commit_bundle_t` | 两槽有序退休 + 独立 Trap 事件 |
| LSU/Fetch→MMU | 前向 | 见 §7 | VA、类型、权限、请求 ID |
| Cache→存储桥 | 前向 | `mem_req_t` | 34 位 PA、字节使能、数据、请求 ID/代次 |
| 存储桥→Cache | 后向 | `mem_resp_t` | 请求 ID/代次、数据、错误 |
| Commit/Trap→前端/后端 | 前向 | `redirect_t` | 原因、目标 PC、新 fetch_gen、清除范围 |
| FPU 独立接口 | 双向 | `fpu_req_t`/`fpu_resp_t` | 算子、操作数、舍入、事务 ID、flags |

逐槽字段：

- `fetch_slot_t`：`valid`、`pc`、`instr`、`pred_taken`、`pred_target`、`pred_index`、`fetch_exc_valid/cause/tval`、`fetch_gen`。第二槽取指失败只在该槽到达提交头时产生异常。
- `decoded_slot_t`：粗粒度 `op_class_e` + 细粒度 `exec_op_e`、rd/rs1/rs2、立即数、读写使能、分支/跳转/访存/CSR/Fence/返回标记、非法指令 cause/tval、访存宽度、CSR 操作/地址/5 位 `csr_uimm`、`fetch_exc_*`、`pred_index`。
- `renamed_slot_t`：Token、`exec_op_e`、源就绪/值/Tag、rd、PC、指令、预测/预测索引、架构下一 PC、取指异常、非法指令信息、访存/CSR/系统标记。
- `issue_slot_t`：Token、FU、`exec_op_e` + 原指令、源操作数、立即数、PC、rd、CSR 地址/5 位立即数、预测索引、取指/非法异常、下一 PC。ALU/分支/Load 的子操作由 `exec_op_e` 区分（ADD/SUB、BEQ/BNE、LB/LBU 等），不依赖粗粒度 `op_class_e`。
- `wb_msg_t`：Token、结果、异常、分支解析结果/真实下一 PC、访存写回数据。
- `retire_record_t`/`trap_event_t`：见 `docs/architecture/retire-contract.md`。

## 4 时序表

符号：`S0`/`S1` 为槽 0/槽 1；`X→Y` 表示同拍事件。所有行均假设无 reset。

| 场景 | 输入/事件 | 期望行为 |
| --- | --- | --- |
| T01 接收 0 槽 | `slot_valid=00` | `ready` 可高；`accept_count=0`；无状态变化 |
| T02 接收 1 槽 | `slot_valid=01`，资源足够 | 接受 S0，`accept_count=1`，RAT/ROB 只更新 S0 |
| T03 接收 2 槽 | `slot_valid=11`，资源足够 | 接受 S0、S1，`accept_count=2`；S1 源按 S0 新映射解析 |
| T04 只剩 1 个 ROB/队列项 | `slot_valid=11`，仅 1 项空间 | 消费者返回 `accept_count=1`；只接收 S0；发送方保持 S1 与 bundle 稳定，下一拍 S1 成为新的 S0 |
| T05 槽间 RAW | S1.rs1 = S0.rd | S1 源 Tag 指向 S0 的新 Token；S1 不读旧 ARF |
| T06 槽间 WAW | S0.rd = S1.rd | 最终 RAT 映射指向 S1；S0 的映射被覆盖 |
| T07 槽间 WAR | S0.rs1 = S1.rd | S0 源值在重命名时固定；S1 写不改变 S0 已绑定源 |
| T08 x0 | rd=x0 | 永不建立映射，`rd_we` 必须为 0 |
| T09 入队遇同拍广播 | Dispatch S0 与 WB 同拍 | 必须捕获广播：S0 源可直接就绪，或等待已结束的生产者必须被唤醒 |
| T10 Flush 遇完成 | Flush 与 WB 同拍 | Flush 优先；年轻项不得被完成消息复活 |
| T11 Flush 遇外部响应 | Flush 与存储响应同拍 | 响应按 `req_id/gen` 判定；过期响应丢弃，不写回/不重新入队 |
| T12 第二槽异常 | S0 正常、S1 异常 | 可先提交 S0；S1 异常项保留至下一拍头部处理；S1 不写 ARF |
| T13 双槽同目标提交 | S0.rd=S1.rd | ARF 最终保留 S1（较年轻）结果 |
| T14 不可取消 Store/MMIO 遇中断 | 提交头 Store/MMIO 事务在途，中断挂起 | 先完成事务并退休，再在下一边界响应中断；本拍不切换 |
| T15 Token 代次回绕 | `gen` 接近回绕 | 回绕前停止分配并排空旧请求；禁止仅凭 `idx` 匹配 |
| T16 FPU 背压 | `fpu_resp.valid=1` 且下游未 ready | 结果保持；`txn_id` 稳定；不得接受新请求覆盖未取走结果 |
| T17 第二槽取指异常 | S0 正常、S1 `fetch_exc_valid` | S0 可正常提交；S1 异常在其到达提交头时处理，不覆盖 S0 |
| T18 空 ROB 中断 | ROB 为空，中断使能 | EPC 使用记录的架构下一 PC；本拍不提交普通指令 |

## 5 元数据路径（生产者 → 存储/通道 → 消费者）

| 元数据 | 生产者 | 存储/通道 | 消费者 |
| --- | --- | --- | --- |
| PC、指令、预测方向/目标 | Fetch | fetch_slot_t → decoded/renamed/issue | 分支单元、提交记录 |
| 预测索引 | Fetch | `fetch_slot_t.pred_index` → decoded/renamed/issue | BPU 训练/提交 |
| 取指异常 cause/tval | Fetch | fetch_slot_t → decoded/renamed/issue/commit | 提交头 Trap |
| 非法指令 cause/tval | Decode | decoded_slot_t → renamed/issue/commit | 提交头 Trap |
| 执行子操作 | Decode | `exec_op_e` + 原指令 → issue | ALU/BRU/LSU |
| CSR 5 位立即数 | Decode | `csr_uimm[4:0]` → renamed/issue | CSR 单元 |
| Token | Rename | rob_token_t → issue/WB/commit | ROB/完成/提交 |
| 实际 next_pc | Execute/BRU | `wb_msg_t.actual_next_pc` → ROB | 提交/恢复 |

异常信息可以在专用元数据通道中传递，不要求每个 FU 都携带完整字段；但第二名消费者不得因通道省略而丢失第二槽取指异常或非法指令信息。

## 6 Flush / Redirect 契约

`redirect_t` 字段：`valid`、`cause`（branch/trap/replay）、`target_pc`、`new_fetch_gen`、`flush_all`、`cancel_pending_mem`。

- 首版 `flush_all=1`：清除所有年轻 ROB/IQ/访存 FIFO/RAT 映射与前端槽。
- 已接受的外部请求允许完成，但其过期响应不得写回、重新入队或填回已失效的翻译项。
- 错误路径普通 Cache Refill 可保留为微架构状态；错误路径 Store/MMIO/CSR 更新禁止发生。
- Flush 与完成/入队同拍时，Flush 优先。
- 复位同样要处理外部在途事务；不能假设清除内部 valid 后事务消失。

## 7 完成与写回

- 每个 FU 完成接口支持背压，结果保持到被接收。
- 两路完成端口不足时使用结果寄存器/队列等待；任意多个 FU 同拍完成不得丢结果或长期饿死。
- 完成消息携带 `{token, result, exception, actual_next_pc}`；只有 Token 与有效项匹配才更新/唤醒。
- 入队与 Writeback 同拍必须捕获广播。

## 8 MMU / Cache / 存储桥

- Fetch/Load/Store 各一路查找；Miss 向共享 PTW 发请求。
- PTW 通过 DCache 物理访问入口读 PTE，不绕过到旧外部 RAM。
- 存储请求 `mem_req_t` 携带 34 位 PA、读写、大小、字节使能、数据、`cacheable`、请求 ID 与代次。
- 响应 `mem_resp_t` 携带请求 ID、代次、数据、错误；错误映射到 access fault。
- MMIO 请求必须标记 `cacheable=0`，且只在提交头发出。
- 仲裁只在真正可服务的请求间进行，避免“PTW 等待被 Load 占住的端口”形成循环等待。

## 9 FPU 独立接口

- 请求 `{valid, token, op, a, b, rm, txn_id}`；响应 `{valid, txn_id, result, flags, error}`。
- 首版一次一个运算在途；长延迟结果保持至被接收；复位、背压、连续请求与 Busy 期间请求均需定向测试。
- 非法 `rm` 的接口处理固定为：拒绝并返回 `error=1`，不随机选择模式。
- 该接口不构成 RV32F 支持声明。

## 10 自检夹具

`make check-p0-02` 运行：

- Verilator `--lint-only -Wall --assert` 检查两个类型包与自检夹具。
- 编译并运行 `type_selfcheck`，校验 XLEN/VA/PA、槽数、ROB/IQ/FIFO 容量、Token 位宽、各 bundle 位宽、RAM 常量，并构造每个字段一次以强制类型检查。
- 负向参数夹具 `type_invalid_probe`（`-GINJECT_INVALID=1`）必须产生 `P0-02_INVALID_PARAM_DETECTED` 且非零退出。

## 11 已冻结决策与剩余问题

以下为 P0-02-R1 已关闭的接口决策：

- 双槽接收采用**反向前缀 accept_count**，前向 bundle 不带 accept_count；发送方在接收确认前保持 bundle 稳定。
- CSR 立即数为完整 5 位 `csr_uimm[4:0]`，用 `csr_uimm_valid` 区分寄存器/立即数形式。
- 正常退休与 Trap 同拍互斥；S0 正常、S1 异常时先退休 S0，下一拍输出 Trap。
- `seq` 只在 `retire_trace_t`（仿真包装）中；可综合 `retire_record_t` 不含 seq。
- Token 为 5 位 index + 8 位 generation；回绕前禁止新分配，排空 ROB/IQ/FU/访存/取指/翻译/外部事务；取消请求也必须收尾。

仍需管理方在冻结时确认的次要问题：`wb_msg_t.actual_next_pc` 是否也用于异常路径（当前由 Trap 事件携带 target）；FPU 事务与 ROB 提交的时序在 P6 前细化。
