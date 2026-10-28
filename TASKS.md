# 任务清单（TASKS）

> **用法**：完成一项将 `[ ]` 改为 `[x]`，并在“变更记录”中注明日期与证据。
> **状态**：`[x]` 已完成｜`[~]` 进行中｜`[ ]` 未开始｜`[!]` 阻塞/待确认
> **最后更新**：2026-10-28

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
| SCCB 初始化与 Chip ID | **已上板通过（用户实测 LED2/3/4 常亮）** | `top_cam_id`、`bringup-sccb-id.md` |
| DVP 采集 | **三通道时序通过；2026-10-28 11 通道尝试失败（HREF/VSYNC 不稳定）；HREF 极性 A/B 待 D0–D7 确认** | PCLK **48.000MHz**、VSYNC 30fps/0x22 高有效、HREF 15kHz；LED4 只查长度；见 `verification/board/evidence/20261028_dvp_11ch/` |
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
- [x] **D5** 下载链路验证：用户已 Program SRAM 成功。
- [x] **D6** SCCB 读取 Chip ID：用户实测 LED2/3/4 常亮（0x5640）。
- [ ] **D7** DVP 采集（**未开始**）。
- [ ] **D8** HDMI 显示（**未开始**）。

## E. 跨对话协作

- [x] **E1** 建立 `AGENTS.md`：项目事实、规则、当前状态、坑点、下一步。
- [x] **E2** 建立 `fpga-bringup` skill：构建、仿真、调试阶梯、完成后的更新流程。
- [x] **E3** 建立 `CLAUDE.md` 指针，避免重复内容。
- [x] **E4** 清理根目录与脚本目录的 TD 临时日志。

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
- [x] **H5.5** 按 `verification/board/bringup-sccb-id.md` 烧录并记录 LED：
  LED1 闪烁，LED2/3/4 常亮，Chip ID 读取成功（用户实测）。
- [ ] **H5.6** 通过后实现 DVP 接收（PCLK/VSYNC/HREF/数据对齐）。
- [ ] **H5.7** 实现 HDMI 输出并显示。
- [ ] **H5.8** 需要时再评估 DDR 帧缓存。

## I. DVP 采集阶段（2026-10-26）

### I1. 资料与寄存器依据

- [x] **I1.1** 获取 OV5640 Product Specification V2.03（2011-05-26），在线链接登记在
  `docs/camera/README.md`；PDF 不入库。
- [x] **I1.2** 获取 ALIENTEK OV5640 FPGA 驱动 V1.0（2020-05-04）作为初始化参考；
  代码不入库，只记录来源、版本和差异。
- [x] **I1.3** 核对 `0x4300=0x61`：RGB565，输出序列 `0x1`，高字节在前。
- [x] **I1.4** 核对 `0x503D=0x80`：Pre-ISP 彩条使能；`0x00` 正常图像。
- [x] **I1.5** 发现 `0x4740` 默认值 `0x20` 与 ALIENTEK 代码的 HREF/VSYNC
  假设冲突；2026-10-26 实测确认 `0x22` 的 **VSYNC 高有效**（与 datasheet
  bit0 相反）；HREF 引脚极性仍 A/B 未定，显式写 `0x4740=0x22` 并回读。
- [ ] **I1.6** 把实测 PCLK/HREF/VSYNC 参数写入 `verification/` 并更新仿真。

### I2. RTL 与仿真

- [x] **I2.1** 实现 `fpga/rtl/common/async_fifo_gray.v`（Gray 指针异步 FIFO）。
- [x] **I2.2** 实现 `fpga/rtl/camera/dvp_capture.v`（PCLK 域采样、字节配对、
  帧/行/像素计数、事件生成、错误标志）。
- [x] **I2.3** 实现 `fpga/rtl/camera/dvp_status_monitor.v`（50MHz 域事件消费与检查）。
- [x] **I2.4** 实现 `fpga/sim/tb/tb_dvp_capture.v`：真实 PCLK、异步 50MHz、
  真实行/场结构、数据 skew、setup/hold 监视。
- [x] **I2.5** 16 行快速回归在 24/48/50MHz 下通过；HREF/VSYNC 四种极性组合
  （高/高、高/低、低/低）通过。
- [x] **I2.6** 480 行 × 1280 PCLK 完整帧仿真通过：`bytes_err=0`,
  `setup_err=0`, `hold_err=0`，963 个事件。
- [x] **I2.7** 错误沿/错误采样时刻变异测试被 setup/hold 监视器捕获。
- [ ] **I2.8** 用实测 PCLK/消隐/极性重跑完整帧仿真。

### I3. 配置与上板

- [x] **I3.1** 实现 `ov5640_cfg.v` + `ov5640_cfg_rom.v`：RGB565 表、
  显式 `0x4740=0x22`、`0x503D` 彩条模式、关键寄存器回读。
- [x] **I3.2** 配置仿真/回读回归通过（`tb_ov5640_bringup.v`，DIV=10）；
  原有 `tb_top_cam_id.v`（DIV=250）仍通过。
- [x] **I3.3** 新建 `top_dvp_test.v`、`top_dvp_test.adc/.sdc`、构建脚本；
  PCLK 作为真实时钟约束（实测 **50MHz**），TD 构建通过
  （Setup +10.245 ns，Hold +0.054 ns），位流 `build/bitstream/top_dvp_test.bit`。
  证据：`verification/static/top_dvp_test_build_2026-10-26.md`。
- [x] **I3.4** **上板三通道：时序通过**。通道映射 Ch0=PCLK、Ch1=VSYNC、
  Ch2=HREF；实测 PCLK **48.000MHz**、HREF 15kHz/66.665µs/高 40µs
  （1920 PCLK）/低 26.665µs（1280 PCLK）、VSYNC 30Hz/33.33ms/`0x22`
  高有效、每帧 **480** 行。HREF 极性 A/B 仍待 D0–D7 确认。
  证据：`verification/board/evidence/20261026_dvp_three_channel/`。
- [x] **I3.4a** 2026-10-26 的 2.3GB LA CSV 证明：**`0x22` 是 VSYNC 高有效**
  （空闲低、66.665µs 高脉冲），**`0x23` 是低有效**；`0x4740[0]` 的实际
  效果与 datasheet 相反。13:16 位流的 `0x22` + `VSYNC_ACTIVE_HIGH=0`
  配对错误；16:24 诊断改为 `0x22`+1。`EXPECTED_PIX=2000` 是 50MHz
  假设下的旧值，按 48MHz 应为 1920（高）/1280（低）。
- [x] **I3.4b** LA CSV 已定位 LED4 原因：
  1. VSYNC 极性配对错误（见 I3.4a）；
  2. HREF 每帧有一次 **1.373 ms 长高**（垂直消隐），开始于 VSYNC 上升前
     240µs、结束于 VSYNC 下降后 1.066ms，横跨 VSYNC 脉冲；被当成
     65920 字节的长行，且 `vsync_mid_line` 每帧置位。
  每帧 HREF 上升沿实为 **480**，不是 500；`EXPECTED_LINES=480` 正确。
- [~] **I3.5** **彩条 + HREF 低有效诊断位流**已构建并通过仿真：
  **2026-10-26 16:24:00**，SHA-256 `506e01ad...cca07a`；
  `COLOR_BAR=1`、`0x4740=0x22`、`VSYNC_ACTIVE_HIGH=1`、
  `HREF_ACTIVE_HIGH=0`、`EXPECTED_PIX=1280`、`EXPECTED_LINES=480`；
  Setup +10.381 ns / Hold +0.038 ns / 800 slices。
  原始二进制已被 2026-10-28 12:33 构建覆盖；同 RTL/QoR 重建为
  `top_dvp_test_20261026_rebuild.bit`（SHA `b6df6c18...`，非逐 bit 相同）。
- [x] **I3.5a** 用户报告 16:24 位流 LED4 熄灭；**但 LED4 只检查行长度/
  行数，不检查像素值**：低相位 1280 PCLK 与高相位“1280 有效 + 640 dummy”
  都能让 `EXPECTED_PIX=1280` 通过。HREF 极性 A/B 仍未定，需 D0–D7 两相
  彩条对比。
- [ ] **I3.5b** **2026-10-28 11 通道尝试失败**：13:58 HREF 包络
  15 kHz/1280 字节但 VSYNC 无效、D0–D7 全 0；14:36 HREF 单测 29.53 kHz。
  推测摄像头复位/重插后回到默认 1280×960，FPGA 未重跑 SCCB；接地可解释
  毛刺但不能单独解释稳定频率。证据：
  `verification/board/evidence/20261028_dvp_11ch/`。
- [ ] **I3.6** 上板：整机断电重上电，烧重建位流，抓 PCLK/HREF/VSYNC +
  D0–D7 两相彩条；帧/行/像素计数稳定后才归档。

## 待确认（阻塞项）

| # | 问题 | 影响 | 状态 |
|---|---|---|---|
| Q1 | 万用表通断/短路检查是否完成？ | 无法确认实物接线 | **待用户执行** |
| Q2 | 实物模组 P1 的 Pin 1 方向是否与 README/官方照片一致？ | 摄像头侧可能反接 | 官方照片已佐证，实物待确认 |
| Q3 | SCCB 上拉是否足够？ | 否则无法通信 | 首测已启用 FPGA 内部上拉；若 LED1 不亮则补 4.7 kΩ |
| Q4 | RESET/PWDN 是否需要外部默认电阻？ | 上电状态不确定 | 待决定 |
| Q5 | PCLK 实际频率/OV5640 输出分辨率？ | 时序约束与 HDMI 时钟 | PCLK=**48.000MHz**、480 行/帧、HREF 高 1920 PCLK/低 1280 PCLK；0x22=VSYNC 高有效、0x23=低有效；**HREF 极性 A/B 待 D0–D7 彩条**；1.373ms 消隐长高已测 |
| Q6 | HDMI 目标分辨率/刷新率？ | 时钟与带宽规划 | 待定 |
| Q7 | 是否使用 DDR 帧缓存？ | 架构与资源 | 待定 |
| Q8 | 板卡原理图是否允许公开再分发？ | 决定 PDF 是否入库 | 待确认 |

## 下一步动作（按顺序）

1. ~~Chip ID 上板验证~~ —— 已完成（LED1 闪，LED2/3/4 常亮，0x5640）。
2. ~~DVP 采集 RTL + 真实时序仿真~~ —— 已完成；见
   `verification/static/dvp_capture_sim_2026-10-26.md`。
3. ~~配置模块 `ov5640_cfg.v`~~ —— 已完成并通过配置/回读仿真。
4. ~~上板三通道~~ —— **时序通过**：PCLK **48.000MHz**、VSYNC 高有效
   （`0x22`）、15kHz 行 / 30Hz 帧。旧记录里的 50MHz/2000 PCLK 已按
   48MHz 修正为 1920 PCLK 高 / 1280 PCLK 低。
5. **16:24 诊断设计**：`0x22` + `VSYNC_ACTIVE_HIGH=1` +
   `HREF_ACTIVE_HIGH=0` + `EXPECTED_PIX=1280` + 480 行 + `COLOR_BAR=1`。
   LED4 熄灭只证明低相位 1280 PCLK；**HREF 极性 A/B 未定**。
6. **2026-10-28 11 通道尝试失败**：先整机断电重上电、烧重建位流，
   抓 PCLK/HREF/VSYNC，再抓 D0–D7 低/高两相彩条；在定极性前不改配置。
7. 最后做 HDMI 时序与显示；DDR 帧缓存暂不引入。

## 变更记录

| 日期 | 内容 |
|---|---|
| 2026-10-28 | **11 通道尝试失败，本分支只 PR 不合并**：13:58 采集中 PCLK=**48.000MHz**、HREF 包络 15kHz/1280 字节（低有效假设），但 CH2 高相位有 12–16ns PCLK 串扰、CH1 只有 4ns 尖峰不是 VSYNC、D0–D7 全 0；14:36 HREF 单测变成 **29.53kHz**（30.856µs 高/3.002µs 低/33.858µs 周期）。推测摄像头重插/复位后回到默认 1280×960、FPGA 未重跑 SCCB；接地可解释毛刺但不能单独解释稳定频率。**HREF 极性 A/B 仍未定**：16:24 LED4 熄灭只证明 1280 长度，不证明低相位是有效数据。证据：`verification/board/evidence/20261028_dvp_11ch/`。位流：12:33 失败构建 SHA `893dc3fa...` 已复制保存；16:24 原始 SHA `506e01ad...` 已被覆盖，同 RTL/QoR 重建为 `top_dvp_test_20261026_rebuild.bit`（SHA `b6df6c18...`，非逐 bit 相同）。 |
| 2026-10-26 | **彩条 + HREF 低有效诊断位流**：`0x4740=0x22`、`VSYNC_ACTIVE_HIGH=1`、`HREF_ACTIVE_HIGH=0`、`EXPECTED_PIX=1280`、`EXPECTED_LINES=480`、`COLOR_BAR=1`。配置仿真 PASS（`0x503D=0x80`）；HREF 低/VSYNC 高 50MHz 1280B 采集仿真 PASS；TD 构建 16:24:00，Setup +10.381ns / Hold +0.038ns / 800 slices，SHA-256 `506e01ad...`。预期：1.373ms 消隐长高不再计入；HREF 低相位约 1333 PCLK，LED4 可能因 1333 vs 1280 仍亮。 |
| 2026-10-26 | **2.3GB LA CSV 分析**：新 `0x22` 的 VSYNC 为**高有效**（空闲低、66.665 µs 高脉冲、33.333 ms 周期）；旧 `0x23` 为低有效——`0x4740[0]` 实际效果与 datasheet 相反。HREF 15 kHz/66.665 µs，典型高 40 µs = 2000 PCLK；每帧 **480** 个 HREF 上升沿；每帧一次 **1.373 ms** HREF 长高（垂直消隐），开始于 VSYNC 上升前 240 µs、结束于下降后 1.066 ms，横跨 VSYNC。**LED4 原因=极性配对错误 + 长高被当成 65920 字节行/`vsync_mid_line`，不是 480 vs 500**。 |
| 2026-10-26 | 新位流（`0x4740=0x22`、50MHz、`EXPECTED_PIX=2000`）复测：**LED4 仍亮**。三通道时序通过，但行/场计数仍不匹配；最可能是 `EXPECTED_LINES=480` 与实际约 500 行/帧不符，或某行错误 sticky。待定位。 |
| 2026-10-26 | **DVP 三通道验证通过**：Ch0=PCLK、Ch1=VSYNC、Ch2=HREF；PCLK **50MHz**、HREF **高有效**（15kHz，66.67µs，40µs 高 = 2000 PCLK）、VSYNC **低有效**（30Hz，33.33ms）、约 500 行/帧。按实测修正 `0x4740=0x22`、`VSYNC_ACTIVE_HIGH=0`、`EXPECTED_PIX=2000`、PCLK SDC=50MHz；DVP 极性仿真组合通过；位流重建（Setup +10.245ns，Hold +0.054ns，800 slices）。遗留：HREF 高 2000 字节 vs 640 像素有源 1280 字节，待彩条/D0–D7。 |
| 2026-10-26 | **DVP 三通道上板初步捕获**：`top_dvp_test.bit` 已烧录；LED1/LED3 正常闪烁，LED2/LED4 常亮。LED2=`cfg_ok`，LED3=帧计数翻转，LED4=几何/错误状态。LA 初步显示约 30Hz 帧、15kHz 行、疑似 50MHz PCLK；通道映射、PCLK 真实频率和 VSYNC 极性仍需同窗同标确认。证据：`verification/board/evidence/20261026_dvp_three_channel/`。 |
| 2026-10-26 | **配置链路与 DVP 上板顶层完成**：新增 `ov5640_cfg.v`、生成的 `ov5640_cfg_rom.v`（249 条，含 `0x4740=0x23`）、`ov5640_bringup.v`、`top_dvp_test.v`、约束与构建脚本。配置/回读仿真通过（`tb_ov5640_bringup.v`）；TD 6.2.1 构建通过（Setup WNS +11.108 ns，Hold WNS +0.050 ns，813 slices），位流 `build/bitstream/top_dvp_test.bit`。PCLK 约束 48MHz 为**临时值**，待实测。证据：`verification/static/top_dvp_test_build_2026-10-26.md`；上板步骤：`verification/board/bringup-dvp-three-channel.md`。 |
| 2026-10-26 | **DVP 采集仿真通过**：新增 `async_fifo_gray.v`、`dvp_capture.v`、`dvp_status_monitor.v`、`tb_dvp_capture.v`；24MHz/48MHz、16 行快速回归和 480 行完整帧均通过（`bytes_err=0`、setup/hold 0）；错误沿变异被 setup/hold 监视器捕获。登记 OV5640 规格书 V2.03 和 ALIENTEK V1.0 的在线引用与再分发约束；发现 `0x4740` 默认极性矛盾，计划显式写 `0x23`。证据：`verification/static/dvp_capture_sim_2026-10-26.md`。 |
| 2026-10-24 | 建立 `AGENTS.md`、`.claude/skills/fpga-bringup/SKILL.md`、`CLAUDE.md` 指针；清理 TD 临时日志。 |
| 2026-10-24 | **上板验证通过**：LED1 闪烁，LED2/3/4 常亮，SCCB 读到 Chip ID 0x5640；逻辑分析仪解码 `0x3C W 30 0A [SR] 0x3C R 56` / `30 0B ... 40`，证据归档到 `verification/board/evidence/20261024_sccb_chip_id/`。 |
| 2026-10-24 | 修复 SCCB master 漏采 1 周期 start 脉冲的问题（新增 `start_pending` 锁存）；testbench 改用 DIV=250 复测通过；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | SCCB 改为 **repeated START** 读时序，时钟降到 **50kHz**，ACK 高不作为失败条件；对齐本机厂商 OV5640 例程；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | SCCB 的 ACK 高不再作为失败条件（SCCB 第 9 位为 Don't Care）；LED2 改为“事务完成”指示；重建位流，WNS +12.684 ns。 |
| 2026-10-24 | 修正最小工程的时钟/用户灯球位：**C4 为 50MHz**，**D10/E10/C6/D6 对应物理 LED1–LED4**；重建位流，WNS +12.684 ns。此前 D4/E10/C6/D6/A5 为误读。 |
| 2026-10-24 | 建立最小 SCCB Chip ID 工程、约束、TD 构建脚本与 testbench；ModelSim 仿真通过，TD 综合/布局布线/位流出图通过。 |
| 2026-10-24 | 复核高分辨率 J2 图：确认 **J2-30=GND、J2-32=GPIOB_27**，撤回 10-23 的错误对调结论；恢复用户原表。 |
| 2026-10-23 | 核对板卡/摄像头原理图；生成 wiring.md、wiring-check.md、camera_pinmap_draft.adc；当时误读 J2-30/32，已于 10-24 撤回；记录 SCCB 上拉与 P1 符号偏移风险。 |
| 2026-10-21 | 建立目录骨架、README、TASKS、`.gitignore` 与各目录策略文件。 |
