# 2026-11-08 DDR 最小读写测试上板证据

> **状态：BOARD RUN（2026-11-08，用户报告）——未进入 READY，不是 DDR PASS。**
>
> 用户实际 Program SRAM；上传位流 SHA-256 已核对：
> `610b0b1fe491ded30d8837a8d12ecef7a31780303161d81d32cdda7473751fd5`
>
> 结果：**LED1 正常闪烁；LED2/LED3/LED4 均不亮**。
>
> 这只说明当前位流没有观察到 `ddr_ready`/pattern PASS/超时；
> **不能**据此断定校准失败的具体原因。原始位流已保留。
> 后续状态调试：`verification/board/evidence/20261108_ddr_debug/`、
> `docs/display/ddr-debug.md`。

## 1. 测试配置

| 项目 | 值 |
|---|---|
| 日期 | 2026-11-08 |
| 板卡 | PH1P35_FT V1 / HX1P35B_FT_40P |
| 器件 | PH1P35MDG324 |
| DDR | 封装内 DDR2 512Mb x16（64 MB，1.5 V） |
| 位流 SHA | `610b0b1f…`（用户已核对） |
| 下载方式 | Program SRAM |
| 测试 | 16 × 128-bit pattern 写/读/比对 |
| ref_clk | C4 50 MHz |
| DDR 时钟 | 533.33 MHz（DDR2-1066，CAL_EN=1） |

## 2. LED（用户实测）

| LED | 含义 | 预期 | 实测 |
|---|---|---|---|
| LED1 | 50 MHz 心跳 | 1 Hz 闪 | **正常闪烁** |
| LED2 | `ddr_ready`（`ddrphy_rdy` 经 `dhi_clk` 同步） | 常亮 | **不亮** |
| LED3 | pattern PASS | 常亮 | **不亮** |
| LED4 | pattern FAIL/超时 | 熄灭（PASS） | **不亮** |

## 3. 现象分析（暂定）

- LED2 是 `ddrphy_rdy` 经 **`dhi_clk`** 两级同步后的结果；如果
  PLL/`dhi_clk` 未起或 `ddrphy_rdy` 未拉高，LED2 不亮。
- pattern 状态机的 `start=ddr_ready`；`ddr_ready=0` 时它停在
  `ST_IDLE`，**不发起 AXI 事务**。
- `ST_IDLE` 刻意不启动 timeout（等校准是无限期的），所以 LED4
  也不亮；这不是“超时坏了”，而是超时被放在依赖 READY 的状态机里。
- 原顶层没有引出 `ddrphy_rst_n`，无法区分 PLL 未锁与校准未完成。

**不能**根据这组 LED 断言“校准失败”或“PLL 未锁”；需要状态调试位流。

## 4. 结论

**FAIL to reach READY（用户报告，2026-11-08）。**

- 单行/pattern 测试没有进入读写阶段；
- 原始 `top_ddr_test.bit` 保留，未覆盖；
- 下一步：烧 `top_ddr_debug.bit`，看 LED2=`ddrphy_rst_n`、
  LED3=`ddrphy_rdy`、LED4=独立超时。

最小读写 PASS 仍未被证明；更不代表 640×480 帧缓存/实时画面。
