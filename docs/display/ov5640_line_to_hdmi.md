# OV5640 单行 → HDMI：设计、调查与验证

> **当前状态（2026-11-08）**：
> - RTL、3 个 ModelSim testbench、TD 6.2.1 构建均已完成。
> - Setup WNS **+6.027 ns**，Hold WNS **+0.020 ns**（紧），
>   821 slices（3.87%），1 个 ERAM。
> - **上板 PARTIAL PASS（用户报告）**：LED1–LED4 全部符合设计；
>   HDMI 显示单行重复的 480 行；但画面为“左侧宽黑条 + 右侧浅蓝紫”，
>   不是预期 8 色条；像素内容正确性未确认。用户已暂停彩条/LA 排查，
>   转阶段 2 DDR。证据：
>   `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`。
>
> 本阶段只验证**一条摄像头图像行**的 D0–D7 数据路径，然后把这行
> 重复显示在 480 行上；不实现完整帧缓存，不接 DDR。

## 1. 为什么先做单行

完整帧缓存需要 DDR 或大容量片上 RAM、帧同步、读写仲裁。
在确认 D0–D7 的**字节顺序、HREF 有效窗口、RGB565 颜色**之前
就做完整帧，会把“数据路径错误”和“帧缓存错误”混在一起。

单行重复显示把问题缩小到：

```text
OV5640 内部彩条
  → DVP D0–D7 / PCLK / HREF
  → 640 个 RGB565 像素
  → 640×16 双时钟行缓存
  → RGB565→RGB888
  → 已验证 HDMI/TMDS
```

只要显示器出现摄像头内部彩条，就说明这条最小路径成立。
它**不**证明 480 行都采集正确，也不证明帧率/完整性。

## 2. 1920 vs 1280：先把这个矛盾说清楚

已有实测与换算：

| 项目 | 数值 | 说明 |
|---|---|---|
| PCLK | **48.000 MHz** | 2026-10-26 LA 实测 |
| HREF 高 | 40 µs ≈ **1920 PCLK** | 50 MHz 假设下会写成 2000 |
| HREF 低 | 26.665 µs ≈ **1280 PCLK** | |
| 行周期 | 66.665 µs ≈ 3200 PCLK | 15 kHz |
| 640 RGB565 像素 | **1280 字节** | 每像素 2 字节 |
| 垂直消隐 HREF 长高 | 1.373 ms ≈ **65,900 字节** | 必须排除 |

所以：

- “2000 PCLK”来自 50 MHz 近似；按实测 48 MHz，高相位是 **1920**。
- 高相位 1920 = 1280 + 640 额外字节；低相位正好 1280。
- **不能直接假设**多出的 640 是无效填充，也不能为了彩条随意丢弃。
- 现有 A/B 两种解释：
  - **A：HREF 低有效** → 低相位 1280 是有效数据，高相位 1920 是消隐。
  - **B：HREF 高有效** → 高相位前 1280 是有效数据，后 640 是 dummy；
    低相位 1280 是消隐。

本设计的选择：

- 默认 `HREF_ACTIVE_HIGH=1`（按用户最新说明“HREF 高有效”）；
- 默认 `CAPTURE_START=0`，取高相位**前 1280 字节**；
- 如果显示器证明有效数据是高相位**后 1280 字节**，改
  `CAPTURE_START=640` 重新构建；
- 用 `LINE_MIN=1200, LINE_MAX=2200` 过滤垂直消隐的 65,900 字节长高；
- **不根据 LED/长度检查宣布 A/B 已定**；以显示器实际彩条为准。

## 3. 数据路径与模块

```text
cam_pclk 域
  D0-D7 + HREF
    └─ ov5640_line_capture
         ├─ 字节计数/窗口选择
         ├─ RGB565 高低字节拼接
         ├─ 行长过滤（拒绝 1.373 ms 消隐长高）
         ├─ 写流水寄存器
         └─ capture_done（冻结）

  line_buffer_dpram（640×16，双时钟 ERAM）
         │
pixel_clk 域（25.0 MHz）
         └─ RGB565→RGB888
              └─ 已验证 tmds_encoder ×3
                   └─ tmds_serializer ×4（125 MHz DDR）
                        └─ HDMI1
```

| 文件 | 作用 |
|---|---|
| `fpga/rtl/camera/ov5640_line_capture.v` | PCLK 域单行采集/字节拼接/行长过滤 |
| `fpga/rtl/common/line_buffer_dpram.v` | 640×16 双时钟行缓存 |
| `fpga/rtl/display/rgb565_to_rgb888.v` | RGB565→RGB888 |
| `fpga/rtl/top/ov5640_line_to_hdmi_core.v` | 行缓存 + 已验证 HDMI 链路 |
| `fpga/rtl/top/top_ov5640_line_to_hdmi.v` | SCCB bringup + core + LED |
| `fpga/constraints/top_ov5640_line_to_hdmi.adc/.sdc` | 引脚/时序 |
| `fpga/scripts/build_top_ov5640_line_to_hdmi.tcl/.bat` | TD 构建 |
| `fpga/sim/tb/tb_ov5640_line_capture.v` | 单行采集自检 |
| `fpga/sim/tb/tb_top_ov5640_line_to_hdmi.v` | 核心集成自检 |

## 4. 关键设计点

### 4.1 HREF 有效窗口

- `ov5640_line_capture` 在 HREF 有效相位内数字节；
- `CAPTURE_START=0` 取窗口 `[0,1280)`，`CAPTURE_START=640` 取
  `[640,1920)`；
- 只在窗口内、低字节（偶/奇配对的后一字节）写 RAM；
- 行长 `line_total` 用 17 位，`LINE_MIN..LINE_MAX` 接受 1280/1920，
  拒绝 65,900 的消隐长高；
- `STARTUP_LINES=3`：接受 3 条有效行后才冻结，避免首行不稳定。

### 4.2 RGB565 字节顺序

- `0x4300=0x61`：RGB565，输出序列 1，**高字节在前**。
- 第一字节 = `{R[4:0],G[5:3]}`，第二字节 = `{G[2:0],B[4:0]}`。
- 默认 `BYTE_SWAP=0`；如果显示器颜色明显错乱，可改 `BYTE_SWAP=1`
  重新构建，而不是凭空改 RTL。

摄像头内部彩条寄存器（公开 datasheet 摘录）：

- `0x503D=0x80`：bit7=1 测试使能；bits[3:2]=00 **标准 8 色条**；
  bits[1:0]=00 彩条选择。
- **精确的颜色顺序在可查到的 datasheet 摘录中没有明确给出**，
  不能凭 FPGA 彩条的顺序强行认定；以显示器实际结果为准。
- 配置表没有写 `0x4741`/`0x4745`；它们保持默认。如果彩条顺序/
  数据格式明显不对，再查这两个寄存器的默认值/回读，不要盲目改。
- 应用笔记常把 `0x503D=0x80` 与 `0x4741=0x00` 一起写；本设计
  依赖默认值，并在上板时观察。

### 4.3 行缓存与冻结

- 640×16 双时钟 RAM：写 cam_pclk，读 pixel_clk；
- 接受一条有效行后 `capture_done=1`，停止写；
- `capture_done` 经两级同步进 pixel_clk；
- 未捕获前显示深蓝背景 `0x000040`；
- 捕获后 480 行重复同一行。

这样**不会**出现“摄像头写、HDMI 同时读同一缓存”的撕裂。
代价是画面冻结在一条行；这是本阶段有意的限制。

### 4.4 HDMI 链路

- 复用已验证的 `pll_hdmi`（25.0/125.0 MHz）、`video_timing`
  （800×521，59.981 Hz）、`tmds_encoder`、`tmds_serializer`；
- 没有重写 PLL/TMDS/PHY/约束；
- TMDS 引脚/时序与已上板成功的彩条设计相同。

## 5. 验证状态

### 5.1 仿真（PASS）

| Testbench | 结果 |
|---|---|
| `tb_ov5640_line_capture` | PASS：消隐长高拒绝、1920 有效行、640 像素逐项、冻结、CAP_START=640、BYTE_SWAP=1 |
| `tb_top_ov5640_line_to_hdmi` | PASS：背景、capture_done、8 色条、RGB565→RGB888、读地址对齐 |

证据：`verification/static/ov5640_line_to_hdmi_sim_2026-11-08.md`。

### 5.2 TD 构建（PASS）

```text
clk_50m 50 MHz / cam_pclk 48.001 MHz / pixel 25 MHz / serial 125 MHz
Setup WNS +6.027 ns
Hold  WNS +0.020 ns   (紧，0 violation)
821 slices (3.87%), 1 ERAM
```

`check_timing` 有 1 个 HIGH 的 dummy node（`cam_sda.ts`，SCCB inout
三态节点）和 12 个无 output delay 的慢速输出；详见
`verification/static/top_ov5640_line_to_hdmi_build_2026-11-08.md`。

### 5.3 上板（PARTIAL PASS，用户报告）

- LED1 心跳、LED2 cfg_ok、LED3 capture_done、LED4 灭：全部符合。
- HDMI 显示单行重复的 480 行；但画面是“左侧宽黑条 + 右侧浅蓝紫”，
  不是预期 8 色条；像素内容/字节序/A-B 窗口/±1 像素对齐未确认。
- 用户决定暂停彩条/LA 排查，先进入阶段 2 DDR。
- 结果：`verification/board/evidence/20261108_ov5640_line_hdmi/`。

## 6. 给初学者的说明

1. **实现了什么？** 从摄像头 D0–D7 抓一条行，存进 FPGA 内部 RAM，
   再用已经成功的 HDMI 链路把这行重复显示 480 次。
2. **为什么先做？** 把“摄像头数据/字节顺序”从“完整帧缓存/DDR”里
   隔离出来；显示不对时，只需查 DVP/字节/窗口。
3. **对应什么知识？** DVP 采样、字节配对、双时钟 RAM/CDC、
   有效窗口/行长过滤、RGB565 扩展、HDMI 时序对齐。
4. **输入/输出？** `ov5640_line_capture`：PCLK/HREF/D0–D7 →
   16-bit 写地址/数据/写使能；核心：两路时钟 + 相机 → TMDS。
5. **用了什么资源？** 821 slices、1 个 ERAM、1 个 PLL、
   4 个 TMDS33 IO；0 DSP。
6. **怎么判断对？** 仿真逐像素比对；TD WNS>0；上板看 LED2
   （配置）、LED3（捕获）、LED4（错误）和显示器彩条。
7. **失败最可能在哪层？** 配置/SCCB → HREF 有效窗口 A/B →
   字节顺序 → RAM/CDC → HDMI。
8. **下一阶段？** 完整 480 行 + 帧缓存（DDR 调查报告：
   `docs/display/ddr-investigation.md`），再做实时画面。

## 7. 明确不做

- 不实现完整帧缓存/DDR（本阶段）；
- 不做 720p/1080p、音频、HDCP、EDID；
- 不修改已验证的 HDMI PLL/TMDS/时序；
- 不在未观察显示器结果前宣称摄像头彩条通过。
