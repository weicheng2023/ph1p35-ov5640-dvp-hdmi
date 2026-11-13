# HDMI 彩条仿真证据（2026-11-07）

> 工具：ModelSim SE-64 2020.4
> 设计：`top_hdmi_colorbar`（640×480，59.981 Hz，8 色竖条）
> 位置：本地 `build/sim_hdmi2/`（波形/数据库不入库）
>
> 本文件记录**实际执行的仿真**与结果。仿真通过 ≠ 上板通过。

## 1. 仿真环境与边界

- 编译命令（示意）：

```tcl
vlib work
vlog -sv fpga/sim/models/pll_hdmi_sim.v \
        fpga/sim/models/ph1p_logic_oddr_sim.v \
        fpga/rtl/display/video_timing.v \
        fpga/rtl/display/color_bar.v \
        fpga/rtl/display/tmds_encoder.v \
        fpga/rtl/display/tmds_serializer.v \
        fpga/rtl/display/serial_load_gen.v \
        fpga/rtl/top/top_hdmi_colorbar.v \
        fpga/sim/tb/tb_top_hdmi_colorbar.v
vsim -c -do "run -all; quit" work.tb_top_hdmi_colorbar
```

- **主仿真用行为模型**：
  - `fpga/sim/models/pll_hdmi_sim.v`：1250 MHz 行为 VCO，分频出
    25.0/125.0 MHz，10 µs 后 lock。它不验证真实 PLL 的环路滤波/抖动。
  - `fpga/sim/models/ph1p_logic_oddr_sim.v`：行为 ODDR，d0/d1 都在
    posedge 采样，d0 在高相位输出、d1 在低相位输出。它不验证 IO 延迟、
    摆幅、差分 N 端。
- **额外的 PLL 配置验证**：用 TD 自带的
  `sim_release/ph1p/ph1p_phy_pll_v2.v` 功能模型单独跑 PLL
  （见 §7）。它不是主仿真的 PLL 模型，也不代表硅片抖动/IO 电气。

## 2. 结果汇总

| Testbench | 结果 | 关键输出 |
|---|---|---|
| `tb_tmds_encoder` | **PASS** | 4 个控制码 + 4 个数据码 + disparity |
| `tb_tmds_serializer` | **PASS** | 5 个字，串行顺序 = din[0..9] |
| `tb_video_timing` | **PASS** | 1 帧 = 800×521，DE=307200，HS low=50016，VS low=1600 |
| `tb_top_hdmi_colorbar` | **PASS** | 8 色 + 4 控制码 + TMDS 翻转 |
| TD 厂商 PLL 功能模型 | **PASS**（配置 lock） | 25.0/125 MHz，C0=40.000 ns，C1=8.000 ns |

## 3. `tb_tmds_encoder` 详细结果

```text
ok   ctrl=00: dout=1101010100
ok   ctrl=01: dout=0010101011
ok   ctrl=10: dout=0101010100
ok   ctrl=11: dout=1010101011
ok   data=00: dout=0100000000
ok   data=ff: dout=1000000000
ok   data=55: dout=0100110011
ok   data=aa: dout=1000110011
ok   disparity sequence
TB: PASS - tmds_encoder
```

检查点：

- 控制码与 DVI 1.0 表一致。
- `din=0x00`、`0xFF`、`0x55`、`0xAA` 在 `cnt=0` 时的精确 10 位输出。
- 连续两个 `0x00` 走 running-disparity 的反相分支（第二个为
  `1111111111`）。
- 输出无 X/Z。

## 4. `tb_tmds_serializer` 详细结果

```text
ok   din=1011001110 -> serial=1011001110
ok   din=0000011111 -> serial=0000011111
ok   din=0100000000 -> serial=0100000000
ok   din=1111111111 -> serial=1111111111
ok   din=0010110101 -> serial=0010110101
TB: PASS - tmds_serializer
```

检查点：

- 10 个串行位按 `din[0]` 到 `din[9]` 的顺序输出（DVI LSB-first）。
- `0000011111` 是 TMDS 时钟通道的 5 高/5 低图案。
- 覆盖了全 0、全 1、控制码图案。

## 5. `tb_video_timing` 详细结果

```text
TB: PASS - video_timing, 1 frame = 800x521, de=307200, hs_low=50016, vs_low=1600
```

检查点（**完整 800×521 帧，不是缩短帧**）：

- `hcount` 范围 0..799，`vcount` 范围 0..520。
- `de = (h<640) && (v<480)`，每帧 307,200 个有效像素。
- HSYNC 低有效，位置 656..751，每行 96 个时钟；521 行共 50,016。
- VSYNC 低有效，位置 490..491，2 行；800×2 = 1,600 个时钟。
- 帧末 `(799,520)` 正确回卷。
- 25.0 MHz / (800×521) = 59.981 Hz。

## 6. `tb_top_hdmi_colorbar` 详细结果

```text
PLL locked, reset released at t=10300000000
ok   h=40 rgb=ffffff
ok   h=120 rgb=ffff00
ok   h=200 rgb=00ffff
ok   h=280 rgb=00ff00
ok   h=360 rgb=ff00ff
ok   h=440 rgb=ff0000
ok   h=520 rgb=0000ff
ok   h=600 rgb=000000
ok   ctrl h=700 v=0 ch0=0101010100
ok   ctrl h=40 v=490 ch0=0010101011
ok   ctrl h=700 v=490 ch0=1101010100
ok   ctrl h=100 v=480 ch0=1010101011
TMDS clock edges=3203796, channel0 edges=3156284
TB: PASS - top_hdmi_colorbar
```

检查点：

- PLL lock 后复位释放。
- 第 0 行的 8 个色条中心值：白/黄/青/绿/品红/红/蓝/黑。
- 通道 0 的 4 种控制码：
  - `v=0,h=700`：HSYNC 低、VSYNC 高 → ctrl 10 → `0101010100`
  - `v=490,h=40`：HSYNC 高、VSYNC 低 → ctrl 01 → `0010101011`
  - `v=490,h=700`：两者低 → ctrl 00 → `1101010100`
  - `v=480,h=100`：两者高 → ctrl 11 → `1010101011`
- TMDS 时钟和数据通道都在翻转（不是 stuck）。

## 7. TD 厂商 PLL 功能模型（配置验证）

模型：`D:\Software\Anlogic\TD_6.2.1\sim_release\ph1p\ph1p_phy_pll_v2.v`
（TD 自带，非加密）。

可复现的检查 TB：`fpga/sim/tb/tb_pll_vendor.v`。

```tcl
vlog -sv $TD_HOME/sim_release/ph1p/ph1p_phy_pll_v2.v \
         fpga/sim/tb/tb_pll_vendor.v
vsim -c -do "run -all; quit" work.tb_pll_vendor
```

期望：

```text
ok   PLL lock = 1
ok   C0 period = 40.000 ns
ok   C1 period = 8.000 ns
TB: PASS - pll_vendor (25.0/125.0 MHz, lock)
```

下面的被否决配置是本地 ad-hoc 参数扫描的结果，没有单独入库的 TB。

### 7.1 采用的配置（PASS）

```text
FIN=50 MHz, REFCLK_DIV=2, FBCLK_DIV=1
FBKCLK=CLKC0_EXT, FEEDBK_MODE=NORMAL, PLL_FEED_TYPE=EXTERNAL
CLKC0_DIV=50, CLKC1_DIV=10
LPF_RES=0, LPF_CAP=25, ICP_CUR=29, PLL_FASTLOOP=ENABLE
```

结果：

```text
lock at 120us = 1
C0 period = 40.000 ns (expect 40.000)
C1 period = 8.000 ns (expect 8.000)
```

### 7.2 被否决的 25.2 MHz 配置（FAIL）

同模型下，以下配置在 150 µs 内 **lock=0**：

```text
25.2 MHz VCO feedback (N=5, M=126, NOCOMP)           -> lock=0
25.2 MHz VCO feedback + PLL_FEED_TYPE=INTERNAL       -> lock=0
25.2 MHz fractional C0 feedback (N=5, M=2 + 0.52)    -> lock=0
25.2 MHz fractional C0 feedback (N=1, M=0 + 0.504)   -> lock=0
```

参考工程的 75/375 MHz 配置在同一模型中能 lock（120 µs），说明模型本身
可用；25.2 MHz 的失败不是“模型完全不能用”。

**结论**：采用 25.0/125 MHz 整数 C0 反馈，V total 521 把帧率补到
59.981 Hz。PLL 的真实锁定/抖动仍由板上 LED2 和示波器确认。

## 8. 未覆盖/未证明

- 真实 PLL 的抖动、相位噪声、温度/电压变化下的 lock（功能模型只验证
  配置趋势）。
- 真实 `PH1P_LOGIC_ODDR` 的 IO 时序、摆幅、差分 N 端。
- TMDS33 的板级电气（49.9 Ω 上拉、共模、终端）。
- 显示器对无 EDID 的 640×480 59.98 Hz 的接受度。
- 上板显示结果。

这些必须在 `verification/board/bringup-hdmi-colorbar.md` 中实测。
