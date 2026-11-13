# 上板步骤：Stage 3 OV5640 → DDR 双缓冲 → HDMI 实时显示

> 位流：`build/bitstream/top_cam_fb_hdmi.bit`
> SHA-256：`787b26ee9bd6e7e171e74a0947df6cd793b657838d282d05c4e8f9fe88ace15e`
> （2026-11-13 HREF 极性修复版：**`HREF_ACTIVE_HIGH=0`**，
> Setup +0.404 / Hold +0.020 ns，0 违约端点，6952 slices，0 RAM；详见
> `verification/static/top_cam_fb_hdmi_build_2026-11-13.md`）
> 旧的 `HREF_ACTIVE_HIGH=1` 版保留为
> `top_cam_fb_hdmi_hrefhigh_20261113.bit`（SHA `a25a2ac9…`）。
> 摄像头彩条诊断位流：`top_cam_fb_hdmi_colorbar.bit`
> （同极性，只改 `0x503D=0x80`；SHA
> `76d2ec77e46fc2675f4d6dbee6ddddc086d44ce86752cff4598a3fdf931f50ab`）。
> 顶层：`fpga/rtl/top/top_cam_fb_hdmi.v`
> 接线以 `docs/hardware/wiring.md` 为准，本文件不复制引脚表。

## 1. 前提

- 阶段 2 已上板：`top_ddr_fb_hdmi_paxi_fix_20261109.bit` 显示完整测试图。
- HDMI 彩条已上板。摄像头 SCCB/DVP 三通道已上板。
- **CAL_EN=0 是实验配置**，本轮只验证实时图像通路，不证明 PHY 校准。

## 2. 接线

1. 摄像头 ATK-MC5640 接 J2（P1 方向按丝印确认）。
2. HDMI 显示器接 HDMI1，先接显示器再上电（HPD 可能被 D6 锁存）。
3. JTAG/下载器接好；**上电前先确认 3.3 V 与 GND 不短路**。

## 3. 烧录

1. 打开 BitWizard（`TD/bin/bw.exe`）→ Refresh → Add
   `build/bitstream/top_cam_fb_hdmi.bit`。
2. **Program SRAM** → Run（先不要烧 Flash）。
3. 记录烧录时间、位流 SHA、板卡温度/供电（若可测）。

## 4. LED 语义

| 物理 LED | 含义 |
|---|---|
| LED1 | 1 Hz 心跳 |
| LED2 | DDR `ddrphy_rdy` 且 16-beat 自检通过（进入运行态） |
| LED3 | 至少一帧摄像头数据已写入 DDR（`complete_valid`） |
| LED4 | 任意错误（DDR/采集/FIFO/流/摄像头超时） |

正常期望：**LED1 闪烁，LED2 常亮（约 1 s 内），LED3 在首帧写入后常亮
（约 1–2 s），LED4 熄灭。**

## 5. 屏幕语义

| 画面 | 含义 |
|---|---|
| 摄像头实时画面 | 正常 |
| 深蓝 | 等待（尚未 video_valid / 无完整帧） |
| 红 | DDR 16-beat 自检失败 |
| 品红 | 写侧/读侧错误（帧头协议、超时） |
| 橙 | 摄像头采集超时（无 VSYNC / 无有效行） |
| 黄 | 显示 FIFO 下溢/溢出或流错误 |

## 6. 本轮要观察/记录的内容

1. 是否出现摄像头实时画面；移动摄像头/遮挡镜头，画面是否持续更新。
2. LED1–LED4 是否符合第 4 节；若异常，记录组合与出现时间。
3. **重点：阶段 2 彩条“每个色块右缘向右突出的短横细线、持续向上滚动”
   的现象在本阶段是否仍存在、以什么形式存在**（若能看到色块/边缘）。
   记录：出现的行位置、是否滚动、滚动方向/速度、是否与画面内容相关。
   不要在本轮修改 DDR 侧代码。
4. 若有条件：拍照/录像（含显示器与板卡 LED 同框），记录显示器型号/输入模式。
5. 若画面异常但 LED 正常：先烧已构建好的摄像头内部彩条版本
   `build/bitstream/top_cam_fb_hdmi_colorbar.bit`（SHA
   `76d2ec77…`，同极性、只改 `0x503D=0x80`），区分“摄像头像素问题”与
   “DDR/HDMI 显示问题”。必要时可自行重建：
   `CAM_COLOR_BAR=1 fpga\scripts\build_top_cam_fb_hdmi.bat`。

## 7. 后续排查参考（须用户确认后再动 DDR 侧代码）

- 原厂 Lab（`D:\Projects\01_Research\2026_10_Thesis_Bachelor\HX1P35A_Contest_202606\7_lab_ex_2026_nosoft\lab_ex1_mipi_hdmi`）
  的 `video_out.v` 在**每帧 VSYNC 复位显示 FIFO**，并从所选缓冲区基址重新
  开始读；注释还要求 FIFO 剩余空间大于一次突发长度（DDR 读延迟 ≥40 拍）。
  这能把“读写指针相位漂移”类伪影限制在消隐期。
- 本 Stage 3 读侧用“帧末排空显示 FIFO 后重新开始”的方法达到同样的
  帧对齐；若毛刺仍然存在，说明不是帧相位漂移，应转向 8:1 组合读/
  颜色边界/时序，而不是先改 DDR 写侧。
- 以上只是排查参考，本轮**不修改** DDR 侧代码。

## 8. 记录位置

把结果写入：

```text
verification/board/evidence/YYYYMMDD_cam_fb_hdmi/README.md
```

至少包含：日期、位流 SHA、烧录方式（SRAM/Flash）、LED 实测、屏幕现象、
拍摄/录像文件名、限制与未确认项。**未实测前不要标记 PASS。**
