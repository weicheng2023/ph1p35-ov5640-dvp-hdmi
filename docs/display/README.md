# HDMI 显示彩条：实现与验证

> **当前状态（2026-11-09）**：
> - **HDMI 彩条已上板成功（用户报告）**：用户使用
>   `top_hdmi_colorbar.bit` 在 PH1P35 实物板成功显示 FPGA 内部 8 色条。
>   证据为用户口头报告，**没有照片/电压/LA 记录**；见
>   `verification/board/evidence/20261107_hdmi_colorbar/README.md`。
> - 该 PASS **不代表** OV5640 摄像头彩条、全部 TMDS 电气或长期稳定性。
> - 独立 HDMI 彩条 RTL/仿真/TD 构建均通过：640×480 59.981 Hz，
>   Setup +5.170 ns / Hold +0.054 ns / 107 slices。
> - **OV5640 单行 → HDMI：PARTIAL PASS（2026-11-08 用户报告）**：
>   单行采集与 HDMI 显示初步连通，LED 全对；画面左黑条 + 右浅蓝紫，
>   非预期 8 色条；像素内容正确性未确认。证据：
>   `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`。
> - **阶段 2 DDR 帧缓存：STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09
>   用户报告）**。测试图 → DDR → HDMI 已完整显示。关键修复：PAXI
>   原生地址单位是 16-bit word，128-bit 块 `ADDR_STEP=8`；全写掩码
>   高有效（`16'h0000`）；AW 接受后下一周期给 WVALID；并修复 gearbox
>   块边界 FIFO pop 晚一拍。ModelSim 12/12 PASS（CRC `F53A4D4F`），
>   TD Setup +0.110 / Hold +0.020 ns、5283 slices；位流
>   `top_ddr_fb_hdmi_paxi_fix_20261109.bit`（SHA `e83d9c54…`）。
>   CAL_EN=0 仍是实验配置，不证明完整 PHY 校准或长期稳定性。
>   详见 `docs/display/ddr-framebuffer-bringup.md`；
>   证据 `verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`。
> - **下一阶段：Stage 3（OV5640 → DDR 双缓冲 → HDMI 实时帧）**，
>   见 `docs/project/next-session-prompt.md`。
>
> 保留已验证的 PLL、TMDS 编码/串行化、HDMI 时序，不要无故重写。

## 1. 目标与边界

第一阶段只证明：

1. FPGA 能独立产生正确的 640×480 视频时序；
2. 内部 8 色竖条经 TMDS 送到 HDMI 显示器；
3. 显示器稳定显示，无摄像头、无 DDR。

不做：720p/1080p、摄像头画面、DDR 帧缓存、HDMI 音频/InfoFrame/HDCP、
EDID 读取、热插拔检测。

## 2. 路线选择：为什么自写 TMDS

先调查了“方案 A：直接用厂商 HDMI IP 的测试图案（TPG）”：

- TD 6.2.1 安装目录 `ip/`、`ip/depot/` 中**没有 HDMI Transmitter IP**；
  `find -iname "*hdmi*"` 无结果。
- 第三方参考工程
  `build/ref/anlogic-ph1p35-vision` 里有一个
  `hdmi_1_4b_transmitter_core_wrapper.enc.v`（厂商加密 IP），
  但该仓库没有 LICENSE，本地 TD 也没有对应文件。
  **不复制、不修改、不破解、不再分发**。
- 因此方案 A 在本机不可用。改用 **方案 B：自写 DVI-compatible TMDS
  编码器 + 10:1 DDR 串行器**，PHY 使用 TD 已提供的
  `PH1P_LOGIC_ODDR` 原语，时钟使用 `PH1P_PHY_PLL_V2`。

参考工程只用于确认**同一器件 PH1P35MDG324** 的 P 端球位/TMDS33 用法
（`user_source/constraints_source/pin.adc`），没有把它的 RTL 复制进本仓库。

## 3. 引脚

**不再在本文重复引脚表。** 唯一有效表：
[`docs/hardware/wiring.md` §8](../hardware/wiring.md#8-hdmi1p06_hdmi1引脚与方向)。

要点：

- 差分对：**G16/H16、F17/E18、H14/H13、C17/D18**。
- 只约束 P 端（G16/F17/H14/C17），`IOSTANDARD = TMDS33`，N 端由 TD
  按差分对推断（参考工程同样只约束 P 端）。
- BANK32 的 `VCCIO_32 = VCC_3V3`。
- DDC/HPD 本阶段不使用。

## 4. 架构

```text
clk_50m (C4)
  └─ pll_hdmi (PH1P_PHY_PLL_V2)
       ├─ pixel_clk  = 25.0 MHz
       └─ serial_clk = 125.0 MHz   (5 x pixel，DDR -> 250 Mbps/lane)

top_hdmi_colorbar
  ├─ video_timing.v      800x521 计数器, DE/HS/VS
  ├─ color_bar.v         8 条 80px 竖条 RGB888
  ├─ tmds_encoder.v x3   TMDS 8b/10b + 控制码
  ├─ serial_load_gen.v   每个 pixel 一个 load 脉冲
  ├─ tmds_serializer.v x4 10:1 DDR（PH1P_LOGIC_ODDR）
  └─ 4 对 TMDS 输出（只声明 P 端）
```

### 4.1 视频时序

| 参数 | Horizontal | Vertical |
|---|---:|---:|
| Active | 640 | 480 |
| Front porch | 16 | 10 |
| Sync | 96 | 2 |
| Back porch | 48 | **29** |
| Total | 800 | **521** |

- 像素时钟 **25.0 MHz**：25.0e6 / (800×521) = **59.981 Hz**。
- HSYNC/VSYNC **低有效**。
- DE 有效区 640×480；每帧 307,200 个有效像素。
- 8 条竖条每条 80 像素：白/黄/青/绿/品红/红/蓝/黑。

**为什么 V total 是 521 而不是 DMT 的 525？**

PH1P 的整数 PLL（C0 反馈、VREF ≥10 MHz）能干净锁定的像素时钟是
**25.0 MHz**，不是 25.2 MHz。25.0e6/(800×525) = 59.524 Hz，超出常用
±0.5% 的 VESA 窗口；把垂直后肩从 33 行减到 29 行，得到
25.0e6/(800×521) = **59.981 Hz**，误差 0.03%。有效像素、同步宽度、
同步位置都不变，只少了 4 行后肩消隐。这是**有记录的取舍**，不是
“50 MHz ÷ 2 然后声称 60 Hz”。

### 4.2 时钟与 PLL

- PLL 用 **C0 反馈**（`FBKCLK=CLKC0_EXT`, `FEEDBK_MODE=NORMAL`）：
  C0 = 50 × 1 / 2 = 25.0 MHz；VCO = 25.0 × 50 = 1250 MHz；
  C1 = 1250 / 10 = 125.0 MHz。
- 为什么不用 25.2 MHz：
  - 精确 25.2 需要 C0 = 50 × M/N，M/N = 63/125。C0 反馈下
    VREF = 50/125 = 0.4 MHz，低于 TD 的 10 MHz 下限；
  - 25.2 的 VCO 反馈（N=5/M=126）和 fractional-N 配置在 TD 厂商
    PLL 功能模型中**都不能 lock**；25.0 MHz 整数 C0 反馈能 lock
    （约 120 µs），并输出精确的 40.000 ns / 8.000 ns。
- TD 时序报告：clk0 25.000 MHz、clk1 125.000 MHz、clk2 50.000 MHz。
- 厂商 PLL 功能模型的结果记录在
  `verification/static/hdmi_colorbar_sim_2026-11-07.md` §7；它验证的是
  配置/锁定趋势，不是硅片抖动或 IO 电气。

### 4.3 TMDS 通道映射

| 通道 | 数据 | 控制（DE=0） | 差分对 |
|---|---|---|---|
| 0 | Blue[7:0] | {VSYNC, HSYNC} | G16/H16 |
| 1 | Green[7:0] | 2'b00 | F17/E18 |
| 2 | Red[7:0] | 2'b00 | H14/H13 |
| CLK | — | 10'b0000011111 | C17/D18 |

- 控制码：00→1101010100，01→0010101011，10→0101010100，
  11→1010101011（DVI 1.0）。
- 编码器 `dout[0]` 是**最先发送**的位；串行器先发 `din[0]`。
- `PH1P_LOGIC_ODDR` 的 `d0` 在 posedge、`d1` 在 negedge 输出；
  两个位都在 posedge 采样（见仿真模型注释）。

## 5. 文件

| 文件 | 作用 |
|---|---|
| `fpga/rtl/display/video_timing.v` | H/V 计数器、DE/HS/VS |
| `fpga/rtl/display/color_bar.v` | 8 色竖条 |
| `fpga/rtl/display/tmds_encoder.v` | TMDS 8b/10b 编码 |
| `fpga/rtl/display/tmds_serializer.v` | 10:1 DDR 串行化（PH1P_LOGIC_ODDR） |
| `fpga/rtl/display/serial_load_gen.v` | 共享 load 脉冲（四通道对齐） |
| `fpga/rtl/display/pll_hdmi.v` | PH1P_PHY_PLL_V2 25.0/125 MHz |
| `fpga/rtl/top/top_hdmi_colorbar.v` | 独立顶层 + LED |
| `fpga/constraints/top_hdmi_colorbar.adc` | 引脚/IO 标准 |
| `fpga/constraints/top_hdmi_colorbar.sdc` | 50 MHz 输入 + 派生 PLL 时钟 |
| `fpga/scripts/build_top_hdmi_colorbar.tcl/.bat` | TD 命令行构建 |
| `fpga/sim/models/pll_hdmi_sim.v` | 仿真用行为 PLL（25/125 MHz） |
| `fpga/sim/models/ph1p_logic_oddr_sim.v` | 仿真用行为 ODDR |
| `fpga/sim/tb/tb_tmds_encoder.v` | 编码器自检 |
| `fpga/sim/tb/tb_tmds_serializer.v` | 位序/串行化自检 |
| `fpga/sim/tb/tb_video_timing.v` | 全帧时序自检 |
| `fpga/sim/tb/tb_top_hdmi_colorbar.v` | 顶层集成自检 |
| `fpga/sim/tb/tb_pll_vendor.v` | 用 TD 厂商 PLL 功能模型检查 25.0/125.0 MHz lock |

## 6. 验证状态

### 6.1 仿真（PASS）

| Testbench | 结果 | 证据 |
|---|---|---|
| `tb_tmds_encoder` | PASS：4 个控制码 + 0x00/0xFF/0x55/0xAA + disparity | `verification/static/hdmi_colorbar_sim_2026-11-07.md` |
| `tb_tmds_serializer` | PASS：5 个 10-bit 字，串行顺序 = din[0..9] | 同上 |
| `tb_video_timing` | PASS：完整 800×521 帧，DE=307200，HS low=50016，VS low=1600 | 同上 |
| `tb_top_hdmi_colorbar` | PASS：8 色值 + 4 个控制码 + TMDS 输出翻转 | 同上 |
| TD 厂商 PLL 功能模型 | PASS：25.0/125 MHz 配置 lock，C0=40.000 ns，C1=8.000 ns | 同上 §7 |

仿真的边界：主仿真用 `fpga/sim/models/` 的行为 PLL/ODDR，
**没有验证厂商 PLL 的环路滤波/抖动/真实 lock**（另用 TD 厂商功能模型
单独验证配置能 lock），也没有验证 IO 电气。这些由 TD 构建和上板
LED2/示波器确认。

### 6.2 TD 构建（PASS）

- 器件 PH1P35MDG324，speed 3，TD 6.2.1。
- Setup WNS **+5.170 ns**，Hold WNS **+0.054 ns**，0 violated endpoints。
- 107 slices（0.50%），0 RAM，0 DSP。
- `check_timing`：0 个 HIGH 级问题；8 个输出无 output delay（4 LED +
  4 TMDS，MEDIUM）。LED 是慢速状态信号；TMDS 内部路径已按 125 MHz
  clk1 分析，但显示器侧没有可引用的 setup/hold 规范，因此没有编造
  output delay。
- 已知 warning：`PHY-5016 PLL clkc is driving an IO without location /
  not driving a clock-capable IO`。这是布局早期对 PLL 输出驱动 IO 的
  通用检查；TMDS 数据脚不是 GCLK 脚，但 ODDR 走的是 IO 内的高速
  opclk。routed 报告显示 clk1 到达 `opclk` 且时序收敛。**仍需上板确认**。
- 位流 SHA-256：`60fb0d0de3aabe36285e1d3cb6ea82bff5e88e271ae18f6374081931c908ef63`。
- 证据：`verification/static/top_hdmi_colorbar_build_2026-11-07.md`。

### 6.3 上板（未执行）

按 `verification/board/bringup-hdmi-colorbar.md` 操作。**不要把本节
当成已通过**；用户实测结果写入
`verification/board/evidence/20261107_hdmi_colorbar/`。

## 7. 给初学者的说明

### 7.1 当前实现了什么？为什么先做这一步？

实现了一个**完全独立于摄像头**的视频源：FPGA 自己数像素、自己产生
行/场同步、自己生成彩条，再按 HDMI 的 TMDS 规则串行发送。

先做这一步，是因为它把“显示链路”从“摄像头链路”里隔离出来：
如果彩条都不显示，问题一定在 HDMI 时钟/TMDS/显示器/供电，而不是
DVP 数据或摄像头寄存器。等彩条稳定后，再把彩条替换成摄像头像素，
排查范围会小很多。

### 7.2 对应什么数字电路知识？

- **视频时序**：用 H/V 计数器把时间轴切成“有效像素/前肩/同步/后肩”。
- **TMDS 编码**：8 位像素 → 10 位字符，用 XOR/XNOR 减少跳变，
  再用 running disparity 选择是否反相，保证直流平衡。
- **串行化**：像素时钟 25.0 MHz，TMDS 位时钟 125 MHz（5×），
  每个串行时钟送 2 位（DDR），10 位正好一个像素。
- **跨时钟/相位**：像素域产生一个 toggle，串行域用边沿检测得到
  每个像素一个 load 脉冲；四个通道共用这个脉冲，保证相位一致。
- **IO 原语**：`PH1P_LOGIC_ODDR` 把最后 2:1 并串放在 IO 单元里；
  `PH1P_PHY_PLL_V2` 产生像素/串行时钟。
- **PLL 取舍**：整数分频能锁 25.0 MHz，不能干净锁 25.2 MHz；
  用 V total 521 把帧率补到 59.981 Hz。

### 7.3 每个模块的输入/输出

| 模块 | 输入 | 输出 |
|---|---|---|
| `video_timing` | pixel_clk, rst | hcount, vcount, de, hs, vs |
| `color_bar` | hcount, de | rgb[23:0] |
| `tmds_encoder` | pixel_clk, rst, din[7:0], ctrl[1:0], de | dout[9:0] |
| `serial_load_gen` | pixel_clk, serial_clk, rst | load |
| `tmds_serializer` | serial_clk, rst, load, din[9:0] | serial_out |
| `pll_hdmi` | clk_50m | pixel_clk, serial_clk, lock |
| `top_hdmi_colorbar` | clk_50m | led[3:0], 4×TMDS P |

### 7.4 用了哪些 FPGA 资源？

- 107 slices（0.50%），128 个寄存器，110 个 LUT（gate 阶段）。
- 1 个 PLL（`PH1P_PHY_PLL_V2`）。
- 4 个 TMDS33 IO（每个含 ODDR/串行化资源）。
- 0 RAM、0 DSP。
- 时钟：50 MHz 输入 + 2 个 PLL 输出（25.0/125.0 MHz）。

### 7.5 怎么判断它是对的？

- 仿真：`tb_video_timing` 数一整个 800×521 帧的 DE/HS/VS；
  `tb_tmds_encoder` 对控制码和已知数据码逐位比对；
  `tb_tmds_serializer` 把串行输出抓回来，确认 din[0] 先发；
  `tb_top_hdmi_colorbar` 检查 8 个色条中心和控制码。
- 构建：Setup/Hold WNS > 0，`check_timing` 无 HIGH 级问题。
- 上板：LED2 = PLL lock，LED3 = 出复位，LED4 ≈ 0.94 Hz 帧翻转；
  显示器出现 8 条竖条。

### 7.6 如果失败，最可能是哪一层？

按这个顺序查，不要跳：

1. **供电/方向**：HDMI pin 18 是否有 5V；`+3.3V_HDMI` 是否建立；
   HPD 是否被锁存（不要只看 HPD 判断插入）。
2. **PLL**：LED2 是否常亮。不亮 → 查 25.0/125 MHz 配置、Q17 供电。
3. **TMDS 引脚/IO**：TD 是否真的把 G16/F17/H14/C17 配成 TMDS33；
   N 端是否配对；`PHY-5016` warning 是否对应实际输出异常。
4. **时序/数据**：像素时钟、DE/HS/VS、控制码、串行位序。
5. **显示器**：输入源是否选对；是否接受无 EDID 的 640×480 59.98 Hz。
6. **电气**：49.9 Ω 上拉后的共模/摆幅；Q17 带载电压。

逻辑分析仪不能直接解码 250 Mbps 的 TMDS 差分信号；不要用普通 LA
去“看”TMDS 数据，应该用示波器看共模/摆幅/时钟。

### 7.7 下一阶段怎么用？

彩条稳定后，把 `color_bar.v` 的输出替换成摄像头像素（RGB565→RGB888），
保持 `video_timing`/`tmds_encoder`/`serializer` 不变。若摄像头分辨率/
时钟与 640×480 不同，需要先做帧缓存/缩放/跨时钟域，再进 HDMI。

## 8. 相关文件

- 引脚事实：`docs/hardware/wiring.md` §8
- 硬件复核：`verification/board/evidence/20261107_hdmi_pin_review/README.md`
- 仿真证据：`verification/static/hdmi_colorbar_sim_2026-11-07.md`
- 构建证据：`verification/static/top_hdmi_colorbar_build_2026-11-07.md`
- 上板步骤：`verification/board/bringup-hdmi-colorbar.md`
- 上板证据目录：`verification/board/evidence/20261107_hdmi_colorbar/`
- **OV5640 单行设计**：`docs/display/ov5640_line_to_hdmi.md`
- **OV5640 单行上板**：`verification/board/bringup-ov5640-line-hdmi.md`
- DDR 调查：`docs/display/ddr-investigation.md`
- 构建/仿真流程：`.claude/skills/fpga-bringup/SKILL.md`

## 9. OV5640 单行 → HDMI（PARTIAL PASS）

完整设计/调查见 `docs/display/ov5640_line_to_hdmi.md`。摘要：

- 摄像头内部彩条（`0x503D=0x80`）→ D0–D7 → 单行 640×16 双时钟
  ERAM → RGB565→RGB888 → 已验证 HDMI/TMDS。
- HREF 高 1920 / 低 1280（48 MHz 实测）；默认取高相位前 1280 字节，
  `CAPTURE_START=640` 取后 1280；`LINE_MIN/MAX` 拒绝 1.373 ms
  消隐长高。
- 仿真 3/3 PASS；TD Setup +6.027 ns / Hold +0.020 ns（紧）/
  821 slices / 1 ERAM；位流 SHA `67eec013...`。
- **上板 PARTIAL PASS（用户报告）**：LED 全对，显示器出现单行重复的
  480 行；但画面是“左黑条 + 右浅蓝紫”，不是预期 8 色条。
- 像素正确性留到 DDR 实时画面阶段；当前转阶段 2 DDR 帧缓存
  （`docs/display/ddr-investigation.md`）。
