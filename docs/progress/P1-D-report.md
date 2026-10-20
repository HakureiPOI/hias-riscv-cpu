# P1-D Load/Store 与访存仲裁报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-D |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 任务基线 | `8c292473e8e85505b8571684d2d3d25d606d6c3d` |
| 分支 | `codex/p1-d-load-store` |
| 被测试实现 Commit | `b42794cbe2e704251b277fc65a3a0f6c73ad6622` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-D-report.md` |
| 证据目录 | `verification/evidence/P1-D/`（1328 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `d5d81b0c1b44e1ecd8cce37539e7e4d769360d9884ed16057727904952012b9f` |

本轮在 29 条整数/控制指令基础上新增 LB/LH/LW/LBU/LHU/SB/SH/SW，完成取指/数据共享 RAM 仲裁、RAM 数据访问故障停止和真实访存退休。未实现 CSR/Trap、MMIO 外设、Cache/MMU、OoO、完整 DiffTest、SoC 替换和 FPGA；未合入 `main`，未进入 P1-E/F。

## 1 实现内容

### D01 LSU 与退休

- `p1_integer_core` 新增 8 条 Load/Store：EA=(旧 rs1+符号扩展 imm) mod 2^32，PA 零扩展到 34 位；Bare、cacheable=1、M 模式。
- Keeper 保存原 PC/instr、EA/PA、宽度、读写、标量写数据、Token/fetch_gen/ARF 结果，直到完成或 fault。单条在途，提交前不接受下一条。
- mask 为四字节字内 lane；Store wdata 为低 8/16/32 位标量、不左移；桥返回低位零扩展原始值，LB/LH 在 LSU 做符号扩展，LBU/LHU 零扩展，LW 原样。
- Load 只在匹配成功响应后完成，ARF 只在真实提交边沿写入；Load x0 仍执行访问。Store 不写 ARF，成功响应后恰好退休一次。
- Store 在单项顺序提交槽头授权下发送；接受后不可取消，普通 redirect 不撤销/重发；失败 Store 不写 RAM。
- 退休携带真实 mem_valid/we/va/pa/size/mask/wdata/rdata；普通 ALU/branch mem_valid=0。seq 仍由真实退休事件递增。

### D02 共享仲裁

- `p1_bus_arbiter` 管理前端 fetch 与 LSU data 两个 client，全局最多一笔已接受事务。
- 请求 valid&&!ready 时保持完整 payload；选择在未接受时锁定，后来的 client 不能抢占。
- 双客户端同时等待时按 last-owner 轮转（LSU/FETCH 交替），保证有限公平服务。
- 只有被选 client 看到 ready；响应只路由给 owner，非 owner valid=0；响应背压时桥保持。
- 集成 TB 逐拍检查 held LSU 请求完整 payload；counters 区分 data_req/data_resp/fetch_req/fetch_resp/ram_writes/data_req_waits。定向数据请求/响应 63/63、写 31；三个随机种子各 data_req/resp 264/264、writes156、loads108。
- 错路 Store/Load 片段位于 taken branch 后；实际 data_req/writes 与未加入该片段一致，未产生错路访存。

### D03 数据故障

- 自然对齐预检：非对齐 LH/LHU/LW cause=4；SH/SW cause=6。对齐但 RAM 外/MMIO/保留地址：Load cause=5、Store cause=7；tval=原 EA。预检失败不发数据请求。
- 桥返回 error 时仍处理为 Load 5/Store 7。失败 Load 不写 ARF；失败 Store 不改变 RAM；不产生正常退休/假 Trap。
- fault kind 扩展为 3 位：0 fetch、1 illegal、2 unsupported、3 control misalign、4 load misalign、5 load access、6 store misalign、7 store access。
- 原 P1-C 以 LW 作为 unsupported 的用例已替换为合法 CSR 指令；CSR/系统仍未实现，数据访问不再冒充未实现指令。
- 数据 fault 首次观察后继续 16 个实际边沿，metadata/Token 保持、ARF 独立预期不变、无 commit/Trap/RAM 写；保护区 RAM 逐字节不变。

## 2 验证结果（V01—V06）

总入口：`make check-p1-d`，在被测试 Commit `b42794c` 上退出 0，输出 `P1-D_CHECK_ALL_PASS`。

### V01 指令/内存语义

- 定向 ELF 覆盖 8 条 Load/Store、四 byte lane、两 half lane、word、0x7f/0x80/0xff/0x8000 扩展边界、负偏移、地址加法回绕到 RAM base、RAM 首区、x0 load/store、rd=rs1、RAW/WAW、Store 后 Load、部分写保护相邻字节。
- 数据区 `0x80018000` 初始化并最终回读；DUT Load 回读与独立初始写/Spike 参考一致。
- 定向退休 160 条，data_req=63/data_resp=63，RAM writes=31。

### V02 仲裁/协议

- `arbiter_tb`：双客户端公平选择、请求锁定/最终握手稳定、owner 响应路由、非 owner 不接收、响应背压、reset 清 owner。
- 集成 data_req==data_resp；每种子至少 64 Load 与 64 Store（随机 data_req=264、writes=156、loads=108）。
- 响应延迟、`accept_stall_i`、`req_gate_i`/`lsu_gate_i` 请求停顿及 held payload 检查通过；错路 Load/Store 不产生数据请求/写。

### V03 故障/停止

数据 fault 证据：

| 用例 | kind | cause | tval | commits |
| --- | ---: | ---: | --- | ---: |
| load_misalign | 4 | 4 | 0x2 | 0 |
| load_x0_misalign | 4 | 4 | 0x2 | 0 |
| load_access | 5 | 5 | 0x0 | 0 |
| store_misalign | 6 | 6 | 0x80018002 | 2 |
| store_access | 7 | 7 | 0x10000000 | 2 |
| bridge_load_error | 5 | 5 | 0x80018000 | 1 |

每例首次 fault 后 16 边沿 metadata/Token 保持、ARF 独立镜像不变、无 commit/Trap/写；保护区 RAM 不变。

### V04 真实退休/参考

| 程序 | 退休数 | data_req/writes | 结果 |
| --- | ---: | ---: | --- |
| directed | 160 | 63/31 | PASS |
| random 0x1a2b3c4d | 2205 | 264/156 | PASS |
| random 0x5e6f7a8b | 2202 | 264/156 | PASS |
| random 0x9c0d1e2f | 2123 | 264/156 | PASS |

- Spike 使用同 ELF、`--pc=0x80000000`、`--instructions=5000`、`--log-commits`；终点自循环后缀验证后裁剪。
- 逐条比较 PC/instr/priv/rd_we/rd/数据、DUT next_pc（参考后继 PC 推导）及 mem_valid/we/va/pa/size/mask/wdata/rdata；最终 32 ARF 与 256B 数据区（数据区 SHA 对应 dump）一致。
- Load x0 的 mem_rdata 参考不可直接观察，报告/DUT 记录保留，差分器不伪造参考值；DUT 访问与退休仍检查。

### V05 检测/总入口

- `p1d_diff` 七类注入 `pc/instr/rd/next_pc/missing/duplicate/token` 均经干净基线后按指定字段/位置检出；`pc_extra` 返回 EXTRA_ERRORS，不被计为 PC 成功。
- 格式/尾记录/priv/next_pc/seq/类型变体拒绝；正常对照 PASS。
- `P1_D_INJECT=pc make check-p1-d`：定向正常步骤失败，summary FAIL，退出非零。
- `P1_D_PROBE_EXTRA=1 make check-p1-d`：原预期 PC 检出探针被 pc_extra 额外错误影响，rc3 不再满足 rc1/DETECTED，步骤和总入口 FAIL。
- 主机看门狗/kill-after、周期/退休/事务预算、真实构建退出码传播保留。

### V06 回归/追溯

- 实现先提交 `b42794c`；正常和注入运行均在同一 Commit。
- `P1_C_EVIDENCE=verification/evidence/P1-D/regression/P1-C make check-p1-c` 退出 0，`P1-C_CHECK_ALL_PASS`；内部 P1-B/P1-A/P0 回归通过。
- 证据 1328 个文件（1327 个清单条目 + `SHA256SUMS`）；`sha256sum -c` 通过。

## 3 文件清单

| 路径 | 说明 |
| --- | --- |
| `rtl/core/p1_integer_core.sv` | Load/Store、LSU 状态、数据退休/fault |
| `rtl/core/p1_bus_arbiter.sv` | fetch/data 单事务共享仲裁 |
| `rtl/core/p1_integer_top.sv` | 前端+仲裁+RAM/桥+后端集成 |
| `rtl/p1_d.f` | P1-D RTL 文件清单 |
| `software/p1d/directed.S` | 定向 Load/Store 程序 |
| `scripts/gen_p1d_random.py` | 三固定种子随机整数+访存程序 |
| `verification/p1d/tb/tb_arbiter.cpp` | 仲裁协议 TB |
| `verification/p1d/tb/tb_data_faults.cpp` | 数据故障/停止/RAM 保护 |
| `scripts/p1d_diff.py` | 含 mem 字段和 RAM dump 的 Spike 差分 |
| `scripts/check_p1_d.sh` | P1-D 总入口 |
| `docs/architecture/p1-d-modules.md` | 模块/仲裁/故障/验证说明 |

## 4 V01—V06 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| V01 | 通过 | 8 条/Lane/扩展/偏移/回绕/x0/重叠/部分写 |
| V02 | 通过 | 公平、稳定、路由、背压、错路、守恒、随机 Load/Store |
| V03 | 通过 | 4/5/6/7、x0、桥错误、16 边沿、RAM 保护 |
| V04 | 通过 | 定向+三种子、逐条退休+mem+ARF+RAM dump |
| V05 | 通过 | 负向/格式/实际入口失败/预算/看门狗 |
| V06 | 通过 | 实现先提交、同 Commit exit 0、P1-C/P1-B/P1-A/P0、哈希 |

## 5 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| CSR 状态、Trap/MRET/WFI/Fence、完整异常处理 | 未实现（P1-E/F） |
| UART/test_result/MMIO 外设、启动/终止协议 | 未实现（P1-F/G）；当前 MMIO/保留地址数据访问为 access fault |
| M/A/C/F、FPU | 未实现 |
| Cache/MMU/PTW、OoO/ROB/IQ/BPU | 未实现 |
| 完整 DiffTest、SoC 替换、FPGA | 未实现 |

37 条正常子集与 RAM 访存差分通过不等于完整 RV32I/P1 门禁通过；数据故障停止不等于 Trap 已实现。未合入 `main`，未进入 P1-E/F。

## 6 交付摘要

```text
任务：P1-D
任务基线 Commit：8c292473e8e85505b8571684d2d3d25d606d6c3d
分支：codex/p1-d-load-store
被测试实现 Commit：b42794cbe2e704251b277fc65a3a0f6c73ad6622
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-D-report.md
证据目录：verification/evidence/P1-D/
证据数量：1328 项（含 SHA256SUMS）
SHA256SUMS：d5d81b0c1b44e1ecd8cce37539e7e4d769360d9884ed16057727904952012b9f
V01—V06：全部通过
```
