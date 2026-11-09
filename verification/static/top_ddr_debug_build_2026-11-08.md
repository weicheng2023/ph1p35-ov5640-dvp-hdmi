# DDR 状态调试顶层 TD 构建证据（2026-11-08）

> 工具：Tang Dynasty 6.2.1
> 设计：`top_ddr_debug` + `ddr_status_debug` + `ddr2`（无 AXI 事务）
> 器件：PH1P35MDG324 / speed 3
> 位流：`build/bitstream/top_ddr_debug.bit`
> SHA-256：`03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46`
>
> 本构建只把 PLL/复位/校准/超时状态引到 LED；不发起 AXI 读写。
> 构建通过 ≠ DDR 校准/读写通过。

## 1. 设计

```text
top_ddr_debug
  ├─ PH1P_LOGIC_BUFG (clk_50m -> clk_50m_buf)
  ├─ POR 65,535 周期
  ├─ 1 Hz 心跳
  ├─ ddr2 (CAL_EN=1 默认)
  │    └─ vendor DDR2 512Mb x16 IP（AXI/APB 接 0）
  └─ ddr_status_debug (clk_50m_buf)
       ├─ ddrphy_rst_n -> 2FF -> LED2
       ├─ ddrphy_rdy   -> 2FF -> LED3
       └─ 1 s 超时（仅 clk_50m） -> LED4（锁存）
```

- `CAL_EN=1` 默认；`DDR_CAL0=1` 构建只改 `CAL_EN=0` 的对照，
  输出 `top_ddr_debug_cal0.bit`，不覆盖本位流。
- 50 MHz ref 的 PLL 参数与 `top_ddr_test` 相同：
  N=3/M=64/C=2/CLK3=21，DDR 时钟 533.33 MHz。
- 显式 BUFG：调试顶层 `clk_50m` 负载少，工具会自动插入 SCLK；
  BUFG 让 50 MHz 逻辑走一个全局缓冲。

## 2. 状态逻辑仿真

`tb_ddr_status_debug`（TIMEOUT=50）3/3 PASS：

```text
ok   case1: PLL locked, READY high, no timeout
ok   case2: PLL locked, READY missing, timeout latched
ok   case3: no PLL lock, no READY, timeout latched
TB: PASS - ddr_status_debug
```

这证明 LED 映射/超时/锁存逻辑，不证明真实 DDR 状态。

## 3. TD 构建结果

```text
Setup WNS  +1.446 ns   TNS 0   Violated S-EP 0
Hold  WNS  +0.020 ns   TNS 0   Violated H-EP 0   (紧)
Slices     1960 (9.24%)
RAMs       0
DSPs       0
DRAMHARDCON 7
```

时钟（约束路径）：

| Clock | Freq | Fanout | WNS |
|---|---:|---:|---:|
| `u_ddr2/usr_clk` | 133.351 MHz | ~1067 | +1.446 / +0.020 |
| `u_ddr2/mcu_clk` | 50.798 MHz | 29 | +11.1 / +0.05 |
| `u_ddr2/ctl_clk` | 133.351 MHz | 6 | 0 / 0 |
| `u_ddr2/ddr_clk` | 533.618 MHz | 6 | 0 / 0 |
| `clk_50m` (BUFG) | 50 MHz | 4 | 0 / 0 |

## 4. check_timing / 已知告警（未隐藏）

- **6 个 HIGH no-clock nets**：`clk_50m_dup_1`、BUFG 后
  `u_bufg_clk_auto_created_sclk_*` 4 条、IP 内部
  `u_ddrphy_fiu_wrapper/apb_pclk`。工具认为这些 SCLK/IP 内部 net 的
  root clock 不是 `clk_50m`。**这意味着 clk_50m 侧部分路径没有被完整
  时序分析**；LED/超时逻辑很慢且时钟物理连通，但不要把它当成
  时序签收。
- **1 个 HIGH dummy node**：PLL `pllreset`（vendor IP 内部）。
- **1 个 HIGH PLL 频率告警**：`ddr_clk` 约束 533.600 vs PLL 533.333
  （0.05% 舍入）。
- **USR-6133 CRITICAL-WARNING**：primary clock
  `u_pll0/u_pll_inst.refclk` 定义在 internal clock network；
  vendor `derive_clocks` 造成，建议用 generate_clock；未修复。
- 23 个无 input delay、49 个无 output delay（封装内 DDR/慢速 LED）。
- **Hold +0.020 ns 很紧**。

> 结论：本构建**可用于 LED 状态诊断**，但不是“时序完全干净”的
> 生产签收。若要继续，下一步是加 generated clock/BUFG 约束并审计
> 上述 6 条 no-clock net，而不是用 `unconstr_io` 或异步组掩盖。

## 5. 与原始 `top_ddr_test` 的关系

- 原始 `top_ddr_test.bit`（SHA `610b0b1f...`）**保留不动**；
- 原始实测 LED1 闪、LED2/3/4 灭，与“`ddrphy_rdy` 未拉高 + timeout
  只在 pattern 状态机启动后运行”一致；
- 本调试位流只改状态观测，不重新实现 DDR 控制器。

## 6. 上板

按 `verification/board/bringup-ddr-debug.md`：
LED1 心跳、LED2 `ddrphy_rst_n`、LED3 `ddrphy_rdy`、LED4 1 s 超时。
结果写入 `verification/board/evidence/20261108_ddr_debug/`。

### 6.1 CAL_EN=1 实测（用户报告，2026-11-08）

等待 >10 s 后：

| LED | 实测 |
|---|---|
| LED1 心跳 | **闪** |
| LED2 `ddrphy_rst_n` | **亮** |
| LED3 `ddrphy_rdy` | **灭** |
| LED4 超时 | **亮** |

判断：PLL/复位已释放（LED2=1），但 `ddrphy_rdy` 未到（LED3=0），
1 s 独立超时已触发（LED4=1）。这**不是**校准失败原因的证明；下一步
按 `top_ddr_debug_cal0_build_2026-11-08.md` 做只改 CAL_EN 的对照。
