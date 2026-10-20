# P1-C 整数执行与顺序提交

状态：P1-C 实施模块说明。复用已验收 P1-B 前端与 P1-A RAM/桥；实现 29 条 RV32I 整数/控制流指令、32×32 ARF、单项顺序提交和子集 Spike 差分。未实现 Load/Store、CSR/Trap、M/A/C/F、OoO、Cache/MMU/FPU、真实完整 DiffTest 或 SoC 替换。

## 1 文件与端口

文件清单：`rtl/p1_c.f`。

| 文件 | 模块 | 职责 |
| --- | --- | --- |
| `rtl/core/p1_arf.sv` | `p1_arf` | 32×32 整数寄存器堆；双组合读、提交写；x0 恒零、写 x0 抑制；复位清零 |
| `rtl/core/p1_alu.sv` | `p1_alu` | 10 条 OP、9 条 OP-IMM、LUI/AUIPC、JAL/JALR、6 条分支的结果/目标/方向 |
| `rtl/core/p1_integer_core.sv` | `p1_integer_core` | 单指令在途后端；ARF 读、ALU、Token/顺序提交、redirect、held fault |
| `rtl/core/p1_integer_top.sv` | `p1_integer_top` | P1-B 前端 + 真实 RAM/桥 + 整数后端集成 |
| `verification/p1c/tb/integer_tb_top.sv` | TB 包装 | 暴露提交、fault、ARF、前端恢复观察端口 |
| `verification/p1c/tb/*.cpp` | TB | ALU/ARF、DUT 退休/ARF 记录、fault/控制边界 |

`p1_integer_top` 主要端口：

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `clk`, `reset` | in | 单时钟、同步高有效复位 |
| `accept_stall_i` | in | 后端 IDLE 接受停顿；前端保持译码结果 |
| `load_valid/load_word_addr/load_data` | in | 测试镜像加载端口 |
| `resp_delay_i` | in | 桥响应延迟测试输入 |
| `commit_o` | out | 冻结 `commit_bundle_t`；只 S0 正常退休，Trap 恒空 |
| `fault_valid_o` 及 `fault_*` | out | held fault kind/PC/instr/cause/tval/Token/fetch_gen |
| `arf_debug_o[0:31]` | out | 验证观察，不参与执行 |
| `redirect_valid_o/redirect_target_o` | out | 控制转移提交时驱动前端的真实 redirect |
| `decoded_valid_o/decoded_pc_o` | out | 前端译码观察 |
| `req_pending_o`, `mem_*`, `ram_write_o` | out | 前端/桥观察；整数后端不发起访存 |

P1-D/E 边界：Load/Store 由 P1-D 接入；CSR/Trap/MRET/WFI/Fence 由 P1-E/F 接入。当前合法但未实现的这些编码进入 `fault_kind=2` 的停止状态，不写 ARF、不提交、不产生访存副作用，也不伪装成非法编码。

## 2 顺序后端与身份

- 状态：`IDLE → EXEC → EXEC2 → EXEC3 → COMMIT → IDLE`；每条非 fault 指令接受后固定四拍提交，给前端预取/译码一个稳定窗口。单指令在途，无旁路。
- `decoded_accept_o` 仅在 IDLE 且 `decoded_valid_i` 且 `!accept_stall_i` 时返回 1；frontend 保持完整 payload。
- 每次接受分配 `rob_token_t{idx=0, gen=next_gen}`，gen 每次接受递增；单指令在途保证回绕前旧项已提交或停止。Token 随真实提交/fault 输出，不在日志端用 seq 伪造。
- ARF 读在 IDLE 组合读取（x0 为 0）；提交边沿写 `rd`/`rd_data`。JALR 的 `rd=rs1` 使用提交前旧值；RAW/WAW 由单在途顺序自然满足。
- `COMMIT` 拍输出 S0 正常退休，更新 ARF；所有正常项（包括 rd=x0、非写回分支）恰好一次。Trap/mem/csr 字段恒无效。
- 控制转移（JAL/JALR/六分支）提交时同时输出 `redirect_o`，目标为真实 `next_pc`；该条自身的提交/链接写入不受 redirect 影响，前端年轻项被清除。未 taken 分支也保守重取 PC+4。
- 集成顶层提供测试专用 `req_gate_i`：同一真实请求握手在核心侧看到 `ready=0`、桥侧看到 `valid=0`，生产桥/RAM 不变；TB 用控制流提交实际触发四种恢复时序（未接受请求、已接受响应等待、响应同拍、held 译码），并观察原控制流自身提交/链接写与旧路径不退休。
- 目标对齐：JAL/ taken 分支检查 bit1:0；JALR 先清 bit0 再检查 bit1。未对齐 taken 目标进入 fault kind=3、cause=0、tval=错误目标；未 taken 同一目标不 fault，不写 ARF、不提交。
- 故障优先级：fetch exception > illegal encoding > legal-but-unsupported > misaligned target。fault 进入停止状态并保持 PC/instr/cause/tval/Token/fetch_gen；当前不更新 `mepc/mcause/mtval/mstatus`，也不产生 Trap 事件，Trap 留给 P1-E。

## 3 整数/控制语义

- OP：ADD/SUB 模 2^32；SLL/SRL/SRA 取低 5 位移位量；SLT/BLT/BGE 有符号；SLTU/BLTU/BGEU 无符号；XOR/OR/AND 位运算。
- OP-IMM：I 立即数按 12 位符号扩展；SLTIU 对符号扩展后的 32 位立即数做无符号比较；SLLI/SRLI/SRAI 只用 `imm[4:0]`。
- LUI 写立即数；AUIPC 使用原 PC+立即数；JAL/JALR 链接 PC+4。
- JALR 目标 `(rs1_old + imm) & ~1`；JAL/branch 目标 `PC+imm`。
- 分支未 taken 的 `next_pc=PC+4`；仅实际 taken 才检查目标对齐。

## 4 软件与 Spike 子集差分

- `software/p1c/directed.S`：初始化全部架构寄存器，覆盖 29 条、RAW/WAW、x0、rd/source 重叠、正负/边界、前后向控制流、有限循环、JAL/JALR 链接与 bit0 清除、taken/untaken 对齐差别，结束于 `end: jal x0,end`。
- `scripts/gen_p1c_random.py`：三个固定种子，每个生成初始化 + 40 次有界循环 + 随机算术/前向分支/跳转 + 尾部，退休数 >1000。
- 软件链接复用 `software/smoke/link.ld` 与平台单一来源；只用 rv32i/ilp32、无 C/M/访存/CSR。
- Spike 使用 `config/platform.spike.args`、`--pc=0x80000000` 直接进入目标 ELF，`--instructions=5000` 有限运行，`--log-commits` 记录参考提交。脚本在第一个 `end` PC 截断参考流（无启动 ROM 指令），不丢弃任何 DUT 退休。
- DUT TB 从 `commit_o` 记录 source=dut 正常记录（真实 Token/next_pc/seq），停止于同一 `end` PC；`scripts/p1c_diff.py` 比较 PC、原指令、priv、rd 写/值、DUT next_pc 与相邻参考 PC（最后一条用 end 快照，标记 derived）、最终 32 个 ARF 寄存器和退休数。参考 Token 不可观测，只断言 DUT idx=0 与 gen 递增/回绕。
- 差分完整消费 DUT 文件：公共入口调用 `check_retire_contract.validate_stream` 校验 `hias-retire/2` 的 seq/字段/类型/来源规则，再检查恰好一个末尾终点退休，拒绝其后额外正常记录/Trap/坏行；真实 `priv` 来自 DUT 记录；参考后缀只允许终点自循环，最后 `next_pc` 由实际后继参考 PC 推导。最终寄存器/提交终点/提交后 next_pc/退休数分别校验。格式错误在正常、注入和 `pc_extra` 模式中都先返回基线失败。
- 差分负向：`pc`、`instr`、`rd`、`next_pc`、`missing`、`duplicate`、`token` 七类先验证干净基线，只有指定字段/位置/计数差异才产生成功标记；脏基线、目标错误伴随额外错误、错误原因不符分别拒绝。实际总入口在注入原正常步骤后自行 FAIL。
- 监视器负向：观察夹具在首次 fault 注入错误 x1 链接值但随后稳定，必须被独立镜像拒绝；保持期间改变一寄存器必须被真实保持监视拒绝。正常关闭注入通过；实际总入口在注入 fault 步骤后 FAIL。
- 恢复/停止验证：真实定向程序覆盖六分支 taken/untaken 矩阵；请求门控四类恢复场景；fault TB 从复位建立独立 32 寄存器镜像，仅按预期正常提交更新，首次 fault 即与镜像比较，保持 16 个实际边沿继续比较且核对完整身份/元数据、无 commit/Trap/RAM 写；新增 JALR 清 bit0 后 bit1 仍非对齐的停止用例。
