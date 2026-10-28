# DVP 上板第一步：抓 PCLK / VSYNC / HREF 三通道

> **目标**：先用逻辑分析仪确认 OV5640 的 PCLK 频率、VSYNC/HREF 极性、
> 行/场结构。**本轮不抓 D0–D7，不做彩条，不做 HDMI。**
>
> 位流已生成：`build/bitstream/top_dvp_test.bit`。
> 尚未在你的实物上验证；下面的参数表需要你实测填写。

## 1. 这个位流做什么

1. FPGA 上电后拉低 PWDN、拉低 RESET，约 10 ms；
2. 释放 RESET，等待约 20 ms；
3. SCCB 读 Chip ID（0x300A/0x300B），成功后写 RGB565 配置表；
4. 配置完成后回读关键寄存器（0x4300 / 0x4740 / 0x3808–0x380B / 0x503D 等）；
5. 回读通过后使能 DVP 采集，等 10 帧后开始计数；
6. LED 显示状态；PCLK/VSYNC/HREF 同时可在 J2 上用 LA 抓取。

配置表显式写 **`0x4740 = 0x22`**：VSYNC 实测 **高有效**；HREF 的**引脚**
极性仍待 D0–D7 两相对比确认。此前尝试的 `0x23` 对应 VSYNC 低有效。

## 2. 涉及文件

| 用途 | 路径 |
|---|---|
| 顶层 RTL | `fpga/rtl/top/top_dvp_test.v` |
| 上电/复位/ID/配置封装 | `fpga/rtl/camera/ov5640_bringup.v` |
| RGB565 配置/回读 | `fpga/rtl/camera/ov5640_cfg.v` |
| 配置表 ROM（生成） | `fpga/rtl/camera/ov5640_cfg_rom.v` |
| DVP 采集 | `fpga/rtl/camera/dvp_capture.v` |
| 异步事件 FIFO | `fpga/rtl/common/async_fifo_gray.v` |
| 50MHz 监视器 | `fpga/rtl/camera/dvp_status_monitor.v` |
| 引脚约束 | `fpga/constraints/top_dvp_test.adc` |
| 时序约束 | `fpga/constraints/top_dvp_test.sdc` |
| 构建脚本 | `fpga/scripts/build_top_dvp_test.bat` / `.tcl` |
| 位流 | `build/bitstream/top_dvp_test.bit` |
| 构建记录 | `verification/static/top_dvp_test_build_2026-10-26.md` |

## 3. 接线

摄像头接线保持 `docs/hardware/wiring.md` 的完整接法。本测试额外需要把
LA 接到 J2 的这三根：

| 信号 | ATK P1 | J2 | FPGA 球位 | 方向 |
|---|---:|---:|---|---|
| PCLK | 15 | **J2-7** | F14 | camera → FPGA |
| VSYNC | 4 | **J2-21** | K16 | camera → FPGA |
| HREF | 6 | **J2-20** | K17 | camera → FPGA |

D0–D7 可以保持连接，本轮不要求抓；下一轮彩条再抓。

注意：

- **不要接 J2-11（5 V）**；摄像头 3.3 V 接 J2-29，GND 接 J2-30。
- SCL/SDA 仍依赖 FPGA 内部上拉；若 LED2 一直不亮，优先补 4.7 kΩ 外部上拉。
- 摄像头先接好再上电，不要带电插拔。

## 4. 生成/下载位流

如果已有 `build/bitstream/top_dvp_test.bit`，可直接下载。重新生成：

```bat
setx TD_HOME "C:\path\to\TD_6.2.1"
cd /d <repo-root>
fpga\scripts\build_top_dvp_test.bat
```

下载：BitWizard → Refresh → Add `top_dvp_test.bit` → **Program SRAM** → Run。
首次验证不要写 Flash。

## 5. LED 含义与预期

| 物理 LED | 信号 | 含义 |
|---|---|---|
| LED1 | `hb` | 1Hz 心跳，FPGA 已配置并运行 |
| LED2 | `cfg_ok` | 配置 + 回读成功 |
| LED3 | `mon_frame_cnt[0]` | 每来一帧翻转；有帧时快速闪烁/变暗 |
| LED4 | 错误 | 配置错误、行/场错误或事件 FIFO 溢出 |

预期时间线：

1. 下载后 LED1 先闪；
2. 约 0.3 s 内 LED2 点亮（上电/复位/ID/249 条配置 + 回读）；
3. 再过约 10 帧，LED3 开始翻转；
4. 如果实际行/像素数与默认 1280/480 一致，LED4 保持灭。

> LED4 亮但 LED2 亮：配置本身成功，但 DVP 行/场计数与默认值不符。
> 这不一定是硬件故障；先把三通道实测值记下来，再更新参数。
>
> LED2 不亮：配置/回读失败。先检查 SCCB 上拉、摄像头供电和接线；
> 可以用旧的 `top_cam_id.bit` 复核 Chip ID。

### 5.1 2026-10-26 实测结果（通过）

用户确认的通道映射：

| LA 通道 | 信号 | J2 | 球位 |
|---|---|---|---|
| Channel 0 (D0) | PCLK | J2-7 | F14 |
| Channel 1 (D1) | VSYNC | J2-21 | K16 |
| Channel 2 (D2) | HREF | J2-20 | K17 |

实测：

| 项目 | 实测值 |
|---|---|
| PCLK | **48.000 MHz**（20.833 ns；旧写的 50 MHz 是 20 ns 量化误读） |
| VSYNC 周期 / 帧率 | **33.333 ms / 30 Hz** |
| VSYNC 极性 | **`0x22` = 高有效**（空闲低、66.665 µs 高脉冲）；**`0x23` = 低有效**（空闲高、短低脉冲） |
| HREF 周期 / 行率 | **66.665 µs / 15 kHz** |
| HREF 高/低电平 | 高 **40 µs = 1920 PCLK**；低 **26.665 µs = 1280 PCLK** |
| HREF 极性 | **A/B 未定**：低相位 1280 PCLK（低有效）；或高相位 1280 有效 + 640 dummy（高有效）。需 D0–D7 彩条对比 |
| 每帧 HREF 上升沿 | **480**（不是 500） |
| 每帧行周期 | 500 个（33.333 ms / 66.665 µs），其中约 20 行为垂直消隐 |
| 每帧 HREF 长高 | **1.373 ms**，开始于 VSYNC 上升前 240 µs、结束于下降后 1.066 ms |

LED 状态：LED1/LED3 正常闪烁，LED2/LED4 常亮。LED2=`cfg_ok`。

LED4 原因（2026-10-26 CSV）：**VSYNC 极性配对错误**（`0x22` 实测高有效，
而当前参数是 0）+ **HREF 每帧 1.373 ms 长高**被当成 65920 字节的长行，
且 VSYNC 沿落在 HREF 高电平内触发 `vsync_mid_line`。**不是 480 vs 500**。

结论：**三通道时序验证通过**。证据：
`verification/board/evidence/20261026_dvp_three_channel/`。

> 2026-10-26 的修正方向需要调整：`0x22`+`VSYNC_ACTIVE_HIGH=0` 是错误配对。
> 应改为 `0x22`+1，或回 `0x23`+0；同时处理垂直消隐期间的 HREF 长高。
> 行数保持 480。D0–D7/彩条留到下一轮。
>
> **2026-10-28：11 通道尝试失败。** 13:58 的 HREF 包络仍是 15 kHz/
> 1280 字节，但 CH1 不是 VSYNC、D0–D7 全 0；14:36 的 HREF 单测变成
> 29.53 kHz。16:24 的 LED4 熄灭只证明低相位是 1280 PCLK，**不证明低相位
> 是有效彩条**（高有效 B 解释同样能通过长度检查）。复测步骤见
> `verification/board/evidence/20261028_dvp_11ch/README.md` §5。

## 6. LA 采集设置

- 通道：PCLK（J2-7）、VSYNC（J2-21）、HREF（J2-20）。
- 采样率：至少 **200 MS/s**；PCLK 已实测为 **48.000 MHz**，建议 **250–500 MS/s**。
- 触发：VSYNC 边沿（先试上升沿；若没有，再试下降沿）。
- 时间窗：至少覆盖 **2–3 帧**；若帧率未知，先用 50–100 ms 窗口。
- 地：LA 地必须与 J2-30（GND）可靠连接，不要只靠 USB 地。

## 7. 需要记录的数据

| 项目 | 实测值 | 备注 |
|---|---|---|
| PCLK 频率 / 周期 | | |
| PCLK 占空比 | | |
| PCLK 在消隐期是否停振 | | 是/否 |
| VSYNC 极性 | | 高有效/低有效 |
| VSYNC 脉宽 | | PCLK 周期或 µs |
| VSYNC 周期 / 帧率 | | |
| HREF 极性 | | 高有效/低有效 |
| HREF 高电平 PCLK 数 | | 期望 1280（RGB565 640 像素） |
| 每帧 HREF 行数 | | 期望 480 |
| HREF 周期 / 行率 | | |
| D0 是否有活动（可选） | | 本轮可不抓 |

同时记录：

- 位流路径/日期；
- LA 型号、采样率、触发设置、时间窗；
- LED1–4 的状态和变化；
- 任何异常（无波形、波形抖动、电平幅度异常等）。

## 8. 判定

本轮“通过”的最低条件（2026-10-26 已全部满足）：

- [x] LED1 心跳；LED2 点亮。
- [x] LA 能稳定抓到 PCLK、VSYNC、HREF。
- [x] 记录到可重复的 PCLK 频率、VSYNC 周期/脉宽、HREF 高电平 PCLK 数、
      每帧行数。
- [x] 极性/电平与 3.3 V/2.8 V 兼容性没有明显异常。

不要求本轮 D0–D7 正确；彩条和字节序在下一轮验证。

## 9. 证据归档

把截图/波形导出和记录放到：

```text
verification/board/evidence/20261026_dvp_three_channel/
```

`README.md` 至少包含：日期、位流、接线、LA 设置、实测参数、LED 状态、
结论和限制。不要填写未测量的数字。

## 10. 下一步

1. ~~用实测 PCLK/极性更新 SDC、`0x4740`、`VSYNC_ACTIVE_HIGH` 和
   `EXPECTED_PIX`~~ —— 已完成，但按 48 MHz 修正：`0x22`、VSYNC 高有效、
   `EXPECTED_PIX=1280`（低相位）/1920（高相位）；HREF 极性待 D0–D7。
2. 重新下载 16:24 重建位流 `top_dvp_test_20261026_rebuild.bit`，
   确认 LED2 亮、LED4 状态；**不要用 LED4 单独判定数据正确**。
3. 整机断电重上电后再抓 PCLK/HREF/VSYNC；若 HREF 29.5 kHz，同窗抓
   PCLK 判断是否默认 1280×960 模式。
4. 生成/使用 `COLOR_BAR=1` 的位流，抓 D0–D7：
   - 确认 RGB565 高字节在前；
   - 解释 HREF 高 1920 PCLK / 低 1280 PCLK 与 640 像素（1280 字节）的关系：
     A. 低有效 = 低相位就是有效数据；B. 高有效 = 高相位前 1280 有效 +
     640 dummy。用彩条 run table 定论。
5. 再进入 HDMI 时序。
