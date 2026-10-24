# 任务清单（TASKS）

> **用法**：完成一项将 `[ ]` 改为 `[x]`，并在“变更记录”中注明日期与证据。
> **状态**：`[x]` 已完成｜`[~]` 进行中｜`[ ]` 未开始｜`[!]` 阻塞/待确认
> **最后更新**：2026-10-24

## 0. 当前结论

- 已导入板卡原理图、摄像头原理图/数据手册、FPGA 数据手册；PDF 仅本地保留，不入库。
- Git 仓库已初始化（`main` 分支），已有基线提交。
- **最小 SCCB Chip ID 工程已建立**：RTL、约束、TD 构建脚本、testbench。
- ModelSim 仿真通过：读回 `0x56/0x40`，Chip ID 匹配。
- TD 6.2.1 综合/布局布线/位流通过：WNS +12.684 ns、Hold +0.047 ns。
- **尚未在实物上烧录验证**；DVP 和 HDMI 未开始。
- 接线复核：**J2-30 = GND，J2-32 = GPIOB_27（SCL/R6）**，用户原表正确；
  2026-10-23 的“GND/SCL 接反”结论是误读，已撤回。

### 阶段状态一览

| 阶段 | 状态 | 依据/说明 |
|---|---|---|
| 系统需求与基本架构 | **已建立** | README §1–2；DVP + SCCB + HDMI 主线 |
| 硬件资料整理 | **已完成** | 板卡/摄像头/FPGA 原理图与手册已归档 |
| 原理图连接关系核对 | **已完成（摄像头 P1 丝印待确认）** | `docs/hardware/wiring.md` §6 |
| 实物连接 | **用户报告已完成** | 用户自述，未独立验证 |
| 电气检查 | **待用户完成** | `verification/board/wiring-check.md` |
| FPGA TD 环境验证 | **构建已完成，下载待验证** | TD 6.2.1 综合/布局布线/位流通过 |
| SCCB 初始化与 Chip ID | **RTL/仿真/位流完成，待上板** | `top_cam_id`、`bringup-sccb-id.md` |
| DVP 采集 | **待开发/待测试** | 未开始 |
| HDMI 显示 | **待开发/待测试** | 未开始 |
| 整体系统集成 | **待开发/待测试** | 以上均未完成 |

## A. 现状与资料审查

- [x] **A1** 扫描仓库文件，建立清单（文档、PDF、空目录）。
- [x] **A2** 检查 Git 状态：仓库已初始化，无历史提交。
- [x] **A3** 检查是否存在旧 PCLK→D4 约束/文档 —— 仓库内未发现；本文档明确 F14。
- [x] **A4** 检查重复/冲突接线文件 —— 未发现其他接线表。
- [x] **A5** 标记原厂 PDF 的入库策略：版权/再分发未确认，加入 `.gitignore`，仅本地保留。
- [x] **A6** 评估迁移风险：无旧 TD 工程，不存在绝对路径迁移问题。

## B. 目录与规范

- [x] **B1** 顶层职责划分（docs/fpga/verification/tools/third_party/archive/build）。
- [x] **B2** 目录树与命名规则。
- [x] **B3** 源码/生成物/第三方/归档边界。
- [x] **B4** 资料放置规则（README §8）。
- [x] **B5** 顶层 RTL 建立后复核目录（rtl/top、rtl/camera、sim/tb、scripts 已启用）。

## C. Git 与工程管理

- [x] **C1** 目录骨架与 `.gitkeep`。
- [x] **C2** README/TASKS/各目录说明。
- [x] **C3** `.gitignore`（build、波形、日志、`_local/`、受限 PDF）。
- [x] **C4** `git init`，建立 `main` 分支。
- [x] **C5** 首个基线提交（`chore` 骨架提交，见本次提交历史）。
- [x] **C6** 导入原理图/数据手册并登记来源（见 `docs/hardware/wiring.md` §8）。
- [x] **C7** 无旧工程迁移需求；未删除、未覆盖任何原始文件。
- [ ] **C8** 远程仓库与推送 —— 当前无 remote；推送前需用户确认。

## D. 工程级验证

- [x] **D1** TD 工程入口存在（`fpga/project/top_cam_id.al`）；项目模式顶层提示见 bringup 文档。
- [x] **D2** 综合/布局布线可复现（TD 命令行脚本，已实测）。
- [x] **D3** 时序检查通过（Setup WNS +12.684 ns，Hold WNS +0.047 ns）。
- [x] **D4** 仿真回归通过（ModelSim，Chip ID 0x5640）。
- [ ] **D5** 下载链路验证（**待上板**）。
- [~] **D6** SCCB 读取 Chip ID：RTL/仿真/位流完成，**待实物验证**。
- [ ] **D7** DVP 采集（**未开始**）。
- [ ] **D8** HDMI 显示（**未开始**）。

## H. 硬件接线阶段（2026-10-23）

### H1. 资料与图纸

- [x] **H1.1** 收集并登记板卡原理图 `HX1P35B_FT_40P_*.pdf`。
- [x] **H1.2** 收集并登记摄像头原理图 `ATK-MC5640_V1.2.pdf`。
- [x] **H1.3** 确认板卡型号/器件：PH1P35_FT V1、PH1P35MDG324。
- [x] **H1.4** 确认摄像头接口：8-bit DVP、SCCB、板载 24 MHz、P1 2×9。
- [x] **H1.5** 确认不使用 MIPI J9。

### H2. 原理图交叉核对

- [x] **H2.1** 核对 ATK P1 信号顺序（含 D1–D6 交错）。
- [x] **H2.2** 核对 J2-1~40 的 GPIO/电源/GND 分配。
- [x] **H2.3** 确认 **J2-30=GND，J2-32=GPIOB_27**；用户原表正确（此前的误读已撤回）。
- [x] **H2.4** 核对 15 个使用网络的 FPGA 球位（BANK22/BANK32）。
- [x] **H2.5** 核对 PCLK：ATK P1-15 → J2-7 → GPIOB_6 → F14（GCLKIOT3）。
- [x] **H2.6** 核对 Bank 电压：VCCIO_32/VCCIO_22 = 3.3 V → LVCMOS33。
- [x] **H2.7** 记录摄像头 P1 原理图符号编号与物理排针号的 2 位偏移。
- [~] **H2.8** 核对模组物理 Pin 1/电源脚丝印 —— 官方照片已佐证 GND/3V3 同端；
  实物 Pin 1 方向仍需用户按丝印确认。

### H3. 交付文档与约束

- [x] **H3.1** 生成 `docs/hardware/wiring.md`（含勘误与历史说明）。
- [x] **H3.2** 生成 `verification/board/wiring-check.md`（面向初学者，实测栏留空）。
- [x] **H3.3** 生成 `fpga/constraints/camera_pinmap_draft.adc`（明确“未绑定顶层”）。
- [x] **H3.4** 生成 `fpga/constraints/README.md`（语法依据、使用条件、未验证项）。
- [x] **H3.5** 更新 README 的硬件信息、入口索引、进度与风险。
- [x] **H3.6** 将原厂 PDF 加入 `.gitignore`，避免误提交。
- [x] **H3.7** 建立最小 RTL：`sccb_master.v`、`ov5640_id_reader.v`、`top_cam_id.v`。
- [x] **H3.8** 建立本测试约束 `top_cam_id.adc/.sdc` 与 TD 构建脚本。
- [x] **H3.9** 建立 testbench 并通过 ModelSim 仿真。

### H4. 实物与电气验证（待人工）

- [ ] **H4.1** 按原表复核 GND=J2-30、SCL=J2-32（**无需换线**）。
- [ ] **H4.2** 断电通断检查 18 根线（含 PCLK 只在 J2-7）。
- [ ] **H4.3** 检查 3.3 V–GND 不短路、J2-11(5 V) 未误接。
- [ ] **H4.4** 摄像头不接时测 J2-29=3.3 V、J2-30=0 V。
- [ ] **H4.5** 接摄像头后测 3.3 V、电流、温升。
- [ ] **H4.6** 确认 SCCB 上拉（补 4.7 kΩ 或验证内部上拉）。
- [ ] **H4.7** 测 RESET/PWDN 默认电平，确认无浮空风险。
- [ ] **H4.8** 填写 `wiring-check.md` 实测表并签字/日期。

### H5. 最小 RTL 与上板

- [x] **H5.1** 建立最小 TD 工程与 50MHz/复位/LED/SCCB 顶层。
- [x] **H5.2** 实现 SCCB 主机与 OV5640 Chip ID 读取（0x300A/0x300B）。
- [x] **H5.3** ModelSim 仿真通过（Chip ID 0x5640）。
- [x] **H5.4** TD 综合/布局布线/位流生成通过（WNS +12.684 ns）。
- [ ] **H5.5** 按 `verification/board/bringup-sccb-id.md` 烧录并记录 LED。
- [ ] **H5.6** 通过后实现 DVP 接收（PCLK/VSYNC/HREF/数据对齐）。
- [ ] **H5.7** 实现 HDMI 输出并显示。
- [ ] **H5.8** 需要时再评估 DDR 帧缓存。

## 待确认（阻塞项）

| # | 问题 | 影响 | 状态 |
|---|---|---|---|
| Q1 | 万用表通断/短路检查是否完成？ | 无法确认实物接线 | **待用户执行** |
| Q2 | 实物模组 P1 的 Pin 1 方向是否与 README/官方照片一致？ | 摄像头侧可能反接 | 官方照片已佐证，实物待确认 |
| Q3 | SCCB 上拉是否足够？ | 否则无法通信 | 首测已启用 FPGA 内部上拉；若 LED1 不亮则补 4.7 kΩ |
| Q4 | RESET/PWDN 是否需要外部默认电阻？ | 上电状态不确定 | 待决定 |
| Q5 | PCLK 实际频率/OV5640 输出分辨率？ | 时序约束与 HDMI 时钟 | 待定 |
| Q6 | HDMI 目标分辨率/刷新率？ | 时钟与带宽规划 | 待定 |
| Q7 | 是否使用 DDR 帧缓存？ | 架构与资源 | 待定 |
| Q8 | 板卡原理图是否允许公开再分发？ | 决定 PDF 是否入库 | 待确认 |

## 下一步动作（按顺序）

1. 按 `verification/board/wiring-check.md` 完成断电检查（GND=J2-30，SCL=J2-32）。
2. 完成独立供电与摄像头电流/温升检查。
3. 双击 `fpga/scripts/build_top_cam_id.bat`，确认生成 `build/bitstream/top_cam_id.bit`。
4. 按 `verification/board/bringup-sccb-id.md` 用 BitWizard Program SRAM，记录 LED。
5. 若 LED1 不亮，补 4.7 kΩ SCCB 上拉后再试。
6. Chip ID 通过后，再进入 DVP 采集与 HDMI 输出。

## 变更记录

| 日期 | 内容 |
|---|---|
| 2026-10-24 | 修复 SCCB master 漏采 1 周期 start 脉冲的问题（新增 `start_pending` 锁存）；testbench 改用 DIV=250 复测通过；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | SCCB 改为 **repeated START** 读时序，时钟降到 **50kHz**，ACK 高不作为失败条件；对齐本机厂商 OV5640 例程；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | SCCB 的 ACK 高不再作为失败条件（SCCB 第 9 位为 Don't Care）；LED2 改为“事务完成”指示；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | 修正最小工程的时钟/用户灯球位：**C4 为 50MHz**，**D10/E10/C6/D6 对应物理 LED1–LED4**；重建位流，WNS +12.684 ns。此前 D4/E10/C6/D6/A5 为误读。 |
| 2026-10-24 | 建立最小 SCCB Chip ID 工程、约束、TD 构建脚本与 testbench；ModelSim 仿真通过，TD 综合/布局布线/位流出图通过。 |
| 2026-10-24 | 复核高分辨率 J2 图：确认 **J2-30=GND、J2-32=GPIOB_27**，撤回 10-23 的错误对调结论；恢复用户原表。 |
| 2026-10-23 | 核对板卡/摄像头原理图；生成 wiring.md、wiring-check.md、camera_pinmap_draft.adc；当时误读 J2-30/32，已于 10-24 撤回；记录 SCCB 上拉与 P1 符号偏移风险。 |
| 2026-10-21 | 建立目录骨架、README、TASKS、`.gitignore` 与各目录策略文件。 |
