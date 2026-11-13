# 2026-11-08 DDR Frame Buffer → HDMI 上板证据

> **历史记录：已被 2026-11-09 PAXI 修复版取代。**
> 本版本实际烧录后为整屏红、LED3 灭、LED4 亮；根因是 PAXI 地址单位
> 与写掩码极性（详见 `../../static/top_ddr_fb_hdmi_build_2026-11-08.md`
> 和 `../../static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`）。
> 最终通过版本见 `../20261109_ddr_fb_hdmi_paxi_fix/README.md`。
> 以下内容保留为失败诊断历史，不修改原测试数据。
>
> 该版本已实际烧录：整屏红、LED3 灭、LED4 亮（2026-11-08 用户报告）。
> 失败根因与修复见上方说明；本节以下保留原始构建/上板计划。
>
> 位流：`build/bitstream/top_ddr_fb_hdmi.bit`
> SHA-256：`3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`
> 配置：`ddr2 #(.CAL_EN(0))` —— **实验配置，PHY 训练被绕过；不得把
> READY/CRC 通过宣称为完整 PHY 校准通过。**
>
> 上板步骤：`verification/board/bringup-ddr-fb-hdmi.md`
> 构建证据：`verification/static/top_ddr_fb_hdmi_build_2026-11-08.md`
> 仿真证据：`verification/static/ddr_fb_hdmi_sim_2026-11-08.md`

## 1. 测试配置

| 项目 | 值 |
|---|---|
| 日期 | 2026-11-08（构建）；上板日期待填 |
| 板卡 | PH1P35_FT V1 / HX1P35B_FT_40P |
| 器件 | PH1P35MDG324 |
| DDR | 封装内 DDR2 512Mb x16（64 MB，1.5 V） |
| 位流 SHA | `3cde314a…` |
| 下载方式 | 待填（Program SRAM） |
| 图像 | 640×480 RGB565，8 色竖条 + 2 px 边框 + 16×16 标记 + 32 行网格 |
| 帧地址 | beat 4096..42495（单拍 128-bit，80 beat/行 = 38400 beat） |
| DDR 时钟 | 533.33 MHz（DDR2-1066），CAL_EN=0 |

## 2. LED（待填）

| LED | 含义 | 预期 | 实测 |
|---|---|---|---|
| LED1 | 50 MHz 心跳 | 1 Hz 闪 | 待填 |
| LED2 | `ddrphy_rdy` | 常亮 | 待填 |
| LED3 | 整帧写入完成 + 期望 CRC 就绪 | 常亮 | 待填 |
| LED4 | 自检/读回 CRC/FIFO/流错误 | 熄灭 | 待填 |

## 3. 显示器（待填）

| 项目 | 预期 | 实测 |
|---|---|---|
| 启动前背景 | 深蓝 `0x000040` | 待填 |
| 正常图像 | 8 色竖条 + 白边 + 左上标记 + 横网格 | 待填 |
| 颜色顺序 | 白/黄/青/绿/品红/红/蓝/黑 | 待填 |
| 行列/方向 | 标记在左上；网格每 32 行 | 待填 |
| 撕裂/错行/闪烁/彩点 | 无 | 待填 |
| 红色错误画面 | 无 | 待填 |

## 4. 结论（待填）

- [ ] DDR READY
- [ ] 16-beat 自检 PASS（LED3 只在整帧写完后亮；自检失败会是红灯）
- [ ] 整帧读回 CRC 通过（ChipWatcher `dbg_crc_expected == dbg_crc_actual`）
- [ ] HDMI 图像正确
- [ ] 无 FIFO underflow/overflow

> 已知尚未证明：CAL_EN=0 的 PHY 建立/保持窗口、长期稳定性、
> 温度/电压余量；显示器侧 TMDS 电气质量。
