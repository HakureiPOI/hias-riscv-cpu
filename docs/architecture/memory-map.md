# 地址图、PMA 与参考模型配置（P0-02 冻结基线）

状态：**规格已冻结，见 [管理验收](../progress/P0-02-R2-review.md)。** 单一事实来源为 `config/platform.json`；生成文件与检查器见第 6 节。P1-A 已实现 RAM 地址/合法性检查和桥，P1-C 已接通真实取指/整数执行，CPU 数据访问在 P1-D 待实现。P1 栏表示整个 P1 的目标，实际 UART/test_result 在 P1-F 实现；当前未实现 MMIO 不能假成功。

## 1 位宽与地址空间

| 项 | 值 | 说明 |
| --- | --- | --- |
| XLEN | 32 | 整数寄存器与 VA |
| VA | 32 位 | 无 C 时指令 4 字节对齐 |
| PA | 34 位 | Sv32 翻译结果；P1 Bare 下 VA 直接作为 PA 低 32 位，高 2 位为 0 |
| 物理地址空间 | `0x0_0000_0000`–`0x3_FFFF_FFFF` | 超出 34 位在接口上不可能出现；高位非零且不在 PMA 内的地址产生访问故障 |

P1 为 Bare：VA 零扩展为 34 位 PA。P5 引入 Sv32 后，PPN 拼接产生 34 位 PA；任何超出 PMA 的 PA 产生 access fault，禁止静默截断或折回低地址。

## 2 RAM

| 项 | 值 |
| --- | --- |
| 基址 | `0x8000_0000` |
| 大小 | `0x0002_0000`（128 KiB） |
| 末地址（不含） | `0x8002_0000` |
| 对齐 | 4 KiB |
| 属性 | Cacheable，可读/写/执行 |
| 复位向量 | `0x8000_0000` |

P1 与最终 DUT 使用同一 128 KiB 物理 RAM 配置。参考模型 Spike 必须使用 `-m0x80000000:0x20000`，不能使用 `-m128`（128 MiB）。P0-01 的 `-m128` 仅作历史冒烟，已由本轮替换。

## 3 软件保留布局

由 `config/platform.json` 的 `software` 字段计算，生成到 `software/generated/platform.h`/`.ld`：

| 区域 | 地址范围 | 大小 | 说明 |
| --- | --- | --- | --- |
| 程序/数据/`.bss`/tohost/fromhost | `0x8000_0000`–`0x8001_9F00` | 由链接决定 | 必须在 `PLATFORM_PROGRAM_LIMIT` 之前结束 |
| 签名保留 | `0x8001_9F00`–`0x8001_A000` | 256 B | `begin_signature`/`end_signature` 类用途 |
| Sv32 页表保留 | `0x8001_A000`–`0x8001_E000` | **16 KiB（4 个完整 4 KiB 页）** | 一个根页 + 三个叶页的演示预算；P1 不使用但保留 |
| 对齐空隙 | `0x8001_E000`–`0x8001_EFF0` | 0xFF0 B | 页表终点到栈底之间的空隙，不分配 |
| 栈 | `0x8001_EFF0`–`0x8001_FFF0` | 4 KiB | 向下增长 |
| 栈顶保护 | `0x8001_FFF0`–`0x8002_0000` | 16 B | 不分配 |

页表区必须严格等于 `[0x8001a000,0x8001e000)`、大小 `0x4000`；生成器与链接脚本、ELF 符号逐一校验。不得把栈底 `0x8001eff0` 当作页表终点。

链接脚本对这些区域做 `ASSERT`，重叠或越界会使链接失败。

## 4 MMIO

所有 MMIO 为不可缓存、有副作用区域；读和写只能在提交头执行，错误路径不得访问。未实现区域不得默认视为有效 MMIO。

| 名称 | 基址 | 大小 | P1 | 最终 | 访问 | 契约 |
| --- | --- | --- | --- | --- | --- | --- |
| `clint` | `0x0200_0000` | `0xC000` | 预留 | 定时器/软件中断 | RW | Spike 参考地址；P1 DUT 不解码 |
| `plic` | `0x0C00_0000` | `0x400000` | 预留 | 外部中断 | RW | Spike 参考地址；P1 DUT 不解码 |
| `uart0` | `0x1000_0000` | `0x1000` | 实现 | 实现 | RW | DATA/STATUS 寄存器见下表；P1 仅字节访问 |
| `test_result` | `0x1000_1000` | `0x1000` | 实现 | 实现 | RW | 32 位 RESULT：读返回最近写入值，无读副作用，复位 0；仅对齐字访问 |
| `fpu_mmio` | `0x1000_2000` | `0x1000` | 预留 | FP 演示 | RW | 独立 FP32 MMIO 演示预留；未实现 |

MMIO 寄存器契约（P1）：

| 区域 | 偏移 | 名称 | 宽度 | 方向 | 复位 | 规则 |
| --- | --- | --- | --- | --- | --- | --- |
| uart0 | `0x00` | DATA | 8 | RW | 0 | 写 THR、读 RBR；只允许字节访问 |
| uart0 | `0x04` | STATUS | 8 | RO | `0x01` | bit0 tx_ready，bit1 rx_valid；写忽略 |
| test_result | `0x00` | RESULT | 32 | RW | 0 | 对齐字读写；读返回最近写入值，无读副作用 |

访问规则：

- UART：仅字节访问 DATA/STATUS；半字/字或未定义偏移产生 access fault（P1 简化）。
- test_result：仅 32 位对齐字访问；字节/半字/未对齐访问产生 access fault；读无副作用。
- 未列出的地址：按 PMA 产生 access fault；不得返回 0 伪装成功。
- 写副作用在提交头发生；不可取消事务（Store/MMIO）先完成再响应中断。
- MMIO 地址不与 RAM 或彼此重叠；检查器强制 4 KiB 对齐、不重叠、寄存器自然对齐与不重叠。

## 5 参考模型（Spike）配置

| 项 | 值 |
| --- | --- |
| 模型 | Spike 1.1.1-dev，Commit `5a760667bf0d0ab893173b9eeff9c109c8d7dd9a` |
| ISA | `rv32i`（P1）；最终 `rv32im_zicsr_zifencei` + `svade`（P5 冒烟） |
| 特权 | P1 `m`；最终 `msu` |
| 内存 | `-m0x80000000:0x20000` |
| DTB | `--disable-dtb` |
| 启动 | Spike 引导 ROM 位于 `0x1000`，不写入 RAM；`tohost/fromhost` 由 ELF 符号定位 |
| 退出 | HTIF：`tohost` 写 `(code << 1) | 1`；Spike 以 0/非 0 退出 |

已实际验证（见 `verification/evidence/P0-02/logs/`）：

- `spike --isa=rv32i --priv=m --disable-dtb -m0x80000000:0x20000 <elf>` 退出 0，程序签名 `0x50415353` 写入 `0x80000120` 附近。
- `--isa=rv32im_zicsr_zifencei_svade --priv=msu` 被该 Spike 版本接受（`--dump-dts` 显示 `riscv,isa` 与 `mmu-type = "riscv,sv32"`），但不表示完整缺页软件已验证。
- 该 Spike 版本**没有**独立的 Svade 运行时开关；`svade` 作为 ISA 扩展字符串被接受，`menvcfg.ADUE` 由 `svadu` 扩展决定（`csr_init.cc`）。P5 必须在参考模型配置中显式记录该差异，并确保 DUT 与模型都选择“A/D 由软件管理”。
- `-m` 参数以字节为单位、要求 4 KiB 对齐；`0x1ffff` 会被警告并向上对齐到 4 KiB 边界，因此统一使用 `0x20000`。

## 6 单一事实来源与生成

- 配置：`config/platform.json`（含 MMIO 寄存器偏移/宽度/方向/复位）。
- 生成器/检查器：`scripts/gen_platform.py`（`--validate-only` 仅做语义校验，`--check` 另查生成物漂移）。
- 生成文件（禁止手改）：
  - `software/generated/platform.h`
  - `software/generated/platform.ld`
  - `config/platform.spike.args`
  - `config/platform.generated.json`
- 重新生成：`python3 scripts/gen_platform.py`
- 一致性检查：`python3 scripts/gen_platform.py --check`（比较生成内容，拒绝漂移，漂移返回 3）
- 语义校验：`python3 scripts/gen_platform.py --validate-only`（非法配置返回 2）
- 链接/ELF/Spike 一致性：`python3 scripts/check_platform.py`
- 负向配置：`python3 scripts/check_platform.py --negative`（语义错误必须 exit 2 + 指定原因；生成物漂移单独用例 exit 3）

`software/smoke/link.ld` 通过 `INCLUDE software/generated/platform.ld` 使用同一组常量；`scripts/run_ref_smoke.sh` 从 `config/platform.spike.args` 读取 Spike 参数。软件常量、链接区域与参考内存因此同源。

## 7 HTIF 与 DUT 边界

- `tohost`/`fromhost` 是 Spike HTIF 宿主协议，不是 FPGA 硬件协议。
- DUT P1 不实现 HTIF；板上使用 UART + test_result 寄存器停机与签名。
- Spike 引导 ROM（`0x1000`）只存在于参考模型；DUT 从 `0x8000_0000` 直接复位，不仿造引导 ROM。
- 参考启动阶段通过 `--pc`/ELF 入口与 `--disable-dtb` 对齐；不得把参考引导代码当作 DUT 必须实现的地址。

## 8 待审问题

1. P1 是否实现 `clint` 的最小 MTIP/MSIP，或完全留给 P5；当前为预留。
2. UART 半字/字访问是否按 access fault 处理，需与课程板卡 UART 对齐。
3. P5 的 Svade 在 Spike 中的表达方式（ISA 字符串 `svade` vs `menvcfg.ADUE`）需要与参考模型适配任务一起冻结。
4. FPGA 实际 RAM/BRAM 容量与 128 KiB 基线的关系待板卡确认。
