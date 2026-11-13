# DDR → HDMI PAXI 修复版上板说明（2026-11-09）

目标：一个位流完成 16 块自检、完整测试图写入、逐像素读回/CRC 校验、
FIFO 预充和来自 DDR 的 HDMI 图像显示。

**上板状态：STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09，用户报告）。**
用户已实际烧录并确认测试图 → DDR → HDMI 成功显示。本文件保留为
复现步骤和故障判读；LED 逐项、CRC、照片等细节未提供，见
[实物记录](evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md)。

## 位流

使用 `build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit`。
SHA-256 和时序见 [构建记录](../static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md)。
不要误用旧 `top_ddr_fb_hdmi.bit`（SHA `3cde314a…`）；旧文件保留用于追溯。

配置仍是 CAL_EN=0、50 MHz 参考时钟，PHY 训练被绕过。
READY、内存比较或屏幕图像都不能作为完整 PHY 校准成功证据。
HDMI PLL、TMDS、视频时序和 SDC 保持不变。

## 操作

1. 只连接电源、HDMI 显示器、USB-JTAG，不需要摄像头或逻辑分析仪。
   引脚依据仍是 [wiring.md](../../docs/hardware/wiring.md)。
2. BitWizard 中 Refresh → 添加上述新位流 → **Program SRAM** → Run。
3. 记录启动后约 1 秒和 10 秒的 LED 与画面；不需要额外 DDR 压力测试。
4. 结果和照片放到 [本次证据目录](evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md)。

## LED 与画面判读

- LED1：心跳。
- LED2：DDR READY。
- LED3：整帧写请求完成且期望 CRC 已计算；**不代表校验已经通过**。
- LED4：锁存错误；重新下载/复位才开始新一轮。

屏幕背景用于区分错误：

- **深蓝 `000040`**：等待 READY、自检/写帧/校验或预充中。长时间停留时记录 LED。
- **红 `FF0000`**：16 块自检失败或自检事务超时，error_code=1。
- **橙 `FF8000`**：写帧错误/超时，error_code=2。
- **品红 `FF00FF`**：整帧逐像素/CRC 校验失败，或该阶段读事务错误，error_code=3。
- **黄 `FFFF00`**：FIFO 下溢/溢出，或预充/连续显示阶段读错误，error_code=4。
- **完整测试图**：白、黄、青、绿、品红、红、蓝、黑八条竖条；2 px 白边框、
  左上 16×16 红白棋盘标记、每 32 行灰色横线。它来自 DDR 读数据，经 FIFO/gearbox 显示。

错误色是纯色全屏；不要把正常测试图中的单条红/黄/品红色条当作错误。
短暂上电过渡色不作为判据，以稳定画面为准。

## 验收

仅在实际观察到完整测试图、方向/边框/网格正确且 LED4 熄灭后，记录
“CAL_EN=0 下测试图 → DDR → HDMI 功能通过（用户实测）”。
如果只有 LED 正常或仍为深蓝屏，不能记作通过。
若失败，记录纯色种类、四灯状态、位流 SHA 和照片即可，不要求先搭建完整仿真平台。

内部调试信息保留：自检首错地址/期望/实际数据、逐像素首错、actual/expected CRC、
FIFO 错误和 error_code。期望 CRC 为 `F53A4D4F`。
地址快照单位为 **16-bit word**：帧基地址 4096；帧内第 k 块地址 `4096+8*k`。

## 复现构建与仿真

构建：`fpga/scripts/build_top_ddr_fb_hdmi.bat`。
仿真：`powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_paxi_fix.ps1`。
详见 [12 项行为仿真记录](../static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md)。
