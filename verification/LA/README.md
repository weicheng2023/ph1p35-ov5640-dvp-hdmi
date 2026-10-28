# 逻辑分析仪原始抓包

> 原始 CSV 体积很大（0.5 s @ 200 MHz × 3 通道约 2.3 GB），**不入库**；
> `verification/LA/*.csv` 已被 `.gitignore` 忽略。这里只保留抓包清单和分析结论。

## 当前抓包

| 文件 | 采样率 | 时长 | 通道 | 备注 |
|---|---|---:|---|---|
| `DVP_10_26_15_47.csv` | 200 MHz | 0.5 s | Ch0=PCLK, Ch1=VSYNC, Ch2=HREF | 2026-10-26 三通道 |
| `DL32 Plus.csv` | 200 MHz | 1 ms | 11 通道 | 2026-10-28 13:41，D0–D7 有跳变 |
| `pclk vsync href.csv` | 250 MHz | 1 ms | 11 通道 | 2026-10-28 13:58，HREF 包络有效、VSYNC 无效 |
| `href.csv` | 250 MHz | 1 ms | 3 通道 | 2026-10-28 14:36，只有 HREF；29.53 kHz |

2026-10-28 的失败尝试、现象/推测和复测步骤见
`verification/board/evidence/20261028_dvp_11ch/README.md`。

## 2026-10-26 关键结论（含 2026-10-28 修正）

- **PCLK = 48.000 MHz**，不是 50 MHz。
  - 0.5 s 内 24,000,131 个上升沿 → 48.000 MHz；
  - 200 MS/s 下 20/21 ns、250 MS/s 下 20/24 ns 是 5/4 ns 采样的量化，
    不是抖动；
  - 旧文档的 50 MHz 是 20 ns 粗量化的误读；SDC 50 MHz 偏保守。
- `0x4740=0x22`：VSYNC **高有效**（空闲低、66.665 µs 高脉冲、33.333 ms 周期）。
- `0x4740=0x23`：VSYNC **低有效**（空闲高、短低脉冲）。
- HREF = **15 kHz / 66.665 µs 周期**；高约 **40 µs = 1920 PCLK**，
  低约 **26.665 µs = 1280 PCLK**（按 48 MHz 计算；旧文档的 2000 PCLK
  是 50 MHz 下的近似）。
- 每帧 **480** 个 HREF 上升沿；每帧一次 **1.373 ms** HREF 长高（垂直消隐），
  横跨 VSYNC 脉冲。
- **HREF 极性仍未最终证明**：低相位正好 1280 PCLK，16:24 的
  `HREF_ACTIVE_HIGH=0` + `EXPECTED_PIX=1280` 会因长度匹配而让 LED4 熄灭；
  但高相位 1920 PCLK 也可能是“1280 有效 + 640 dummy”的高有效模式。
  必须用 D0–D7 彩条比较低/高兩相才能定论（见 2026-10-28 证据文档 §3.4）。

## 分析工具

```bash
perl tools/analyze_dvp_la.pl "verification/LA/pclk vsync href.csv" --href-active=low
perl tools/analyze_la_csv.pl verification/LA/DVP_10_26_15_47.csv
perl tools/find_long_href.pl verification/LA/DVP_10_26_15_47.csv
```

`analyze_dvp_la.pl` 默认 CH0=PCLK、CH1=VSYNC、CH2=HREF、CH3..10=D0..D7；
`analyze_la_csv.pl` 统计三通道脉宽/HREF 高内 PCLK 数；`find_long_href.pl`
定位超长 HREF 高。两个脚本都按行流式读取，不把 CSV 装入内存。

`href.csv` 只有 HREF，没有 PCLK；脚本会报 `no PCLK rise edge`，这是正常的，
用原始脉宽统计即可（30.856 µs 高 / 3.002 µs 低 / 33.858 µs 周期 = 29.53 kHz）。

## 2026-10-28 结论摘要

- 13:58 11 通道：PCLK 48.000 MHz；HREF 低有效包络 15 kHz / 1280 字节/行，
  但高相位有 12–16 ns 的 PCLK 串扰；VSYNC 通道只有 4 ns 尖峰，不是 30 Hz；
  D0–D7 全 0（同批 13:41 数据是跳变的，故更像探头/接线状态）。
- 14:36 HREF 单测：30.856 µs 高 / 3.002 µs 低 / 33.858 µs 周期 = **29.53 kHz**，
  稳定、干净；不是 15 kHz HREF，也不是 30 Hz VSYNC。
- **推测**：14:36 更像摄像头复位后回到默认 1280×960 时序（≈41.5 MHz、
  30.8 fps），而不是接地干扰直接改频率；FPGA 只在启动时配置一次，
  摄像头复位后不会自动重跑 SCCB。
- 接地/多地环路可以解释毛刺和 4 ns 尖峰，但不能单独解释稳定的 29.53 kHz。
- 复测时先整机断电再上电，抓 PCLK+HREF+VSYNC；若 HREF 仍 29.5 kHz，
  同窗抓 PCLK 判断是否 ~41.5 MHz 的默认模式。

## 优先做的小实验

1. HREF 边沿触发，抓 100 µs（约 1.5 行），250 MS/s，11 通道；
   同时用 `--href-active=low` 和 `--href-active=high` 分析，比较哪一相
   出现 8 色彩条。
2. VSYNC 边沿触发，抓 35 ms（一帧），250 MS/s；确认 480 行/帧。
3. 不要一开始用 Stream 模式抓 0.5 s，CSV 会到 GB 级。
