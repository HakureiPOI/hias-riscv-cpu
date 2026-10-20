# P1-B 取指、译码与前端集成

状态：P1-B 实施模块说明。前端只完成取指、RV32I/Zicsr/Zifencei 译码和结果保持；不执行指令、不更新 CSR、不产生真实退休/Trap。

## 1 文件与端口

文件清单：`rtl/p1_b.f`。

| 文件 | 模块 | 职责 |
| --- | --- | --- |
| `rtl/frontend/p1_fetch.sv` | `p1_fetch` | 单活动槽取指；一个在途读；候选 PC+4；请求取消、已接受响应排空丢弃、结果保持、代次回绕排空 |
| `rtl/frontend/p1_decode.sv` | `p1_decode` | 纯组合 RV32I 40 条、Zicsr 六种、Zifencei、MRET/WFI；非法/不支持编码分类；保留取指异常与元数据 |
| `rtl/frontend/p1_frontend_core.sv` | `p1_frontend_core` | Fetch+Decode 连接；译码结果保持与反向 prefix_accept；redirect 优先清除 |
| `rtl/frontend/p1_frontend_top.sv` | `p1_frontend_top` | 接入已验收 `ram_bridge`/`ram_128k` 的实际集成顶层；只读取指，不产生 commit/Trap |
| `verification/p1b/tb/decode_tb_top.sv` | TB 包装 | 独立译码单元标量端口 |
| `verification/p1b/tb/frontend_tb_top.sv` | TB 包装 | 真实 RAM/桥 + 测试专用请求门控与一次性故障响应注入 |

`p1_frontend_top` 主要端口：

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `clk`, `reset` | in | 单时钟；同步高有效复位 |
| `redirect_i` | in | 冻结 `redirect_t`；仅接受 4 字节对齐目标，未对齐只报协议错误 |
| `load_valid/load_word_addr/load_data` | in | 测试/初始化 RAM 加载端口；取指启动前使用 |
| `resp_delay_i` | in | 桥响应延迟测试输入 |
| `decoded_o`, `decoded_valid_o` | out | 冻结 `decoded_slot_t` 单活动槽结果 |
| `decoded_accept_i` | in | 冻结 `prefix_accept_t`；只接受 S0，S1 返回 `accept_error_o` |
| `mem_req_valid_o/mem_req_ready_o` | out | 观察桥请求握手 |
| `mem_resp_valid_o/mem_resp_ready_o` | out | 观察桥响应握手 |
| `commit_o` | out | 冻结 `commit_bundle_t`；恒 `slot_valid=0`、`trap_valid=0` |
| `req_pending_o`, `fetch_*`, `decoded_*` | out | 验证观察端口，不属于架构提交 |

P1-C 接入位置：消费 `decoded_o`/`decoded_valid_o`，按 `decoded_accept_i` 逐个接收 S0；把执行单元产生的 redirect 接到 `redirect_i`。后端负责 ALU、分支/LSU、CSR 状态、Trap/退休；P1-B 不产生这些事件。`fetch_gen` 已从取指槽经译码结果保留，供后续按代次丢弃旧项。

## 2 取指契约

- 复位 PC=`RESET_VECTOR`，M/Bare，无 C；顺序候选 PC 每条 +4。
- 请求为 4 字节 word 读：PA 为 VA 零扩展，`byte_mask=4'b1111`、`is_store=0`、`wdata=0`、`size=MEM_WORD`。
- 最多一个请求在途；请求只有在 `valid && ready` 边沿接受。未接受时请求 payload 保持；redirect 取消尚未接受的请求。
- 已接受的读必须收尾；redirect 后响应被消费但不生成新译码事件。响应按保存的请求 PC/ID/代次匹配，不按重定向后的 PC 归属。
- 不匹配 ID/代次的响应被丢弃并继续等待真正响应；测试包装可先注入错误 ID/代次再送真实响应。
- 译码结果在消费前保持 PC、指令、预测占位、异常和 `fetch_gen`；`pred_taken=0`、`pred_target=PC+4`、`pred_index=0`。
- 取指访问错误产生 `fetch_exc_valid=1`、cause=instruction access fault(1)、tval=原取指 PC，且不置 `illegal`；异常结果保持并在交付一次后等待 redirect。
- 代次回绕前阻塞新请求，直到在途响应/旧响应排空；缩小 `GEN_W` 的集成构建强制覆盖。

## 3 译码契约

- 覆盖 RV32I 40 条（含 FENCE/ECALL/EBREAK）、Zicsr 六种、Zifencei、MRET/WFI。
- `rd=x0` 时 `rd_we=0`；Load x0 仍保留 `is_load`；合法 HINT 不因无写回而非法；CSRRS/CSRRC 的读不由 `rd_we=0` 抑制。
- 移位立即数只把 `shamt[4:0]` 作为运算量；I/S/B/U/J 立即数按语义符号扩展。
- 非法编码保留原 32 位指令到 `illegal_tval`，cause=illegal instruction(2)，并清除子操作的写回/访存/CSR/系统标志。
- M/A/C/F、SRET/SFENCE.VMA 等 P1 不支持范围标非法；FENCE/FENCE.I 未用字段按基线忽略。
- 任意输入预测元数据原样传递；Decode 不重新生成覆盖。
- 共享类型扩展：`decoded_slot_t` 与 `renamed_slot_t` 增加 `fetch_gen`。调用者为 P1-B 前端与未来 P1-C 消费者；原因是任务要求代次从取指经译码保存；影响是 packed struct 宽度变化，当前无 P1-C 消费者。

## 4 验证入口

`make check-p1-b`：

1. `p1_frontend_top` 与集成 TB 包装执行 `verilator --lint-only -Wall --assert`。
2. 独立 76 项译码表：40 条指令、CSR 六种、zimm=0/31、HINT/FENCE 保留字段、x0、立即数边界、非法/不支持编码；另跑 `+mismatch` 受控负向。
3. 真实 RAM/桥集成：从复位向量逐字取到独立镜像、RAM 末字、越界取指异常、背压、请求停顿、响应延迟、连续 redirect、同拍响应 redirect、旧 ID/代次、故障响应后恢复、强制代次回绕；3 个固定种子合计 1020 次译码接受。
4. 受控负向与挂起探针：前端 `+mismatch` 只经字段比较路径失败；`+hang`/忽略 TERM 分别验证 124/137 主机看门狗。
5. `make check-p1-a` 回归（含 P0），所有嵌套证据写入 `verification/evidence/P1-B/regression/`。
