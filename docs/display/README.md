# HDMI 显示彩条 — 规划与核对

> **当前方向（2026-11-06）**：摄像头 DVP 部分暂停；先做 **FPGA 内部彩条
> → HDMI 显示器** 的最小显示链路。不接摄像头、不用 DDR。
> 本文是显示阶段的入口；具体上板前必须先从原理图核对引脚/方向/IO 标准。

## 1. 目标

第一阶段只证明：

1. FPGA 能产生正确的 640×480@60 视频时序；
2. 内部 8 色竖条能经 TMDS 送到 HDMI 显示器；
3. 显示器稳定显示，无摄像头、无 DDR。

720p/1080p、摄像头画面、帧缓存、HDMI 音频/InfoFrame 都留到后面。

## 2. 先确认的三件事（不要跳过）

### 2.1 HDMI1 是输出还是输入？

板卡原理图 **P06_HDMI1**（PDF 第 8 页，`HX1P35B_FT_40P_7.pdf`）的
连接器有 TMDS D0/D1/D2/CLK、+5V、HPD、DDC（SCL/SDA）、CEC、屏蔽地。
**仅凭连接器外形不能判断方向**：

- 如果是 **source/output**：FPGA 驱动 TMDS，读 HPD/EDID，显示器显示彩条。
- 如果是 **sink/input**：FPGA 接收 TMDS，连接器 +5V/HPD 由外部源提供；
  这种情况下不能用这块板直接输出彩条，需要外接 HDMI 发送器或换板。

先看原理图的 +5V 电源方向、TPS2051B 的 IN/OUT、HPD 的驱动方向、
DDC 电平转换方向，再用万用表确认（断电测通断，上电测 HPD/5V）。
**确认是 source 之前不要写 TMDS 输出 RTL。**

### 2.2 TMDS 引脚/IO 标准

从 FPGA 页（`HX1P35B_FT_40P_2.pdf`，sheet 3）读到的 **候选**球位：

| 信号 | FPGA 球位 | 备注 |
|---|---|---|
| HDMI1_D0_P | H16 | IO_R8P_32,T2 |
| HDMI1_D0_N | F17 | IO_R8N_32,T2 |
| HDMI1_D1_P | E18 | IO_R9P_32,T2 |
| HDMI1_D1_N | H14 | IO_R9N_32,T2 |
| HDMI1_D2_P | H13 | IO_R10P_32,T2_DQS_P |
| HDMI1_D2_N | C17 | IO_R10N_32,T2_DQS_N |
| HDMI1_CLK_P | D18 | IO_R11P_32,GCLKIOT0,T2 |
| HDMI1_CLK_N | G15 | IO_R11N_32,GCLKIOC0,T2 |

这些是 **候选**，不是已验证约束。必须核对：

- BANK32 的 VCCIO 电压（决定 LVDS/LVCMOS 标准）；
- 49.9 Ω 端接/AC 耦合是否在板上；
- TD 6.2.1 是否支持这些球的 TMDS/OSERDES/DDIO；
- DDC（HDMI1_SCL/SDA）、HPD、+5V、GND、屏蔽地的实际球位/针脚。

**禁止**凭网络名/连接器外形直接写 `.adc`。

### 2.3 时钟/分辨率

第一版建议 **640×480@60**（VGA/DMT）：

| 参数 | 值 |
|---|---|
| 像素时钟 | 25.175 MHz（常用 25.2 MHz 也可，先按显示器接受度） |
| H total / active | 800 / 640 |
| H front / sync / back | 16 / 96 / 48 |
| V total / active | 525 / 480 |
| V front / sync / back | 10 / 2 / 33 |
| 同步极性 | H/V 负极性 |
| TMDS bit clock | 10 × 像素时钟 ≈ 251.75 MHz（若用 5× DDR，则 125.875 MHz） |

板载 50 MHz（C4）→ PLL 产生像素时钟和 TMDS 位时钟。先确认 PH1P35 的
PLL/OSERDES 能到所需频率；如果只能到 720p 的 74.25 MHz 像素/742.5 MHz
位时钟，再评估。

## 3. 建议架构

```text
clk_50m (C4)
  └─ PLL ── pixel_clk (25.175 MHz)
        └─ tmds_clk (×5 或 ×10)
top_hdmi_colorbar
  ├─ video_timing.v     640×480 H/V counters, active/de/HS/VS
  ├─ color_bar.v        8 条竖条 RGB888
  ├─ tmds_encoder.v     8b/10b + control (DE/HS/VS)
  ├─ tmds_serializer.v  10:1 (OSERDES/DDIO) ×3 data + 1 clock
  └─ hdmi_pins          4 differential pairs
```

第一版做 **DVI-compatible TMDS**：只发视频/控制码，不做 HDMI 音频、
InfoFrame、HDCP。大多数 HDMI 显示器会按 DVI 模式接受。

## 4. 上板/验收

1. 断电核对 HDMI1 方向、TMDS/DDC/HPD/5V/GND 通断。
2. TD 引脚报告/IO 标准核对；写 `.adc/.sdc`。
3. ModelSim：时序计数器、DE/HS/VS、TMDS 控制码、8b/10b 编码。
4. TD 6.2.1 综合/布局布线/bitgen；WNS>0。
5. Program SRAM；接显示器；预期 **8 色竖条**（白/黄/青/绿/品红/红/蓝/黑
   或按实现顺序），640×480@60 稳定。
6. 无显示时按顺序查：HPD 是否被显示器拉高、DDC/EDID 是否有 5V、
   TMDS 差分/共模、像素时钟、GND/屏蔽、显示器输入源选择。
7. 证据放 `verification/board/evidence/YYYYMMDD_hdmi_colorbar/`；
   更新 `TASKS.md`、`README.md`、`AGENTS.md`、skill。

## 5. 明确不做

- 不接摄像头、不改 DVP RTL/寄存器；
- 不做 DDR 帧缓存；
- 不做 HDMI 音频/InfoFrame/HDCP；
- 不在未确认 HDMI1 方向/IO 标准前写输出 RTL。

## 6. 相关文件

- 板卡原理图：`docs/hardware/HX1P35B_FT_40P_*.pdf`（本地，不入库）
- 已提取文本：`build/pdf-text/HX1P35B_FT_40P_2.txt`（FPGA 页）、
  `..._7.txt`（HDMI 页）— 仅辅助，最终以高 DPI 原理图为准
- 构建/仿真流程：`.claude/skills/fpga-bringup/SKILL.md`
- 当前状态：`AGENTS.md`、`TASKS.md`
