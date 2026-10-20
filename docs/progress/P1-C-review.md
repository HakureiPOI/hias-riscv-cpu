# P1-C 管理审查

审查日期：2026-10-20（Asia/Shanghai）。结论：**认可本轮已交付真实整数执行、ARF 和单项提交/退休链路，但 V02—V04 的验证门禁尚未闭环；暂不验收、不合入 main、不进入 P1-D/E。** 按 [P1-C-R1 任务](../tasks/P1-C-R1-差分与边界验证修复.md)继续原分支，重点修复差分和验证，不重做整数后端。

## 1 版本、证据与边界

| 项目 | 核对结果 |
| --- | --- |
| 任务基线 | `9156a0b5edc83995521653ce8508b7d43c3fd92a` |
| 被测试实现 | `7643d36c7b4cd590e7b62226f08931b736d9ab7d` |
| 最终交付 | `e73c8641a7a27ef9822fc8ab6ddbb12a43f76ecd`，分支 `codex/p1-c-integer-execute` |
| 报告 | 交付分支 `docs/progress/P1-C-report.md` |
| 证据 | `verification/evidence/P1-C/`；518 个清单条目逐个重算一致，无重复/遗漏，连同清单共 519 个文件 |
| 清单 SHA-256 | `2a70e44f9c49a4f9d4a3b27e22d2bc4f7010b89fc9a29e099d5f315808ac0e03` |
| 测试后差异 | 仅新增报告和证据，没有功能变化 |
| 历史保护 | 未改写已验收各轮证据 |

Windows 管理侧读取 Git 对象、RTL、TB、软件/差分脚本、原始日志并重算哈希；未执行提交的程序、RTL、Spike 或 Linux 总入口。以下失效路径由静态审查得出，动态旧版复现由容器 R1 完成。

## 2 可保留的成果

- p1_arf 提供真实双读/提交写；p1_alu 有 29 类整数/控制流；单项后端在接受时保存运算结果、PC/原指令、Token/next_pc，在提交边沿写 ARF 并产生正常退休，分支自身提交/链接写和年轻前端取消分开处理。这已超出前端取字夹具范围，不否认其真实执行属性。
- Token 来自后端单项分配，不由日志 seq 冒充；仅 idx=0 的 P1 临时顺序槽，不是 32 项 ROB 或 OoO。Fetch/非法/合法未实现/目标异常在 RTL 中分开停止，未伪造 CSR/Trap。
- 日志确有 directed=118、随机 1281/1281/1282 条，随机合计 3844；现有差分入口对这些输入返回 PASS，最终 DUT ARF 与参考写回日志重建状态一致。参考最终寄存器是日志重建值，不能称为额外读取的 Spike 全寄存器快照。
- 正常 make check-p1-c 为 PASS，含 P1-B/P1-A/P0；pc 注入原正常差分步骤后总入口 FAIL。Lint、ALU/ARF 单元和有限 Spike 执行可复用，不重做环境或已验收前端/RAM。

## 3 阻塞项

行号以最终交付 `e73c864` 为准，实施文件尚未合入 main。

### F01：DUT 文件被截断，priv 不是逐记录比较

`scripts/p1c_diff.py:62–82` 在读到第一条 `pc=end_pc` 后 break，忽略后续全部 DUT 行。第 151 行的 retire_count 校验针对这个截短列表，也无法发现文件尾额外记录。可构造：在正常 trace 后追加一条 schema 合法、seq/Token 正确递增的终点或其他退休记录，保留原 regs.json；格式检查仍可能通过，差分读入长度却保持原值，额外事件被丢弃。这违反“不能丢弃任何 DUT 退休”和额外记录检测要求。

第 117 行的 priv 比较是常量 `"M"` 对 Spike priv，没有读取 `d["priv"]`。将一条格式合法 DUT 记录的 priv 改为 S，仍可能通过差分。当前 TB 第 117 行确实检查 DUT 端口为 M，这是已有保护，但不能代替差分器检查其输入文件的实际字段。

参考端因有限运行留有大量 end 自循环，可以按明确协议选取参考区间；DUT 文件必须全量消费、严格拒绝额外/缺失/格式错误/终点后事件。最后一条 next_pc 当前直接使用 end_pc 参数；原始 Spike 尾部已有后继记录，应使用实际参考后继 PC 或真实终点观察，标明 derived，不把参数称为快照。最终 DUT 的 final_pc 当前是 last_commit_pc，也应说明是提交终点，避免与提交后的 next_pc 混淆。

### F02：负向注入可被无关差异冒充，七类证据实际只有六类

`scripts/p1c_diff.py:163–193` 注入前未对未修改的两侧执行完整 compare；注入后捕获任意 DiffError，就按命令行指定 kind 打印 DETECTED，不核对首差异 field/index。

例如先让基线第 0 条 PC 错误，再请求 --inject rd，脚本仍可能将首个 PC 差异报告为 RD_DETECTED；--inject token 更只检查 Token，不会先验证基线 PC/指令/写回对照。现有正常输入确实通过，不代表探针对脏基线或非目标错误的成功判据正确。

`scripts/check_p1_c.sh` 的负向循环和入口 INJECT 可选项没有 instr，证据目录也没有 diff-inject-instr.log；报告却写七类均有证据。修复后应实际纳入该类，按真实文件/结果计数。每种注入需指定预期错误字段、位置/计数关系；先验证干净基线，错误原因不符不能得到该类成功标记。

### F03：恢复覆盖计数与停止/边界证据不足

1. `verification/p1c/tb/tb_integer.cpp:94–98` 的 redirect_pending 取自 req_pending，它表示请求已接受后的响应在途，不是 valid=1、ready=0 的尚未接受请求。当前集成没有请求门控；redirect_stall 是后端 accept_stall，不能代替请求背压。redirect_dec 只取上一拍 decoded_valid，未关联未接受保持身份。因此不能用现有四个非零数字证明原任务要求的四种恢复位置。
2. `verification/p1c/tb/tb_faults.cpp:69–71` 在首次观察 fault 或足够的组合提交 valid 时就退出；jalr_clear 的末条未必推进到实际提交边沿。故障路径没有多拍保持观察，只有零前缀提交的用例检查 ARF 全零；fetch 等有已提交前缀时未检查完整 ARF 不变。未对齐 JALR 清 bit0 后 bit1 仍为 1 的集成停止用例缺失。
3. ALU 单元 `tb_alu.cpp:81–93` 将立即数限制为非负低位值；将 rng&0xfff 转为 int32_t 不会作 12 位符号扩展。真实汇编已有部分负立即数覆盖，但不能把该单元的随机组数等同于负立即数/高位边界覆盖。应补明确的 32 位符号扩展立即数与 LUI/AUIPC 高位锚点，分支方向矩阵也应给实际覆盖结果。

需要真实控制流提交触发的请求未接受、响应在途、响应同拍、译码保持场景；在相同边沿证明该分支自身正常退休/链接写保留、旧路径没有接受/退休。停止状态需跨多个实际边沿验证 fault 完整身份/元数据保持、ARF 无额外变化、无正常提交/Trap/写副作用。不得用重命名计数或直接外部 redirect 替代后端控制流恢复。

管理侧另从四个原始 Spike 提交前缀按指令编码、当前/后继 PC 统计分支路径（未运行提交代码）：BEQ taken/untaken=2/1，BNE=162/6，BLT=0/2，BGE=0/1，BLTU=1/0，BGEU=82/0。缺少 BLT/BGE taken 和 BLTU/BGEU untaken 的集成证据，报告“六种分支 taken/untaken 均通过”的表述不成立；ALU 模块覆盖不能代替这些真实控制流路径。

## 4 路线

R1 保留整数后端及其真实提交成果，关闭 F01—F03 后在新实现 Commit 完整复测。仅发现真实 RTL 缺陷时具体修复，不以检查器通过为由屏蔽问题。Load/Store、CSR/Trap、完整 DiffTest、OoO/存储系统、SoC 替换和 FPGA 继续按后续任务推进。
