# top_ov5640_line_to_hdmi TD 6.2.1 构建证据（2026-11-08）

> 设计：OV5640 内部彩条 → DVP D0–D7 → 单行缓存 → 已验证 HDMI
> 器件：PH1P35MDG324，speed 3
> 工具：Tang Dynasty V6.2.168116
> 构建入口：`fpga/scripts/build_top_ov5640_line_to_hdmi.tcl`
>
> **构建通过 ≠ 上板通过。** 本文件只记录综合/布局布线/时序/位流。

## 1. 构建命令

```bat
set TD_HOME=D:\Software\Anlogic\TD_6.2.1
cd /d <repo-root>
fpga\scripts\build_top_ov5640_line_to_hdmi.bat
```

流程：

```text
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
read_hdl (top + core + camera + line RAM + display RTL)
read_adc top_ov5640_line_to_hdmi.adc
optimize_rtl
read_sdc top_ov5640_line_to_hdmi.sdc
optimize_gate
legalize_phy_inst
read_sdc
place
route
report_qor / report_timing_summary / check_timing / write_csv
bitgen
```

## 2. 时钟

```text
clk0:  50.000 MHz  clk_50m
clk1:  48.001 MHz  cam_pclk          (约束 20.833 ns)
clk2:  25.000 MHz  u_core/u_pll/...clkc[0]
clk3: 125.000 MHz  u_core/u_pll/...clkc[1]
```

`cam_pclk` 与 HDMI 时钟组异步；双时钟行缓存 + `capture_done`
两级同步是 CDC 机制。SDC 用 `set_clock_groups -asynchronous` 声明，
不是用 false path 掩盖问题。

## 3. 时序结果

```text
STA coverage : 98.39%
SWNS         : 6.027 ns
STNS         : 0.000 ns
HWNS         : 0.020 ns
HTNS         : 0.000 ns
```

- Setup WNS **> 0**，Hold WNS **> 0**，0 violated endpoints。
- **Hold 只有 +0.020 ns，余量很紧**。最差路径：
  `u_core/u_cap/ram_wr_addr_reg[1]` → `u_core/u_line_ram/...addra[11]`
  （cam_pclk 域，ERAM 写地址）。已加一级写流水寄存器；
  如果上板出现数据不稳定，优先复查这条路径/换 RAM 映射。
- 相机输入路径在 cam_pclk 域约束为 10/2 ns（临时值），
  不是实测板级延迟。

## 4. 资源

```text
#slices : 821  (3.87%)
#RAMs   : 1     (line buffer inferred as ERAM)
#DSPs   : 0
```

`line_buffer_dpram` 的 640×16 双时钟数组被推断为 **1 个 ERAM**，
时序报告中的 `ERAM=1` 路径也证实了这一点。

## 5. `check_timing`

```text
1.  no clock                       (0)
2.  clock definition               (0)
3.  dummy node                     (1)  HIGH
4.  invalid constraint             (0)
5.  pll/clock buffer constraints   (0)
6.  combinational loops            (0)
7.  soft fifo exception            (0)
8.  no path constraints            (0)
9.  shadowed/ignored exception     (0)
10. no input delay                 (1)  MEDIUM
11. no output delay                (12) MEDIUM
12. partial input delay            (0)
13. partial output delay           (0)
14. abnormal input delay           (0)
```

### 5.1 dummy node (HIGH)

```text
DummyNode in Model: PH1P_PHY_HD_PAD
    cam_sda_syn_2.ts
```

- `cam_sda` 是 SCCB 双向 inout；`ts` 是 IO pad 的三态控制节点。
- **同一套 `cam_sda` 代码已经在板上验证过 SCCB Chip ID = 0x5640**，
  包括需要摄像头驱动 SDA 的读事务。因此这条 report 目前判断为
  **工具结构检查的已知 artifact**，不是已观察到的功能故障。
- 不能因此宣称“check_timing 全绿”；也不能在没有证据时把它当致命错误。
  如果后续 SCCB 读写异常，优先复查这个 inout/三态路径。

### 5.2 no input delay (MEDIUM)

```text
cam_sda
```

`cam_sda` 是 50 kHz SCCB 双向线，不作为高速输入时序对象；
`cam_data/href/vsync` 都有 input delay。可接受，记录在案。

### 5.3 no output delay (MEDIUM, 12)

4 个 TMDS + 4 个 LED + `cam_scl/cam_sda/cam_reset_n/cam_pwdn`。
TMDS 内部路径按 125 MHz 分析；LED 和 SCCB/控制是慢速信号。
没有编造显示器侧 output delay。

## 6. 已知 warning

```text
PHY-5016 WARNING: PLL clkc is driving an IO without location.
PHY-5016 WARNING: PLL clkc is not driving a clock-capable IO.
PHY-5088 WARNING: Clock_Analyzer: 1 clock-net(s) because they drive
                  other clock net, may cause clock skew.
```

- `PHY-5016` 与已上板的彩条设计相同；彩条已用户报告显示成功。
- `PHY-5088` 是时钟网络分析提示；时序报告已包含 clock skew。
- 这些 warning 不能代替上板验证。

## 7. 位流

| 项目 | 值 |
|---|---|
| 文件 | `build/bitstream/top_ov5640_line_to_hdmi.bit`（本地，gitignored） |
| SHA-256 | `67eec013651ccdde7291e3e26d1ec1a506e92111076651f0a49cf7ff0e3222cd` |
| 生成时间 | 2026-11-08 |

位流不逐 bit 可复现；以 RTL/约束/脚本为可复现依据。

## 8. 构建产物

```text
build/bitstream/top_ov5640_line_to_hdmi.bit
build/bitstream/top_ov5640_line_to_hdmi_final_timing.rpt
build/bitstream/top_ov5640_line_to_hdmi_route.qor
build/bitstream/top_ov5640_line_to_hdmi_route.check_timing
build/bitstream/top_ov5640_line_to_hdmi_netlist.csv
```

按 `.gitignore` 不入库。
