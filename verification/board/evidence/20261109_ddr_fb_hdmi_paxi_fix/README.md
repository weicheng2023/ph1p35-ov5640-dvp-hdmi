# DDR → HDMI PAXI 修复版实物记录

> **状态：STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09，用户报告）。**
>
> 用户实际烧录并确认：修复后的 **FPGA 内部测试图 → DDR → HDMI**
> 工程成功上板显示。图像由 DDR 读回数据经 FIFO/gearbox 输出，不是
> 本地旁路图案；失败版本曾整屏红色，不能作为最终结果。
>
> 本轮证据为用户报告。**LED 逐项状态、CRC 数值、显示器型号、照片/
> 视频文件名未提供**，不以推测值补填；如后续补充，直接在本文件追加。
>
> 位流：`build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit`
> SHA-256：`e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`
> 构建：TD 6.2.1；Setup +0.110 ns / Hold +0.020 ns；5283 slices。
> 配置：**CAL_EN=0、50 MHz 参考时钟；PHY 训练被绕过**。

## 1. 测试配置

| 项目 | 值 |
|---|---|
| 日期 | 2026-11-09（用户报告） |
| 板卡 | PH1P35_FT V1 / HX1P35B_FT_40P |
| 器件 | PH1P35MDG324 |
| DDR | 封装内 DDR2 512Mb x16（64 MiB，1.5 V） |
| 位流 SHA-256 | `e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16` |
| 下载方式 | Program SRAM（用户报告） |
| 摄像头 | 未连接 |
| 配置 | `ddr2 #(.CAL_EN(0))`，实验配置 |
| 地址映射 | 原生 PAXI 16-bit word 地址；128-bit 块步长 8；帧基地址 4096 |
| 写掩码 | 全字写 `16'h0000`（高有效，0=写，1=屏蔽） |

## 2. 结果

| 项目 | 结果 |
|---|---|
| 完整测试图显示 | **成功（用户报告）** |
| 图像来源 | DDR 读回 → 异步 FIFO → 8:1 gearbox → HDMI（设计路径） |
| 8 色竖条 / 2 px 白边 / 左上标记 / 32 行网格 | 用户确认工程成功显示；未逐项文字描述 |
| LED1/2/3/4 实测 | **未提供**（UNVERIFIED） |
| CRC actual/expected 实测 | **未提供**（UNVERIFIED；仿真/设计期望值 `F53A4D4F`） |
| 照片 / 视频 / 显示器型号 | **未提供**（UNVERIFIED） |
| 长时间稳定性 / 温度电压余量 | **未验证** |

## 3. 证据等级与边界

- 本记录是 **USER-REPORTED BOARD FUNCTIONAL PASS**：用户确认功能图像
  上板显示；没有独立的照片、LA、电压或 ChipWatcher 记录。
- 该结果证明：在 CAL_EN=0 实验配置下，16 块自检、整帧写入、逐像素/
  CRC 读回、FIFO/gearbox 与 HDMI 数据通路能够完成一次完整显示。
- **不证明**：完整 PHY 训练/校准、长期稳定性、温度/电压余量、
  所有地址/掩码边界组合、复杂 burst，或摄像头整帧链路通过。
- 旧失败版本（整屏红、LED3 灭、LED4 亮）保留在
  `../20261108_ddr_fb_hdmi/README.md` 和
  `../../static/top_ddr_fb_hdmi_build_2026-11-08.md`，作为诊断历史，
  不篡改、不作为最终结果。

## 4. 复现

- 上板步骤：[bringup-ddr-fb-hdmi-paxi-fix.md](../../bringup-ddr-fb-hdmi-paxi-fix.md)
- 仿真 12/12：[ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md](../../../static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md)
- TD 构建：[top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md](../../../static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md)
