# PH1P35 板载 DDR 与帧缓存方案调查（2026-11-08）

> 本文件是**调查/设计报告 + 已确认事实**，不是 DDR 已可用的板上证据。
> 结论等级：DATASHEET_CONFIRMED / TOOL_CONFIRMED / REFERENCE_CONFIRMED /
> BOARD_MEASUREMENT_REQUIRED / UNRESOLVED。
>
> 关键结论：**PH1P35MDG324 的 DDR 是封装内集成存储器（SiP），
> 不是板上的外部 DDR 颗粒；本地原理图没有外部 DDR 图页是正常的。**
> TD 6.2.1 的 `MIS_DDRF6F1D0P0_1.1` 对 `PH1P35MDG324` 的
> `Integrated` 模式走 **DDR2 512Mb x16、1.5 V** 路径。
> 这仍是“工具/数据手册确认”，**校准和读写必须上板验证**。
>
> **2026-11-09 进展（阶段 2 收尾）**：
> - 最小 DDR 测试（CAL_EN=1）上板未 READY；**CAL_EN=0 对照 READY 可达**。
> - 第一次测试图 → DDR → HDMI 上板失败（整屏红、LED3 灭、LED4 亮）。
>   根因：PAXI 原生地址单位是 **16-bit word**，128-bit 块步长应为 8
>   （原实现 +1）；写掩码为**高有效**（原实现 `FFFF` 把全字屏蔽）。
>   行为模型旧版也未检查这两点，故仿真误通过。
> - 修复后 **ModelSim 12/12 PASS**，正常 CRC `F53A4D4F`；TD
>   Setup +0.110 / Hold +0.020 ns、5283 slices；最终位流
>   `top_ddr_fb_hdmi_paxi_fix_20261109.bit`（SHA `e83d9c54…`）。
> - **用户实测：FPGA 测试图 → DDR → HDMI 完整显示**
>   → **STAGE 2 — BOARD FUNCTIONAL PASS（用户报告）**。
>   详见 `docs/display/ddr-framebuffer-bringup.md` 与
>   `verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`。
> - 证据边界：CAL_EN=0 的 READY/CRC/图像通过**不等于**完整 PHY 校准通过，
>   也不证明长期稳定性、温度/电压余量。

## 1. 已确认的硬件事实

### 1.1 数据手册（DATASHEET_CONFIRMED）

来源：`docs/hardware/DS1300_PH1P_Datasheet.pdf`，§2.11/§2.12
（PDF 第 45 页，印刷页码 39）。

| 项目 | PH1P35MDG324 | PH1P35MHG324 |
|---|---|---|
| 集成存储器 | **SDRAM 16-bit，512 Mb** | SDRAM 16-bit，1024 Mb |
| 突发长度 | BL8 | BL8 |
| 写数据掩码 | 支持 | 支持 |
| 延迟校准 | 后台延迟校准 | 后台延迟校准 |
| `VCCIO_DDR` | **1.5 V**（1.425/1.5/1.575） | `VCCIO_DDR4` 1.35 V |
| 外部存储接口 | DDR2/DDR3/DDR4，x8/x16，800 Mbps，最多 2 rank | 同左 |

- 512 Mb = **64 MB**（512/8）。
- 封装内存储器直接与 FPGA 的 DDR PHY 相连，**没有板级 DDR 球位**。
- 外部存储接口（DDR2/3/4、72-bit）是 FPGA 的通用能力，不代表本板
  另外焊了外部颗粒；本地原理图没有外部 DDR 图页，与“集成”一致。
- **UNRESOLVED（仅速度等级）**：数据手册这一节没有给出集成存储器的
  DDR 代数/速度等级（DDR2-800/1066 等），也没有颗粒丝印可读；
  速度结论见 1.3 的 TD IP/参考工程证据。

### 1.2 板上电源/时钟（SCHEMATIC_CONFIRMED）

本地原理图（`docs/hardware/HX1P35B_FT_40P_1..10.pdf`）：

- `P01_FPGA`：`VCCIO_DDR`、`VCCIODDR`、`DDR_VREF` 等网络；
- `P08_EX_DEVICE`：**SIT9121AI-2B1** 有源晶振，输出 `DDR_CLK`，
  经 100 Ω（R262，100R/NC）到 `FPGA_DDR_100MHZ_LVDS_P/N`；
- 板卡系统时钟：50 MHz 有源晶振 U31 → `FPGA_A_SYSCLK_50MHZ` → **C4**；
- 摄像头 PCLK：F14（GCLKIOT3），已有 DVP 设计使用。

> **UNRESOLVED**：100 MHz 差分 DDR 时钟在 PH1P35MDG324 上的
> **具体球位**尚未写入 `docs/hardware/wiring.md`。在补齐之前，
> 最小 DDR 测试优先用已知的 **C4 50 MHz** 作为 IP 的 `ref_clk`，
> 用 TD 的 PLL 计算过程重新算分频（见 1.5）。

### 1.3 TD 6.2.1 IP 的集成模式（TOOL_CONFIRMED）

IP 路径：

```text
D:\Software\Anlogic\TD_6.2.1\ip\depot\MIS_DDRF6F1D0P0_1.1
```

`PH1P_DDRPHY_IP/Other/ph1p_ddrphy_ip/pkg/cfg.csv` 明确列出：

```text
PH1P35MDG324,DDR2+DDR3+DDR4+Integrated,Integrated=2+DDR2=DDR3=DDR4=12,
BANK11_0+BANK12_1+BANK32_2,pkg324,
Normal_BANK32+Integrated_BANK12,...
```

`Dependency.tcl` / `gen_define.tcl` / `gen_file.tcl` 对
**`PH1P_DDR_TYPE=Integrated` + `IP_DEVICE=PH1P35MDG324`** 的处理：

| 项目 | 值 | 证据 |
|---|---|---|
| 协议 | **DDR2**（`DRAM_DDR2`） | `gen_define.tcl` 第 14 行 |
| 容量 | **512 Mb**（`DDR2_512M`） | `update_comp_density` |
| 位宽 | **x16**（`DDR2_X16`） | `update_integrated_comp` |
| 几何 | ROW=**13**，COL=**10**，BA=**2**（4 bank） | `update_addr_width`/`update_ba_width` |
| 地址 | ADR=13，MC_ADDR=25 | 同上 |
| I/O | **1.5 V**，`PH1P_VCCIO_1V50` | `PH1P_IO_VOL` 默认 1.5 |
| PHY I/O 标准 | `SSTL15` / `DIFF_SSTL15` | `adc/ap111_ddr2_x16_324.adc` |
| PHY 配置 ROM | `ddrphy_cfg_rom_MDG324.txt` | `gen_file.tcl` |
| PHY 引脚矩阵 | `ph1p_ddrphy_bus_matrix_MDG324.vh` 等 | `gen_file.tcl` |
| ADC | `adc/ap111_ddr2_x16_324.adc`（PHY 站点） | `gen_file.tcl` 集成分支 |
| 用户接口 | AXI4（128-bit）+ APB 调试 | IP 顶层 |

容量核对：`2^13 row × 2^10 col × 4 bank × 16 bit = 512 Mb = 64 MB`。

> **用户接口选择（最小测试）**：生成的 `ph1p_ddrmc_wrapper` 默认暴露
> **原生 `paxi_*` 接口**（字地址，1 地址 = 128-bit beat；无 B 响应通道），
> 与参考工程 `ddr2.v` 一致。定义 `MC0_MIS_AXI` 会切换成完整 AXI4
> （`axi_*`，含 ID/len/size/burst/B 通道），需要额外的
> `mc0_axi2mc_top_all.enc.sv`。最小读写测试用原生 `paxi_*`；
> 后续帧缓存可以继续用它，或改用完整 AXI4。

**速度**：`update_speed_bin` 对 Integrated MDG324 + 800 Mbps 允许
`DDR2-800D/E、DDR2-1066、DDR2-1333-8/9`；`update_cl` 对应
CL=5/6/7/9。IP 的 `PH1P_DDR_SPEED` 默认 800（`tCK=2500 ps`），
但**参考工程实际生成的是 `DDR2_1066`（tCK=1876 ps，CL=7，CWL=6）**。
本板集成存储器的最终速度等级仍建议按 **DDR2-800/1066 两档**
做上板校准验证，先跑 1066（参考配置），失败再降 800。

### 1.4 参考工程（REFERENCE_CONFIRMED，同器件/同封装，不同板卡）

本地 `build/ref/anlogic-ph1p35-vision`（第三方比赛工程，未入库）：
README 写明目标器件 **`PH1P35MDG324`**，架构为
`camera → MIPI/ISP → DDR2 frame buffer → HDMI`。

其 `user_source/hdl_source/ph1p35_ddr/ddr2/` 是 TD 生成的 DDR2 IP：

| 文件 | 与 TD MDG324 文件对比 |
|---|---|
| `ddrphy_cfg_rom.txt` | 与 `ddrphy_cfg_rom_MDG324.txt` **逐字节相同** |
| `ph1p_ddrphy_bus_matrix.vh` | 与 `..._MDG324.vh` **逐字节相同** |
| `ph1p_ddrphy_ddrio.vh` | 与 `..._MDG324.vh` **逐字节相同** |
| `ph1p_ddrphy_pad_type.vh` | 与 `..._MDG324.vh` **逐字节相同** |
| `src/adc/ddr2.adc` | 与 `ap111_ddr2_x16_324.adc` 仅实例路径前缀不同 |
| `ph1p_mis_define.vh` | `DRAM_DDR2/DDR2_512M/DDR2_X16/DDR2_1066/PH1P35_DDRIO_PAD/PH1P_VCCIO_1V50` |

参考工程的顶层 `pin.adc` **没有**给 `ddr_*` 分配封装球位；
DDR 引脚只由 IP 的 `ddr2.adc` 分配到 FPGA 内部 PHY 站点
（`X0Y…`）。这与“封装内集成存储器”一致。

> 参考工程只用于**确认参数/文件一致性**。不要复制它的加密 MC、
> bitstream 或整棵生成树入仓；不要把它当成本板已校准的证据。
> 参考工程 README 也明确这是“第一阶段目标”，不等于已验证完成。

### 1.5 时钟方案（TOOL_CONFIRMED 计算）

板上 50 MHz（C4）可直接作为 IP 的 `ref_clk`。用 TD IP 自带的
`update_pll` 过程计算（ref=50 MHz，目标 533.33 MHz DDR 时钟）：

| 参数 | 值 |
|---|---|
| `PLL0_REFCLK_FREQ` | 50.0 MHz |
| `PLL0_REFCLK_DIV` | 3 |
| `PLL0_FBKCLK_DIV` | 64 |
| `PLL0_CLK2_DIV` | 2 |
| `PLL0_CLK3_DIV` | 21 |
| `PLL0_FRAC` / `SDM` | DISABLE / 0 |
| 实际 DDR 时钟 | 533.33 MHz（DDR2-1066） |
| `PLL1_REFCLK_FREQ` | 133.333 MHz |
| `PLL1_REFCLK_DIV` / `CLK0_DIV` | 4 / 12 |

参考工程用 100 MHz 时是 `N=3, M=32, C=2`；50 MHz 时变为
`N=3, M=64, C=2`，输出同为 533.33 MHz。先上板验证 50 MHz
参考是否能让 `ddrphy_rdy` 拉高；若 PLL/校准异常，再补 100 MHz
差分时钟球位并改用 100 MHz。

### 1.6 带宽/容量

| 项目 | 数值 |
|---|---|
| 集成容量 | 64 MB |
| 单帧 640×480 RGB565 | 614,400 B = 600 KiB |
| 双帧/乒乓 | 1.17 MiB |
| DDR2-1066 x16 理论峰值 | 约 2.13 GB/s（16 bit × 1066 Mbps） |
| 写+读平均需求 | 约 55 MB/s |
| 写+读峰值上限 | 约 146 MB/s |

容量和带宽都足够；**校准、PHY 引脚、帧同步、AXI 仲裁**才是难点。

### 1.7 最小测试实现（2026-11-08，TOOL_CONFIRMED）

- `fpga/rtl/ddr/ddr2_top.v`：plain wrapper，50 MHz ref，
  `N=3/M=64/C=2/CLK3=21`，`CAL_EN=1`，原生 `paxi_*`。
- `fpga/rtl/ddr/ddr_axi_pattern_test.v`：16 个 128-bit beat 写/读/
  逐字比对；LED 反映 `ddrphy_rdy`/PASS/FAIL。
- `fpga/rtl/top/top_ddr_test.v`：POR、APB 接 0、`dhi_clk` 同步、
  LED1..4。
- IP 组装：`build/ddr_ip/`（参考生成树 + TD cal RTL，不入库）；
  `fpga/scripts/prepare_ddr_ip.sh`；IP ADC/SDC 用 `-ip ddr2`。
- **时序修正**：PHY `usr_clk -> clk_50m` 校准 CDC 在未加约束时
  报 Setup -1.390 / Hold -0.239；在 IP SDC 末尾追加
  `set_clock_groups -asynchronous -group [get_clocks {ddr_clk usr_clk ctl_clk mcu_clk ref_clk}]`
  后，Setup +0.913 / Hold +0.020。
- 资源：3389 slices（15.97%），0 RAM，0 DSP，31 DRAMHARDCON；
  位流 SHA `610b0b1f...`。
- **仍未证明**：`ddrphy_rdy` 校准、实际读写、带宽/双缓冲。

## 2. 推荐架构（完整帧）

```text
OV5640 DVP (PCLK 48 MHz)
  └─ 行采集/字节拼接 (RGB565)
       └─ 写 FIFO (PCLK -> dhi_clk)
            └─ AXI4 写主机 (128-bit 打包)
                 └─ DDR MC (TD IP) ── 封装内 DDR2 x16
                      └─ AXI4 读主机 (128-bit)
                           └─ 读 FIFO (dhi_clk -> pixel_clk)
                                └─ RGB565->RGB888
                                     └─ 已验证 HDMI/TMDS
```

关键设计点：

1. **乒乓帧缓存**：两块 600 KiB 区域；摄像头写 A、HDMI 读 B；
   VSYNC 边界交换；交换前确认目标 buffer 不被读。
2. **AXI 位宽打包**：x16 DDR 的 AXI 数据是 128 bit；
   RGB565 每像素 2 B，8 像素 = 1 个 128-bit beat。
3. **时钟/复位**：`ref_clk` 先用 50 MHz C4；AXI 用户逻辑用
   `dhi_clk`；`sys_rst_n`/`apb_prst_n` 用同步复位；
   等 `ddrphy_rdy` 后再发事务。
4. **APB**：最小测试可把 `apb_psel/penable/pwrite/paddr/pwdata`
   明确接 0；`apb_pclk/apb_prst_n` 接 50 MHz/复位。不要像参考
   顶层那样让 APB 输入悬空。
5. **仲裁**：单 AXI slave，简单 round-robin；行有效优先写，
   消隐优先读；小 FIFO 吸收突发。
6. **校准**：`CAL_EN=1`；`ddrphy_rdy` 必须实测；先做
   独立读写测试，再接摄像头。

## 3. 分阶段计划与验收

| 阶段 | 内容 | 证据 |
|---|---|---|
| D1 | 独立 DDR 初始化/校准：只等 `ddrphy_rdy`，LED 指示 | TD 构建 + 上板 LED |
| D2 | 已知 pattern 写/读/比对（本阶段） | ModelSim（AXI FSM）+ TD + 上板 LED |
| D3 | FPGA 生成 640×480 RGB565 测试图 → DDR → HDMI | 仿真 + TD + 屏幕 |
| D4 | OV5640 → DVP → FIFO → DDR 双缓冲 → HDMI | 仿真 + TD + 屏幕/镜头遮挡 |
| D5 | 实时像素正确性（移动/遮挡/已知色卡），解决 HREF/颜色 | 屏幕 + 记录 |

每一阶段都必须分开记录：**仿真通过 ≠ TD 构建通过 ≠ 上板通过**。

## 4. 待确认清单

| # | 项目 | 等级 | 下一步 |
|---|---|---|---|
| 1 | 集成 DDR 类型/容量/位宽 | DATASHEET_CONFIRMED（512Mb x16 集成） | — |
| 2 | 集成 DDR 协议/代数 | TOOL_CONFIRMED（TD 走 DDR2 512M x16） | 上板校准确认 |
| 3 | 速度等级（800/1066） | REFERENCE_CONFIRMED（参考用 1066） | 先 1066，失败降 800 |
| 4 | 板级 DDR 球位 | 不适用（封装内） | 不做外部引脚核对 |
| 5 | 100 MHz 差分 DDR 时钟球位 | UNRESOLVED | 补 `wiring.md`（备用） |
| 6 | 50 MHz ref PLL | TOOL_CONFIRMED（计算 + TD 构建 533.6 MHz） | 上板看 `ddrphy_rdy` |
| 7 | `ddrphy_rdy` 校准 | BOARD_MEASUREMENT_REQUIRED | 上板 LED2 |
| 8 | 读写 pattern | 仿真 3/3 PASS + TD 构建通过 | 上板 LED3 |
| 9 | 带宽/仲裁 | 设计阶段 | D3/D4 实测 |
| 10 | 双帧 1.17 MiB 容量 | 容量足够（64 MB） | D4 |
