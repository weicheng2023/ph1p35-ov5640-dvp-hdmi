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

配置表显式写 **`0x4740 = 0x22`**：PCLK/HREF 高有效、**VSYNC 低有效**。
这是 2026-10-26 实测后修正的值；此前尝试的 `0x23`（VSYNC 高有效）与 LA
波形不符。

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
| PCLK | **50 MHz**（20 ns，50%） |
| VSYNC 周期 / 帧率 | **33.33 ms / 30 Hz** |
| VSYNC 极性 | **低有效**（空闲高、短低脉冲） |
| HREF 周期 / 行率 | **66.67 µs / 15 kHz** |
| HREF 高电平 | **40 µs（60%）** |
| HREF 高电平 PCLK 数 | **2000**（40 µs × 50 MHz） |
| 每帧总行数 | **500**（33.33 ms / 66.67 µs） |
| 有源行数 | 预期 480，未单独计数 |

LED 状态：LED1/LED3 正常闪烁，LED2/LED4 常亮。LED2=`cfg_ok`；
LED4 是旧默认值 `EXPECTED_PIX=1280` 与实际 2000 不符，不是配置失败。

结论：**三通道验证通过**。证据：
`verification/board/evidence/20261026_dvp_three_channel/`。

> 2026-10-26 已按实测修正：`0x4740=0x22`、`VSYNC_ACTIVE_HIGH=0`、
> `EXPECTED_PIX=2000`、PCLK SDC=50 MHz，并重新生成位流。
> 新位流已复测：**LED4 仍亮**，说明行/场计数仍不匹配
> （可能 `EXPECTED_LINES=480` vs 实际约 500 行/帧）。三通道时序验证仍通过；
> LED4 的计数问题待定位。D0–D7/彩条留到下一轮。

## 6. LA 采集设置

- 通道：PCLK（J2-7）、VSYNC（J2-21）、HREF（J2-20）。
- 采样率：至少 **200 MS/s**；PCLK 已实测为 **50 MHz**，建议 **500 MS/s–1 GS/s**。
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
   `EXPECTED_PIX`~~ —— 已完成（50 MHz、`0x22`、VSYNC 低有效、2000）。
2. 重新下载修正后的 `top_dvp_test.bit`，确认 LED2 亮、LED4 是否熄灭。
3. 生成 `COLOR_BAR=1` 的位流，抓 D0–D7：
   - 确认 RGB565 高字节在前；
   - 解释 HREF 高电平 2000 字节 vs 有源 640 像素（1280 字节）的差异
     （dummy/padding 还是实际宽度不同）。
4. 再进入 HDMI 时序。
