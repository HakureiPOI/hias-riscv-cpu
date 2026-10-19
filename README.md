# 2026 HIAS 计算机体系结构课程设计 | RISC-V CPU Design

本项目计划实现 RV32 双发射乱序处理器，完成动态分支预测、Cache、Sv32 MMU/TLB、独立 FP32 运算部件及 FPGA 验证。

P0-01 环境与验证冒烟已通过管理审查，进入 P0-02 规格与接口基线阶段。当前仅有验证夹具和参考执行，尚无已验收的自主 CPU RTL；设计参数和时间表不代表功能已经实现。

## 项目文档

- [项目设计书](docs/项目设计书.md)：课程要求映射、架构方案、接口约定、验证门禁、里程碑与风险处理。
- [技术调研记录](docs/research/技术调研-2026-10-19.md)：官方规范、开源参考、选型依据及调研边界。
- [协作流程](docs/协作流程.md)：Windows 管理审查、Ubuntu 24 容器内 opencode 实施，用户手动转交。
- [当前实施任务 P0-02](docs/tasks/P0-02-规格与接口基线.md)：ISA/CSR、平台配置、共享类型、模块接口与退休/Trap 契约。
- [P0-01-R1 管理验收](docs/progress/P0-01-R1-review.md)：三项问题关闭，允许合入；93 项证据哈希及版本对应已核对。
- [P0-01 首轮审查](docs/progress/P0-01-review.md)与[修复任务](docs/tasks/P0-01-R1-验证入口修复.md)：保留首轮问题与修复要求。
- [原任务 P0-01](docs/tasks/P0-01-环境与验证冒烟.md)：环境、RTL 自检、RV32 软件与参考执行的原始范围。
- [验证入口](docs/verification.md)：实际执行过的 `make` 入口、夹具、参考执行与证据位置。
- [ISA 支持表](docs/architecture/isa-support.md) · [CSR 支持表](docs/architecture/csr-support.md) · [地址图](docs/architecture/memory-map.md) · [接口](docs/interfaces.md) · [退休契约](docs/architecture/retire-contract.md) · [验证计划](docs/verification-plan.md)
- [P0-01 实施报告](docs/progress/P0-01-report.md)：首轮真实命令、退出码、证据与未完成项。
- [P0-01-R1 实施报告](docs/progress/P0-01-R1-report.md)：修复后的正常与故障注入结果。
- [课程实验要求](docs/course/实验要求.md)：依据课程原始文件整理，包含待澄清事项。
- [原始实验指导书](docs/course/体系结构实验指南-2025秋季.docx)与[课程考核指南](docs/course/课程考核指南.docx)。
- [初步计划书存档](docs/archive/初步计划书-2026-10-19.md)：用户初稿，供追溯；后续实施以项目设计书为准。

内部交付目标为 **2026 年 12 月 31 日**。课程原文暂定二月初考核，实际验收和提交时间以教师、助教通知为准。
