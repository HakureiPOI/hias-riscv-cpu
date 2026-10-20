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
- 验证侧维护独立的下一请求 PC 模型：复位为 `RESET_VECTOR`，合法 redirect 更新为目标，接受请求后按顺序 +4；每个真实握手逐字段检查 VA/PA 与 word 只读契约。该模型不从 DUT PA/译码 PC 反向生成。
- 已接受的读必须收尾；redirect 后响应被消费但不生成新译码事件。响应按保存的请求 PC/ID/代次匹配，不按重定向后的 PC 归属。
- 只有 ID 与代次都匹配的响应才能结束已接受请求；错误 ID/代次响应可以消费但保留在途身份、取消标志和回绕屏障。取消项即使后续响应身份匹配也只释放身份且不生成结果。
- 译码结果在消费前保持 PC、指令、预测占位、异常和 `fetch_gen`；`pred_taken=0`、`pred_target=PC+4`、`pred_index=0`。
- 请求 held 期间至最终握手边沿完整比较 is_store、VA、PA、size、byte_mask、wdata、cacheable、priv、ID、gen；测试包装只可改变观察值，生产桥请求不受影响。
- 取指访问错误产生 `fetch_exc_valid=1`、cause=instruction access fault(1)、tval=原取指 PC，且不置 `illegal`；异常结果保持并在交付一次后等待 redirect。
- 代次回绕前阻塞新请求，直到在途响应/旧响应排空；缩小 `GEN_W` 的集成构建强制覆盖。

## 3 译码契约

- 覆盖 RV32I 40 条（含 FENCE/ECALL/EBREAK）、Zicsr 六种、Zifencei、MRET/WFI。
- JAL opcode 下 `instr[14:12]` 是 J-type 立即数，不检查 funct3；`0x000010ef`/`0x000012ef` 分别译码为 JAL x1/x5、imm=+4096。JALR 与其他实际存在的功能码检查保留。
- `rd=x0` 时 `rd_we=0`；Load x0 仍保留 `is_load`；合法 HINT 不因无写回而非法；CSRRS/CSRRC 的读不由 `rd_we=0` 抑制。
- 移位立即数只把 `shamt[4:0]` 作为运算量；I/S/B/U/J 立即数按语义符号扩展。
- 非法编码保留原 32 位指令到 `illegal_tval`，cause=illegal instruction(2)，并清除子操作的写回/访存/CSR/系统标志。
- M/A/C/F、SRET/SFENCE.VMA 等 P1 不支持范围标非法；FENCE/FENCE.I 未用字段按基线忽略。
- 任意输入预测元数据原样传递；Decode 不重新生成覆盖。
- 共享类型扩展：`decoded_slot_t` 与 `renamed_slot_t` 增加 `fetch_gen`。调用者为 P1-B 前端与未来 P1-C 消费者；原因是任务要求代次从取指经译码保存；影响是 packed struct 宽度变化，当前无 P1-C 消费者。

## 4 验证入口

`make check-p1-b`：

1. `p1_frontend_top` 与集成 TB 包装执行 `verilator --lint-only -Wall --assert`。
2. JAL 规范锚点：锁定 RISC-V 工具链 assembler/objdump 对 `0x000010ef`、`0x000012ef`、正负/边界立即数和 `instr[14:12]=0..7` 的编码/反汇编留证。
3. 独立 92 项译码表：40 条指令、JAL 全部 8 个 `instr[14:12]` 值、正负/边界立即数、CSR 六种、zimm=0/31、HINT/FENCE 保留字段、x0、非法/不支持编码；另跑 `+mismatch` 受控负向。
4. 真实 RAM/桥集成：从复位向量逐字取到独立镜像、RAM 末字、越界取指异常、背压、请求停顿、响应延迟、连续 redirect、同拍响应 redirect、非法目标同拍、旧 ID、旧代次、取消后错误响应、强制代次回绕；默认 `GEN_W=8` 与 `GEN_W=2` 配置均运行，3 个固定种子合计 1020 次译码接受。
5. 统一边沿监视：独立请求/响应所有权队列、结果队列、独立请求 PC 模型、全字段译码/请求比较、请求/译码 payload 稳定性、全局错误累计；每阶段/种子输出请求、匹配完成、无主响应、译码接受与错误统计。请求 PC 或 held 请求字段的受控改变分别由 `pc`/`req` 类别检出。
6. 受控负向与注入：前端/译码 `+mismatch`、`+inject_directed`、`+inject_random0` 的 op 成功标记只在 `op_errors>0`、其他错误为 0 且完整流程完成时产生；`other`/`extra` 变体返回可区分的错误原因，runner 不接受为指定 op 检出。`+hang`/忽略 TERM 分别验证 124/137 主机看门狗。
7. 构建失败传播：default/wrap 两个前端构建分别经受控包装，真实生成可执行文件后返回 3；对应配置的运行被抑制，构建步骤和总入口均非零。
8. 旧版复现：对 `278f6f7` 在独立目录复现 JAL 非法、redirect+accept 泄漏、取消后错误响应提前释放与早期错误被清除。
9. `make check-p1-a` 回归（含 P0），所有嵌套证据写入 `verification/evidence/P1-B-R2/regression/`。
