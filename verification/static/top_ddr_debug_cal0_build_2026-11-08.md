# DDR 调试 CAL_EN=0 对照构建（2026-11-08）

> 目的：在 `top_ddr_debug` 上板结果为
> **LED1 闪、LED2 亮、LED3 灭、LED4 亮**（PLL/复位已释放，
> 但 `ddrphy_rdy` 未到，1 s 超时已触发）后，做**只改 CAL_EN** 的
> 对照。
>
> CAL_EN=0 只用于定位 READY 卡点；**即使 LED3 亮起，也不证明
> DDR 读写/数据可靠**。

## 1. 原始状态（保留）

| 位流 | SHA-256 | 状态 |
|---|---|---|
| `top_ddr_test.bit` | `610b0b1fe491ded30d8837a8d12ecef7a31780303161d81d32cdda7473751fd5` | 原始 pattern 测试；LED1 闪/LED2-4 灭；保留 |
| `top_ddr_debug.bit` | `03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46` | CAL_EN=1 调试；上板 LED1 闪/LED2 亮/LED3 灭/LED4 亮；保留 |

本次对照输出独立文件：`top_ddr_debug_cal0.bit`，不覆盖上面两个。

## 2. 只改 CAL_EN 的证据

### 2.1 顶层选择

`fpga/rtl/top/top_ddr_debug.v` 的**同一个文件**：

```verilog
`ifdef DDR_CAL0
    localparam integer CAL_EN_LOCAL = 0;
`else
    localparam integer CAL_EN_LOCAL = 1;
`endif
...
ddr2 #(.CAL_EN (CAL_EN_LOCAL)) u_ddr2 (...);
```

默认构建：`DDR_CAL0` 未定义 → `CAL_EN_LOCAL=1`。
对照构建：`DDR_CAL0=1` → `CAL_EN_LOCAL=0`。

### 2.2 `ddr2` wrapper

`fpga/rtl/ddr/ddr2_top.v` 的**同一个文件**：

```verilog
module ddr2 #(parameter integer CAL_EN = 1) (...);
...
ph1p_ddrmc_wrapper_63f4ac254419 #(
    .tCK              (1876),
    ...
    .CAL_EN           (CAL_EN),
    .CWL              (6),
    .CL              (7),
    .PLL0_REFCLK_FREQ (50.0),
    ...
) ph1p_ddrmc_wrapper (...);
```

### 2.3 参数对照

| 参数 | CAL_EN=1 调试 | CAL_EN=0 对照 |
|---|---:|---:|
| `CAL_EN` | 1 | **0** |
| `tCK` | 1876 | 1876 |
| `DX_NUM` / `BG_WIDTH` / `BA_WIDTH` | 2 / 0 / 2 | 2 / 0 / 2 |
| `ROW_WIDTH` / `COL_WIDTH` / `ADR_WIDTH` | 13 / 10 / 13 | 13 / 10 / 13 |
| `CL` / `CWL` / `WDM` | 7 / 6 / 1 | 7 / 6 / 1 |
| `HOST_*` / `DRAM_*` | 75 / 0 / 75 | 75 / 0 / 75 |
| `PLL0_REFCLK_FREQ` | 50.0 | 50.0 |
| `PLL0_REFCLK_DIV` / `FBKCLK_DIV` | 3 / 64 | 3 / 64 |
| `PLL0_CLK2_DIV` / `CLK3_DIV` | 2 / 21 | 2 / 21 |
| `PLL1_REFCLK_FREQ` / `DIV` / `CLK0_DIV` | 133.3333 / 4 / 12 | 133.3333 / 4 / 12 |
| `MC_*` / `AXI_*` | 不变 | 不变 |
| 参考时钟 | C4 50 MHz | C4 50 MHz |
| 复位 | POR 65,535 周期 | 同 |
| ADC / SDC | 同一文件 | 同 |
| LED 逻辑 | 同 | 同 |
| AXI/APB | 全部接 0 | 同 |

### 2.4 文件/脚本对照

- `top_ddr_debug.v`、`ddr_status_debug.v`、`ddr2_top.v`：**同一文件**；
- vendor IP 文件列表：**同样 38 个文件**（cal RTL 仍列出，
  `CAL_EN=0` 时校准功能被禁止）；
- `top_ddr_debug.adc` / `top_ddr_debug.sdc` / `ddr2.adc` / `ddr2.sdc`：
  **同一文件**；
- `build_top_ddr_debug.tcl`：`DDR_CAL0=1` 时只多做
  `-define DDR_CAL0`，输出前缀改为 `top_ddr_debug_cal0`；
- 没有修改 `top_ddr_test` 工程/位流。

## 3. ModelSim 状态仿真

`tb_ddr_status_debug`（TIMEOUT=50）重跑 3/3 PASS：

```text
ok   case1: PLL locked, READY high, no timeout
ok   case2: PLL locked, READY missing, timeout latched
ok   case3: no PLL lock, no READY, timeout latched
TB: PASS - ddr_status_debug
```

说明：这是状态/超时逻辑仿真；CAL_EN 是 vendor IP 参数，仿真不实例化
加密 IP，因此不模拟校准本身。

## 4. TD 构建结果（CAL_EN=0）

位流：`build/bitstream/top_ddr_debug_cal0.bit`
SHA-256：`f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0`

```text
Setup WNS  +2.073 ns   TNS 0   Violated S-EP 0
Hold  WNS  +0.021 ns   TNS 0   Violated H-EP 0
Slices     1290 (6.08%)      (CAL_EN=1: 1960 / 9.24%)
RAMs       0
DSPs       0
DRAMHARDCON 7                (same)
```

时钟（与 CAL_EN=1 相同的 PLL/频率）：

| Clock | Freq | Fanout | WNS |
|---|---:|---:|---:|
| `u_ddr2/usr_clk` | 133.351 MHz | 645 | +2.073 / +0.021 |
| `u_ddr2/mcu_clk` | 50.798 MHz | 29 | +12.061 / +0.036 |
| `u_ddr2/ctl_clk` | 133.351 MHz | 6 | 0 / 0 |
| `u_ddr2/ddr_clk` | 533.618 MHz | 6 | 0 / 0 |
| `clk_50m` (BUFG) | 50 MHz | 4 | 0 / 0 |

`check_timing`（CAL_EN=0）：

- **4 个 HIGH no-clock nets**（CAL_EN=1 为 6 个；少掉的 2 条来自
  被省略的 cal 逻辑 SCLK 分支，SDC 未改）：`clk_50m_dup_1`、
  BUFG 后 2 条 SCLK、IP 内部 `apb_pclk`；
- 1 个 HIGH PLL dummy node；
- 1 个 HIGH PLL 频率舍入：533.600 vs 533.333；
- **USR-6133**：primary clock 在 PLL internal refclk（未修复）；
- 23 个无 input delay、49 个无 output delay；
- **不是时序签收**；Hold +0.021 仍紧。

资源差异（1960→1290 slices）与 `ph1p_ddrphy_wrapper.v` 的
`if (CAL_EN == 1'b1) begin : cal_en ... end` 一致：CAL_EN=0 时
cal 生成块不实例化；**这是唯一参数差异的直接结果**，不是额外 RTL 改动。

### 4.1 两次构建的实际差异（CAL_EN=1 vs 0）

| 项目 | CAL_EN=1 | CAL_EN=0 |
|---|---|---|
| `top_ddr_debug.v` | 同一文件 | 同一文件 |
| `ddr_status_debug.v` / `ddr2_top.v` | 同一文件 | 同一文件 |
| `read_hdl` 文件数 | 38 | 38 |
| `read_hdl` 选项 | `-top top_ddr_debug` | `-top top_ddr_debug -define DDR_CAL0` |
| `CAL_EN` 参数 | 1 | **0** |
| 其他 wrapper 参数 | 见 §2.3 | **完全相同** |
| ADC/SDC | 同一文件 | 同一文件 |
| LED/AXI/APB | 同 | 同 |
| Setup WNS | +1.446 ns | +2.073 ns |
| Hold WNS | +0.020 ns | +0.021 ns |
| Slices | 1960 | 1290 |
| DRAMHARDCON | 7 | 7 |
| `check_timing` no-clock | 6 | 4（SDC 未改，少的来自 cal 生成块） |

**注意**：CAL_EN=0 时 `ph1p_ddrphy_wrapper.v` 的
`if (CAL_EN == 1'b1)` 生成块不实例化，因此 slices/时序/no-clock 数量
会变化；这不是额外的 RTL 或约束改动。cal RTL 文件仍编译，但
`CAL_EN=0` 不实例化校准块。

> 时序报告：`build/bitstream/top_ddr_debug_cal0_final_timing.rpt`、
> `top_ddr_debug_cal0_route.qor`、`top_ddr_debug_cal0_route.check_timing`
> （CAL0 的 `check_timing` 已复制为 `_cal0` 文件名；CAL1 的
> `check_timing` 文件因 top 名称相同被 CAL0 构建覆盖，CAL1 摘要保留在
> `build/td_ddr_debug_build.log` 和
> `verification/static/top_ddr_debug_build_2026-11-08.md`）。

## 5. 上板预期

烧 `top_ddr_debug_cal0.bit`：

- LED1 应闪；
- LED2 应亮（PLL/复位释放，与 CAL_EN=1 相同）；
- LED3 是 `ddrphy_rdy`：如果 **CAL_EN=0 让它亮**，只说明
  “READY 状态能到达”，**不证明 DDR 数据读写可靠**；
- LED4 是独立超时：LED3 亮且 LED4 灭 = READY 在 1 s 内；LED3 亮但
  LED4 亮 = READY 晚于 1 s；LED3 仍灭 = CAL_EN=0 也没有让 READY 到，
  需要继续查初始化/复位/时钟，而不是直接改数据路径。
- 不论 LED3 结果，**本实验不发起 AXI/APB 事务，也不证明 DDR 可用**。
