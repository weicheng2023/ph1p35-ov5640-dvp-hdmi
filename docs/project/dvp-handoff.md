# DVP 阶段交接

> 给下一个对话/开发者的 DVP 开工说明。
> **先读 `AGENTS.md` 和 `TASKS.md`，再读本文件。**
> 当前基线：SCCB Chip ID = `0x5640` 已上板验证；DVP 尚未开始。

## 1. 已验证的基线

- 板卡：PH1P35_FT V1 / HX1P35B_FT_40P，PH1P35MDG324
- 时钟：**C4**，50MHz
- 用户灯：**D10/E10/C6/D6** -> 物理 LED1–4；A5 = GPIOA32
- SCCB：SCL R6/J2-32，SDA T5/J2-33，50kHz，repeated START
- Chip ID：`0x5640`（逻辑分析仪证据在 `verification/board/evidence/`）
- 构建：`fpga/scripts/build_top_cam_id.bat`（TD 6.2.1 命令行）
- 仿真：`fpga/sim/tb/tb_top_cam_id.v`（DIV=250）

DVP 阶段可以复用：

- `fpga/rtl/camera/sccb_master.v`（写寄存器）
- `fpga/rtl/camera/ov5640_id_reader.v` 的上电/复位思路
- `fpga/constraints/top_cam_id.adc/.sdc` 的时钟与 LED 约束
- `fpga/scripts/build_top_cam_id.tcl` 的构建流程

## 2. 还没做

- OV5640 的 DVP 输出格式/分辨率配置（当前只读了 Chip ID）
- PCLK/VSYNC/HREF 的实测与极性确认
- DVP 数据接收、行/场计数
- PCLK 域到系统/HDMI 域的 CDC
- HDMI 输出
- DDR 帧缓存

## 3. 三条必须记住的警告

### 3.1 短脉冲/短持续时间信号

这个项目已经因为“脉冲太短”踩过一次坑：

- reader 的 `sccb_start` 只有 **1 个 50MHz 周期（20ns）**；
- master 只在分频 tick 采样，DIV=250 时漏掉，SCL/SDA 一直不动；
- 修复：`start_pending` 锁存。

DVP 阶段同样要小心：

- **PCLK 可能比系统时钟快**（OV5640 常见 24–84MHz），不要用 50MHz 直接采 PCLK 边沿。
- HREF/VSYNC 的有效宽度按 **PCLK 周期**计，可能很短；不要假设它们会保持多个系统时钟。
- 数据在哪个 PCLK 边沿有效必须以 OV5640 手册/实测为准，不能凭经验。
- 单周期脉冲跨时钟域必须锁存/同步；多比特数据必须用 FIFO 或握手，不能用简单两级触发器。
- 先确定 PCLK 频率，再写时序约束；不要为了“先跑通”加 false path。

### 3.2 PDF 读取位置对齐错误

已经发生过两次：

- J2 右侧网络标签整体偏移，导致一度误判 GND/SCL 接反；
- `P01_FPGA_2` 的 LED/时钟标签偏移，导致把 C4 写成 D4、把 A5 当成 LED。

规则：

1. 读球位优先用 `pdftotext -table`，不要只信 `-layout` 或缩略图。
2. 关键引脚用高 DPI 裁剪（`pdftoppm -r 800/1000`）逐行追踪导线。
3. 交叉检查：引脚能力（是否 GCLK）、板卡丝印、另一个图页、实测。
4. **不要新建第二份引脚表**；修正 `docs/hardware/wiring.md`。
5. 任何“看起来差一行”的映射，先停，用上面三种方法确认。

### 3.3 仿真必须还原真实时序

SCCB 已经出现过“仿真过、硬件挂”：

- testbench 用 `SCCB_DIV=2`，start 脉冲碰巧对上 tick；
- 硬件 DIV=250，脉冲被漏掉。

DVP 仿真要求：

- 使用真实 PCLK 频率（或至少真实分频比），不要用 1/2 分频图省事。
- 生成真实的 VSYNC/HREF 消隐和脉宽，不要只给几个周期。
- 覆盖上电/复位、首个无效帧、行边界、帧边界。
- 异步输入要按真实跨时钟域处理；不要用“同源时钟”简化。
- 观察建立/保持窗口；数据在 PCLK 边沿附近变化时，仿真应能暴露问题。
- 一个只在简化时序下通过的仿真，**不能作为验证证据**。

## 4. DVP 引脚

| 信号 | FPGA 球位 | J2 | 方向 |
|---|---|---|---|
| PCLK | F14 | J2-7 | camera -> FPGA |
| VSYNC | K16 | J2-21 | camera -> FPGA |
| HREF | K17 | J2-20 | camera -> FPGA |
| D0 | K15 | J2-22 | camera -> FPGA |
| D1 | K13 | J2-23 | camera -> FPGA |
| D2 | L15 | J2-24 | camera -> FPGA |
| D3 | L16 | J2-25 | camera -> FPGA |
| D4 | P10 | J2-26 | camera -> FPGA |
| D5 | P9 | J2-27 | camera -> FPGA |
| D6 | P8 | J2-28 | camera -> FPGA |
| D7 | R7 | J2-31 | camera -> FPGA |

注意：D1–D6 在 ATK P1 排针上是交错的，不能按物理相邻顺序推算。
完整表见 `docs/hardware/wiring.md`。

## 5. 建议工作顺序

### 第 1 步：先看默认输出

1. 保持摄像头当前默认配置。
2. 用逻辑分析仪抓 PCLK（J2-7）、VSYNC（J2-21）、HREF（J2-20）。
3. 记录：是否有波形、PCLK 频率、VSYNC/HREF 极性、每帧/每行大致周期。
4. 如果完全没有输出，再进入寄存器配置。

**验收**：有可重复的波形记录/截图，参数写进 `docs/debug/` 或 evidence。

### 第 2 步：配置 OV5640

当前 SCCB master 只读 ID，没有写配置表。需要新增：

- `fpga/rtl/camera/ov5640_cfg.v`（或类似模块）
- 目标格式/分辨率先确认（建议 RGB565 640x480）
- 用 SCCB 写寄存器；参考本机厂商 OV5640 例程的初始化表，但不要整段照抄，
  要记录来源和改动。

**验收**：写配置后能读到预期寄存器值；逻辑分析仪能看到写事务；不破坏 Chip ID 读取。

### 第 3 步：DVP 接收

建议新建：

- `fpga/rtl/camera/dvp_capture.v`
- `fpga/sim/tb/tb_dvp_capture.v`

要点：

- 以 PCLK 为采样时钟（或用足够的过采样，明确写出方案）。
- VSYNC 定帧、HREF 定行；记录行/像素计数。
- 数据位对齐：D0..D7 对应像素位，不要按排针顺序。
- 输出到系统时钟域时用异步 FIFO/握手；不要直接跨域传多比特数据。
- 先输出“帧计数/行计数/像素计数”到 LED 或 UART，确认稳定，再接 HDMI。

**验收**：仿真中帧/行/像素计数与 testbench 注入一致；上板后计数稳定，
逻辑分析仪/证据可复现。

### 第 4 步：HDMI

DVP 数据稳定后再做 HDMI 时序和显示。DDR 帧缓存暂不引入。

## 6. 仿真要求（DVP）

Testbench 至少包含：

- 真实 PCLK 周期（例如 24MHz/48MHz，按实际配置）。
- VSYNC/HREF 的真实前后沿和消隐。
- 多行、多帧，含首帧/边界帧。
- 异步复位和 PCLK 域/系统域交叉。
- 断言：行计数、像素计数、帧边界、无元数据丢失。

建议同时保留一个“最小可观察”仿真（少量像素）用于快速回归，
但**最终验收必须跑真实时序版本**。

## 7. 完成定义

DVP 阶段完成需要同时满足：

- [ ] PCLK/VSYNC/HREF 实测参数有记录。
- [ ] OV5640 配置表有来源和版本记录。
- [ ] DVP 接收仿真在真实时序下通过。
- [ ] TD 综合/布局布线/时序通过。
- [ ] 上板帧/行/像素计数稳定，有 evidence。
- [ ] 没有为了通过而添加未论证的 false path。
- [ ] 文档、TASKS、AGENTS 状态同步更新。

## 8. 待确认

- OV5640 目标输出格式/分辨率（RGB565？640x480？）。
- PCLK 实际频率。
- VSYNC/HREF 极性、数据有效边沿。
- 是否需要外部 SCCB 上拉（当前内部上拉已工作，但 DVP 阶段可复测）。
- 是否使用 DDR 帧缓存（暂不）。
- HDMI 目标分辨率/像素时钟。
