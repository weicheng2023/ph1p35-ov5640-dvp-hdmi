# 任务清单（TASKS）

## 2026-11-09 PAXI 最小修复

- [x] 统一 16-bit word 地址单位，三个主机模块 `ADDR_STEP=8`；全字写使用高有效掩码 `0000`。
- [x] AW 接受后第 1 周期提供 WVALID；模型检查独立握手、反压稳定性和两周期限制。
- [x] 修复模型对齐/地址/掩码语义；旧 +1 和 FFFF 负例均检出。
- [x] 保留自检、整帧比较/CRC、FIFO 错误检测；红/橙/品红/黄错误分类。
- [x] 单像素 DDR 来源检查发现并修复 gearbox 块边界 FIFO pop 晚一拍。
- [x] ModelSim 必要回归 12/12 PASS，正常 CRC F53A4D4F；见
  [仿真记录](verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md)。
- [x] 新独立位流 TD 构建与时序核查：Setup +0.110 / Hold +0.020 ns，
  5283 slices；SHA `e83d9c54…`。保留原位流，check_timing 提示详见
  [构建记录](verification/static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md)。
- [x] 新位流实物显示测试：用户烧录 `top_ddr_fb_hdmi_paxi_fix_20261109.bit`
  （SHA `e83d9c54…`）并确认 **FPGA 内部测试图 → DDR → HDMI 成功显示**。
  记录为 **STAGE 2 — BOARD FUNCTIONAL PASS（用户报告）**；LED 逐项/
  CRC/照片未提供。证据：
  [实物记录](verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md)、
  [启动说明](docs/display/ddr-framebuffer-bringup.md)。

变更记录：2026-11-09 依据 IPUG034 v1.2 和同型号 Lab1 修复接口假设。
旧 2026-11-08 行为仿真未覆盖真实地址单位/掩码，不能据其证明 MIS 接口正确。
CAL_EN=0、50 MHz、DDR/HDMI PLL、TMDS、视频时序、SDC 不改；不开展完整 PHY 仿真或压力测试。

> **用法**：完成一项将 `[ ]` 改为 `[x]`，并在“变更记录”中注明日期与证据。
> **状态**：`[x]` 已完成｜`[~]` 进行中｜`[ ]` 未开始｜`[!]` 阻塞/待确认
> **最后更新**：2026-11-09

## 0. 当前结论

- 已导入板卡原理图、摄像头原理图/数据手册、FPGA 数据手册；PDF 仅本地保留，不入库。
- Git 仓库已初始化（`main` 分支），已有基线提交。
- **最小 SCCB Chip ID 工程已建立**：RTL、约束、TD 构建脚本、testbench。
- ModelSim 仿真通过：读回 `0x56/0x40`，Chip ID 匹配。
- TD 6.2.1 综合/布局布线/位流通过：WNS +12.684 ns、Hold +0.047 ns。
- SCCB Chip ID **0x5640 已上板验证**；DVP 三通道 2026-11-06 复核通过后**暂停**。
- HDMI 640×480 彩条 **2026-11-08 用户报告上板成功**（FPGA 内部彩条）。
- OV5640 单行 → HDMI **PARTIAL PASS（2026-11-08 用户报告）**：LED 全对，
  画面是一行重复，但显示“左黑条 + 右浅蓝紫”，不是预期 8 色条；
  像素内容正确性未确认。用户暂停彩条/LA 排查。
- **阶段 2 DDR 帧缓存：BOARD FUNCTIONAL PASS（2026-11-09 用户报告）**。
  CAL_EN=0 下 READY 可达；修复 PAXI 地址单位（16-bit word，块步长 8）
  和写掩码极性（`0000`=全写）后，FPGA 测试图 → DDR → HDMI 成功显示。
  仿真 12/12 PASS；最终位流 `e83d9c54…`。CAL_EN=0 仍是实验配置，
  不证明完整 PHY 校准或长期稳定性。
- **下一阶段：Stage 3（OV5640 → DDR → HDMI 实时帧缓存）**，见
  `docs/project/next-session-prompt.md`。
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
| DVP 采集 | **2026-11-06 三通道复核通过后暂停**；摄像头彩条（D0–D7 两相）延后，不在当前计划 | VSYNC 30Hz/33.333ms、HREF 15kHz/40µs；50MS/s PCLK 为 2MHz 混叠；见 `verification/board/evidence/20261106_dvp_3ch_recheck/` |
| HDMI 显示彩条 | **2026-11-08 用户报告上板成功**：FPGA 内部 8 色条已显示；证据为用户口头报告，无照片/电压记录 | `verification/board/evidence/20261107_hdmi_colorbar/README.md` |
| OV5640 单行 → HDMI | **PARTIAL PASS（2026-11-08 用户报告）**：单行采集与 HDMI 显示初步连通，LED 全对；画面左黑条 + 右浅蓝紫，非预期 8 色条；像素正确性未确认 | `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`、`docs/display/ov5640_line_to_hdmi.md` |
| DDR 帧缓存 | **STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09 用户报告）**：PAXI ADDR_STEP=8、掩码 `0000` 修复后，测试图 → DDR → HDMI 完整显示。仿真 12/12 PASS；Setup +0.110 / Hold +0.020 ns；5283 slices；位流 `e83d9c54…`；CAL_EN=0 实验配置 | `verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`、`verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`、`docs/display/ddr-framebuffer-bringup.md` |
| 整体系统集成 | **待开发/待测试** | 摄像头完整帧缓存/DDR 未完成 |

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
- [x] **I3.5b** **2026-10-28 11 通道尝试失败**：13:58 HREF 包络
  15 kHz/1280 字节但 VSYNC 无效、D0–D7 全 0；14:36 HREF 单测 29.53 kHz。
  推测摄像头复位/重插后回到默认 1280×960，FPGA 未重跑 SCCB；接地可解释
  毛刺但不能单独解释稳定频率。证据：
  `verification/board/evidence/20261028_dvp_11ch/`。
- [x] **I3.5c** **2026-11-06 三通道复核通过**：
  `2026_11_6_PCLK_VSYNK_HREF.atkdl`（50 MS/s，200 ms）VSYNC
  30 Hz/33.333 ms/66.66 µs 高，HREF 15 kHz/39.997 µs 高/26.66 µs 低，
  479 正常行/帧（等效 480）；29.53 kHz 异常未复现。PCLK 50 MS/s
  为 2 MHz 混叠，不能单独证明 48 MHz。证据：
  `verification/board/evidence/20261106_dvp_3ch_recheck/`；
  工具 `tools/extract_atkdl.pl`、`tools/analyze_dvp_sync.pl`。
- [ ] **I3.6** **下一步彩条**：整机断电重上电，烧
  `top_dvp_test_20261106_colorbar.bit`（SHA `b6df6c18...`），
  200/250 MS/s 抓 11 通道，HREF 触发 100 µs；用
  `analyze_dvp_la.pl --href-active=low/high` 比较哪一相出现 8 色条。
  确认 1280 字节、RGB565 高字节在前、HREF A/B 后再归档。

## J. HDMI 彩条阶段（2026-11-07）

### J1. 硬件复核

- [x] **J1.1** HDMI1 方向 = **source**：D5 从 VCC_5V 给 pin 18 供 5V；
  HPD 由显示器驱动、FPGA 读取；DDC 3.3V↔5V 电平转换。
- [x] **J1.2** TMDS 差分对 **G16/H16、F17/E18、H14/H13、C17/D18**；
  `pdftotext -table` + 高 DPI 裁剪复核；旧 H16/F17 组合作废。
- [x] **J1.3** `VCCIO_32 = VCC_3V3`（C401–C406 去耦）。
- [x] **J1.4** R180–R187 8×49.9 Ω 上拉到 `+3.3V_HDMI`；
  `HDMI_A_5V` 与 `HDMI_A0_5V` 分离；D6 造成 HPD 锁存；
  Q17 控制 `+3.3V_HDMI` 上电顺序。
- [x] **J1.5** 证据：`verification/board/evidence/20261107_hdmi_pin_review/`。

### J2. 厂商 IP 调查

- [x] **J2.1** TD 6.2.1 `ip/`、`ip/depot/` **无 HDMI Transmitter IP**。
- [x] **J2.2** 第三方 `hdmi_1_4b_transmitter_core_wrapper.enc.v` 不复制、
  不修改、不破解、不再分发。
- [x] **J2.3** 选方案 B：自写 TMDS 编码/串行化，PHY 用
  `PH1P_LOGIC_ODDR`，PLL 用 `PH1P_PHY_PLL_V2`。

### J3. RTL 与仿真

- [x] **J3.1** `video_timing.v`、`color_bar.v`、`tmds_encoder.v`、
  `tmds_serializer.v`、`serial_load_gen.v`、`pll_hdmi.v`、
  `top_hdmi_colorbar.v`。
- [x] **J3.2** `tb_tmds_encoder` PASS（控制码 + 数据码 + disparity）。
- [x] **J3.3** `tb_tmds_serializer` PASS（串行顺序 din[0..9]）。
- [x] **J3.4** `tb_video_timing` PASS（完整 800×521 帧）。
- [x] **J3.5** `tb_top_hdmi_colorbar` PASS（8 色 + 4 控制码）。
- [x] **J3.6** `tb_pll_vendor` PASS：25.0/125.0 MHz 配置在 TD 厂商
  PLL 功能模型中 lock，C0=40.000 ns / C1=8.000 ns。
- [x] **J3.7** 证据：`verification/static/hdmi_colorbar_sim_2026-11-07.md`。

### J4. TD 构建

- [x] **J4.1** PLL 50 MHz → 25.0 MHz / 125.0 MHz（C0 反馈，VCO 1250）。
- [x] **J4.2** TMDS33 约束 G16/F17/H14/C17；N 端由工具推断。
- [x] **J4.3** Setup WNS **+5.170 ns**，Hold WNS **+0.054 ns**，
  0 violated endpoints。
- [x] **J4.4** `check_timing` HIGH 级 0；8 个输出无 output delay（MEDIUM：
  4 LED + 4 TMDS）。
- [x] **J4.5** 位流 SHA-256
  `60fb0d0de3aabe36285e1d3cb6ea82bff5e88e271ae18f6374081931c908ef63`。
- [x] **J4.6** 证据：`verification/static/top_hdmi_colorbar_build_2026-11-07.md`。
- [!] **J4.7** 已知 warning：`PHY-5016 PLL clkc ... not driving a
  clock-capable IO`；routed 时序已到 `opclk`，但必须上板确认。

### J5. 上板

- [~] **J5.1** 静态电压测量：**用户未提供**，保持待补。
- [x] **J5.2** 接显示器，Program SRAM：**用户报告完成**。
- [~] **J5.3** LED1–LED4：**用户未逐项提供**。
- [x] **J5.4** 观察 8 色竖条：**用户报告成功显示 FPGA 内部彩条**。
- [x] **J5.5** 证据写入 `verification/board/evidence/20261107_hdmi_colorbar/`
  （已记录为 **USER-REPORTED PASS**，无照片/电压/日志）。

> 说明：J5 的 PASS 只证明“FPGA 内部彩条 → HDMI 显示器”可见；
> 不代表摄像头像素路径、TMDS 电气或完整协议已经验证。

### J6. 后续（本阶段不做）

- [ ] **J6.1** 用摄像头像素替换彩条（需先解决 DVP/HREF 数据相）。
- [ ] **J6.2** 如显示器需要 EDID/热插拔，再评估 DDC/HPD。
- [ ] **J6.3** 720p/1080p、DDR 帧缓存、音频/InfoFrame/HDCP。

## K. OV5640 单行 → HDMI 阶段（2026-11-08）

> 目标：在**已成功的 HDMI 链路**上显示真正来自 OV5640 D0–D7 的
> 内部彩条数据，而不是 FPGA 自己生成的彩条。先做单行缓存/重复显示，
> 不引入 DDR。

### K1. 现有工程复核

- [x] **K1.1** 读取 `ov5640_bringup/cfg/cfg_rom/dvp_capture/top_dvp_test`。
- [x] **K1.2** 确认 `0x4300=0x61`（RGB565，高字节在前）、
  `0x4740=0x22`、`0x503D=0x80`（COLOR_BAR=1）。
- [x] **K1.3** 确认 HDMI 链路（PLL/TMDS/时序）已上板用户报告成功，
  作为回归基准保留。

### K2. 2000/1920 vs 1280 字节调查

- [x] **K2.1** 记录：PCLK 实测 48.000 MHz；HREF 高 40 µs ≈ **1920**
  PCLK（不是 50 MHz 假设下的 2000）；HREF 低 26.665 µs ≈ **1280** PCLK。
- [x] **K2.2** RGB565 640 像素 = 1280 字节。高相位 1920 = 1280 有效
  + 640 额外；低相位 1280。A/B 仍未由 D0–D7 数据最终判定。
- [x] **K2.3** 设计单行采集：只取 HREF 有效相位的前 1280 字节
  （参数 `CAPTURE_START=0`，可改 640 取后 1280）；用行长
  [1200,2200] 过滤垂直消隐的长 HREF。
- [ ] **K2.4** 用摄像头内部彩条显示结果最终确认 A/B 与字节顺序。

### K3. RTL

- [x] **K3.1** `ov5640_line_capture.v`：PCLK 域字节计数、RGB565 拼接、
  行长过滤、`capture_done`。
- [x] **K3.2** `line_buffer_dpram.v`：双时钟 640×16 行缓存。
- [x] **K3.3** `rgb565_to_rgb888.v`。
- [x] **K3.4** `ov5640_line_to_hdmi_core.v`：行缓存 + 已验证 HDMI 链路。
- [x] **K3.5** `top_ov5640_line_to_hdmi.v`：SCCB bringup + core + LED。
- [x] **K3.6** ADC/SDC/构建脚本。

### K4. 仿真

- [x] **K4.1** `tb_ov5640_line_capture`：1920 高相位、1280 低相位、
  65,920 消隐长高、字节顺序、行长过滤。
- [x] **K4.2** `tb_top_ov5640_line_to_hdmi`：核心 + HDMI 8 色输出。
- [x] **K4.3** 复核 `tb_dvp_capture` 不被改动（或改动后重跑）。
- [x] **K4.4** 证据：`verification/static/ov5640_line_to_hdmi_sim_2026-11-08.md`。
  三个 TB PASS：单行采集（CAP_START 0/640、BYTE_SWAP）、核心集成
  （背景 + 8 色）；消隐长高 65,920 被拒绝。

### K5. TD 构建

- [x] **K5.1** PCLK 48 MHz / pixel 25 MHz / serial 125 MHz 约束。
- [x] **K5.2** Setup/Hold WNS > 0，RAM 推断/资源检查。
- [x] **K5.3** 位流生成并记录 SHA：
  `67eec013651ccdde7291e3e26d1ec1a506e92111076651f0a49cf7ff0e3222cd`。
- [x] **K5.4** 结果：Setup +6.027 ns / Hold **+0.020 ns**（紧）/
  821 slices（3.87%）/ 1 ERAM。`check_timing` 有 1 个 HIGH dummy node
  （`cam_sda.ts`，SCCB inout）和 12 个 MEDIUM output delay；
  详见 `verification/static/top_ov5640_line_to_hdmi_build_2026-11-08.md`。

### K6. 上板（PARTIAL PASS，2026-11-08 用户报告）

- [x] **K6.1** 保留彩条回归位流，不覆盖。
- [x] **K6.2** 用户烧录新位流；LED1/2/3/4 全部符合设计。
- [x] **K6.3** 画面为单行重复；左侧宽黑条、右侧大面积浅蓝紫，
  **不是**预期 8 色条；颜色顺序/字节序/±1 像素对齐未确认。
- [x] **K6.4** 证据 `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`
  （PARTIAL PASS，仅用户口头报告，无照片/电压/LA）。
- [ ] **K6.5** 像素正确性留到 DDR 实时画面阶段再解决（用户决定暂停彩条/LA）。

### K7. DDR 调查（2026-11-08 已确认）

- [x] **K7.1** 板载 DDR：数据手册 §2.12 确认 PH1P35MDG324
  **封装内 16-bit 512Mb SDRAM**（64 MB），VCCIO_DDR 1.5 V；
  本地无外部 DDR 图页，与“集成”一致。
- [x] **K7.2** TD IP `MIS_DDRF6F1D0P0_1.1`：`cfg.csv` 有
  `PH1P35MDG324 ... Integrated`；集成分支走 **DDR2 512Mb x16**
  （`DDR2_512M`/`DDR2_X16`），PHY 用 `ddrphy_cfg_rom_MDG324.txt`。
- [x] **K7.3** 参考工程 `build/ref/anlogic-ph1p35-vision` 目标同为
  PH1P35MDG324；其 cfg rom/矩阵文件与 TD MDG324 文件逐字节相同；
  生成参数 `DDR2_1066`、tCK=1876、CL=7、CWL=6。
- [x] **K7.4** 用户接口 AXI4 128-bit + APB、`ddrphy_rdy` 校准、
  `dhi_clk`；50 MHz ref 的 PLL 参数已用 TD 过程算出。
- [x] **K7.5** 单帧 600 KiB、双帧 1.17 MiB；64 MB 容量足够；
  带宽需求约 55 MB/s 平均、146 MB/s 峰值，DDR2-1066 足够。
- [x] **K7.6** 乒乓/仲裁/帧同步方案见报告 §2。
- [x] **K7.7** 报告 `docs/display/ddr-investigation.md`（2026-11-08）
  已更新为“集成 DDR2 512Mb x16、TD IP、参考工程、50 MHz PLL”。

## L. 阶段 2：DDR 帧缓存（2026-11-08 开始）

> 目标：先证明 DDR 初始化/校准/读写可用，再用 FPGA 测试图验证
> 640×480 RGB565 帧缓存，最后接 OV5640 实时画面。

### L1. 独立 DDR 最小读写测试（无摄像头）

- [x] **L1.1** 组装 `PH1P35MDG324 Integrated` DDR2 IP：
  参考树 + MDG324 cfg rom/矩阵 + TD cal RTL；
  生成物 `build/ddr_ip/`，不入库；`fpga/scripts/prepare_ddr_ip.sh`。
- [x] **L1.2** `top_ddr_test` + `ddr2` wrapper + `ddr_axi_pattern_test`：
  50 MHz ref、POR 复位、APB 明确接 0、等 `ddrphy_rdy`；
  原生 `paxi_*` 写/读 16 个 128-bit pattern 并逐字比对。
- [x] **L1.3** LED：LED1=心跳、LED2=`ddrphy_rdy`、LED3=PASS、
  LED4=FAIL/超时。
- [x] **L1.4** ModelSim：行为 AXI 从模型验证主机 FSM（3/3 PASS，
  含反压/故意翻转）；TD 构建通过：Setup +0.913 / Hold +0.020 /
  3389 slices / 31 DRAMHARDCON；位流 SHA `610b0b1f...`。
  证据：`verification/static/ddr_test_sim_2026-11-08.md`、
  `verification/static/top_ddr_test_build_2026-11-08.md`。
- [ ] **L1.5** 原 pattern 测试上板：**LED1 闪，LED2/3/4 灭**（用户
  实测，SHA `610b0b1f...`）。现象与 `ddrphy_rdy` 未到 + `ST_IDLE`
  不启动 timeout 一致；**不能**据此断言校准失败原因。
- [x] **L1.5a** 建 DDR 状态调试位流：LED2=`ddrphy_rst_n`、
  LED3=`ddrphy_rdy`、LED4=独立 50 MHz 超时；无 AXI 事务。
  `top_ddr_debug.bit` SHA `03339cf5...`；构建/告警
  `verification/static/top_ddr_debug_build_2026-11-08.md`；
  状态逻辑 sim 3/3 PASS。
- [x] **L1.5b** CAL_EN=1 调试上板：**LED1 闪、LED2 亮、LED3 灭、
  LED4 亮**（用户实测 >10 s）。PLL/复位已释放，READY 未到，超时触发。
- [x] **L1.5c** 构建 **只改 CAL_EN=0** 的对照：
  `top_ddr_debug_cal0.bit` SHA `f3facdf8...`；Setup +2.073 /
  Hold +0.021 / 1290 slices；与 CAL_EN=1 的 1960 slices 差异来自
  `ph1p_ddrphy_wrapper.v` 的 `if (CAL_EN==1)` cal 生成块；PLL/ref/
  tCK/CL/CWL/复位/SDC/LED/AXI-APB 未变。证据
  `verification/static/top_ddr_debug_cal0_build_2026-11-08.md`。
- [x] **L1.5d** CAL_EN=0 上板（用户实测）：**LED1 闪、LED2 亮、
  LED3 亮、LED4 灭** → READY 可达。训练被绕过，**不证明数据可靠**；
  后续数据证明由 `top_ddr_fb_hdmi` 的 16-beat 自检 + 整帧读回 CRC 承担。
- [x] **L1.6** 证据目录/步骤已建立：
  `verification/board/evidence/20261108_ddr_test/`、
  `verification/board/evidence/20261108_ddr_debug/`。

### L2. FPGA 测试图 → DDR → HDMI

- [x] **L2.1** 生成 640×480 RGB565 测试图：8 色竖条（80 px/条）、
  2 px 白边、16×16 左上红白棋盘标记、每 32 行灰网格；
  `fb_pattern.v` 同时供写侧期望数据/CRC 与读侧逐像素比对。
- [x] **L2.2** 独立工程 `top_ddr_fb_hdmi`：16-beat 自检 → 38400 个
  单拍 128-bit 写（BASE=4096）→ DRAIN → 整帧读回逐像素 + **实际数据**
  CRC → FIFO 预充 192 字 → VSYNC 对齐启动 → 异步 FIFO →
  8:1 gearbox → HDMI。`CAL_EN=0` 为实验配置。
  - ModelSim 3/3 PASS：正常 / `READY_DELAY=2` / 帧内 beat 4100 注入
    1 bit（`err_addr=4100`、CRC `306B3F2A≠F53A4D4F`、进入 `PH_ERROR`）。
  - 正常 CRC：`crc_expected == crc_actual == 0xF53A4D4F`。
  - HDMI 第一帧 line 10 的 8 色/边框/标记、line 32 网格、line 33 白条
    位置全部正确；无 underflow/overflow。
  - 证据：`verification/static/ddr_fb_hdmi_sim_2026-11-08.md`。
- [x] **L2.3** TD 构建：Setup **+0.163 ns** / Hold **+0.021 ns**（紧）/
  5116 slices（24.11%）/ 0 RAM / 0 DSP / 100 DRAMHARDCON；
  `check_timing` HIGH：no clock 0、invalid constraint 0、dummy node 2
  （未用 PHY 输出 + 2 个悬空 `pllreset`）、PLL 533.600 vs 533.333 舍入；
  MEDIUM 22 input / 53 output 无 delay。位流 SHA `3cde314a…`。
  证据：`verification/static/top_ddr_fb_hdmi_build_2026-11-08.md`。
- [ ] **L2.4** 上板：按 `verification/board/bringup-ddr-fb-hdmi.md`
  记录 LED、背景/图像/颜色/行列/错误画面，写入
  `verification/board/evidence/20261108_ddr_fb_hdmi/README.md`。
- [ ] **L2.5** 记录实际读写带宽与是否撕裂/错行/颜色错误（上板后）。

### L3. OV5640 → DDR 双缓冲 → HDMI

- [x] **L3.1** DVP 整帧采集 → PCLK→dhi_clk 异步 FIFO（129-bit beat）
  → PAXI 128-bit 单拍写。`ov5640_frame_capture.v`、`cam_fb_writer.v`；
  行 RAM + 行长过滤 + 缺行黑填充 + 帧头协议。
- [x] **L3.2** DDR 读 → 128-bit 显示 FIFO → gearbox → RGB565→RGB888 → HDMI。
  `cam_fb_reader.v`、`cam_fb_hdmi_core.v`。
- [x] **L3.3** 乒乓帧缓存：写侧只在显示未占用目标缓冲区时接受帧头；
  读侧每显示帧一遍，帧末等显示 FIFO 排空后才换 buffer（避免撕裂）。
- [x] **L3.4** ModelSim：Stage 3 快速 9/9 PASS + 640×480 真实时序 1/1 PASS；
  Stage 2 12 例回归仍 12/12 PASS。证据
  `verification/static/cam_fb_hdmi_sim_2026-11-13.md`。
- [x] **L3.5** TD 构建 + 时序核查 + 位流。首版
  （`HREF_ACTIVE_HIGH=1`）Setup **+0.184 ns** / Hold **+0.020 ns**，
  6920 slices，SHA `a25a2ac9…`；上板为“左黑 + 右浅蓝”，与单行版一致。
  **2026-11-13 极性修复**：数据手册 `0x4740` bit1=HREF 极性、默认
  `0x20` 为低有效；正点原子参考用默认 `0x20` + HREF 高采集，说明本
  模组引脚极性与 datasheet 相反；我们写 `0x22`（bit1=1）→ 引脚 HREF
  低有效，低相位 1280 PCLK = 640 像素。故只把 `HREF_ACTIVE_HIGH`
  1→0，重建为 `top_cam_fb_hdmi.bit`，SHA-256
  `787b26ee9bd6e7e171e74a0947df6cd793b657838d282d05c4e8f9fe88ace15e`，
  Setup **+0.404 / Hold +0.020 ns**，6952 slices，0 RAM/191
  DRAMHARDCON。旧版保留为 `top_cam_fb_hdmi_hrefhigh_20261113.bit`。
  彩条诊断位流同极性重建为 `top_cam_fb_hdmi_colorbar.bit`（SHA
  `76d2ec77…`，Setup +0.820 / Hold +0.020 ns，6933 slices；旧 HREF=1
  版保留为 `top_cam_fb_hdmi_colorbar_hrefhigh_20261113.bit`）。
  `check_timing`：3 个 dangling 节点（HIGH）、PLL 533.600/533.333
  舍入、23 输入/57 输出未设 IO delay（MEDIUM）；不作完整签核。
  **上板结果待用户实测。** 证据
  `verification/static/top_cam_fb_hdmi_build_2026-11-13.md`。
- [ ] **L3.6** 上板：摄像头实时画面、移动/遮挡更新；记录阶段 2 彩条
  “色块右缘短横毛刺、向上滚动”在本阶段是否仍存在及形式。步骤
  `verification/board/bringup-cam-fb-hdmi.md`。
- [ ] **L3.7** 镜头移动/遮挡/已知色卡验证像素正确性；
  再解决 HREF 窗口/字节序遗留问题。

## 待确认（阻塞项）

| # | 问题 | 影响 | 状态 |
|---|---|---|---|
| Q1 | 万用表通断/短路检查是否完成？ | 无法确认实物接线 | **待用户执行** |
| Q2 | 实物模组 P1 的 Pin 1 方向是否与 README/官方照片一致？ | 摄像头侧可能反接 | 官方照片已佐证，实物待确认 |
| Q3 | SCCB 上拉是否足够？ | 否则无法通信 | 首测已启用 FPGA 内部上拉；若 LED1 不亮则补 4.7 kΩ |
| Q4 | RESET/PWDN 是否需要外部默认电阻？ | 上电状态不确定 | 待决定 |
| Q5 | PCLK 实际频率/OV5640 输出分辨率？ | 时序约束与 HDMI 时钟 | PCLK=**48.000MHz**、480 行/帧、HREF 高 1920 PCLK/低 1280 PCLK；0x22=VSYNC 高有效、0x23=低有效；**HREF 极性 A/B 待 D0–D7 彩条**；1.373ms 消隐长高已测 |
| Q6 | HDMI 目标分辨率/刷新率？ | 时钟与带宽规划 | **640×480@60**（25.0 MHz pixel / 125 MHz serial，v1 彩条） |
| Q7 | 是否使用 DDR 帧缓存？ | 架构与资源 | **阶段 2 使用**：封装内 512Mb x16 DDR2；先做最小读写测试 |
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
6. ~~2026-10-28 11 通道失败/2026-11-06 复核~~ —— **三通道复核通过**：
   VSYNC 30 Hz、HREF 15 kHz、480 行；PCLK 50 MS/s 混叠，需 200/250 MS/s。
7. **DVP 暂停**：摄像头彩条（D0–D7 两相）延后；当前不继续。
8. **HDMI 显示彩条**（不接摄像头、不用 DDR）：
   - ~~原理图确认 HDMI1 source、TMDS 球位/IO 标准~~ —— 已完成
     （G16/H16、F17/E18、H14/H13、C17/D18；TMDS33）。
   - ~~640×480@60 内部 8 色条 RTL/仿真/TD 构建~~ —— 已完成
     （4/4 仿真 PASS；Setup +5.170/Hold +0.054 ns；107 slices）。
   - ~~上板实测~~ —— **2026-11-08 用户报告 PASS**（FPGA 内部 8 色条），
     证据 `verification/board/evidence/20261107_hdmi_colorbar/`。
   - 入口 `docs/display/README.md`。
9. **阶段 2：DDR 帧缓存** —— **BOARD FUNCTIONAL PASS（2026-11-09）**：
   - 已确认 PH1P35MDG324 封装内 **DDR2 512Mb x16、1.5 V**；
     TD IP `MIS_DDRF6F1D0P0_1.1`，`Integrated` 模式/MDG324 配置；
   - `top_ddr_test`：CAL_EN=1 上板未 READY；CAL_EN=0 对照 READY 可达；
   - PAXI 修正：地址单位 16-bit word，128-bit 块 `ADDR_STEP=8`；
     全写掩码 `16'h0000`（高有效）；AW 接受后下一周期 WVALID；
   - 修复 gearbox 块边界 FIFO pop 晚一拍；仿真 12/12 PASS；
   - 最终位流 `top_ddr_fb_hdmi_paxi_fix_20261109.bit`，SHA
     `e83d9c54…`；Setup +0.110 / Hold +0.020 ns；用户确认测试图
     → DDR → HDMI 完整显示；证据
     `verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`；
   - **下一阶段 Stage 3**：OV5640 → DDR 双缓冲 → HDMI 实时画面，
     见 `docs/project/next-session-prompt.md`。
   - 详见 `docs/display/ddr-framebuffer-bringup.md`、
     `docs/display/ddr-investigation.md` 与本文 L 节。

## 变更记录

| 日期 | 内容 |
|---|---|
| 2026-11-13 | **Stage 3 实现与仿真/构建完成（未上板）**。复用阶段 2 的 DDR/HDMI 已验证模块与 PAXI 契约（word 地址 +8、掩码 `0000`、AW→W 下一拍），新增 `ov5640_frame_capture`（PCLK 整帧采集、行 RAM、行长过滤、缺行黑填充、帧头）、`cam_fb_writer`（乒乓写、`buf_free` 门控）、`cam_fb_reader`（每显示帧一遍、帧末等显示 FIFO 排空后换 buffer）、`cam_fb_hdmi_core`、`top_cam_fb_hdmi`、ADC/SDC/构建脚本/仿真脚本。`async_fifo_gray` 仅新增只读 `wr_empty`。仿真：采集 7/7、集成快速 2/2、640×480 真实时序 1/1 PASS；Stage 2 原 12 例仍 12/12 PASS。仿真修复 5 个真实问题（写侧帧头弹出晚一拍、仲裁器提前释放读、ARVALID 撤回、采集 FIFO 写使能晚一拍丢字、显示 FIFO 反压占总线）。TD：首版（`HREF_ACTIVE_HIGH=1`）Setup **+0.184 / Hold +0.020 ns**、6920 slices、0 RAM/191 DRAMHARDCON，SHA `a25a2ac9…`；上板为“左黑 + 右浅蓝”，与 2026-11-08 单行版一致。**2026-11-13 极性定位与修复**：数据手册 table 7-18 `0x4740` bit1=HREF 极性（默认 `0x20` 低有效）；正点原子参考不写 `0x4740`（默认 `0x20`）并用 HREF 高电平采集，说明本模组引脚极性与 datasheet 相反（与 bit0/VSYNC 反相一致）。我们写 `0x22`（bit1=1）→ 引脚 **HREF 低有效**，低相位实测 1280 PCLK = 640 像素。只改 `HREF_ACTIVE_HIGH` 1→0 重建：Setup **+0.404 / Hold +0.020 ns**、6952 slices，位流 SHA `787b26ee…`；旧版保留为 `hrefhigh_20261113.bit`。**上板结果待用户实测。** 用户要求在实时画面上观察阶段 2 彩条毛刺是否仍存在，本轮不改 DDR 侧代码。证据：`verification/static/cam_fb_hdmi_sim_2026-11-13.md`、`verification/static/top_cam_fb_hdmi_build_2026-11-13.md`、`verification/board/bringup-cam-fb-hdmi.md`。 |
| 2026-11-09 | **阶段 2 色条毛刺：新增寄存器字缓冲（WBUF）试验位流（未上板）**。用户报告 `top_ddr_fb_hdmi_paxi_fix_20261109.bit` 上每个色条右边缘有向右突出的短横毛刺、持续向上滚动，怀疑 FIFO 头 → 8:1 MUX → RGB565→RGB888 → TMDS 的组合路径。新增 `pixel_gearbox_wbuf.v`（128-bit `word_buf` 寄存器 + 8:1 MUX + RGB565 寄存器；像素 6 弹出、像素 7 锁存下一字、消隐期预装）、`ddr_fb_hdmi_core` 参数 `USE_WBUF`（默认 0 不改原路径）、`top_ddr_fb_hdmi_wbuf.v`、构建脚本与仿真脚本。像素总延迟 2 拍，DE/HS/VS 同步延迟 2 拍对齐。ModelSim **8/8 PASS**：默认与 WBUF 两路都做 307200 像素全帧逐点比对（0 错），另有 READY_DELAY=2、DDR 源单像素、underflow、corrupt 负例；原 12 例回归重跑确认默认路径不变。TD：Setup **+0.218 ns** / Hold +0.020 ns、4547 slices、**4 ERAM**（显示 FIFO 被推断成 ERAM，原为 800 个 mslice）、36 DRAMHARDCON；位流 `top_ddr_fb_hdmi_wbuf_20261109.bit`，SHA `1f14bce5…`；原位流 `e83d9c54…` 未覆盖。**未上板，不声称毛刺成因或修复**。注意：本试验同时改了流水线和 FIFO 存储实现；若毛刺消失，还需“强制分布式 RAM”对照才能定位。证据：`verification/static/ddr_fb_hdmi_wbuf_sim_2026-11-09.md`、`verification/static/top_ddr_fb_hdmi_wbuf_build_2026-11-09.md`、`verification/board/bringup-ddr-fb-hdmi-wbuf.md`。 |
| 2026-11-09 | **阶段 2 收尾：STAGE 2 — BOARD FUNCTIONAL PASS（用户报告）**。用户烧录 `top_ddr_fb_hdmi_paxi_fix_20261109.bit`（SHA `e83d9c54…`）后确认 FPGA 内部测试图 → DDR → HDMI 成功显示。最终修复：PAXI 原生地址单位为 16-bit word，128-bit 块 `ADDR_STEP=8`；全写掩码 `16'h0000`（高有效，0=写/1=屏蔽）；AW 接受后下一周期提供 WVALID 并保持到 WREADY；行为模型修正对齐/掩码/握手检查，旧 `+1`/`FFFF` 负例均可检出。DDR-source 单像素检查发现并修复 gearbox 块边界 FIFO pop 晚一拍。ModelSim 必要回归 **12/12 PASS**（正常 CRC `F53A4D4F`）；TD 6.2.1：Setup **+0.110 ns** / Hold **+0.020 ns**、5283 slices、0 RAM/0 DSP/100 DRAMHARDCON；`check_timing` 仍有 PLL/dummy/未设 IO delay 提示，不作完整时序签核。CAL_EN=0、50 MHz、DDR/HDMI PLL、TMDS、视频时序、SDC 未改。LED 逐项、CRC/照片未提供，记录为 **USER-REPORTED FUNCTIONAL PASS**，不宣称完整 PHY 校准或长期稳定性。证据：`verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`、`verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`、`verification/static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md`、`docs/display/ddr-framebuffer-bringup.md`。旧 11-08 `3cde314a…` 失败版保留为诊断历史。 |
| 2026-11-08 | **DDR Frame Buffer → HDMI：RTL + ModelSim 3/3 + TD 构建完成（待上板）**。CAL_EN=0 对照已由用户实测：LED1 闪、LED2/3 亮、LED4 灭 → READY 可达（训练被绕过，不证明数据可靠）。新增独立 `top_ddr_fb_hdmi` / `ddr_fb_hdmi_core` / `fb_pattern` / `crc32_16` / `fb_writer` / `fb_reader` / `pixel_gearbox`、ADC/SDC/构建脚本、TB。核心流程：16-beat 自检 → 38400 个**单拍 128-bit** 写（BASE=4096、80 beat/行）→ 保守 DRAIN 1024（不声称写完成）→ 整帧读回逐像素比对 + **实际读回数据** CRC → FIFO 预充 192 字 → VSYNC 下降沿对齐 `video_valid` → 异步 FIFO（128×256，Gray 指针）→ 8:1 gearbox → 复用已上板 HDMI PLL/TMDS。仿真：正常 CRC `F53A4D4F`、`READY_DELAY=2` 同值、帧内 beat 4100 注入 1 bit → `err_addr=4100`、CRC `306B3F2A`、进入 `PH_ERROR` 且不启动显示；HDMI 第一帧 8 色/边框/标记/网格位置全部正确；无 underflow/overflow。TD：Setup **+0.163 ns** / Hold **+0.021 ns** / 5116 slices（24.11%）/ 0 RAM / 0 DSP / 100 DRAMHARDCON；`check_timing` HIGH no-clock 0、invalid 0、dummy 2（未用 PHY 输出 + 悬空 pllreset）、533.600 vs 533.333 舍入；位流 SHA `3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`。CDC 审计：本设计跨域仅有 Gray 指针 FIFO + 2FF；实验证明设计级二组异步声明在 TD 中与厂商 IP 单组声明冲突/冗余（invalid），强行替换会让厂商 IP 内部约束失效（Setup -2.467 ns），故最终保留厂商 IP SDC 并在文档中逐项说明。既有彩条/单行/DDR test/DDR debug 位流全部保留未覆盖。证据：`verification/static/ddr_fb_hdmi_sim_2026-11-08.md`、`verification/static/top_ddr_fb_hdmi_build_2026-11-08.md`、`verification/board/bringup-ddr-fb-hdmi.md`、`verification/board/evidence/20261108_ddr_fb_hdmi/README.md`（NOT RUN）。下一步：用户上板看 LED 与显示器图像。 |
| 2026-11-08 | **CAL_EN=1 调试上板：PLL/复位已释放，READY 未到；构建 CAL_EN=0 对照**。用户实测 `top_ddr_debug.bit`（SHA `03339cf5...`）等待 >10 s：LED1 闪、LED2 亮、LED3 灭、LED4 亮 → `ddrphy_rst_n`=1（PLL/复位释放），`ddrphy_rdy`=0，1 s 独立超时触发。按现有 `DDR_CAL0=1` 机制构建只改 `CAL_EN` 的对照：`top_ddr_debug_cal0.bit` SHA `f3facdf8...`；TD Setup **+2.073 ns** / Hold **+0.021 ns** / 1290 slices / 7 DRAMHARDCON；CAL_EN=1 同源构建 1960 slices，差异来自 `ph1p_ddrphy_wrapper.v` 的 `if (CAL_EN==1'b1)` cal 生成块。PLL 参数（50 MHz/N=3/M=64/C=2/CLK3=21）、tCK/CL/CWL、复位、SDC、LED 逻辑、AXI/APB 接 0 全部不变；IP 文件列表同为 38 个，仅 `read_hdl` 多 `-define DDR_CAL0`、输出前缀不同。ModelSim 状态仿真 3/3 PASS。原 `top_ddr_test.bit`（`610b0b1f...`）与原 `top_ddr_debug.bit`（`03339cf5...`）均保留未覆盖。`check_timing`：CAL0 4 个 HIGH no-clock（CAL1 6 个，SDC 未改）、1 PLL dummy、533.600 vs 533.333、USR-6133；**不是时序签收**。下一步：CAL0 上板看 LED3/LED4；即使 LED3 亮也只证明 READY 到达，不证明数据可靠。 |
| 2026-11-08 | **原 DDR pattern 测试上板失败（LED2/3/4 灭）；建 DDR 状态调试位流**。用户实测 `top_ddr_test.bit`（SHA `610b0b1f...`）：LED1 正常闪，LED2/3/4 不亮。分析：LED2 原为 `ddrphy_rdy` 经 `dhi_clk` 同步；若 PLL/`dhi_clk` 未起或 READY 未到，`ddr_ready=0`，pattern 状态机停在 `ST_IDLE`；`ST_IDLE` 刻意不启动 timeout，故 LED4 也不亮；`ddrphy_rst_n`（PLL/复位释放）原顶层未引出，无法区分 PLL 未锁与校准未完成。新增 `top_ddr_debug`：LED1 心跳、LED2 `ddrphy_rst_n`（2FF）、LED3 `ddrphy_rdy`（2FF）、LED4 独立 50 MHz 1 s 超时（锁存）；AXI/APB 全接 0，不发起读写；显式 `PH1P_LOGIC_BUFG`。`ddr_status_debug` sim 3/3 PASS。TD：Setup **+1.446 ns** / Hold **+0.020 ns**（紧）/ 1960 slices / 7 DRAMHARDCON；位流 SHA `03339cf5...`。`check_timing` 仍有 6 个 HIGH no-clock SCLK net、1 个 PLL dummy、533.600 vs 533.333、USR-6133 primary-clock-on-internal-refclk；**不是时序签收**。原始 `top_ddr_test.bit` 保留。下一步：烧调试位流看 LED 组合；仅当 LED2=1/LED3=0/LED4=1 再做 CAL_EN=0 对照。 |
| 2026-11-08 | **DDR 最小读写测试：仿真 + TD 构建通过（上板未执行）**。组装 `PH1P35MDG324 Integrated` DDR2 512Mb x16 IP（参考生成树 + TD cal RTL，`build/ddr_ip/` 不入库）；新增 `ddr2` plain wrapper（50 MHz ref，PLL N=3/M=64/C=2/CLK3=21）、`ddr_axi_pattern_test`（原生 `paxi_*`，16×128-bit 写/读/比对）、`top_ddr_test`（LED：心跳/校准/PASS/FAIL）、ADC/SDC/构建脚本/准备脚本。ModelSim 3/3 PASS（正常、READY_DELAY=2、CORRUPT=1）。TD：Setup **+0.913 ns**、Hold **+0.020 ns**（紧）、3389 slices（15.97%）、0 RAM/0 DSP/31 DRAMHARDCON；位流 SHA `610b0b1f...`。修正了 PHY `usr_clk -> clk_50m` CDC 误报（IP SDC 内追加 DDR 时钟异步组）：修正前 WNS -1.390/Hold -0.239。`check_timing` 仍有 2 个 PLL dummy node、533.600 vs 533.333 频率舍入、22/49 无输入/输出 delay（封装内 DDR/慢速输出，预期）。证据：`verification/static/ddr_test_sim_2026-11-08.md`、`verification/static/top_ddr_test_build_2026-11-08.md`；上板步骤 `verification/board/bringup-ddr-test.md`；证据目录 `verification/board/evidence/20261108_ddr_test/`（NOT RUN）。**下一步：用户烧录看 LED2/LED3**。 |
| 2026-11-08 | **单行 → HDMI 标为 PARTIAL PASS；阶段 2 DDR 开始**。用户上板：LED1/2/3/4 全部符合设计；HDMI 显示单行重复的 480 行，但画面为“左侧宽黑条 + 右侧大面积浅蓝紫”，不是预期 OV5640 内部 8 色条；像素内容正确性未确认。按用户决定暂停彩条/LA 排查，记录为 **PARTIAL PASS（用户口头报告，无照片/电压/LA）**：`verification/board/evidence/20261108_ov5640_line_hdmi/README.md`。DDR 调查更新：数据手册 §2.12 确认 PH1P35MDG324 **封装内 16-bit 512Mb SDRAM**（64 MB，VCCIO_DDR 1.5 V）；TD IP `cfg.csv` 的 `Integrated` 模式对 MDG324 走 **DDR2 512Mb x16**（`DDR2_512M/DDR2_X16`、`ddrphy_cfg_rom_MDG324`、`ap111_ddr2_x16_324.adc`）；参考工程 `build/ref/anlogic-ph1p35-vision` 目标同器件，其 cfg rom/矩阵与 TD MDG324 文件逐字节相同，生成参数 `DDR2_1066`/tCK=1876/CL=7/CWL=6；50 MHz ref 的 PLL 参数用 TD `update_pll` 算出（N=3/M=64/C=2/CLK3=21）。新增阶段 2 任务 L1–L3；下一步 `top_ddr_test` 最小读写测试。 |
| 2026-11-08 | **OV5640 单行 → HDMI 设计/仿真/TD 构建完成（未上板）**。复核现有配置：`0x4300=0x61`（RGB565 高字节先）、`0x4740=0x22`、`0x503D=0x80`（COLOR_BAR）。澄清 2000 是 50 MHz 近似；实测 48 MHz 下 HREF 高 1920、低 1280；高相位 = 1280 有效 + 640 额外，A/B 未定。新增 `ov5640_line_capture`（PCLK 字节计数、窗口 `CAPTURE_START`、行长过滤、写流水）、`line_buffer_dpram`（640×16 双时钟）、`rgb565_to_rgb888`、`ov5640_line_to_hdmi_core`、`top_ov5640_line_to_hdmi`、ADC/SDC/构建脚本。仿真 3/3 PASS（65,920 消隐长高拒绝、1920 接受、CAP_START 0/640、BYTE_SWAP、核心 8 色）；TD：50/48.001/25/125 MHz，Setup **+6.027 ns**、Hold **+0.020 ns**（紧）、821 slices、1 ERAM；`check_timing` HIGH dummy node `cam_sda.ts`（SCCB inout，已上板 Chip ID 验证过同代码）、`cam_sda` 无 input delay、12 个无 output delay。位流 SHA `67eec013...`。**上板未执行**；步骤 `verification/board/bringup-ov5640-line-hdmi.md`。DDR 调查：`docs/display/ddr-investigation.md`。 |
| 2026-11-08 | **HDMI 彩条上板成功（用户报告）**：用户使用 `top_hdmi_colorbar.bit` 在 PH1P35 实物板成功显示 FPGA 内部彩条。证据为用户口头报告，**无照片/电压/LA 记录**；已写入 `verification/board/evidence/20261107_hdmi_colorbar/README.md`，标记 USER-REPORTED PASS。该结果不代表摄像头像素路径或全部 HDMI 电气已通过。**下一步：OV5640 内部彩条 D0–D7 → 单行缓存 → 已验证 HDMI 链路**；并行调查 DDR IP。新增 `top_ov5640_line_to_hdmi` 阶段任务 K1–K7。 |
| 2026-11-07 | **HDMI 彩条独立设计完成（仿真/构建，未上板）**。硬件复核：HDMI1=source，TMDS 对 G16/H16、F17/E18、H14/H13、C17/D18，VCCIO_32=3.3V；记录 8×49.9Ω 上拉、`HDMI_A_5V`/`HDMI_A0_5V` 分离、D6 HPD 锁存、Q17 `+3.3V_HDMI` 上电顺序。TD 6.2.1 无 HDMI IP，第三方 `.enc` 不使用，改自写 TMDS。新增 display RTL/4 个 testbench/独立顶层/ADC/SDC/构建脚本。仿真 4/4 PASS（全帧 800×521）；TD 构建 Setup +5.170 ns / Hold +0.054 ns / 107 slices；`check_timing` HIGH 级 0，8 个 output delay 为 MEDIUM；位流 SHA `60fb0d0d...`。**上板未执行**，按 `verification/board/bringup-hdmi-colorbar.md` 等待用户实测。证据：`verification/static/hdmi_colorbar_sim_2026-11-07.md`、`verification/static/top_hdmi_colorbar_build_2026-11-07.md`、`verification/board/evidence/20261107_hdmi_pin_review/`。 |
| 2026-11-06 | **方向切换：DVP 暂停，转 HDMI 显示彩条**。不再做摄像头彩条；先确认 HDMI1 是 source/output 还是 sink/input，核对 TMDS 候选球位/IO 标准，再做 640×480 内部 8 色条（不接摄像头、不用 DDR）。入口 `docs/display/README.md`，启动 prompt `docs/project/next-session-prompt.md`。 |
| 2026-11-06 | **三通道复核通过（DVP 历史）**：`2026_11_6_PCLK_VSYNK_HREF.atkdl`（50 MS/s，200 ms，3 通道，阈值 1.6 V）实测 VSYNC 30 Hz/33.333 ms/66.66 µs 高，HREF 15 kHz/39.997 µs 高/26.66 µs 低，479 正常行/帧（等效 480）；消隐长高 0.240 ms + 1.066 ms，中间 66.7 µs 低与 VSYNC 重合。2026-10-28 的 29.53 kHz 未复现。PCLK 50 MS/s 欠采样为 2 MHz 混叠，不能单独证明 48 MHz。新增 `tools/extract_atkdl.pl`、`tools/analyze_dvp_sync.pl`；`top_dvp_test_20261106_colorbar.bit` 是摄像头彩条旧副本，当前不用于 HDMI。DVP 暂停，摄像头彩条延后。证据：`verification/board/evidence/20261106_dvp_3ch_recheck/`。 |
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
