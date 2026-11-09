# DDR 状态调试上板步骤（2026-11-08）

> 目标：只验证 DDR 的 **PLL 锁定 / 复位释放 / 初始化校准 READY / 超时**，
> 不发起任何 AXI 读写。
>
> CAL_EN=1 位流：`build/bitstream/top_ddr_debug.bit`
> SHA-256：`03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46`
> （Setup +1.446 / Hold +0.020 ns，1960 slices）
>
> CAL_EN=0 对照：`build/bitstream/top_ddr_debug_cal0.bit`
> SHA-256：`f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0`
> （Setup +2.073 / Hold +0.021 ns，1290 slices；只改 CAL_EN）
>
> 构建记录：`verification/static/top_ddr_debug_build_2026-11-08.md`、
> `verification/static/top_ddr_debug_cal0_build_2026-11-08.md`
> 构建：`fpga/scripts/build_top_ddr_debug.bat`
> 设计/故障判断：`docs/display/ddr-debug.md`
>
> 实测后写入
> `verification/board/evidence/20261108_ddr_debug/README.md`。

## 1. 准备

- 只接电源 + USB-JTAG；**不要接摄像头/HDMI**。
- 板卡 PH1P35_FT V1，器件 PH1P35MDG324。
- 确认 C4 50 MHz 有源晶振正常（唯一时钟输入）。
- 构建前先运行 `fpga/scripts/prepare_ddr_ip.sh`。

## 2. 构建

```bat
cd fpga\scripts
build_top_ddr_debug.bat
```

默认 `CAL_EN=1` → `build/bitstream/top_ddr_debug.bit`。
**不要**用 `DDR_CAL0=1` 作为第一步；它只是后续对照。

## 3. LED 定义

| LED | 信号 | 含义 |
|---|---|---|
| LED1 | 50 MHz 心跳 | 时钟/位流/电源基本正常 |
| LED2 | `ddrphy_rst_n` | PLL 锁定 / PHY 复位释放 |
| LED3 | `ddrphy_rdy` | 初始化/校准完成 |
| LED4 | 独立 50 MHz 超时（锁存） | 1 s 内 READY 未拉高 |

## 4. 实测记录

CAL_EN=1 已实测（用户报告，2026-11-08，等待 >10 s）：

| LED | 实测 |
|---|---|
| LED1 心跳 | 闪 |
| LED2 `ddrphy_rst_n` | 亮 |
| LED3 `ddrphy_rdy` | 灭 |
| LED4 超时 | 亮 |

判断：PLL/复位已释放，READY 未到，1 s 超时触发；执行 CAL_EN=0 对照。

CAL_EN=0 上板时记录：

- 1 s 时 LED1/LED2/LED3/LED4；
- 10 s 时 LED1/LED2/LED3/LED4；
- 若 LED3 晚于 1 s 亮，记录大约时间；
- 位流 SHA-256；
- 任何复位/重插后的变化。

## 5. LED 组合判断

| LED1 | LED2 | LED3 | LED4 | 判断 | 下一步 |
|---|---|---|---|---|---|
| 灭 | — | — | — | 时钟/位流/电源 | 烧已知彩条位流确认板卡 |
| 闪 | 灭 | 灭 | 灭 | 复位后 <1 s | 等 2 s 再看 |
| 闪 | 灭 | 灭 | 亮 | **PLL 未锁定/复位未释放** | 查 C4 50 MHz、POR、PLL；再考虑 100 MHz ref |
| 闪 | 亮 | 灭 | 亮 | **PLL 锁定，READY 未来** | 先做 CAL_EN=0 对照，再加阶段诊断 |
| 闪 | 亮 | 亮 | 亮 | READY 晚于 1 s | 记录延迟，查校准时钟/参考频率 |
| 闪 | 亮 | 亮 | 灭 | PLL+READY 正常 | 回到 pattern 测试；仍不代表数据可靠 |

## 6. 后续对照（仅在 LED2 亮、LED3 灭、LED4 亮时）

已构建：

```text
build/bitstream/top_ddr_debug_cal0.bit
SHA-256 f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0
```

该位流只把 `CAL_EN` 从 1 改成 0（PLL/参考时钟/tCK/CL/CWL/复位/
SDC/LED 逻辑/AXI-APB 全部不变）。烧录后：

- LED1 应闪；LED2 应亮（PLL/复位释放）；
- LED3 是 `ddrphy_rdy`：若 CAL_EN=0 让它亮，**只证明 READY 能到达**，
  不证明 DDR 数据读写可靠；
- LED4 是独立超时：LED3 亮且 LED4 灭 = READY 在 1 s 内；LED3 亮但
  LED4 亮 = READY 晚于 1 s；LED3 仍灭 = CAL_EN=0 也没解决，继续查
  初始化/复位/参考时钟，不要直接改数据路径。
- 本实验不发起 AXI/APB 事务，不证明 DDR 可用。

## 7. 证据

`verification/board/evidence/20261108_ddr_debug/README.md`：

- 位流 SHA、下载方式；
- 1 s/10 s LED 状态；
- 是否 LED2 亮、LED3 亮、LED4 灭；
- CAL_EN=0 对照（如有）及结果；
- 明确结论：PLL 锁定？READY？超时？
- 不要写“DDR 通过”；本测试不证明读写/数据可靠性。
