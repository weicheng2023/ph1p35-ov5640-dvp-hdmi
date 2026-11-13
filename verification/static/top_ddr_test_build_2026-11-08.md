# DDR 最小读写测试 TD 构建证据（2026-11-08）

> 工具：Tang Dynasty 6.2.1（命令行为 `td_commands_prompt.exe`）
> 设计：`top_ddr_test` + `ddr_axi_pattern_test` + `ddr2`（plain wrapper）
> 器件：PH1P35MDG324 / speed 3
> 位流：`build/bitstream/top_ddr_test.bit`
> SHA-256：`610b0b1fe491ded30d8837a8d12ecef7a31780303161d81d32cdda7473751fd5`
>
> 本文件记录**实际执行的 TD 构建**。构建通过 ≠ DDR 校准/读写已通过；
> 后者必须上板看 LED。

## 1. 设计与 IP 装配

```text
top_ddr_test
  ├─ ddr2 (fpga/rtl/ddr/ddr2_top.v)
  │    └─ ph1p_ddrmc_wrapper_63f4ac254419 (vendor generated)
  │         ├─ ph1p_ddrmc_top (MC)
  │         ├─ ph1p_ddrphy_wrapper/top/... (PHY)
  │         └─ 加密 MC：alc_mc_top_all.enc.sv
  └─ ddr_axi_pattern_test (native paxi_* 写/读/比对)
```

- DDR：PH1P35MDG324 **封装内 DDR2 512Mb x16**（64 MB，1.5 V）。
- TD IP：`MIS_DDRF6F1D0P0_1.1` 的 `Integrated` 模式，`DDR2_512M`/
  `DDR2_X16`/`DDR2_1066`、`ddrphy_cfg_rom_MDG324.txt`、
  `ap111_ddr2_x16_324` PHY 站点。
- 用户接口：wrapper **原生 `paxi_*`**（字地址，128-bit beat，无 B 通道）；
  未定义 `MC0_MIS_AXI`（完整 AXI4 适配器未使用）。
- 参考时钟：C4 50 MHz；PLL `N=3, M=64, C=2, CLK3=21` →
  DDR 时钟 533.33 MHz（DDR2-1066）。
- `CAL_EN=1`：启用延迟校准；参考工程是 `CAL_EN=0` 且缺少 cal RTL，
  本构建从 TD 安装补齐 `src/rtl/cal/*.v`。
- IP ADC/SDC 用 `read_ip_adc -ip ddr2` / `read_sdc -ip ddr2` 读入，
  路径以 plain `ddr2` wrapper 为根，匹配 `ph1p_ddrmc_wrapper/...`。
- **时序约束修正**：PHY 初始化/校准逻辑里有 `usr_clk -> clk_50m` 的
  CDC 路径；在 IP SDC 末尾追加：

```tcl
set_clock_groups -asynchronous -group [get_clocks {ddr_clk usr_clk ctl_clk mcu_clk ref_clk}]
```

  单组表示这些 DDR 时钟与组外所有时钟（含 `clk_50m`）异步，
  与参考工程顶层约束一致。**不修正时** Setup WNS -1.390 ns /
  Hold -0.239 ns（43 个违例端点，均在 PHY 校准 CDC）；修正后为正值。

## 2. 构建命令

```text
D:\Software\Anlogic\TD_6.2.1\bin\td_commands_prompt.exe fpga/scripts/build_top_ddr_test.tcl
```

或 `fpga/scripts/build_top_ddr_test.bat`。构建前先运行
`fpga/scripts/prepare_ddr_ip.sh` 生成 `build/ddr_ip/`（不入库）。

## 3. 结果

```text
Setup WNS  +0.913 ns   TNS 0   Violated S-EP 0
Hold  WNS  +0.020 ns   TNS 0   Violated H-EP 0   (紧)
Slices     3389 (15.97%)
RAMs       0
DSPs       0
DRAMHARDCON 31
```

时钟：

| Clock | Freq | Fanout | WNS |
|---|---:|---:|---:|
| `u_ddr2/usr_clk` | 133.351 MHz | 2258 | +0.913 / +0.020 |
| `clk_50m` | 50.000 MHz | 139 | +13.635 / +0.024 |
| `u_ddr2/mcu_clk` | 50.798 MHz | 29 | +11.721 / +0.054 |
| `u_ddr2/ctl_clk` | 133.351 MHz | 6 | 0 / 0 |
| `u_ddr2/ddr_clk` | 533.618 MHz | 6 | 0 / 0 |
| `u_ddr2/ref_clk` | 133.351 MHz | 1 | 0 / 0 |

`check_timing`：

- 2 个 HIGH dummy node：PLL `pllreset`（vendor IP 内部）；
- 1 个 HIGH PLL 频率告警：`ddr_clk` 约束 533.600 vs PLL 533.333
  （0.05% 舍入）；
- 22 个无 input delay、49 个无 output delay（DDR 为封装内引脚、
  LED/控制为慢速输出；预期）；
- 0 combinational loops。

## 4. 未证明/边界

- 本构建只证明 **RTL/IP 能综合、布局布线、时序收敛、生成位流**；
- 不证明 `ddrphy_rdy` 校准成功；
- 不证明 16 个 128-bit beat 实际写入/读回正确；
- 不证明 640×480 帧缓存/带宽/双缓冲；
- 上板 LED 结果必须由用户实测，写入
  `verification/board/evidence/20261108_ddr_test/`。

## 5. 下一步

1. 烧 `top_ddr_test.bit`；
2. 预期 LED1 1 Hz、LED2 `ddrphy_rdy` 常亮、LED3 PASS 常亮、LED4 灭；
3. 若 LED2 不亮，先查 PLL/校准/CAL_EN，必要时降 DDR2-800；
4. 通过后进入 L2：FPGA 测试图 → DDR → HDMI。
