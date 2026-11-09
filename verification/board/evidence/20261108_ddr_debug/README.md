# 2026-11-08 DDR 状态调试上板证据

> **状态：CAL_EN=1 调试位流已上板；CAL_EN=0 对照也已上板（2026-11-08
> 用户报告：LED1 闪、LED2/3 亮、LED4 灭 → READY 可达）。**
>
> 本目录还记录**原始 `top_ddr_test` 的实测现象**，作为调试输入。
> 不要把它当成 DDR 校准/读写 PASS。

## 1. 原始 `top_ddr_test` 实测（用户报告，2026-11-08）

- 位流 SHA-256：
  `610b0b1fe491ded30d8837a8d12ecef7a31780303161d81d32cdda7473751fd5`
  （用户已核对上传位流）。
- 下载方式：Program SRAM。
- 结果：

| LED | 原始定义 | 实测 |
|---|---|---|
| LED1 | 50 MHz 心跳 | **正常闪烁** |
| LED2 | `ddr_ready`（`ddrphy_rdy` 同步） | **不亮** |
| LED3 | pattern PASS | **不亮** |
| LED4 | pattern FAIL/超时 | **不亮** |

- 解释（暂定，待调试位流验证）：
  - `ddrphy_rdy` 可能一直为 0；
  - pattern 状态机 `start=ddr_ready`，一直停在 `ST_IDLE`；
  - `ST_IDLE` 特意不启动 timeout，因此 LED4 不亮；
  - `ddrphy_rst_n`（PLL 锁定/复位释放）在原顶层没有接出来，
    无法区分 PLL 未锁与校准未完成。
- **不能**据此断言校准失败的具体原因。

## 2. 调试位流（CAL_EN=1 / CAL_EN=0 均已上板）

### CAL_EN=1

- 位流：`build/bitstream/top_ddr_debug.bit`
- SHA-256：`03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46`
- 构建：Setup +1.446 ns / Hold +0.020 ns（紧）/ 1960 slices /
  7 DRAMHARDCON；构建记录
  `verification/static/top_ddr_debug_build_2026-11-08.md`
- 已知：`check_timing` 6 个 HIGH no-clock SCLK net、USR-6133
  primary-clock-on-internal-refclk；**不是时序签收**，但用于 LED 诊断。

### CAL_EN=0 对照

- 位流：`build/bitstream/top_ddr_debug_cal0.bit`
- SHA-256：`f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0`
- 构建：Setup +2.073 ns / Hold +0.021 ns / 1290 slices /
  7 DRAMHARDCON；**只改 CAL_EN=0**；构建记录
  `verification/static/top_ddr_debug_cal0_build_2026-11-08.md`
- 状态：**已上板（2026-11-08 用户报告）：LED1 闪、LED2 亮、LED3 亮、
  LED4 灭**。READY 可达；PHY 训练被绕过，不证明数据可靠。

- 步骤：`verification/board/bringup-ddr-debug.md`

| LED | 信号 | 1 s 实测 | 10 s 实测 |
|---|---|---|---|
| LED1 | 50 MHz 心跳 | **闪** | **闪** |
| LED2 | `ddrphy_rst_n`（PLL/复位） | **亮** | **亮** |
| LED3 | `ddrphy_rdy`（校准完成） | **灭** | **灭** |
| LED4 | 独立 50 MHz 超时 | **亮** | **亮** |

## 3. 结论

**CAL_EN=1：LED1 闪、LED2 亮、LED3 灭、LED4 亮（用户报告）。**

- PLL/复位已释放（LED2=1）；
- `ddrphy_rdy` 未到（LED3=0）；
- 1 s 独立超时已触发（LED4=1）。

这**不是**“校准失败”的具体原因；只说明 READY 未在窗口内到达。

**CAL_EN=0 对照（用户报告）：LED1 闪、LED2 亮、LED3 亮、LED4 灭**
→ READY 可达。但 CAL_EN=0 绕过 PHY 训练，**不证明数据可靠**；
数据路径由后续 `top_ddr_fb_hdmi` 的自检/读回 CRC 证明。

在 LED2=1、LED3=1、LED4=0 之前，不得写“DDR 初始化/校准通过”。
即使三者满足，也只证明状态机到了 READY，不证明 AXI 读写/数据可靠。
