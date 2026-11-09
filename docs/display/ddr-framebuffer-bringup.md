# DDR Frame Buffer → HDMI：从失败到上板通过

> 阶段 2 最终状态：**STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09 用户报告）**。
> 用户烧录 `top_ddr_fb_hdmi_paxi_fix_20261109.bit` 后确认：
> FPGA 内部 640×480 测试图 → DDR → HDMI 完整显示。
>
> 最终位流 SHA-256：
> `e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`
> 旧失败版 SHA `3cde314a…` 保留，仅用于诊断历史。

## 1. 为什么需要 DDR

HDMI 640×480@60 每帧 614,400 字节（RGB565）。摄像头像素流是 30 fps、
行/场时序与 HDMI 不同；直接把单行缓存重复到 480 行只能证明链路连通，
不能保存完整画面。DDR 帧缓存提供：

- 完整一帧的存储（600 KiB）；
- 写侧（图像/摄像头）与读侧（HDMI）速率解耦；
- 后续 Stage 3 双缓冲/帧交换的基础。

PH1P35MDG324 的 DDR 是**封装内** DDR2 512Mb ×16（64 MiB，1.5 V），
不是板级外置颗粒。TD 6.2.1 的 `MIS_DDRF6F1D0P0_1.1` 以 `Integrated`
模式生成 `DDR2_512M`/`DDR2_X16` 控制器与 PHY。

## 2. 数据路径

```text
FPGA test image (fb_pattern)
  → RGB565, 8 pixels/beat
  → 128-bit pack
  → PAXI single-beat write
  → DDR2 frame buffer (base word 4096, 38400 beats)
  → PAXI single-beat read
  → 128-bit × 256 async FIFO (Gray pointers)
  → 8:1 gearbox (8 × RGB565)
  → RGB565 → RGB888
  → proven HDMI timing/TMDS
  → monitor
```

写侧在整帧握手完成后做一次 CRC-only 扫描，给出 `crc_expected`；
读侧逐像素与同一 `fb_pattern` 比较，并对**实际读回数据**计算 CRC。
只有 `crc_ok` 后才预充 FIFO、在 VSYNC 边界启动显示。

## 3. PAXI 地址单位：为什么步长是 +8

PAXI 数据是 128 bit，地址是 25 bit；地址单位不是 128-bit beat，而是
**16-bit word（2 字节）**：

- 25 位 × 2 字节 = 64 MiB，正好对应器件容量；
- 一个 128-bit beat = 16 字节 = **8 个地址单位**；
- 相邻 beat 的地址必须 +8，且低 3 位为 0（16 字节对齐）。

本机 TD 6.2.1 的 IPUG034 v1.2 与同型号 Lab1 参考工程均采用该映射；
Lab1 的写/读地址在每个 128-bit beat 后 `+8`，每行 240 beat 对应
1920 个 16-bit word（3840 字节 = 1920 个 RGB565 像素）。

第一版实现按“1 地址 = 1 beat”写成 +1，导致 16-beat 自检的地址
0..15 互相覆盖，读回立即不匹配，进入错误状态。修正后：

- 自检：起始地址 0, 8, 16, …, 120；
- 帧缓存：`BASE + beat_index × 8`，`BASE=4096`（字地址，字节偏移 8192）；
- 最后一 beat 起始地址 311288，末字 311295，仍在 25 位范围；
- 错误快照 `err_addr` 同样是 16-bit word 地址。

## 4. 写掩码：为什么全字写用 `0000`

该 PAXI 写掩码是**高电平有效**：

- `wstrb[b] = 0`：写入该字节；
- `wstrb[b] = 1`：屏蔽/保留该字节。

所以完整 128-bit 写应使用 `16'h0000`。第一版使用 `16'hFFFF`，
实际把所有字节都屏蔽掉，DDR 中没有写入任何有效数据。行为模型旧版
也没有实现掩码，因此没有发现该错误。

## 5. 为什么旧仿真没有发现

旧 `ddr_axi_slave_model` 同时犯了两个“和 DUT 一样”的假设：

- 以 `paxi_awaddr` 直接索引 128-bit 数组（等价于地址步长 1）；
- 完全忽略 `paxi_wstrb`。

仿真因此只能证明“DUT 和模型对同一个错误契约自洽”，不能证明真实
MIS 接口正确。修正后的模型：

- 按 `native_addr / 8` 索引 128-bit beat；
- 检查地址对齐/越界；
- 按高有效掩码逐字节写；
- 检查 AW/W/AR 反压期间 payload 稳定；
- 检查 AW 接受后两个周期内出现 WVALID；
- 旧 `ADDR_STEP=1` 和 `wstrb=FFFF` 都作为负例被拒绝。

另外，“DDR 数据来源”用例只修改模型内存中的像素 (40,10)，HDMI 同像素
随之改变、相邻像素不变，证明显示数据确实来自 DDR/FIFO，而不是本地旁路。
该测试还暴露了 gearbox 在 8 像素块边界的 FIFO pop 晚一拍，已修复。

## 6. 逐层验证

| 层级 | 内容 | 结果 |
|---|---|---|
| 单元/集成仿真 | 16-beat 自检、整帧写/读、CRC、FIFO、HDMI 行列、错误注入 | **12/12 PASS** |
| TD 综合/P&R | 综合、布局布线、时序、资源、bitgen | Setup **+0.110 ns** / Hold **+0.020 ns**，5283 slices，0 RAM/0 DSP/100 DRAMHARDCON |
| 实物 | 用户 Program SRAM，观察显示器 | **完整测试图显示（用户报告）** |

ModelSim 正常用例 CRC 为 `F53A4D4F`；注入帧内 1 bit 错误时 CRC 变为
`306B3F2A`，`err_addr` 指向对应字地址并中止/变色。FIFO underflow、
overflow、自检错误、写帧错误均有独立颜色和 `error_code`。

TD 的 `check_timing` 仍有 PLL/dummy 节点、533.600 vs 533.333 频率舍入、
未设 IO delay 等提示；本阶段**不作完整时序签核**，也不通过改 SDC 隐藏。
详细报告见构建记录与 `check_timing` 文件。

## 7. CAL_EN=0 的技术边界

- CAL_EN=1 时本板无法进入 `ddrphy_rdy`；CAL_EN=0 可达 READY，
  同型号 Lab1 也使用该配置。
- CAL_EN=0 **绕过相应 PHY 训练**；READY、自检、CRC 和图像通过只证明
  该实验配置下的数据通路功能，不证明完整 PHY 校准。
- 未验证长期稳定性、温度/电压余量、所有掩码/地址边界组合或复杂 burst。
- 不得为了“收尾好看”修改 CAL_EN、DDR PLL、时钟或 PHY 后再宣称通过。

## 8. 复现入口

- 最终构建：`fpga/scripts/build_top_ddr_fb_hdmi.bat`
- 12 项仿真：`powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_paxi_fix.ps1`
- 上板步骤：[bringup-ddr-fb-hdmi-paxi-fix.md](../../verification/board/bringup-ddr-fb-hdmi-paxi-fix.md)
- 仿真证据：[ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md](../../verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md)
- 构建证据：[top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md](../../verification/static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md)
- 实物证据：[20261109_ddr_fb_hdmi_paxi_fix](../../verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md)
- 失败历史：[20261108_ddr_fb_hdmi](../../verification/board/evidence/20261108_ddr_fb_hdmi/README.md)
