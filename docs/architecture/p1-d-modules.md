# P1-D Load/Store 与共享访存仲裁

状态：P1-D 实施模块说明。复用 P1-B 前端、P1-C ARF/ALU/单条顺序提交和 P1-A RAM/桥；新增 8 条 RAM Load/Store、取指/数据共享仲裁、数据访问故障停止和真实访存退休。未实现 CSR/Trap、MMIO 外设、Cache/MMU、乱序、FPGA。

## 1 文件与端口

文件清单：`rtl/p1_d.f`。

| 文件 | 模块 | 职责 |
| --- | --- | --- |
| `rtl/core/p1_integer_core.sv` | `p1_integer_core` | 29 条旧指令 + 8 条 Load/Store；EA/PA、对齐/PMA 预检、LSU 请求/响应、访存退休和 fault |
| `rtl/core/p1_bus_arbiter.sv` | `p1_bus_arbiter` | 前端/数据共享单事务总线，公平选择、请求稳定、响应所有权路由 |
| `rtl/core/p1_integer_top.sv` | `p1_integer_top` | 前端 + 仲裁器 + RAM/桥 + 后端集成 |
| `verification/p1c/tb/integer_tb_top.sv` | TB 包装 | 提交/ARF/请求响应/内存统计观察 |
| `verification/p1d/tb/arbiter_tb_top.sv` | 仲裁 TB | 双客户端公平、背压、路由、复位 |
| `verification/p1d/tb/tb_data_faults.cpp` | 数据故障 TB | 4/5/6/7、桥错误、16 边沿停止、RAM 保护 |

## 2 Load/Store 语义

- EA=(旧 rs1+符号扩展 imm) mod 2^32；PA=EA 零扩展到 34 位。Bare，cacheable=1，M 模式。
- Load/Store 保持原 PC/instr、EA/PA、宽度、读写、标量数据、Token/fetch_gen，直到完成或停止；单条在途，提交前不接受下一条。
- byte mask 为四字节字内 lane；store wdata 为低 8/16/32 位标量，不左移；桥返回低位零扩展原始值，LSU 对 LB/LH 符号扩展，LBU/LHU 零扩展，LW 原样。
- Load 只在匹配成功响应后完成；ARF 只在提交边沿写；Load x0 仍执行访问。Store 不写 ARF，成功响应后恰好退休一次。
- Store 在单条顺序提交槽头授权下发出；接受后不可取消，普通 Flush 不撤销/重发；失败 Store 不写 RAM。
- 退休携带真实 mem_valid/we/va/pa/size/mask/wdata/rdata；普通 ALU/分支 mem_valid=0。seq 仍只由真实退休递增。

## 3 共享仲裁

- 全局最多一笔已接受事务；前端与 LSU 各一个 client。请求在 valid&&!ready 时保持完整 payload；选择锁定，不能被后来的另一 client 抢占。
- 双客户端同时等待时按 last-owner 轮转：先 LSU 后 FETCH（或反之），保证有限公平服务。
- 只有被选 client 看到 ready；bus 请求送到真实桥。响应只路由给接受事务的 owner；非 owner 看到 valid=0。响应背压时完整保持并由桥等待。
- 前端取消/迟到响应仍按原 fetch ID/gen 排空；数据请求按自己的 req_id/gen 匹配。Store 接受后不可取消。
- 复位清仲裁 owner 和桥控制状态；RAM 数据保持。普通 Flush 不作废已接受 Store/已发生写；不把 reset 当撤销写的手段。
- 测试专用请求门控只隐藏同一真实握手，不修改生产桥/RAM；集成 TB 逐拍检查 held LSU 请求 payload 稳定。

## 4 数据故障

- 预检：非对齐 LH/LHU/LW cause=4；SH/SW cause=6。对齐但 RAM 之外/MMIO/保留地址 Load cause=5、Store cause=7，tval=原 EA；预检失败不发数据请求。
- 桥对已接受请求返回 error 时仍处理为 Load 5/Store 7；失败 Load 不写 ARF，失败 Store 不改变 RAM，不产生正常退休/假 Trap。
- fault kind 扩展为 3 位：0 fetch、1 illegal、2 unsupported、3 control target misalign、4 load misalign、5 load access、6 store misalign、7 store access。fault PC/instr/Token/fetch_gen 保持；之后停止 16+ 边沿，等待 P1-E。
- 合法未实现的 CSR/系统指令仍为 kind=2；原以 LW 充当 unsupported 的 P1-C 用例已改为 CSR，数据访问不再作为“未实现指令”。

## 5 验证入口

`make check-p1-d`：

1. 生产 RTL/TB lint；仲裁单元公平/路由/稳定性/背压/复位。
2. directed ELF：8 条 Load/Store、lanes、符号/零扩展、负偏移、地址回绕、x0、RAW/WAW/源重叠、部分写保护、错路 store/load 不产生数据事务；Spike 逐退休 + RAM dump 差分。
3. 三个固定种子随机 ELF：每种子 >1000 退休、Load/Store 各 >64，混合旧 29 条；Spike 同 ELF 有限运行；DUT/Spike 逐条 PC/instr/priv/rd/next_pc、mem 字段、最终 ARF 和 256B 数据区一致。
4. 数据故障：Load/Store misalign/access、Load x0、桥响应错误；16 边沿 metadata/ARF/RAM 保护。
5. 差分/格式负向；一次正常步骤注入和一次预期检出探针额外错误注入使实际总入口 FAIL。
6. `make check-p1-c`（含 P1-B/P1-A/P0）回归；证据写入 `verification/evidence/P1-D/regression/`。
