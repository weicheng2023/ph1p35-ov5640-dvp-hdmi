# top_ddr_fb_hdmi_wbuf TD 6.2.1 构建（2026-11-09）

## 设计

- 顶层：`fpga/rtl/top/top_ddr_fb_hdmi_wbuf.v`
- 核心：`ddr_fb_hdmi_core #(.USE_WBUF(1))`（参数化，默认 0 不改变原工程）
- 新 gearbox：`fpga/rtl/ddr/pixel_gearbox_wbuf.v`
- DDR/HDMI 其余部分与 `top_ddr_fb_hdmi` 完全一致：厂商 DDR2 512Mb x16 IP、
  `CAL_EN=0`、50 MHz 参考、25/125 MHz HDMI PLL、TMDS、视频时序、PAXI 协议、
  ADC/SDC（复用 `top_ddr_fb_hdmi.adc/.sdc`，实例路径仍为 `u_core/u_hdmi_pll/u_pll`）。
- 构建脚本：`fpga/scripts/build_top_ddr_fb_hdmi_wbuf.tcl` / `.bat`。

**注意：新 tcl 必须用 CRLF 行尾。** 首次用 LF 行尾时 TD 执行到
`read_adc` 时变量为空（`read_adc `），ADC 未加载，`MapIO` 报
`SYN-8228`（TMDS ODDR 无法映射）。改成 CRLF 后正常，ADC 加载
`Map 54 IOs`。

## 输出（本地，git-ignored）

| 文件 | 说明 |
|---|---|
| `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109.bit` | 试验位流，SHA-256 `1f14bce535b429630ed22599a2b801f9d2f6cdd681da9e45019d110ee8c3ee7b` |
| `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_final_timing.rpt` | 时序报告 |
| `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_route.qor` | QoR |
| `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_route.check_timing` | check_timing |
| `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109_netlist.csv` | 网表 |

原上板位流**未被覆盖**：
`build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit`,
SHA-256 `e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`
（构建后复核，未变）。

## 时序与资源

TD 6.2.1，PH1P35MDG324，speed 3，Routed，STA coverage 93.58%。

| 项目 | WBUF 试验 | 原 `top_ddr_fb_hdmi_paxi_fix` |
|---|---|---|
| Setup WNS | **+0.218 ns** | +0.110 ns |
| Hold WNS | +0.020 ns | +0.020 ns |
| 违例端点（setup/hold） | 0 / 0 | 0 / 0 |
| slices | **4547（21.43%）** | 5283 |
| ERAM | **4** | 0 |
| 分布式 RAM（mslice 计数） | 288 | 800 |
| DSP | 0 | 0 |
| DRAMHARDCON | 36 | 100 |

各时钟（C-Freq / SWNS / HWNS）：

| 时钟 | 频率 | SWNS | HWNS |
|---|---|---|---|
| `u_ddr2/usr_clk`（dhi_clk） | 133.351 MHz | +0.218 | +0.020 |
| `pixel_clk` | 25.000 MHz | +10.896 | +0.055 |
| `serial_clk` | 125.000 MHz | +5.994 | +0.058 |
| `clk_50m` | 50.000 MHz | +13.831 | +0.020 |

`pixel_clk` 组最差路径（29.725 ns 余量）的终点是 TMDS 编码器输入端，
起点是 WBUF 的 `word_buf`/`underflow` 寄存器，说明 FIFO 读数据已经不在
“RAM→MUX→转换→编码器”的同一组合路径上。

### 重要：FIFO 存储实现变了

TD 在本试验顶层把 `u_core/u_fifo`（128-bit × 256，异步读 FWFT）推断成
**4 块 ERAM**（`ramread0_syn_*` 类型 `eram`，读口 `clkb/addrb`，同步读），
而原上板工程把同一 FIFO 推断成 **800 个分布式 RAM mslice**。仿真无法
区分这两种映射；TD 的推断在语义上等价于“读地址寄存器 + 输出即
`word_buf`”，但板上试验因此同时改变了：

1. 像素流水线结构（本次要测的变量）；
2. 显示 FIFO 的存储/读端口实现（LUTRAM → ERAM）。

如果毛刺消失，需要再做一个“`(* ram_style = "dram" *)` 强制分布式 RAM”的
对照构建，才能把原因归到流水线还是 LUTRAM 读端口。

## check_timing

HIGH 级：no-clock 0、clock definition 0、**dummy node 2**（未用 PHY 输出
+ 悬空 `pllreset`，与原工程同类）、invalid constraint 0、PLL/clock-buffer
clock constraint 1、combinational loop 0、soft FIFO exception 0。
MEDIUM：no input delay 22、no output delay 53（封装内 DDR / 慢速 LED/TMDS 输出，
无板级 IO 时序规范）。**不是时序签收。**

## 复现

### GUI 查看/编辑工程

`fpga/project/top_ddr_fb_hdmi_wbuf.al`（TD 6.2.1：File → Open Project）。
文件列表与 tcl 构建列表一致：**17 个设计 Verilog + 35 个厂商 DDR2 IP RTL
+ `top_ddr_fb_hdmi.adc/.sdc`**，共 52 个 Verilog，顶层 `top_ddr_fb_hdmi_wbuf`。
`u_ddr2 → ph1p_ddrmc_wrapper_63f4ac254419 → ph1p_ddrmc_top ...` 可在层次里展开。

只排除 `build/ddr_ip/ddr2.v`：它和 `fpga/rtl/ddr/ddr2_top.v` 都定义模块
`ddr2`，且我们的 wrapper 是 50 MHz 参考时钟 + `CAL_EN` 的定制版；IP XML
（`ddr2.xml`）指向的也是同名模块，所以不能和 `ddr2_top.v` 同时加入。

**GUI 只用于浏览/编辑，出位流必须走 tcl/bat**：本设计的 DDR 引脚分配来自
`read_ip_adc -ip ddr2`（`ddr2.adc` 里的 `set_ippin_assignment ddr2(...)`），
P&R 前还要 `legalize_phy_inst`，这两步只在命令行流程里有。
`pixel_gearbox.v` 在 GUI 里可能显示为灰色 `AutoExcluded`：`USE_WBUF=1` 时
核心实例化的是 `pixel_gearbox_wbuf`，未被选中的 generate 分支会被 TD 自动排除，
文件并没有丢。

TD 打开后会把 `<Project Path=".">` 改成绝对路径，提交前要改回 `"."`。

### 命令行

```bat
cd /d <repo-root>
fpga\scripts\build_top_ddr_fb_hdmi_wbuf.bat
```

或（脚本已带 CRLF）：

```bat
"%TD_HOME%\bin\td_commands_prompt.exe" fpga/scripts/build_top_ddr_fb_hdmi_wbuf.tcl
```

前置条件：`build/ddr_ip/` 已由 `fpga/scripts/prepare_ddr_ip.sh` 准备好。
