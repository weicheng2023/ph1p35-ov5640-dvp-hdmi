# DVP 三通道复核 — 2026-11-06

> **结论：VSYNC/HREF 时序复核通过，和 2026-10-26 的 15:47 成功一致。**
> 本次是 3 通道（PCLK/VSYNC/HREF），没有 D0–D7；PCLK 在 50 MS/s 下
> 欠采样，只能作为“与 48 MHz 别名一致”的旁证，不能单独证明 48.000 MHz。
> **DVP 已暂停**；摄像头彩条见 §6（延后，不是当前任务）。当前方向是
> HDMI 显示彩条，见 `docs/display/README.md`。HREF 极性 A/B 仍未由数据确定。

## 1. 采集条件

| 项目 | 值 |
|---|---|
| 文件 | `verification/LA/2026_11_6_PCLK_VSYNK_HREF.atkdl` |
| SHA-256 | `3547d8d1329cb2bf00bfb4f7d0485ca8648e842aa99fb5bf9dc0b9c83d08c016` |
| 大小 | 104,579 bytes（ZIP；解包后 3 个通道各 2×1 MiB bin） |
| 采样率 | **50 MS/s**（`set.ini` `setHz=50000000`；`SamplingFrequency=50000` kHz） |
| 时长 / 深度 | **200 ms**；`SamplingDepth=10,000,000`；通道有效采样 10,000,104（起始 3） |
| 通道 | CH0=PCLK、CH1=VSYNC、CH2=HREF；其余关闭 |
| 阈值 | 1.6 V |
| 触发 | 通道 0（PCLK）触发类型 3；`TriggerSamplingDepth=100,000` |
| 位流 | **未记录在 `.atkdl` 中**。同步波形与 13:16/16:24 两版都一致；本次只验证摄像头输出时序，不依赖 FPGA 的 HREF 参数 |

`.atkdl` 的 bin 是**每字节 8 个采样、LSB 在前**的位流；`N/channel.ini`
第 2 行是起始采样号、第 3 行是有效采样数。分析脚本
`tools/extract_atkdl.pl` 会把它转成与 `tools/analyze_dvp_la.pl` 兼容的
transition CSV。

## 2. 现象（测量）

### 2.1 VSYNC（CH1）— 通过

- 200 ms 内 6 个完整高脉冲：上升沿在 **11.740 / 45.073 / 78.406 /
  111.739 / 145.073 / 178.406 ms**。
- 周期：**33.333 ms**（30.000 Hz），高电平 **66.660–66.680 µs**。
- 空闲低、高脉冲 → **高有效**，与 `0x4740=0x22` 的实测一致。
- 和 2026-10-26 的 33.333 ms / 66.665 µs 一致。

### 2.2 HREF（CH2）— 通过

- 正常行高电平（35–45 µs 窗）：**2,873 个**，平均 **39.997 µs**。
- 正常行低电平：**26.66 µs**（66.66 µs 周期 − 40.00 µs 高）。
- 行周期：**66.66 µs = 15.0 kHz**。
- 每帧正常行（35–45 µs）：**479 个**；加上垂直消隐的长高，等效 **480 行/帧**。
- 垂直消隐：每帧有两个长高：
  - **0.240 ms**，结束于 VSYNC 上升沿；
  - **1.066 ms**，开始于 VSYNC 下降沿之后。
  - 两者之间是 **66.7 µs 低电平**，正好与 VSYNC 高脉冲重合；
    因此 HREF 的“长高包络”是 **0.240 + 1.066 = 1.306 ms 高 +
    0.0667 ms 低 ≈ 1.373 ms**，被 VSYNC 脉冲切成两段。
  - 这解释了为什么按“上升沿”数会得到 **481** 个/帧（479 正常 +
    2 段消隐长高），而有效行仍是 **480**。
- 848 个 **0.42 µs（21 采样）** 的短高脉冲；它们不是正常行，像 PCLK/
  边沿串扰或探头噪声。正常 40 µs 行不受影响；后续彩条采集时应继续
  用单根短地、摄像头侧探头、1.4–1.8 V 阈值来减少它们。

### 2.3 PCLK（CH0）— 只能算旁证

- 50 MS/s 低于 48 MHz PCLK 的 Nyquist（96 MS/s），所以 PCLK 被
  **欠采样/混叠**：采样后看到约 **2 MHz** 的方波。
- 实测上升沿间隔以 **25 采样（500 ns）** 为主（25×72,531、
  26×3,808、24×3,622），高约 10 采样（200 ns）、低约 15 采样（300 ns）。
- 这和 **48 MHz 在 50 MS/s 下混叠到 2 MHz** 完全一致：
  `|48 − 50| = 2 MHz`，周期 25 采样。但混叠不能唯一确定 48 MHz
  （52 MHz 也会混叠到 2 MHz）；**48.000 MHz 的直接证据仍是
  2026-10-26 的 200/250 MS/s 捕获**（平均 20.833 ns）。
- 结论：本次 **不能**用 50 MS/s 的 PCLK 波形去证明 48.000 MHz；
  彩条采集必须用 **200/250 MS/s**。

## 3. 和 2026-10-26 成功采集的对比

| 项目 | 2026-10-26 15:47 | 2026-11-06 本次 |
|---|---|---|
| 采样率 | 200 MS/s | 50 MS/s |
| 时长 | 0.5 s | 200 ms |
| PCLK | 48.000 MHz（直接） | 2 MHz 混叠（欠采样，不能直接证明） |
| VSYNC | 30 Hz，66.665 µs 高，高有效 | 30 Hz，66.66–66.68 µs 高，高有效 |
| HREF | 15 kHz，高 40 µs，低 26.665 µs | 15 kHz，高 39.997 µs，低 26.66 µs |
| 行/帧 | 480 | 479 正常 + 消隐长高 = 480 等效 |
| 消隐长高 | 1.373 ms，横跨 VSYNC | 0.240 + 1.066 ms，中间被 VSYNC 切成 66.7 µs 低 |
| 通道 | 3 | 3 |
| D0–D7 | 无 | 无 |

结论：**VSYNC/HREF 与上次成功一致；PCLK 需要更快的采集才能复核。**
2026-10-28 的 29.53 kHz 异常本次没有复现，说明它更可能是当时的
摄像头复位/默认模式或探头状态，而不是稳定的配置问题。仍需在彩条采集
时保持整机断电重上电，避免再次出现。

## 4. 解释 / 保留项

- **VSYNC/HREF 通过**：周期、脉宽、极性、行数都与 15:47 成功一致。
- **PCLK 欠采样**：50 MS/s 只能看到 2 MHz 混叠；不要把它写成
  “PCLK 48 MHz 已验证”。48.000 MHz 来自 200/250 MS/s 的历史捕获。
- **HREF 极性 A/B 仍未定**：本次只看 HREF 本身（高 40 µs / 低 26.66 µs），
  没有 D0–D7，无法判断 1280 字节有效数据在低相位还是高相位前段。
  16:24 位流的 LED4 熄灭只证明长度，不证明数据。
- **HREF 消隐长高被 VSYNC 切成两段**：与 15:47 的“1.373 ms 连续长高”
  描述略有差异；本次是 0.240 + 0.0667 低 + 1.066 ms，总包络相同。
  不要因为上升沿 481 vs 480 就改 `EXPECTED_LINES`；有效行仍是 480。
- **848 个 0.42 µs 短脉冲**：暂时按串扰/探头噪声处理，不影响正常行；
  彩条采集时观察是否随接地/探头改善。

## 5. 复现分析

```bash
# 1) 把 atkdl 转成 analyze_dvp_la.pl 能读的 transition CSV
perl tools/extract_atkdl.pl \
  "verification/LA/2026_11_6_PCLK_VSYNK_HREF.atkdl" \
  --max-samples=2000000 > build/la_test/20261106_3ch.csv

# 2) 按 HREF 低有效 / 高有效各看一次
perl tools/analyze_dvp_la.pl build/la_test/20261106_3ch.csv --href-active=low
perl tools/analyze_dvp_la.pl build/la_test/20261106_3ch.csv --href-active=high
```

`--max-samples=2000000` 是 40 ms（约 600 行），足够看周期；不加则
转完整 200 ms，CSV 会更大。PCLK 在 50 MS/s 下是混叠，脚本的
PCLK 周期统计只反映混叠频率，不要当 48 MHz 证据。

## 6. DVP 后续（暂停）：摄像头彩条测试

> **当前不执行本节。** 2026-11-06 方向已切换为 **HDMI 显示彩条**
> （FPGA 内部彩条 → 显示器，不接摄像头、不用 DDR）。本节保留为 DVP
> 未来的摄像头彩条计划；当前入口见 `docs/display/README.md` 和
> `docs/project/next-session-prompt.md`。

### 6.1 位流

使用 **16:24 诊断重建**（`COLOR_BAR=1`、`0x503D=0x80`、
`VSYNC_ACTIVE_HIGH=1`、`HREF_ACTIVE_HIGH=0`、`EXPECTED_PIX=1280`、
`EXPECTED_LINES=480`）：

```text
build/bitstream/top_dvp_test_20261026_rebuild.bit
SHA-256 b6df6c18cbe00436b4b8e4099cbe456fe6e1a229e7318486986049d81524087f
```

也可用同内容的 `build/bitstream/top_dvp_test_20261106_colorbar.bit`
（本次复制，SHA 相同）。**不要**用 12:33 的失败调试位流
`top_dvp_test.bit`。

### 6.2 上板 / LA

1. **整机断电再上电**（FPGA + 摄像头一起），让 SCCB 重新配置；
   确认 LED2 亮（`cfg_ok`）。
2. 11 通道接线：
   - CH0 PCLK J2-7 / F14
   - CH1 VSYNC J2-21 / K16
   - CH2 HREF J2-20 / K17
   - CH3–CH10 D0–D7 J2-22/23/24/25/26/27/28/31
   - GND 只留**一根短地** J2-30 或摄像头 P1-1；阈值 **1.4–1.8 V**；
     探头夹摄像头侧、47 Ω 之前。
3. **采样率 200/250 MS/s**（不要 50 MS/s；PCLK 会混叠）。
4. 触发：HREF 下降沿（低有效假设）或上升沿，预触发 10 µs；
   采集 **100 µs**（约 1.5 行）。若 LA 通道数/内存不够，先抓
   PCLK/HREF/D0–D7（10 通道），VSYNC 用 3 通道的大窗口另抓。
5. 分析：

```bash
perl tools/extract_atkdl.pl capture.atkdl --max-samples=200000 > line.csv
perl tools/analyze_dvp_la.pl line.csv --href-active=low  --max-lines=3 --show-pixels=16
perl tools/analyze_dvp_la.pl line.csv --href-active=high --max-lines=3 --show-pixels=16
```

### 6.3 判定

- 先看 **run table**：哪一相（HREF 低或高）出现 8 色条；不要预设
  条宽 80 px 或颜色顺序。`analyze_dvp_la.pl` 的默认 expected 只是
  假设，若实际条宽/顺序不同，先改期望，不要改摄像头。
- 有效行应为 **1280 字节 = 640 像素**；若低相位 1280 字节但 D0–D7
  全 0，说明低相位是消隐，HREF 极性应改为高有效（B 解释）。
- 若高相位有 1920 字节，前 1280 字节为有效彩条、后 640 字节为
  dummy/padding，则 `HREF_ACTIVE_HIGH=1`，`EXPECTED_PIX` 需按实际
  有效窗口决定（1920 或 1280 + 偏移）。
- 确认字节序：`0x4300=0x61`，每像素高字节在前。
- 只有 run table 自洽后，才改 FPGA 的 `HREF_ACTIVE_HIGH` /
  `EXPECTED_PIX`，再加 on-chip checker / LED4。
- 在定极性前，不改 `0x3035/36/37`、`0x3108`、`0x503D`、`0x4300`、
  `0x4740`。

## 7. 证据文件

- `verification/LA/2026_11_6_PCLK_VSYNK_HREF.atkdl` — 本次原始抓包
  （104 KB，已入库；bin 解包在 `build/la_test/atkdl_20261106/`，gitignored）。
- `tools/extract_atkdl.pl` — atkdl → transition CSV。
- `tools/analyze_dvp_la.pl` — 已有的 DVP CSV 分析。
- `verification/board/la-dvp-11ch.md` — 接线与 LA 设置。
