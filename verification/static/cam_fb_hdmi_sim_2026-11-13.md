# Stage 3 仿真记录：OV5640 → DDR 双缓冲 → HDMI

> 日期：2026-11-13
> 工具：ModelSim SE-64 2020.4
> 结论：**全部 Stage 3 仿真 PASS（9/9 快速回归 + 1 个 640×480 全尺寸真实时序用例）**；
> Stage 2 原 12 例回归仍 **12/12 PASS**。
> 本记录只代表仿真；上板结果必须由用户实测后另行记录。

## 1. 目标与架构

```text
OV5640 DVP (PCLK 48 MHz)
  → ov5640_frame_capture        PCLK 域：整行缓存 + 行长过滤 + 8 像素/beat 打包
  → 129-bit async_fifo_gray     PCLK → dhi_clk（Gray 指针）
  → cam_fb_writer               dhi_clk：PAXI 单拍写，乒乓缓冲区
  → DDR2 帧缓存（两帧）
  → cam_fb_reader               dhi_clk：PAXI 单拍读，每显示帧一遍
  → 128-bit async_fifo_gray     dhi_clk → pixel_clk
  → pixel_gearbox               ＜沿用阶段 2 已上板模块＞
  → rgb565_to_rgb888 → TMDS     ＜沿用已上板 HDMI 链＞
```

关键参数（与阶段 2 一致，未改）：

- PAXI 地址单位 16-bit word，128-bit beat 步长 **+8**；
- 全字写掩码 **16'h0000**（高有效，0=写）；
- AW 先接受，WVALID 下一周期给出并保持到 WREADY；
- 帧基址 4096（buffer 0 / 奇数号）与 4096+307200=311296（buffer 1）；
- 每帧 38400 beat（480 行 × 80 beat），640×480 RGB565；
- 显示 FIFO 128-bit × 256，预充 192 字；HDMI 640×480@60 不变；
- `CAL_EN=0` 仍为实验配置。

## 2. RTL 清单

| 文件 | 作用 |
|---|---|
| `fpga/rtl/camera/ov5640_frame_capture.v` | PCLK 域整帧采集：行 RAM、行长过滤、窗口/字节交换、缺行黑填充、帧头 |
| `fpga/rtl/fb/cam_fb_writer.v` | 消费 129-bit beat，按 PAXI 契约写入乒乓缓冲区 |
| `fpga/rtl/fb/cam_fb_reader.v` | 每显示帧读一遍缓冲区；帧末等待显示 FIFO 排空后才开始下一遍 |
| `fpga/rtl/fb/cam_fb_hdmi_core.v` | 自检、PAXI 仲裁、乒乓索引、显示 FIFO/gearbox、HDMI、错误色 |
| `fpga/rtl/top/top_cam_fb_hdmi.v` | 板级顶层（SCCB/DVP/DDR/HDMI/LED） |
| `fpga/rtl/common/async_fifo_gray.v` | 新增只读输出 `wr_empty`（写域看到读指针已排空）；原有端口/行为不变 |

`-define CAM_COLOR_BAR` 可构建摄像头内部彩条版本（只改 `0x503D`），
`CAM_COLOR_BAR=1 fpga\scripts\build_top_cam_fb_hdmi.bat`，输出名带
`_colorbar`，不会覆盖实景位流。

## 3. 乒乓与防撕裂

- 写侧只在 `buf_free = !writer_busy && (wr_idx != 显示缓冲区)` 时接受帧头；
  否则该摄像头帧整体丢弃（不会写一半）。
- 读侧每遍读 38400 beat，随后**停止发读**，等待显示 FIFO 写域 `wr_empty`。
  FIFO 恰好在最后一个有效像素被消费时排空，因此下一遍（以及换 buffer）
  发生在 HDMI 垂直消隐期，不会撕裂。
- 显示帧率 60 Hz、摄像头 30 fps，同一摄像头帧会被显示两次；这是允许的
  重复帧策略。

## 4. 仿真用例与结果

### 4.1 采集单元（`tb_ov5640_frame_capture.v`，7/7 PASS）

真实 48.000 MHz PCLK、HREF 高 1920 / 低 1280 PCLK、VSYNC 高 66.6 µs，
帧边界包含 65,920 PCLK 的消隐长 HREF。

| 用例 | 覆盖 |
|---|---|
| cap_basic | 4 行帧 → 1 帧头 + 4×80 beat，像素逐点匹配 |
| cap_href_low | `HREF_ACTIVE_HIGH=0`（2026-11-13 极性修复后新增） |
| cap_pad | V_ACTIVE=5、实际 4 行 → 缺行填黑 0x0000 |
| cap_long_line | 消隐长 HREF 作为一行被接受（像素窗口内数据为 0） |
| cap_window_640 | `CAPTURE_START=640` 窗口 |
| cap_byte_swap | `BYTE_SWAP=1` |
| cap_buf_busy | VSYNC 时 `buf_free=0` → 整帧丢弃，下一帧恢复 |
| cap_combined | 以上组合 |

### 4.2 集成（`tb_cam_fb_hdmi_core.v`，2/2 快速 + 1/1 全尺寸）

行为 PAXI 从模型 + 行为 PLL/ODDR；摄像头模型带帧号（蓝通道），
显示端在每帧顶部 `(0,0)` 与底部 `(0,V-1)` 同时取蓝通道比较。

| 用例 | 结果 |
|---|---|
| int_quick（64×48 几何） | PASS：自检、首帧写入 DDR 并逐点核对、video_valid、10 个显示帧顶部/底部帧号一致（无撕裂）、帧号推进 |
| int_pressure（`READY_DELAY=2`） | PASS，同上 |
| int_full_640x480（真实 640×480 帧、33.4 ms/帧） | **PASS**：帧号 1 → 2 → 4 推进；无撕裂；无 writer/reader/FIFO/capture 错误 |

### 4.3 回归

- Stage 2 原 12 例（`sim_ddr_fb_paxi_fix.ps1`）：**12/12 PASS**，
  说明 `async_fifo_gray` 增加 `wr_empty` 输出未改变既有行为。
- `fpga/scripts/sim_cam_fb.ps1`：Stage 3 快速回归 9/9 PASS；
  加 `-Full` 追加 640×480 真实时序用例。

## 5. 仿真中发现并修复的问题

1. **写侧帧头弹出晚一拍**：`fifo_rd_en` 是寄存器，`W_IDLE` 同拍进入
   `W_GET` 时 FIFO 头仍是帧头 → 误判“帧内出现帧头”。增加 `W_HDR`
   等待拍。
2. **PAXI 仲裁器提前释放读事务**：仅凭 R 握手结束会释放总线；增加
   “AR 已接受”标志 `arb_rd_ar_done`，避免把陈旧 R 当作本事务完成。
3. **读侧 ARVALID 被撤回**：FIFO 满分支绕过了握手判断，`ARVALID=1`
   且被接受时状态机不前进。改为握手判断独立于“满”分支，且一旦
   拉高 ARVALID 必须保持到握手。
4. **采集侧 FIFO 写使能晚一拍导致丢字**：`async_fifo_gray` 的
   `wr_full` 是“本次写会溢出”的寄存器输出；把 `fifo_wr_en` 再寄存
   一拍会让满判断落后一拍，满时写被 FIFO 丢弃（`wr_overflow`）。
   改为组合驱动写口，状态机与 `!fifo_wr_full` 同拍推进。
5. **显示 FIFO 反压时长期占用 PAXI 总线**：读侧在 FIFO 已满时仍有
   在途读，`rready=0` 使总线被占住，写侧得不到仲裁，摄像头 FIFO
   溢出。增加 2 拍写生效保护（`push_hold`），读请求不再落到“实际
   已满”的边界；`wr_overflow` 归零。
6. **640×480 全尺寸用例暴露的启动死锁**：第 5 项修复前，首个显示
   帧开始前读侧占住总线约 15 ms，导致第 2 帧丢行。修复后 PASS。

## 6. 未决 / 不宣称

- `CAL_EN=0` 是实验配置，不证明完整 PHY 校准或长期稳定性。
- 摄像头实际像素内容（HREF A/B、字节序、单行测试的“左黑条+右浅蓝紫”）
  仍未由 D 数据确认；本仿真的摄像头模型是理想数据。
- 阶段 2 彩条“色块右缘短横毛刺、向上滚动”问题仍未定位（用户已记录于
  `AGENTS.md` / `TASKS.md`，并由 WBUF 试验位流另行观察）。本阶段先让
  摄像头图像上屏，再据实观察该现象是否仍在、以何形式存在；**未修改
  DDR 侧代码，也不声称该问题是 DDR 或 gearbox 引起。**
- 时序：见构建记录；`check_timing` 的 PLL/dummy/IO delay 提示仍存在，
  不作完整时序签核。

## 7. 复现

```powershell
# Stage 3 快速回归（7 采集 + 2 集成）
powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_cam_fb.ps1

# 追加 640×480 真实时序用例（较慢）
powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_cam_fb.ps1 -Full

# Stage 2 回归（确认共享 FIFO 未回归）
powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_paxi_fix.ps1
```
