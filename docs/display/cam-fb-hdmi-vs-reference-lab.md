# Stage 3 `.al` 与参考工程 `lab_ex1_mipi_hdmi` 对比

> 日期：2026-11-13
> 新增工程入口：[`fpga/project/top_cam_fb_hdmi.al`](../../fpga/project/top_cam_fb_hdmi.al)
> 参考工程：`D:\Projects\01_Research\2026_10_Thesis_Bachelor\HX1P35A_Contest_202606\7_lab_ex_2026_nosoft\lab_ex1_mipi_hdmi`
> 结论：**没有修改 DDR IP 内部逻辑/加密文件**。差异集中在：实例参数（50 MHz ref）、
> IP SDC 追加一条时钟组、工程文件组织方式。详见 §2。

## 1. 新 `.al` 的内容

`fpga/project/top_cam_fb_hdmi.al`：

- 设计 RTL 20 个（top/core/writer/reader/capture/DDR 包装/gearbox/FIFO/
  display/camera 配置）；
- 厂商 DDR IP RTL 35 个（含 `alc_mc_top_all.enc.sv`），路径指向
  `../../build/ddr_ip/...`；
- 约束：`../constraints/top_cam_fb_hdmi.adc` + `.sdc`；
- 顶层 `top_cam_fb_hdmi`，`Path="."`。

文件集与 `fpga/scripts/build_top_cam_fb_hdmi.tcl` 的 HDL 列表**逐项一致**
（55 个 HDL，已用脚本比对）。`build/ddr_ip/` 是 `fpga/scripts/prepare_ddr_ip.sh`
生成的本地目录（gitignored）；不存在时先运行该脚本。

**用途限制**：`.al` 只用于 TD GUI 查看/编辑层次。位流必须仍由 tcl/bat 生成，
因为 IP 引脚需要 `read_ip_adc`、P&R 需要 `legalize_phy_inst`；GUI 直接
Synthesis/P&R 不会自动补上这两步。

## 2. IP 是否被改了底层？

逐文件对比 `build/ddr_ip/` 与参考 `user_source/hdl_source/ph1p35_ddr/ddr2/`：

| 文件/目录 | 结果 |
|---|---|
| `Design.xml` | **相同** |
| `DesignConfiguration.xml` | **相同** |
| `ddr2.xml` | **相同** |
| `ph1p_ddrmc_wrapper_63f4ac254419.v` | **相同** |
| `src/rtl/**`（除 cal 目录） | **相同** |
| `src/rtl/cal/**` | 参考没有（其 IP 以 CAL_EN=0 生成）；本地从 TD 安装目录补入，CAL_EN=0 时未使用 |
| `src/sdc/ddr2.sdc` | 本地在末尾**追加 1 行** `set_clock_groups`（见 §3） |

自写包装 `fpga/rtl/ddr/ddr2_top.v`（模块名 `ddr2`）与厂商生成的 `ddr2.v`
只有 3 个参数不同：

| 参数 | 生成值（参考） | 本地值 | 原因 |
|---|---|---|---|
| `PLL0_REFCLK_FREQ` | 100.0 | **50.0** | 板载 C4 为 50 MHz |
| `PLL0_FBKCLK_DIV` | 32 | **64** | 保持 VCO=1066.7 MHz（50/3×64） |
| `PLL1_REFCLK_FREQ` | 133.3 | 133.3333 | 精度写法 |
| `CAL_EN` | 0 | 顶层传 0 | 与参考一致 |

**结论**：只改了实例参数，没有改 IP 内部逻辑；IP 的 UI 配置（Design.xml）
仍是 100 MHz。阶段 2 上板的自检 CRC 与整帧显示证明该 50 MHz 参数组合可用。

**但这是一个隐患**：IP 的 UI 配置与实例参数不一致。若要彻底消除，应在
TD IP 工具中以 50 MHz ref 重新生成 DDR2 IP，然后用其 `ddr2.xml`/文件集；
这会改变文件集，必须重新跑仿真/构建/上板。

## 3. 与参考 `.al` 的结构差异

| 项 | 参考 `camera_to_dsi_display.al` | 本项目 `top_cam_fb_hdmi.al` | 是否合理 |
|---|---|---|---|
| 顶层 | `design_top_wrapper`（MIPI+ISP+HDMI） | `top_cam_fb_hdmi`（DVP+DDR+HDMI） | 合理，设计不同 |
| IP 表示 | IP_FILE 引用 `PLL.xml`、`w128_d512_fifo.xml`、`ddr2.xml` 等，由 TD 重新生成 IP | 直接列 `build/ddr_ip` 下的生成 RTL | 合理但有限制：IP 树在本地 `build/`，且 `ddr2.v` 与本项目 `ddr2` 模块重名被排除；GUI 不能替代 tcl |
| DDR 接口 | `mc_app_*`（Avalon 风格）+ 155-bit 命令 FIFO，内部再转 paxi | 原生 `paxi_*` 直连 | 合理；本项目按 IPUG034/原厂 Lab1 的 paxi 语义 |
| 显示 FIFO | 每帧 VSYNC 复位 FIFO，从所选 buffer 基址重读 | 帧末等 FIFO 排空后重新开始下一遍 | 目标相同（帧对齐），实现不同 |
| 缓冲数量 | 4 帧（0/7M/14M/21M） | 2 帧（4096 / 311296） | 合理；容量足够 |
| SDC | 显式把 DDR 时钟与系统时钟分三组 | 依赖 IP SDC 的组 + 追加一条；不加重叠的设计级组（TD 报 invalid） | 合理；阶段 2 已证明 |
| `Configurations` | `mclk_freq=33MHz`、`boot_mode=mspix4` | 空 | 用 tcl 构建/Program SRAM，不影响；若烧 Flash 需另配 |
| `Path` | 绝对路径 | `Path="."` | 按本项目规则 |

参考工程自身有一个值得注意的点：其 SDC 把 `I_sys_clk`（C4）约束为
**50 MHz**，但 DDR IP 生成参数是 `PLL0_REFCLK_FREQ=100.0, M=32`。
这两者并不自洽；**不要直接照搬参考的 DDR PLL 参数**。本项目的
`50 MHz + M=64` 是 TD `update_pll` 按 50 MHz 参考计算、并由阶段 2
上板验证过的组合。

## 4. 上板现象与根因（2026-11-13）

现象：摄像头内部彩条与实景都呈**左黑 + 右浅蓝**（分界不在正中），
实景颜色随挥手变化（说明 DVP 数据、DDR、HDMI 通路都在工作），
且与 2026-11-08 单行版“左黑条 + 右浅蓝紫”完全一致。

根因（强证据，待上板确认）：

- 数据手册 table 7-18：`0x4740` **bit1 = HREF 极性**（0=低有效，1=高有效），
  默认 `0x20` 时 datasheet 意义下 HREF 低有效。
- 正点原子参考驱动不写 `0x4740`（默认 `0x20`），直接用
  `img_data_en = cam_href`（高有效）采集并出图 → **本模组引脚极性与
  datasheet 位定义相反**（与已实测的 bit0/VSYNC 反相一致）。
- 我们写 `0x4740=0x22`（bit1=1，相对默认翻转 HREF）→ 引脚上
  **HREF 低有效**；实测低相位 26.665 µs = 1280 PCLK = 640 像素 × 2 字节。
- 单行版和 Stage 3 都用 `HREF_ACTIVE_HIGH=1`，抓的是 1920 PCLK 的
  消隐高相位 → 左黑（0x00）+ 右浅蓝（消隐期保持值/串扰，随场景变化）。

修复：保持 `0x4740=0x22`，把 `HREF_ACTIVE_HIGH` 改为 **0**；
不改 `CAPTURE_START`/`BYTE_SWAP`。已重建，等待上板确认。
旧的 `HREF_ACTIVE_HIGH=1` 位流保留为
`top_cam_fb_hdmi_hrefhigh_20261113.bit`（SHA `a25a2ac9…`）。
