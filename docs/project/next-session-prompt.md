# 下一 Session 交接：Stage 3（OV5640 → DDR → HDMI 实时帧）

> 当前工作目录：`D:\Projects\02_Personal_Practice\2026_10_OV5640`
> 分支：`dvp-3ch-recheck-20261106`
> 更新时间：2026-11-09
>
> 本文件让没有历史记忆的 Session 独立继续开发。先读
> `AGENTS.md`、`TASKS.md`、`docs/display/ddr-framebuffer-bringup.md`
> 和 `.claude/skills/fpga-bringup/SKILL.md`。

## 1. 项目与最终目标

- FPGA：Anlogic **PH1P35MDG324**；板卡 PH1P35_FT V1 / HX1P35B_FT_40P。
- 工具：TangDynasty **6.2.1**；ModelSim SE-64 2020.4。
- 摄像头：ATK-MC5640（OV5640，8-bit DVP，SCCB）。
- 显示：HDMI 640×480@60。
- DDR：封装内 DDR2 512Mb ×16（64 MiB，1.5 V）。

最终目标：**OV5640 → DVP → FPGA → DDR Frame Buffer → HDMI 实时显示**。

## 2. 已完成能力

| 能力 | 状态 | 关键证据 |
|---|---|---|
| SCCB Chip ID 0x5640 | **BOARD PASS** | `verification/board/evidence/20261024_sccb_chip_id/` |
| DVP PCLK/HREF/VSYNC 三通道 | **BOARD PASS（时序）** | `verification/board/evidence/20261106_dvp_3ch_recheck/` |
| FPGA 内部彩条 → HDMI | **BOARD PASS（用户报告）** | `verification/board/evidence/20261107_hdmi_colorbar/` |
| OV5640 单行 → HDMI | **PARTIAL PASS（用户报告）** | `verification/board/evidence/20261108_ov5640_line_hdmi/` |
| DDR CAL_EN=0 READY | **BOARD PASS** | `verification/board/evidence/20261108_ddr_debug/` |
| 测试图 → DDR → HDMI | **STAGE 2 BOARD FUNCTIONAL PASS（用户报告）** | `verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/` |
| OV5640 → DDR → HDMI 实时 | **NOT STARTED** | — |

## 3. 当前已验证架构

```text
FPGA Image Generator (fb_pattern)
  → RGB565, 8 pixels / 128-bit beat
  → PAXI single-beat write (ADDR_STEP=8, wstrb=16'h0000)
  → DDR2 frame buffer (base 16-bit-word address 4096, 38400 beats)
  → PAXI single-beat read
  → 128-bit × 256 async FIFO (Gray pointers)
  → 8:1 gearbox
  → RGB565 → RGB888
  → HDMI timing/TMDS
  → monitor
```

写侧：16-beat 自检 → 整帧写入 → 期望 CRC 扫描。
读侧：整帧逐像素与 `fb_pattern` 比较 + **实际读回数据** CRC →
FIFO 预充 192 字 → VSYNC 下降沿启动 `video_valid` → 连续显示。
`write_done` 只表示所有写握手完成且期望 CRC 就绪，**不是**物理写完成；
最终证明是读回比较/CRC。

## 4. 必须保留的技术参数

- FPGA/板卡：PH1P35MDG324 / PH1P35_FT V1。
- DDR：DDR2 512Mb ×16；TD IP `MIS_DDRF6F1D0P0_1.1`。
- **CAL_EN=0**（同器件 Lab1 参考也如此；PHY 训练被绕过）。
- PAXI：128-bit 数据；地址单位 **16-bit word**；`ADDR_STEP=8`；
  全字写掩码 **`16'h0000`**（高有效，0=写，1=屏蔽）。
- AW 先接受；WVALID 下一周期给出并保持到 WREADY。
- 帧基地址 4096（16-bit word，字节偏移 8192）；38400 beat；80 beat/行。
- HDMI 640×480@60：pixel 25.0 MHz / serial 125 MHz；V total 521。
- 时钟：C4 50 MHz ref；DDR `dhi_clk` 约 133.35 MHz。
- FIFO：128-bit × 256，Gray 指针；预充 192 字。
- CRC-32/ISO-HDLC，低字节在前；正常图像 `F53A4D4F`。
- 错误色：红=自检，橙=写帧，品红=读回/CRC，黄=FIFO/流，深蓝=等待。
- 具体基址/深度/时序以最终源码为准，不要凭空改。

## 5. 最终位流与验证

- 位流：`build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit`
- SHA-256：`e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`
- TD：Setup **+0.110 ns** / Hold **+0.020 ns**；5283 slices；
  0 RAM / 0 DSP / 100 DRAMHARDCON。
- ModelSim：**12/12 PASS**（正常、反压、旧步长负例、旧掩码负例、
  整帧、注入错误、FIFO underflow/overflow、DDR-source 单像素）。
- 用户已实测：**完整测试图上板显示**。LED 逐项、CRC、照片未提供；
  记录为 USER-REPORTED FUNCTIONAL PASS。
- `check_timing` 仍有 PLL/dummy/IO delay 提示；不作完整时序签收。

## 6. 已知问题（Stage 3 要面对）

1. OV5640 单行内容仍未完全确认：左侧黑条 + 右侧浅蓝紫，非预期 8 色条；
   像素字节序、HREF A/B、±1 像素对齐未定。
2. HREF 测量长度与 RGB565 理论字节数存在差异（高相位 1920 PCLK /
   低相位 1280 PCLK；A/B 未最终判定）。
3. 摄像头 480 行完整数据尚未验证；实际视频尚未写入 DDR。
4. 摄像头 30 fps 与 HDMI 60 Hz 的帧率差异需要帧缓冲/重复帧策略。
5. CAL_EN=1 的校准流程未解决；CAL_EN=0 长期稳定性未验证。
6. 当前 PAXI 是单拍、单 outstanding；Stage 3 若提高吞吐需重新评估，
   且不得破坏已验证的地址/掩码语义。

## 7. Stage 3 目标与顺序

目标：**OV5640 → DVP → DDR Frame Buffer → HDMI 实时显示。**

优先顺序：

1. 复用当前已通过的 DDR/HDMI 工程和 SCCB/DVP RTL；不要重写 PLL/TMDS。
2. 实现摄像头 RGB565 像素流输入 FIFO（PCLK → DDR 用户时钟）。
3. 将摄像头完整帧写入 DDR：建议独立写缓冲基址，不与测试图区域冲突。
4. 实现双缓冲/乒乓与帧边界交换；读侧只读完整帧，避免撕裂。
5. HDMI 端按 60 Hz 稳定输出最新完整帧（允许重复帧）。
6. 验证镜头移动/遮挡/已知色卡；逐一解决颜色、字节顺序、行错位、
   HREF 窗口问题。
7. 任何新吞吐/突发方案都必须保留 PAXI 地址步长/掩码和读回证明。

## 8. 约束与禁止事项

- 不复制、修改、破解或再分发加密 IP；bitstream/build/厂商 PDF 不入库。
- 不改已验证的 HDMI PLL/TMDS/视频时序和 DDR 基础配置。
- 不改 `0x4740/0x503D/0x4300`，除非有新实测证据并更新文档。
- 不猜引脚；以 `docs/hardware/wiring.md` 为准。
- 不简化仿真来“通过”；模型必须遵守真实地址单位/掩码/握手。
- 不把 ModelSim PASS 或用户口头报告升级为完整 PHY/电气签核。
- 上板结果必须由用户实测；失败记录保留，不篡改历史。

## 9. 新 Session 启动 Prompt（可整段复制）

```text
你接手 PH1P35 × ATK-MC5640 项目，当前工作目录
D:\Projects\02_Personal_Practice\2026_10_OV5640。

项目最终目标：OV5640 → DVP → FPGA DDR Frame Buffer → HDMI 实时显示。

先读（按顺序）：
1. AGENTS.md
2. TASKS.md
3. docs/display/ddr-framebuffer-bringup.md
4. docs/display/ov5640_line_to_hdmi.md
5. docs/hardware/wiring.md
6. .claude/skills/fpga-bringup/SKILL.md

当前状态：
- SCCB 0x5640、DVP 三通道时序、HDMI 内部彩条、CAL_EN=0 READY 均已上板验证。
- 阶段 2 测试图 → DDR → HDMI 已由用户实测功能通过：
  位流 build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit
  SHA-256 e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16
  TD Setup +0.110 / Hold +0.020 ns，5283 slices，ModelSim 12/12 PASS。
- OV5640 单行 → HDMI 仍是 PARTIAL PASS，像素内容/HREF A/B/字节序未确认。
- CAL_EN=0 是实验配置，不证明完整 PHY 校准或长期稳定性。

Stage 3 目标：OV5640 → DDR 双缓冲 → HDMI 实时帧。
先复用现有 SCCB/DVP/DDR/HDMI 模块；不要重写已验证的 PLL/TMDS/视频时序，
不要改 DDR PLL/CAL_EN/地址步长/掩码。先阅读 RTL 与 IP 实际接口，再实现。

关键接口事实（不得回退）：
- PAXI 地址单位是 16-bit word；128-bit beat 步长 ADDR_STEP=8。
- 写掩码高有效：全字写 16'h0000（0=写，1=屏蔽）。
- AW 先接受，WVALID 下一周期给出并保持到 WREADY。
- 写完成只由读回比较/CRC 证明；write_done 不是物理写完成。

先做：
1. 审查现有 top_ddr_fb_hdmi / ddr_fb_hdmi_core / fb_writer / fb_reader 和
   ov5640_line_capture / dvp_capture 的接口与时钟域。
2. 设计摄像头像素流 FIFO 与 DDR 写缓冲；明确基址、帧大小、双缓冲交换。
3. 给出最小可实现步骤，先仿真（保留旧 +1/FFFF 负例），再 TD 构建，
   最后给用户上板步骤。
4. 不开始无关功能，不虚构上板结果。

任何上板结论必须由用户实测确认；遇到不确定信息先查本地文件和 Git 历史，
仍无法确认就标记 UNVERIFIED。
```
