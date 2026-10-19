# P1-A 基础框架、RAM 与存储桥

状态：P1-A 实施候选，待管理审查。本轮不实现取指、译码、执行或退休；骨架不产生伪事务或伪退休。

## 1 文件与端口

文件清单：`rtl/p1_a.f`。

| 文件 | 模块 | 职责 |
| --- | --- | --- |
| `rtl/core/p1_core_skeleton.sv` | `p1_core_skeleton` | 冻结接口骨架；结构化双槽、P1 活动宽度 1；不发起访存、不产生退休/Trap |
| `rtl/soc/ram_128k.sv` | `ram_128k` | 128 KiB 小端字节阵列；同步读写；测试用 load 端口；复位不清数据 |
| `rtl/soc/ram_bridge.sv` | `ram_bridge` | 单事务 RAM 桥；范围/对齐/掩码/数据检查；错误响应；ID/代次保持 |
| `rtl/soc/p1_soc_top.sv` | `p1_soc_top` | 骨架 + 桥 + RAM 的 SoC 包装；用于结构与空闲验证 |
| `verification/p1a/tb/ram_bridge_tb_top.sv` | TB 包装 | 将冻结 packed struct 展开为标量 TB 端口 |
| `verification/p1a/tb/soc_idle_tb_top.sv` | TB 包装 | 暴露骨架的 retire/trap/request 状态 |

核心端口（`p1_core_skeleton`）：

| 端口 | 方向 | 说明 |
| --- | --- | --- |
| `clk`, `reset` | in | 单时钟；同步高有效复位 |
| `mem_resp_i` | in | 冻结 `mem_resp_t` |
| `mem_resp_ready_o` | out | 骨架恒为 1；P1-B 消费响应 |
| `mem_req_o` | out | 冻结 `mem_req_t`；骨架恒 `valid=0` |
| `mem_req_ready_i` | in | 桥的接受信号 |
| `redirect_i` | in | 冻结 `redirect_t`；骨架不使用 |
| `commit_o` | out | 冻结 `commit_bundle_t`；`slot_valid=0`、`trap_valid=0` |
| `idle_o` | out | 骨架恒 1 |

P1-B 插入点：保留以上端口，P1-B 只实现 Fetch/Decode；执行、访存、CSR、真实退休与差分分别由 P1-C—F 推进。真正的取指和后续 Load/Store 通过 `mem_req_o`/`mem_resp_i` 接入桥；退休记录只在真实指令完成时置位，P1-A 不产生。

## 2 存储请求/响应契约

- 请求使用冻结 `mem_req_t`；`valid` 在 `valid && req_ready` 的上升沿被接受。未握手时发送方保持 `valid` 与全部 payload。
- `req_ready` 表示至少可接收当前请求；同一时刻只允许一个请求在途。响应使用冻结 `mem_resp_t`，`valid && resp_ready` 时消费。
- 同一请求只产生一个响应；`req_id` 与 `gen` 原样返回。地址使用完整 34 位 PA，不截断高两位。
- 请求 wdata 为低标量：SB 低 8 位、SH 低 16 位、SW 32 位；`byte_mask` 指示四字节字内 lane。桥把低字节映射到目标 lane。
- 响应 `rdata` 为按访问宽度提取、低位对齐、零扩展的原始值；LB/LH/LBU/LHU 的架构符号扩展由未来 LSU 完成，桥不猜测。
- `flush_i` 只阻止尚未接受的请求；已接受请求不得消失。Store 接受后为不可取消事务；Load 响应可以由调用者根据 ID/代次丢弃。
- 复位环境前提为外部请求已静默/排空；桥与 RAM 不清除数据阵列，RAM 由 TB 的 load 端口或未来镜像加载写入已知内容。

## 3 RAM 与错误规则

- 地址范围严格 `[0x80000000, 0x80020000)`；高位 PA、低于基址、超过末地址、MMIO 地址均返回 access fault。
- byte 任意 lane；half 必须 2 字节对齐；word 必须 4 字节对齐；非对齐返回 misaligned cause。
- byte mask 必须与 size/lane 精确匹配；size=3 等非法宽度、size/mask 不匹配、store 高位数据非零等非法请求在写 RAM 前拒绝，并报告 load/store access fault；只有有效宽度的自然对齐失败报告 misaligned。
- 读错误 cause：load access fault(5) / load misaligned(4)；写错误：store access fault(7) / store misaligned(6)。错误响应 `rdata=0`，内存保持。
- 自然对齐 byte/half/word、首末字节、四种 lane、两种 half lane、部分写保持邻接字节、连续同址读写均覆盖。
- 错误请求不写内存；读/写响应都在 `resp_ready` 背压下保持。

## 4 验证入口

`make check-p1-a` 依次运行：

1. `verilator --lint-only -Wall --assert` 检查 `rtl/p1_a.f`。
2. 空闲骨架 TB：16 周期内 `mem_req_valid=0`、`slot_valid=0`、`trap_valid=0`、`idle=1`。
3. RAM/桥 TB：定向边界 + 3 个固定种子（`0x1a2b3c4d`、`0x5e6f7a8b`、`0x9c0d1e2f`）各 450 笔合法/非法混合事务；独立字节数组记分板；逐边沿检查请求/响应稳定（含最终握手拍）、响应一次、实际 RAM 写事件与非法请求零写；串行与 pipeline 共用接受/完成计数；统一时钟计数覆盖初始化和全部事务。修复后统计以实际日志为准。
4. RAM 负向探针：真实比较路径注入一次错误期望，要求非零退出与 `P1-A_RAM_TB_NEGATIVE_MISMATCH_DETECTED`；稳定性反例先运行无故障正常对照，再用合法 6 位 ID 注入 held 响应变化，仅 `stability_errors` 能产生 `P1-A_RAM_TB_STABILITY_DETECTED`；final-handshake 反例在 ready=1 的最终握手拍改变载荷，由同一监视器报告 `P1-A_RAM_TB_FINAL_HANDSHAKE_DETECTED`。
5. 挂起探针：比较负向入口、专用 timeout 入口以及忽略 TERM 的场景均由有限主机看门狗 + kill-after 执行，分别核对 124/137；超时不会被当成比较探针成功。
6. Token 联合补测：缩小代次下，回绕前存在已取消匹配响应；新分配持续阻塞，真正收尾后恢复（R2 不重开）。
7. 预期失败注入：`P1_A_INJECT_MISMATCH_HANG=1 make check-p1-a` 让原比较步骤在产生比较错误后挂起；其判据仍为 exit 1 + 比较错误，因此超时 124 使该步骤和总入口 FAIL，外层 `timeout` 只作最后保护。
7. `make check-p0-02` 回归（含 P0-01/R1），所有嵌套日志写入 `verification/evidence/P1-A/regression/`。

## 5 未完成与边界

- 未实现取指/译码/ALU/LSU/CSR/ROB/Cache/MMU/FPU；没有真实退休或 DiffTest。
- UART、结果寄存器、中断外设未实现；MMIO 地址当前由桥返回 access fault。
- 未进行 FPGA 综合、时序、资源或上板；无板卡结论。
- P1-B—F 才逐步建立真实程序执行、退休记录与基本差分；P1-B 本身只做取指/译码。
