# DDR 最小调试顶层与故障定位（2026-11-08）

> 目的：先回答“PLL 是否锁定、初始化/校准是否 READY、超时是否触发”，
> **不发起任何 AXI 读写**，不重新实现 DDR 控制器。
>
> 本文解释 LED 含义、原始位流为什么 LED2/3/4 全灭、PLL/复位/参考时钟
> 检查点、CAL_EN 对照方法，以及 `set_clock_groups` 的排除路径审计。

## 1. 原始 `top_ddr_test` 的实测现象

用户实际 Program SRAM：

```text
位流 SHA-256 610b0b1f...（已核对）
LED1 正常闪烁
LED2 不亮
LED3 不亮
LED4 不亮
```

原始位流的 LED 定义：

| LED | 原始定义 |
|---|---|
| LED1 | 50 MHz 心跳 |
| LED2 | `ddr_ready` = `ddrphy_rdy` 经 `dhi_clk` 两级同步 |
| LED3 | pattern PASS |
| LED4 | pattern FAIL/超时（只在 pattern 状态机启动后） |

**现象与设计一致的可能性**：

1. `ddrphy_rdy` 一直为 0 → `ddr_ready=0` → LED2 不亮；
2. `ddr_axi_pattern_test` 的 `start` 就是 `ddr_ready`，所以状态机一直停在
   `ST_IDLE`；
3. `ST_IDLE` 里**刻意不启动 timeout**（等校准是无限期的），因此
   `timeout` 计数器根本没有运行 → LED4 不亮；
4. `dhi_clk` 是 IP 的 PLL1 输出；如果 PLL 没锁定/没跑，`dhi_clk` 不动，
   `rdy_sync`/`rst_dhi_sync` 也不会更新，`ddr_ready` 一直 0；
5. `ddrphy_rst_n`（PLL 锁定/PHY 复位释放）**在原顶层没有接出来**，
   所以无法区分“PLL 没锁”和“PLL 锁了但校准没完成”。

这不是“超时坏了”，而是**超时被放在了一个依赖 DDR 用户时钟/READY 的
状态机里**；DDR 没起来时它永远不会启动。调试顶层把超时移到独立的
50 MHz 域。

### 1.1 CAL_EN=1 调试位流实测（用户报告，2026-11-08）

等待 >10 s 后：

| LED | 实测 |
|---|---|
| LED1 心跳 | 闪 |
| LED2 `ddrphy_rst_n` | 亮 |
| LED3 `ddrphy_rdy` | 灭 |
| LED4 独立超时 | 亮 |

判断：**PLL/复位已释放，`ddrphy_rdy` 未到，1 s 超时已触发**。
这仍不是“校准失败”的具体原因；已构建只改 CAL_EN=0 的对照。

## 2. 调试顶层 LED 定义

`fpga/rtl/top/top_ddr_debug.v`：

| LED | 信号 | 含义 |
|---|---|---|
| LED1 | 50 MHz 心跳 | 时钟/位流/电源基本正常 |
| LED2 | `ddrphy_rst_n`（2 级同步到 50 MHz） | IP PLL 锁定 / PHY 复位释放 |
| LED3 | `ddrphy_rdy`（2 级同步到 50 MHz） | 初始化/校准完成 |
| LED4 | 独立 50 MHz 超时（锁存） | 复位后 1 s 内 READY 未拉高 |

- 不发起 AXI 读写：`paxi_*` 全部接 0；APB 也接 0。
- 超时计数器只在 `clk_50m` 运行，**不依赖 `dhi_clk`**。
- LED4 是锁存：如果 READY 在 1 s 后才出现，LED3 会亮但 LED4 仍亮，
  表示“慢但最终 Ready”；如果 READY 一直不出现，LED3 灭、LED4 亮。
- 如果 LED2 亮、LED3 亮、LED4 灭：PLL + 初始化/校准都在 1 s 内完成。

## 3. LED 组合的故障判断

| LED1 | LED2 | LED3 | LED4 | 判断 | 下一步 |
|---|---|---|---|---|---|
| 灭 | — | — | — | 50 MHz/位流/电源问题 | 烧已知可用彩条位流确认板卡 |
| 闪 | 灭 | 灭 | 灭 | 复位后 <1 s，尚未到超时 | 等 2 s 再看 |
| 闪 | 灭 | 灭 | 亮 | **PLL 未锁定/PHY 复位未释放** | 查 C4 50 MHz、POR、PLL 参数；考虑 100 MHz 差分 ref |
| 闪 | 亮 | 灭 | 亮 | **PLL 锁定，但 1 s 内 READY 未来** | 先做 `CAL_EN=0` 对照；再加初始化/校准阶段诊断 |
| 闪 | 亮 | 亮 | 亮 | PLL/READY 都有，但 READY 晚于 1 s | 记录实际延迟；检查校准时钟/参考频率 |
| 闪 | 亮 | 亮 | 灭 | PLL + READY 均在 1 s 内 | 可回到 pattern 测试；仍不代表数据可靠 |

## 4. `ddr2_top.v` 的 PLL/参考时钟/复位检查

### 4.1 参考时钟

- 当前用 **C4 50 MHz** 同时作 `ref_clk` 和 `apb_pclk`。
- 板卡另有 `FPGA_DDR_100MHZ_LVDS_P/N`（SIT9121 100 MHz 差分），
  但**具体球位尚未写入 `docs/hardware/wiring.md`**；在补齐前不猜引脚。
- 参考工程用 100 MHz；本设计用 50 MHz 是为了先避开未确认的 DDR
  时钟球位。若 LED2 不亮，100 MHz 差分 ref 是下一个候选，但必须先
  确认球位/IBUFDS 原语。

### 4.2 PLL 参数

TD `update_pll` 为 50 MHz ref、533.33 MHz 输出算出的参数：

| 参数 | 值 |
|---|---|
| `PLL0_REFCLK_FREQ` | 50.0 MHz |
| `PLL0_REFCLK_DIV` | 3 |
| `PLL0_FBKCLK_DIV` | 64 |
| `PLL0_CLK2_DIV` | 2 |
| `PLL0_CLK3_DIV` | 21 |
| VCO（M/N × ref） | 1066.67 MHz |
| 相位检测频率（ref/N） | 16.67 MHz |
| DDR 时钟（VCO/C2） | 533.33 MHz |
| `PLL1_REFCLK_FREQ` | 133.333 MHz |
| `PLL1_REFCLK_DIV` / `CLK0_DIV` | 4 / 12 |

- 这些值在 PLL 的相位检测/VCO 范围内（按 `update_pll` 的搜索空间），
  但**没有板上锁定证据**；LED2 就是第一个证据。
- 如果 LED2 不亮，先确认 C4 实际 50 MHz、POR 释放、`sys_rst_n`/
  `apb_prst_n` 没有被拉低；再考虑 100 MHz ref 或 PLL 参数。

### 4.3 复位

- `rst_n`：POR 计数器 65,535 个 50 MHz 周期 ≈ 1.31 ms；
- `sys_rst_n` / `apb_prst_n` 接 `rst_n`；
- `ddrphy_rst_n` 是 IP 的**输出**（不是本设计驱动），调试顶层把它
  接到 LED2；它反映 IP 内部 PLL/PHY 复位释放；
- `ddrphy_rdy` 是 IP 的输出；调试顶层用 2 级触发器同步到 50 MHz；
- 原 `top_ddr_test` 的 `rst_dhi_sync`/`rdy_sync` 依赖 `dhi_clk`；
  如果 PLL 没锁，它们不动。这是原 LED2/4 全灭的结构性原因之一。

## 5. CAL_EN 对照方法

- 默认调试位流：`CAL_EN=1`（开启延迟校准），`top_ddr_debug.bit`。
- 仅当 **LED2 亮、LED3 灭、LED4 亮**（PLL 锁定但 READY 未来）时，
  再构建**只改 CAL_EN** 的对照：

```bat
set DDR_CAL0=1
build_top_ddr_debug.bat
```

输出 `top_ddr_debug_cal0.bit`。它只把 `CAL_EN` 从 1 改成 0，
其他 RTL/约束/PLL 不变。

- 参考工程用 `CAL_EN=0`；这说明“参考实现没有开训练”，**不代表**
  本板关闭训练就是正确修复。`CAL_EN=0` 如果让 READY 拉高，只说明
  训练路径/校准时钟可能是卡点；**数据可靠性仍未验证**。
- 不要在没有对照结果前宣称“校准失败的具体原因”。

## 6. `set_clock_groups` 排除路径审计

当前 IP SDC 末尾（由 `prepare_ddr_ip.sh` 追加）：

```tcl
set_clock_groups -asynchronous -group [get_clocks {ddr_clk usr_clk ctl_clk mcu_clk ref_clk}]
```

单组语义：这些 DDR 时钟与**组外所有时钟**（包括 `clk_50m`）异步。
它排除了以下路径：

1. **IP 内部初始化/校准 CDC**：`u_ddrphy_mdl_cal_wrapper`、
   `u_ddrphy_fiu_wrapper` 等 `usr_clk <-> clk_50m` 路径。原始报告
   显示 43 个违例端点全部落在这些 init/cal 实例上；参考工程顶层
   也用同样的 DDR 时钟异步组。这是 vendor 设计意图，不是用户数据。
2. **本设计的 2 级同步器**：`ddr_status_debug` 的
   `ddrphy_rst_n`/`ddrphy_rdy` → `clk_50m`；2 级触发器是正确 CDC。
3. **复位**：`clk_50m` 域的 POR `rst_n` 到 IP 的 `sys_rst_n`/
   `apb_prst_n`；异步复位，IP 内部有复位同步；APB 已接 0。
4. **没有用户数据路径**跨 `clk_50m`/DDR 时钟：原 pattern 测试在
   `dhi_clk` 域，`start`/状态只通过同步器；调试顶层没有 AXI 数据。
5. **未排除** DDR 时钟内部路径：`usr_clk`/`mcu_clk`/`ddr_clk`
   自身路径仍参与 STA；`clk_50m` 自身路径仍参与 STA。

审计结论：

- 该组**只**切掉上述 CDC/复位类别，没有切掉 AXI 数据/地址路径；
- 修正后 Setup **+0.913 ns** / Hold **+0.020 ns**（Hold 紧，需注意）；
- 这不是“用异步组掩盖同步违规”：原始违例端点全部是 init/cal CDC；
- 但 **Hold +0.020 ns 仍很紧**，不能据此宣称长期稳定。

## 7. 调试位流构建（已完成）

```text
fpga/scripts/build_top_ddr_debug.bat
输出 build/bitstream/top_ddr_debug.bit
SHA-256 03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46
```

- Setup **+1.446 ns** / Hold **+0.020 ns**（紧）/ 1960 slices /
  7 DRAMHARDCON；
- 状态逻辑仿真 `tb_ddr_status_debug` 3/3 PASS；
- **check_timing 仍有 6 个 HIGH no-clock SCLK net、1 个 PLL dummy、
  533.600 vs 533.333 频率舍入、USR-6133 primary-clock 告警**；
  本调试位流用于 LED 状态判断，不是时序签收；
- 原始 `top_ddr_test.bit`（SHA `610b0b1f...`）与原
  `top_ddr_debug.bit`（SHA `03339cf5...`）均保留未动。

### 7.1 CAL_EN=0 对照（已上板）

- 位流：`build/bitstream/top_ddr_debug_cal0.bit`
- SHA-256：`f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0`
- 只改 `CAL_EN=0`；PLL/ref/tCK/CL/CWL/复位/SDC/LED/AXI-APB 不变。
- TD：Setup **+2.073 ns** / Hold **+0.021 ns** / 1290 slices /
  7 DRAMHARDCON；CAL1 为 1960 slices（省略 cal 生成块）。
- `check_timing`：4 个 HIGH no-clock（CAL1 6；SDC 未改）、PLL dummy/
  533.600-vs-533.333、USR-6133；不是时序签收。
- 上板（用户实测）：**LED1 闪、LED2 亮、LED3 亮、LED4 灭**。
  READY 可达；训练被绕过，**不证明数据可靠**。数据证明由
  `top_ddr_fb_hdmi` 的 16-beat 自检 + 整帧读回逐像素/CRC 承担
  （`verification/static/ddr_fb_hdmi_sim_2026-11-08.md`、
  `verification/board/bringup-ddr-fb-hdmi.md`）。

构建记录：`verification/static/top_ddr_debug_build_2026-11-08.md`、
`verification/static/top_ddr_debug_cal0_build_2026-11-08.md`。
上板步骤：`verification/board/bringup-ddr-debug.md`。
证据：`verification/board/evidence/20261108_ddr_debug/`。
