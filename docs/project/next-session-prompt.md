# 下一个 session 的启动 prompt（HDMI 显示彩条）

> 把下面整段复制到新对话作为第一条消息。它假设当前工作目录是
> `D:\Projects\02_Personal_Practice\2026_10_OV5640`，分支
> `dvp-3ch-recheck-20261106`（PR #3），DVP 部分已暂停。

---

你接手 PH1P35 × ATK-MC5640 项目。**方向已切换：不再做摄像头 DVP 彩条。**
DVP 三通道已在 2026-11-06 复核通过（VSYNC 30 Hz、HREF 15 kHz、480 行），
现在暂停摄像头部分。现在开始 **FPGA 内部彩条 → HDMI 显示器** 的最小显示
链路：不接摄像头、不用 DDR、不改 DVP RTL/寄存器。

## 先读

1. `AGENTS.md` — 项目事实、规则、坑点
2. `TASKS.md` — 当前里程碑/阻塞
3. `docs/hardware/wiring.md` — 板卡/接口
4. `docs/display/README.md` — HDMI 彩条规划（本阶段入口）
5. `.claude/skills/fpga-bringup/SKILL.md` — TD/ModelSim/调试流程

## 当前状态

- SCCB Chip ID `0x5640` 已上板验证；DVP 三通道 VSYNC 30 Hz / HREF 15 kHz /
  480 行已复核。摄像头 DVP **暂停**，不要改 `ov5640_*`、`dvp_*`、
  `top_dvp_test.*`、`0x4740/0x503D/0x4300` 等。
- HDMI **还没有 RTL**；`fpga/rtl/display/` 和 `docs/display/` 为空。
- 板卡：PH1P35_FT V1 / HX1P35B_FT_40P，FPGA **PH1P35MDG324**；
  TD 6.2.1；ModelSim SE-64 2020.4；板载 50 MHz 时钟 **C4**。
- 当前 PR #3 只记录 DVP 3 通道复核；不要把它当成 HDMI 实现。

## 目标（第一阶段）

在 **不接摄像头** 的情况下，用 FPGA 内部产生的 **8 色竖条** 驱动 HDMI
显示器：

- 先做 **640×480@60**（像素时钟 25.175/25.2 MHz），DVI-compatible TMDS
  （只发视频/控制码，不做音频/InfoFrame/HDCP）。
- 8 条竖条，RGB888；显示器稳定显示即可。
- 720p/1080p、摄像头画面、DDR 帧缓存都留到后面。

## 第一步：先核对，不要先写 RTL

### 1. HDMI1 是 source/output 还是 sink/input？

看板卡原理图 **P06_HDMI1**（PDF 第 8 页，`HX1P35B_FT_40P_7.pdf`）：
连接器有 TMDS D0/D1/D2/CLK、+5V、HPD、DDC(SCL/SDA)、CEC、屏蔽地。
**仅凭连接器外形不能判断方向。** 先看：

- +5V 是板子输出给显示器，还是显示器/源输入给板子；
- TPS2051B 的 IN/OUT 方向；
- HPD 是 FPGA 驱动还是 FPGA 读取；
- DDC 电平转换方向。

如果 HDMI1 是 **sink/input-only**：不要写 TMDS 输出 RTL，先停下来报告，
并给出“需要外接 HDMI 发送器/换板/换接口”的结论。不要用 GPIO 硬凑 TMDS。

### 2. TMDS 候选球位/IO 标准（必须核对，不要直接写约束）

从 FPGA 页（`HX1P35B_FT_40P_2.pdf`，sheet 3）读到的**候选**：

| 信号 | 候选球位 | 备注 |
|---|---|---|
| HDMI1_D0_P / N | H16 / F17 | IO_R8P/N_32,T2 |
| HDMI1_D1_P / N | E18 / H14 | IO_R9P/N_32,T2 |
| HDMI1_D2_P / N | H13 / C17 | IO_R10P/N_32,T2_DQS |
| HDMI1_CLK_P / N | D18 / G15 | IO_R11P/N_32,GCLKIOT0/C0,T2 |

必须核对 BANK32 的 VCCIO、板上 49.9 Ω/AC 耦合、TD 是否支持这些球的
TMDS/OSERDES/DDIO；DDC/HPD/5V/GND 的球位/针脚也要逐脚从原理图确认。
**禁止凭网络名/连接器外形写 `.adc`。**

### 3. 时钟/资源

- 50 MHz C4 → PLL 产生像素时钟和 TMDS 位时钟。
- 640×480@60：H 800/640，H front/sync/back 16/96/48；
  V 525/480，V front/sync/back 10/2/33；H/V 负极性。
- TMDS 10:1 位时钟 ≈ 251.75 MHz（若用 5× DDR 则 125.875 MHz）。
- 确认 PH1P35 的 PLL/OSERDES 能到所需频率；不能到就降低分辨率/换方案，
  不要用“仿真通过”掩盖硬件做不到。

## 任务清单

1. 写 `verification/board/evidence/YYYYMMDD_hdmi_pin_check/README.md`：
   HDMI1 方向、TMDS 球位、IO 标准、DDC/HPD/5V/GND、依据（原理图页/高 DPI
   截图/万用表）。**先完成这一步再写 RTL。**
2. 设计 `fpga/rtl/display/`：
   - `video_timing.v`：640×480 H/V 计数器、active/DE/HS/VS；
   - `color_bar.v`：8 色竖条 RGB888；
   - `tmds_encoder.v`：8b/10b + control（DE/HS/VS）；
   - `tmds_serializer.v`：10:1（OSERDES/DDIO）×3 data + 1 clock；
   - `top_hdmi_colorbar.v`：PLL、连接、LED 心跳/错误。
3. `fpga/sim/tb/`：真实时序仿真；检查 H/V 周期、DE 宽度、TMDS 控制码、
   8b/10b 编码；不要用简化时钟/假时序。
4. `fpga/constraints/`：`.adc` 引脚/IO 标准、`.sdc` 像素/位时钟；TD 6.2.1
   命令行构建；WNS>0；位流本地保存。
5. 上板：Program SRAM → 接 HDMI 显示器 → 记录 8 色条/分辨率/稳定性。
   无显示时按顺序查 HPD、DDC/EDID 5V、TMDS 差分/共模、像素时钟、GND/屏蔽、
   显示器输入源。
6. 证据放 `verification/board/evidence/YYYYMMDD_hdmi_colorbar/`；更新
   `TASKS.md`、`README.md`、`AGENTS.md`、skill；提交 PR。

## 约束

- **不改摄像头/DVP**：不接摄像头；不改 `ov5640_*`、`dvp_*`、
  `top_dvp_test.*`、`0x4740/0x503D/0x4300`。
- 不提交 PDF、bitstream、TD 日志、`build/`。
- 不猜引脚；用 `pdftotext -table` + 高 DPI 原理图截图 + 通断/上电测量。
- 不简化时序仿真来“通过”。
- 第一版只做 DVI-compatible TMDS；HDMI 音频/InfoFrame/HDCP 不做。
- 如果 HDMI1 是 input-only，停止并报告，不要改板/飞线。

## 验收

- HDMI 显示器稳定显示 640×480@60 的 8 色竖条；
- 摄像头未连接，DVP RTL/配置未改；
- TD 时序 WNS>0，bitstream 可复现；
- 有引脚/方向核对记录、仿真记录、上板证据。
