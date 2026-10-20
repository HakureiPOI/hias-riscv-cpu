# P1-B-R2 验证收尾报告

| 项目 | 内容 |
| --- | --- |
| 任务编号 | P1-B-R2 |
| 执行日期/时区 | 2026-10-20，容器本地 HKT +0800 |
| 管理审查提交 | `51ecc1c765d51652648ba29bd28a7e90e8819377` |
| 原 P1-B-R1 交付 | `0dce6ed385e7062f322eede395ae65adfafcf374` |
| 实际修复基线 | `37524bdc8f894e294e5581685379d410e55d14d8`（合并管理提交后的分支顶端） |
| 分支 | `codex/p1-b-fetch-decode` |
| 被测试实现 Commit | `c14c2befd5483f9ce5b542db32912e453c789add` |
| 最终交付 Commit | 本报告与证据的提交（由交付消息给出） |
| 报告路径 | `docs/progress/P1-B-R2-report.md` |
| 证据目录 | `verification/evidence/P1-B-R2/`（817 项，含 `SHA256SUMS`） |
| 证据 SHA256SUMS | `8d7636e74558c0cf90d638341e29556d05d5919868895b04608ce1d5403b148f` |

本轮只关闭 G01—G03。已接受的 JAL、redirect、取消身份 RTL 未修改；`git diff 37524bd..c14c2be -- rtl` 为空。前端仍不执行指令、不更新 CSR、不产生真实 Trap/退休；未合入 `main`，未进入 P1-C。

## 1 G01：构建失败立即传播

- `scripts/check_p1_b.sh` 的 `build_frontend default 8` 与 `build_frontend wrap 2` 现在立即检查返回值并分别记录 `bad`，设置 `default_build_ok`/`wrap_build_ok`；失败配置不运行其可执行文件，依赖 default 二进制的负向探针也跳过并记录失败。
- 新增 `scripts/run_p1_b_build_wrap.sh`：先执行真实 Verilator 构建，完成后按 `P1_B_FORCE_BUILD_FAIL`/`P1_B_BUILD_TAG` 返回 3；构建日志写入 `binary_exists_after_failed_build: yes/no`。
- 受控证据：
  - `P1_B_EVIDENCE=verification/evidence/P1-B-R2/build-fail/default P1_B_FORCE_BUILD_FAIL=default make check-p1-b`：退出 2，`P1-B-R2_CHECK_ALL_FAIL`；构建日志 `real_rc=0`、`binary_exists_after_failed_build: yes`，`frontend-default-run.log` 不存在，汇总明确记录 build/run skipped。
  - wrap 配置同样退出 2，`frontend-wrap-run.log` 不存在，二进制已生成。
  - 正常包装关闭时完整 `make check-p1-b` 退出 0。

## 2 G02：独立 PC 与完整请求检查

- `frontend_tb_top` 新增请求观察端口：is_store、VA、PA、size、byte_mask、wdata、cacheable、priv、ID、gen；新增仅影响观察值的 `req_observe_mask_xor` 夹具输入，生产 `core_req`、桥请求和 RTL 不变。
- TB 新增独立 `next_req_pc` 模型：
  - 复位=`RESET_VECTOR`；
  - 合法 redirect 更新为目标；
  - 每个真实请求握手后按 +4 前进；
  - 未接受/已取消请求不推进；取指异常等待 redirect；内部预取和背压不改变模型规则。
- 每个请求握手检查 VA/PA 与模型一致，并检查 word 只读契约：`is_store=0`、VA=PA 零扩展、`size=MEM_WORD`、`byte_mask=0xF`、`wdata=0`、`cacheable=1`、`priv=PRIV_M(3)`。held 请求在最终握手边沿比较全部请求字段。
- 负向：
  - `+inject_pc_skip` 一次改变独立 PC 期望；请求 VA/PA 检查各报一次 `cat=pc`，退出 1，`P1-B_FRONTEND_PC_MODEL_MISMATCH_DETECTED`。
  - `+inject_req_stability` 在最末握手边沿通过观察夹具改变 byte_mask；held 载荷稳定性与契约检查拒绝，退出 1，`P1-B_FRONTEND_REQ_STABILITY_DETECTED errors=2`。
  - 正常完整流程无 PC/req 错误并退出 0。

## 3 G03：探针绑定指定错误

- TB 错误计数分为 `op_errors`、`other_errors`、`pc_errors`、`req_errors`，全局 `errors` 仍不清零。frontend 的 `op` 字段使用 `check_op`，PC 顺序使用 `check_pc`，请求契约/稳定性使用 `check_req`；其余检查计入 `other`。
- decode 与 frontend 的负向/注入标记现在只在指定 op 比较实际检出、其他错误为零、完整流程/种子完成时产生。结果码与标记：

| 探针 | 结果码 | 成功/诊断标记 |
| --- | ---: | --- |
| decode `+mismatch` | 1 | `P1-B_DECODE_NEGATIVE_OP_DETECTED op_errors=1` |
| decode `+mismatch_other` | 2 | `P1-B_DECODE_NEGATIVE_WRONG_REASON op_errors=0` |
| decode `+mismatch_extra` | 3 | `P1-B_DECODE_NEGATIVE_EXTRA_ERRORS op_errors=1 other_errors=1` |
| frontend `+mismatch` | 1 | `P1-B_FRONTEND_NEGATIVE_OP_DETECTED op_errors=1` |
| frontend `+mismatch_other` | 2 | `P1-B_FRONTEND_NEGATIVE_WRONG_REASON op_errors=0 other_errors=1` |
| frontend `+mismatch_extra` | 3 | `P1-B_FRONTEND_NEGATIVE_EXTRA_ERRORS op_errors=1 other_errors=1` |
| frontend `+inject_directed` | 1 | `P1-B_FRONTEND_INJECTED_OP_PASS op_errors=1 other_errors=0` |
| frontend `+inject_directed_other` | 2 | `P1-B_FRONTEND_INJECTED_WRONG_REASON op_errors=0 other_errors=1` |
| frontend `+inject_directed_extra` | 3 | `P1-B_FRONTEND_INJECTED_EXTRA_ERRORS op_errors=1 other_errors=1` |
| frontend `+inject_random0` | 1 | `P1-B_FRONTEND_INJECTED_OP_PASS op_errors=1 other_errors=0` |
| frontend `+inject_pc_skip` | 1 | `P1-B_FRONTEND_PC_MODEL_MISMATCH_DETECTED` |
| frontend `+inject_req_stability` | 1 | `P1-B_FRONTEND_REQ_STABILITY_DETECTED errors=2` |

- 实际总入口反例（均保存 `make.log` 与内部日志）：
  - `P1_B_INJECT=directed_other`：frontend 运行输出 `INJECTED_WRONG_REASON op_errors=0 other_errors=1`，总入口退出 2、`result: FAIL`。
  - `P1_B_INJECT=directed_extra`：输出 `INJECTED_EXTRA_ERRORS op_errors=1 other_errors=1`，总入口退出 2、`result: FAIL`。
  - 两类均未产生 `INJECTED_OP_PASS`，未被计为指定 op 检出成功。
- 原有 `+mismatch`、定向/首种子 op 注入完整流程、124/137 超时探针保留并分别绑定类别。

## 4 完整正常回归与阶段统计

正常默认 `GEN_W=8`：`P1-B_FRONTEND_PASS accepted=1405 requests=1777 responses=1780 matched=1777 orphan=3 decode=1405 fetch_exc=1 redirects=420 cycles=10182`。
强制 `GEN_W=2`：`P1-B_FRONTEND_PASS accepted=1196 requests=1571 responses=1577 matched=1571 orphan=6 decode=1196 fetch_exc=1 redirects=423 cycles=9460`。

默认阶段统计（`logs/frontend-default-run.log`）：

| 阶段 | accepted | requests | responses | matched | orphan | redirects | decode | fetch_exc | errors |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| basic-image | 93 | 95 | 95 | 95 | 0 | 2 | 93 | 0 | 0 |
| directed-backpressure | 2 | 2 | 2 | 2 | 0 | 1 | 2 | 0 | 0 |
| directed-held-redirect-accept | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-request-stall | 2 | 2 | 2 | 2 | 0 | 2 | 2 | 0 | 0 |
| directed-response-redirect | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-same-cycle-redirect | 2 | 3 | 3 | 3 | 0 | 2 | 2 | 0 | 0 |
| directed-fault-id-gen | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fault-id | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fault-gen | 2 | 2 | 3 | 2 | 1 | 1 | 2 | 0 | 0 |
| directed-fetch-error | 3 | 3 | 3 | 3 | 0 | 2 | 3 | 1 | 0 |
| directed-illegal-target-pending | 3 | 4 | 4 | 4 | 0 | 2 | 3 | 0 | 0 |
| directed-continuous-redirect | 2 | 2 | 2 | 2 | 0 | 3 | 2 | 0 | 0 |
| directed-wrap | 265 | 265 | 265 | 265 | 0 | 0 | 265 | 0 | 0 |
| random-0 | 341 | 471 | 471 | 471 | 0 | 136 | 341 | 0 | 0 |
| random-1 | 341 | 466 | 466 | 466 | 0 | 142 | 341 | 0 | 0 |
| random-2 | 341 | 452 | 452 | 452 | 0 | 121 | 341 | 0 | 0 |

强制配置额外阶段：`directed-cancel-wrong-wrap-id-gen/id/gen` 各 `5/6/7/6/1/1/5/0/0`（accepted/requests/responses/matched/orphan/redirects/decode/fetch_exc/errors），`directed-wrap` 为 `41/41/41/41/0/0/41/0/0`。三个固定种子分别完成 340 次随机接受，合计 1020；各阶段 drain 额外消费的 held 结果计入 accepted，与 R1 说明一致。

## 5 验证结果（V01—V04）

总入口：`make check-p1-b`，在被测试实现 Commit `c14c2befd5483f9ce5b542db32912e453c789add` 上退出 0，输出 `P1-B-R2_CHECK_ALL_PASS`；`logs/summary.log` 记录同一 `git_head`。

- V01/G01：default/wrap 构建返回值均被检查；正常构建通过；两个受控包装均在真实二进制存在时使构建步骤、运行抑制与总入口非零。lint、JAL 锚点、92 项译码保留通过。
- V02/G02：独立 PC 模型、完整请求字段契约与 held 稳定性正常通过；`+inject_pc_skip`、`+inject_req_stability` 定向负向分别由 `pc`/`req` 类别检出；默认/强制配置和三种子统计通过。
- V03/G03：decode/frontend 的 op/other/extra 三类结果可区分；正常对照通过；wrong-reason 与 extra 实际总入口均 FAIL；旧版 F01/F02/F03 复现仍通过；124/137 探针独立保留。
- V04：实现先提交 `c14c2be`；全套正常检查与所有受控反例均在同一 Commit 上运行；`P1_A_EVIDENCE=verification/evidence/P1-B-R2/regression/P1-A make check-p1-a` 退出 0，`P1-A_CHECK_ALL_PASS`，嵌套 `P0-02_CHECK_ALL_PASS`。证据 817 个文件（816 个日志/源码/数据 + `SHA256SUMS`），`sha256sum -c` 通过。

## 6 文件清单

| 路径 | 说明 |
| --- | --- |
| `scripts/check_p1_b.sh` | R2 总入口；构建返回值检查、请求/PC 负向、op/other/extra 分类 |
| `scripts/run_p1_b_build_wrap.sh` | 真实构建后可控返回 3 的 G01 包装 |
| `verification/p1b/tb/frontend_tb_top.sv` | 完整 mem_req 观察端口与 byte_mask 观察夹具 |
| `verification/p1b/tb/tb_frontend.cpp` | 独立 PC 模型、完整请求稳定性、分类错误与负向 |
| `verification/p1b/tb/tb_decode.cpp` | op/other/extra 分类负向 |
| `docs/architecture/p1-b-modules.md` | G01—G03 当前验证说明 |
| `verification/evidence/P1-B-R2/` | 正常、构建失败、探针失败、旧版复现与 P1-A/P0 证据 |

## 7 G01—G03 / V01—V04 状态

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| G01 | 关闭 | default/wrap 构建失败均立即传播、跳过运行，真实二进制存在时总入口仍 FAIL |
| G02 | 关闭 | 独立 PC 模型、完整请求载荷/最终握手稳定性、PC 与 byte_mask 负向 |
| G03 | 关闭 | op/other/extra 分类，成功标记绑定指定 op 且无额外错误；wrong/extra 总入口 FAIL |
| V01 | 通过 | lint、JAL 锚点、92 项译码、构建失败传播 |
| V02 | 通过 | 独立 PC/请求契约/稳定性、默认与强制回绕、三种子统计 |
| V03 | 通过 | 分类负向、正常对照、实际失败入口、旧版复现、124/137 |
| V04 | 通过 | 同 Commit 正常 exit 0、P1-A/P0 回归、证据哈希 |

## 8 未完成项与边界

| 项目 | 状态 |
| --- | --- |
| 指令执行、ALU、分支解析、LSU 执行 | 未实现 |
| CSR 状态更新、Trap/中断/真实退休 | 未实现；前端不产生 commit/Trap |
| ROB/IQ、BPU、Cache、MMU、FPU、DiffTest | 未实现 |
| P1-C 后端接入 | 未开始；只提供 `decoded_o`/`redirect_i` 接口 |
| SoC 顶层替换空闲骨架 | 未进行 |
| FPGA 综合/时序/上板 | 未进行 |

FENCE/FENCE.I 仍只做保守分类；CSR 地址权限/写合法化留待 P1-E。未合入 `main`，未进入 P1-C。

## 9 交付摘要

```text
任务：P1-B-R2
实际修复基线 Commit：37524bdc8f894e294e5581685379d410e55d14d8
分支：codex/p1-b-fetch-decode
被测试实现 Commit：c14c2befd5483f9ce5b542db32912e453c789add
最终交付 Commit：本报告与证据的提交（由交付消息给出）
报告路径：docs/progress/P1-B-R2-report.md
证据目录：verification/evidence/P1-B-R2/
证据数量：817 项（含 SHA256SUMS）
SHA256SUMS：8d7636e74558c0cf90d638341e29556d05d5919868895b04608ce1d5403b148f
G01—G03 / V01—V04：全部通过
```
