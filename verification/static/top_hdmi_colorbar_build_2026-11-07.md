# top_hdmi_colorbar TD 6.2.1 构建证据（2026-11-07）

> 设计：`top_hdmi_colorbar`（640×480，59.981 Hz，8 色竖条）
> 器件：PH1P35MDG324，speed 3
> 工具：Tang Dynasty V6.2.168116
> 构建入口：`fpga/scripts/build_top_hdmi_colorbar.tcl`
>
> **构建通过 ≠ 上板通过。** 本文件只记录综合/布局布线/时序/位流。

## 1. 构建命令

```bat
set TD_HOME=D:\Software\Anlogic\TD_6.2.1
cd /d <repo-root>
fpga\scripts\build_top_hdmi_colorbar.bat
```

等价的命令行：

```bat
"%TD_HOME%\bin\td_commands_prompt.exe" ^
  "<repo-root>/fpga/scripts/build_top_hdmi_colorbar.tcl"
```

流程：

```text
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
read_hdl (top + display RTL)
read_adc top_hdmi_colorbar.adc
optimize_rtl
read_sdc top_hdmi_colorbar.sdc
optimize_gate
legalize_phy_inst
read_sdc
place
route
report_qor / report_timing_summary / check_timing / write_csv
bitgen
```

## 2. PLL 配置与派生时钟

`pll_hdmi.v`：

```text
FIN         = 50.000 MHz
REFCLK_DIV  = 2
FBCLK_DIV   = 1
FBKCLK      = CLKC0_EXT      (NORMAL)
C0          = 50 * 1 / 2 = 25.0 MHz
VCO         = C0 * CLKC0_DIV = 25.0 * 50 = 1250 MHz
C1          = VCO / 10 = 125.0 MHz
VREF        = 25 MHz
LPF_RES=0, LPF_CAP=25, ICP_CUR=29, PLL_FASTLOOP=ENABLE
```

TD 时序报告 Clock Summary：

```text
clk0:  25.000 MHz  u_pll/u_pll.clkc[0]   fanout 38
clk1: 125.000 MHz  u_pll/u_pll.clkc[1]   fanout 33
clk2:  50.000 MHz  clk_50m               fanout 29
```

为什么不是 25.2 MHz：精确 25.2 需要 M/N = 63/125，VREF 只有 0.4 MHz
（低于 TD 的 10 MHz 下限）；25.2 的 VCO 反馈/fractional 配置在 TD
厂商 PLL 功能模型中不能 lock。25.0 MHz 整数 C0 反馈能 lock，并用
V total 521 把帧率补到 59.981 Hz。详见
`verification/static/hdmi_colorbar_sim_2026-11-07.md` §7。

## 3. 时序结果

`top_hdmi_colorbar_final_timing.rpt`：

```text
STA coverage : 99.03%
SWNS         : 5.170 ns
STNS         : 0.000 ns
HWNS         : 0.054 ns
HTNS         : 0.000 ns
Period Check WNS : 0.000 ns
```

- Setup WNS **> 0**，Hold WNS **> 0**。
- 0 violated setup/hold endpoints。
- 最差路径在 clk1（125 MHz）域；clk0（25 MHz）域 slack 更大。

## 4. `check_timing`

生成的报告：`build/bitstream/top_hdmi_colorbar_route.check_timing`
（本地，gitignored）。

```text
1.  no clock                       (0)
2.  clock definition               (0)
3.  dummy node                     (0)
4.  invalid constraint             (0)
5.  pll/clock buffer constraints   (0)
6.  combinational loops            (0)
7.  soft fifo exception            (0)
8.  no path constraints            (0)
9.  shadowed/ignored exception     (0)
10. no input delay                 (0)
11. no output delay                (8)  MEDIUM
12. partial input delay            (0)
13. partial output delay           (0)
14. abnormal input delay           (0)
```

8 个无 output delay 的输出：

```text
led[3], led[2], led[1], led[0],
tmds_clk_p, tmds_d0_p, tmds_d1_p, tmds_d2_p
```

解释：

- LED 是慢速状态信号，不需要严格 output delay。
- TMDS 输出的内部路径已按 125 MHz clk1 分析；显示器侧没有可引用的
  setup/hold 规范，因此**没有编造** output delay。这是 MEDIUM 提示，
  不是 setup/hold 违例。
- `check_timing` 的 HIGH 级项目全部为 0。

## 5. 资源占用

```text
#slices : 107   (0.50%)
#RAMs   : 0
#DSPs   : 0
```

## 6. 已知 warning（必须保留）

```text
PHY-5016 WARNING: PLL clkc is driving an IO without location.
PHY-5016 WARNING: PLL clkc is not driving a clock-capable IO.
```

分析：

- 这是布局早期（Place Fixed Instances）对 PLL 输出驱动 IO 的通用检查。
- TMDS 数据脚 G16/F17/H14/C17 是 `T2` 高速数据脚，不是 GCLK 时钟输入脚；
  ODDR 使用的是 IO 单元内的高速 `opclk`。
- routed 时序报告显示 clk1 到达 `tmds_*_syn_2.opclk`，且 125 MHz 路径
  Setup/Hold 均为正。
- **不能据此宣称 IO 一定正确**；上板必须用 LED2（PLL lock）和示波器/
  显示器确认。若显示器无图像，优先复查此 warning 与 N 端配对。

另一个已消除的 warning：`derive_pll_clocks` 在 TD 6.2.1 被标记 obsolete；
SDC 已改用 `derive_clocks`，派生时钟结果相同，warning 消失。

## 7. 位流

| 项目 | 值 |
|---|---|
| 文件 | `build/bitstream/top_hdmi_colorbar.bit`（本地，gitignored） |
| SHA-256 | `60fb0d0de3aabe36285e1d3cb6ea82bff5e88e271ae18f6374081931c908ef63` |
| 生成时间 | 2026-11-07 |

注意：位流不逐 bit 可复现（布局布线有随机性）；以 RTL/约束/脚本和
QoR 为可复现依据。重新构建的 SHA 可能不同，但时序/资源应一致。

## 8. 构建产物清单（本地）

```text
build/bitstream/top_hdmi_colorbar.bit
build/bitstream/top_hdmi_colorbar_final_timing.rpt
build/bitstream/top_hdmi_colorbar_route.qor
build/bitstream/top_hdmi_colorbar_route.check_timing
build/bitstream/top_hdmi_colorbar_netlist.csv
```

这些文件按 `.gitignore` 不入库。
