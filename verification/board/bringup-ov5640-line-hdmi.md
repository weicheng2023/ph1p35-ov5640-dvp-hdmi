# OV5640 单行 → HDMI 上板步骤（2026-11-08）

> **实测状态：PARTIAL PASS（2026-11-08 用户报告）。**
> LED1–LED4 全部符合设计；HDMI 显示单行重复的 480 行；但画面是
> “左侧宽黑条 + 右侧浅蓝紫”，不是预期 8 色条。像素内容正确性未确认。
> 用户决定暂停彩条/LA 排查，转阶段 2 DDR。证据：
> `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`。
>
> 本文保留为操作步骤/回归步骤，不是完整 PASS 证据。
>
> 目标：在**已成功的 HDMI 链路**上显示真正来自 OV5640 D0–D7 的
> 内部彩条（一行重复 480 次）。
>
> 位流：`build/bitstream/top_ov5640_line_to_hdmi.bit`
> SHA-256：`67eec013651ccdde7291e3e26d1ec1a506e92111076651f0a49cf7ff0e3222cd`

## 0. 准备

- 摄像头 ATK-MC5640（OV5640，8-bit DVP）接 J2，按
  `docs/hardware/wiring.md`：
  - 3.3V = J2-29，GND = J2-30；
  - SCL = J2-32，SDA = J2-33；
  - VSYNC/HREF/PCLK/D0–D7 按表；
  - **J2-11 是 5V，禁止接摄像头**。
- HDMI 显示器接 HDMI1。
- 确认摄像头模组 P1 的 Pin 1/电源脚方向（见 wiring.md §6.1）。
- 不要接 DDR/其他外设。

## 1. 断电检查

1. 断电，检查摄像头 3.3V/GND 没有短路。
2. 目视检查 J2 排线，特别是 3.3V/GND 和 PCLK。
3. 确认 HDMI 线连接良好。

## 2. 上电

1. 上电，测 J2-29 ≈3.3 V、J2-30 = 0 V。
2. 摄像头模组应温热但不烫；异常发热/电流过大立即断电。
3. HDMI 侧按彩条阶段的电压检查（pin 18 ≈5 V、`+3.3V_HDMI` ≈3.3 V）。

## 3. 下载位流

1. BitWizard → Refresh → Add bit file →
   `build/bitstream/top_ov5640_line_to_hdmi.bit`。
2. **Program SRAM** → Run（首次不要写 Flash）。
3. 记录下载是否成功。

## 4. 预期 LED

| 物理 LED | 含义 | 预期 |
|---|---|---|
| LED1 | 50 MHz 心跳 | 1 Hz 闪 |
| LED2 | cfg_ok（SCCB 配置+回读） | 常亮 |
| LED3 | capture_done（已冻结一条有效行） | 常亮 |
| LED4 | capture_error / 无 cfg_ok / 无 PLL lock | 熄灭 |

- LED2 亮 = 摄像头配置成功（含 `0x503D=0x80` 彩条、`0x4300=0x61`）。
- LED3 亮 = 已经抓到一条长度在 1200–2200 字节之间的行。
- LED4 亮 = 没有有效行或配置失败。

## 5. 预期显示

- 上电/配置完成前：**深蓝色背景**（`0x000040`）。
- 抓到有效行后：**OV5640 内部彩条**，同一行重复 480 次，形成整屏
  竖向条纹。
- 颜色/顺序由 OV5640 内部测试图案决定；不要用“FPGA 彩条”的
  白/黄/青/绿/品红/红/蓝/黑顺序去强行套。
- 记录：颜色顺序、是否有通道交换、是否有整行错位、是否稳定。

## 6. 异常排查

### 6.1 LED2 不亮（配置失败）

1. 查摄像头 3.3V/GND、SCCB SCL/SDA 接线；
2. 查 SCCB 上拉（板卡/模组未画外部上拉，当前用 FPGA 内部上拉）；
3. 可先烧 `top_cam_id.bit` 回归 Chip ID `0x5640`；
4. 不要在没有配置成功时继续判断像素数据。

### 6.2 LED4 亮、LED3 不亮（没有有效行）

1. 确认 PCLK 有波形、频率约 48 MHz；
2. 确认 HREF 有 15 kHz 包络；
3. 当前默认 `HREF_ACTIVE_HIGH=1`。若摄像头实际是低有效，
   需要改参数重建（见 §7）；
4. 确认行长在 1200–2200 字节；如果实际是 1280/1920 之外，
   记录实测值再调整 `LINE_MIN/LINE_MAX`；
5. 如果摄像头回到默认 1280×960（HREF ~29.5 kHz），说明 SCCB
   没有重新配置；整机断电重上电。

### 6.3 LED3 亮但颜色/顺序不对

1. 记录屏幕颜色顺序和是否有红蓝互换；
2. 若整行错位/只有一半正确：可能是 `CAPTURE_START` 选错半段，
   改 640 重建；
3. 若颜色通道互换/字节顺序明显不对：改 `BYTE_SWAP=1` 重建；
4. 若颜色像“高字节/低字节错位”（例如亮度台阶），先查
   `0x4300=0x61` 回读和 `BYTE_SWAP`。

### 6.4 画面闪烁/不稳定

1. 当前设计在捕获一条行后**冻结**，正常不应闪烁；
2. 若闪烁，查 PLL lock（LED2/HDMI）、`+3.3V_HDMI`、摄像头供电；
3. TD 报告 Hold WNS 只有 +0.020 ns；若数据不稳定，记录现象，
   后续可尝试换 RAM 映射/加流水/降低 PCLK 约束验证。

## 7. 重建参数变体

顶层参数（`top_ov5640_line_to_hdmi.v`）：

```verilog
parameter integer HREF_ACTIVE_HIGH = 1;  // 0 = 低有效
parameter integer CAPTURE_START    = 0;  // 0 = 前1280字节, 640 = 后1280
parameter integer BYTE_SWAP        = 0;  // 1 = 交换高低字节
parameter integer STARTUP_LINES    = 3;
```

修改默认值后重新运行：

```bat
fpga\scripts\build_top_ov5640_line_to_hdmi.bat
```

建议一次只改一个参数，并记录位流 SHA 和屏幕结果。

## 8. 测量注意事项

- 不要用普通逻辑分析仪直接解码 125/250 Mbps 的 TMDS；
- 若要抓 DVP，使用 **200/250 MS/s**（50 MS/s 会把 48 MHz PCLK
  混叠成 2 MHz），触发 HREF，至少抓 D0–D7 + PCLK + HREF + VSYNC；
- SCCB 是 50 kHz 慢速总线，可用普通 LA。

## 9. 证据归档

`verification/board/evidence/20261108_ov5640_line_hdmi/README.md`：

- 位流 SHA、下载方式；
- LED1–LED4；
- 摄像头供电/电流/温度；
- 显示器颜色顺序/照片；
- 是否单行重复、是否稳定；
- 任何参数变体（HREF/CAPTURE_START/BYTE_SWAP）及结果；
- 明确 PASS/FAIL/未完成。

## 10. 完成定义（2026-11-08 实测结果）

- [x] 摄像头已连接（用户）。
- [x] LED2（cfg_ok）常亮。
- [x] LED3（capture_done）常亮，LED4 熄灭。
- [x] 显示器出现单行重复的 480 行。
- [ ] 显示器出现 OV5640 **内部 8 色条** —— **未达成**（实际为左黑条 +
      右浅蓝紫）。
- [ ] 记录颜色顺序/字节顺序/±1 像素对齐 —— 未确认。

结论：**PARTIAL PASS**。单行数据路径已连通，但像素内容不正确/未确认；
留到 DDR 实时画面阶段继续排查（HREF A/B、字节序、摄像头内部彩条是否
真正生效）。单行结果不代表 480 行完整采集或实时画面。
