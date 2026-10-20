# P1-D-R1 仲裁身份与验证修复报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-D-R1 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `251a510bfb20b8f8571ff270e9104ca7fe7834c6` |
| 代码变更前起点 | `9307a5428131888951931e4b305da9e780dadcfe` |
| 被测试实现 Commit | `8b4017ccf774b9776c21518d8d788181c846afbf` |
| 分支 | `codex/p1-d-load-store` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-D-R1-report.md` |
| 证据目录 | `verification/evidence/P1-D-R1/`（2242 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `8caa0002d0eb0974a6d06132e6cc19356d22412d5d25455c29e7ad5c6a1181ff` |

本轮只修复 F01—F04，保留已认可的 8 条 Load/Store、Spike 差分和恢复成果。未实现 CSR/Trap、MMIO 外设、Cache/MMU、OoO、完整 DiffTest、SoC 替换或 FPGA；未合入 `main`，未进入 P1-E/F。

## 1 F01：真实握手、归属与迟到响应

- `p1_bus_arbiter` 现在只在真实 `req.valid && ready` 握手时分配 owner；未接受请求被 redirect 取消不产生虚假 owner。
- owner 非空时 `bus_req_o.valid=0`，两客户端 ready=0，禁止第二笔总线接受。
- 接受时保存实际 `req_id`/`gen`；只有 owner 客户端、且 ID/gen 匹配的响应才路由并释放 owner。错误 ID/代次响应可被排空/诊断，但不会释放 owner，后续正确响应仍回到原拥有者。
- 无 owner 的 orphan 响应可排空；响应背压按 owner client ready 保持。
- `tb_arbiter` 新增：错误 ID 后 owner 保持、正确响应后有界完成；锁定 fetch 被取消无虚假 owner；owner 忙时后继请求不被接受；响应背压、公平轮转与复位。
- 旧 b42794c arbiter 用新 TB 复现失败：`wrong id keeps owner`、`lsu after canceled lock` 等 6 项 `P1D_ARB_FAIL`；证据 `old-repro-r1/run.log`，修复后同场景 PASS。

## 2 F02：统一监视与守恒

- 集成 runner 去除复位释放前未监视的真实边沿，显式初始化全部输入；响应完成按 valid&&ready 计数。
- 终点处增加有界排空：gate fetch/data，不产生新接受，等待已接受 fetch/data 响应完成；保留真实接受/完成事件，不用常数修补。
- 新增逐拍 held LSU 请求完整 payload 稳定性检查（is_store/va/pa/size/mask/wdata/id/gen）；显式驱动 `lsu_gate_i` 及 accept stall。
- 实际计数：
  - directed：data_req/data_resp=69/69，fetch_req/resp=192/192，RAM writes=34。
  - random0/1/2：data_req/resp=264/264，fetch_req/resp=2649/2649、2551/2551、2567/2567；RAM writes=156；Loads=108、Stores=156。
- 仲裁 TB 覆盖无主/错身份、owner 忙、锁定取消、响应背压跨边沿；p1d_diff 格式/尾记录/seq/priv/类型、PC/指令/rd/next_pc/missing/duplicate/token/ram 注入均保留。
- 旧正常入口的 fetch 计数不守恒已由排空修复，不声称旧 RTL 实际重复响应。

## 3 F03：fault 初值与边界

- `tb_data_faults` 首次 fault 在再次 edge 前检查：complete PC/instr/cause/tval、Token idx/gen、从真实已接受 Fetch 请求记录得到的 fetch_gen、完整 ARF、无 commit/Trap/RAM 写。
- 提交索引先做范围检查；前缀数量与 Token 独立核对；后续 16 边沿核对全部字段、ARF 和 RAM 保护区，Token idx 也保持。
- 新增边界：
  - RAM 最后合法 byte/half/word（0x8001ffff/0x8001fffe/0x8001fffc）实际 Store/Load。
  - 首个非法 byte/half/word（0x80020000）Load/Store access fault。
  - 真实 32 位 EA 回绕：0xfffffffc + 4 → 0，access fault，tval=0。
  - MMIO load 0x10000000 access fault；x0 misalign、桥响应错误保留。
- 定向 256B 比较改为 64B 已知初始化区；随机三程序仍初始化完整 256B。DUT RAM 通过生产 RAM 内部只读观察/Spike Store 日志重建，不用 DUT 结果自填期望。
- 新增同一监视路径反例：首次 fault 注入错误事件（commit/写）被拒绝；保持期 ARF 变化被拒绝；正常关闭注入通过。

## 4 F04：真实失败传播与有界执行

- 删除“INJECT 非空即 bad”；总入口只传播原正常步骤/原预期检出探针的实际检查结果。
- `nm` 终点发现使用已受保护的保存输出；随机生成、变体生成、Spike、DUT、contract、diff、故障/仲裁运行均在主机 watchdog + kill-after 下执行并检查真实退出码。
- 新增 `P1_D_HANG=end` 受控终点发现挂起：内部 3s timeout 记录 watchdog 失败，外层宽限不触发；实际总入口有界 FAIL。
- 实际入口失败证据：
  - `P1_D_INJECT=pc`：原定向 diff 失败，summary FAIL。
  - `P1_D_PROBE_EXTRA=1`：原 `diff-inject-pc` 得到 rc3/EXTRA_ERRORS，不满足 rc1/DETECTED，步骤 FAIL。
  - `P1_D_INJECT=ram`：RAM monitor 注入一次字节错误，原定向 diff 失败，summary FAIL。
  - `P1_D_HANG=end`：构建完成后终点发现内部 watchdog 触发，summary FAIL，外层未超时。

## 5 正常回归与统计

`make check-p1-d` 在被测试 Commit `8b4017c` 上退出 0，`P1-D_CHECK_ALL_PASS`。

| 程序 | 退休数 | data_req/writes | 结果 |
| --- | ---: | ---: | --- |
| directed | 174 | 69/34 | PASS |
| random 0x1a2b3c4d | 2205 | 264/156 | PASS |
| random 0x5e6f7a8b | 2202 | 264/156 | PASS |
| random 0x9c0d1e2f | 2123 | 264/156 | PASS |

- 三随机种子各 >1000 退休、Load 108/Store 156（均 >64）；Spike 逐条 PC/instr/priv/rd/next_pc/mem 字段、最终 ARF 与已知 256B 数据区通过。
- `P1_C_EVIDENCE=verification/evidence/P1-D-R1/regression/P1-C make check-p1-c` 退出 0，`P1-C_CHECK_ALL_PASS`；P1-B/P1-A/P0 回归通过。
- 仲裁、故障、旧版复现、格式/差分负向、实际入口失败日志均在 `verification/evidence/P1-D-R1/`；历史 P1-D 证据未改写。

## 6 文件与追溯

| 路径 | 说明 |
| --- | --- |
| `rtl/core/p1_bus_arbiter.sv` | 真实握手 owner、身份匹配、owner 忙禁止第二笔 |
| `rtl/core/p1_integer_top.sv` | 请求身份/响应观察、故障注入测试口 |
| `verification/p1d/tb/tb_arbiter.cpp` | 错身份/取消锁/背压/公平负向 |
| `verification/p1c/tb/tb_integer.cpp` | 统一边沿、排空、完整请求稳定、内存统计 |
| `verification/p1d/tb/tb_data_faults.cpp` | 首拍/16 边沿、RAM 边界、EA 回绕、监视负向 |
| `scripts/check_p1_d.sh` | R1 总入口、看门狗、ram/故障负向 |
| `scripts/repro_p1_d_r1.sh` | b42794c arbiter 旧版复现 |

## 7 F01—F04 / V01—V05 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| F01 | 关闭 | 真实握手 owner、错误响应不释放、迟到正确响应 |
| F02 | 关闭 | 统一计数/排空/守恒、完整稳定性、仲裁组合负向 |
| F03 | 关闭 | 首拍/16 边沿、身份/fetch_gen、RAM/MMIO/回绕边界、监视负向 |
| F04 | 关闭 | 真实失败传播、全路径 watchdog、ram/probe/正常注入失败 |
| V01 | 通过 | 仲裁身份、取消、迟到、背压 |
| V02 | 通过 | 逐笔计数、数据事务、held payload、负向 |
| V03 | 通过 | fault 初值/保持、边界、RAM 保护 |
| V04 | 通过 | 实际入口失败、内部有界 watchdog |
| V05 | 通过 | 同 Commit 正常 exit 0、Spike/ARF/RAM、P1-C/P1-B/P1-A/P0、哈希 |

## 8 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| CSR/Trap/MRET/WFI/Fence、完整异常处理 | 未实现（P1-E/F） |
| MMIO 外设、启动/终止协议 | 未实现（P1-F/G） |
| M/A/C/F、FPU、Cache/MMU/PTW、OoO/ROB/BPU | 未实现 |
| 完整 DiffTest、SoC 替换、FPGA | 未实现 |

37 条正常子集与 RAM 访存差分通过不等于完整 RV32I/P1 门禁通过；数据故障停止不等于 Trap 已实现。未合入 `main`，未进入 P1-E/F。

## 9 交付摘要

```text
任务：P1-D-R1
代码变更前起点 Commit：9307a5428131888951931e4b305da9e780dadcfe
分支：codex/p1-d-load-store
被测试实现 Commit：8b4017ccf774b9776c21518d8d788181c846afbf
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-D-R1-report.md
证据目录：verification/evidence/P1-D-R1/
证据数量：2242 项（含 SHA256SUMS）
SHA256SUMS：8caa0002d0eb0974a6d06132e6cc19356d22412d5d25455c29e7ad5c6a1181ff
F01—F04 / V01—V05：全部通过
```
