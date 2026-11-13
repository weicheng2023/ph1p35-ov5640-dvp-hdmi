# DDR → HDMI 寄存器字缓冲（WBUF）试验：仿真 2026-11-09

## 背景与目标

上板观察：`top_ddr_fb_hdmi_paxi_fix_20261109.bit`（阶段 2 测试图）在显示器上
每个色条右边缘出现向右突出的短横细线毛刺，并持续向上滚动。用户怀疑是
“FIFO 头 → 8:1 MUX → RGB565→RGB888 → TMDS 编码器”这一段组合逻辑的时序
问题，建议增加：

- 128-bit Word Buffer（寄存器，预取并保存完整 FIFO 字）；
- 8:1 MUX 后加 RGB565 像素寄存器；
- RGB888 后同步延迟 DE / HS / VS。

本试验只验证**数据通路**是否仍然逐像素正确，不证明板上的毛刺成因。

## RTL 改动（默认路径不变）

| 文件 | 改动 |
|---|---|
| `fpga/rtl/ddr/pixel_gearbox_wbuf.v` | 新增。`word_buf` 128-bit 寄存器 + pix_idx 8:1 MUX + `rgb565` 像素寄存器。 |
| `fpga/rtl/fb/ddr_fb_hdmi_core.v` | 新增参数 `USE_WBUF`（默认 0）。0 = 原 `pixel_gearbox`，1 = `pixel_gearbox_wbuf`。另加 `img888_r` 寄存器与 DE/HS/VS 两级延迟；`pipe_de/pipe_hcount/pipe_vcount` 暴露编码器输入端的真实像素坐标。 |
| `fpga/rtl/top/top_ddr_fb_hdmi_wbuf.v` | 新增试验顶层，其余与 `top_ddr_fb_hdmi` 相同。 |
| `fpga/sim/tb/tb_ddr_fb_hdmi_core.v` | 新增 `USE_WBUF`、`FULL_CHECK`、`FULL_FRAMES`；点检改用 `pipe_*`；可选逐像素全帧比对。 |

### WBUF 的取数时序（关键）

FWFT FIFO 的 `rd_data` 是当前 head：

- 在**像素 6** 拉高 `fifo_rd_en` 弹出当前字，像素 7 仍从 `word_buf` 取数；
- 像素 6 的时钟沿之后 head 变成下一个字，因此像素 7 的时钟沿把
  `fifo_rd_data`（下一个字）锁进 `word_buf`；
- 下一组的像素 0..7 全部来自已寄存的 `word_buf`；
- 消隐期 `video_valid && !rd_empty` 预装第一个字（只装入、不弹出）；
- 640 像素/行 = 80 组整，`pix_idx` 每行自然回到 0，不需要按行复位。

FIFO 为空时保持旧字并把 `underflow` 置位（与 `pixel_gearbox` 语义一致）。

### 像素延迟对齐

`rgb565` 寄存 +1，`img888_r` 寄存 +1，共 2 个像素周期。DE/HS/VS 也同步
延迟 2 个像素周期再送 TMDS 编码器，所以整幅画面相对同步信号的位置不变，
不会裁掉行首/行尾像素。

## 仿真

```powershell
powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_wbuf.ps1
```

ModelSim SE-64 2020.4；50 MHz 系统、133.33 MHz DDR 用户时钟、25/125 MHz
HDMI 行为 PLL/ODDR；日志在 `build/sim_ddr_fb_wbuf/`。

### 结果：8/8 PASS

| 用例 | 参数 | 结果 |
|---|---|---|
| `frame_ref` | 默认（原 gearbox） | PASS，CRC `F53A4D4F` |
| `frame_ref_full` | `FULL_CHECK=1` | PASS，**307200 像素全对** |
| `frame_wbuf` | `USE_WBUF=1` | PASS，CRC `F53A4D4F` |
| `frame_wbuf_full` | `USE_WBUF=1 FULL_CHECK=1` | PASS，**307200 像素全对** |
| `frame_wbuf_pressure` | `USE_WBUF=1 READY_DELAY=2` | PASS |
| `frame_wbuf_ddr_source` | `USE_WBUF=1 DDR_PROOF=1` | PASS，像素 (40,10) 随 DDR 变为绿色 |
| `frame_wbuf_underflow` | `USE_WBUF=1 FIFO_FAULT=1` | PASS，underflow → 黄屏 |
| `frame_wbuf_corrupt` | `USE_WBUF=1 CORRUPT=1` | PASS，CRC `306B3F2A`，`err_addr=4128`，品红屏、不启动视频 |

`FULL_CHECK` 的比对照的是**编码器输入端**的像素坐标
（`pipe_hcount/pipe_vcount`）与 `fb_pattern`，覆盖每一条色条边界和每个 128-bit
字边界。两种 gearbox 都是 307200 像素 0 错，说明寄存器流水线没有引入
字错位、重复或丢像素。

原 12 例回归（`sim_ddr_fb_paxi_fix.ps1`）在改动后已重跑，用于确认默认
`USE_WBUF=0` 路径行为不变：**12/12 PASS**（日志
`build/sim_ddr_fb_paxi_fix/`，运行记录
`build/sim_ddr_fb_paxi_fix_recheck.log`）。

## 结论边界

- 本仿真只证明**数字逻辑逐像素正确**，不能证明板上毛刺来源，也不能证明
  真实 ERAM/LUTRAM 的读端口行为。
- 见构建记录：TD 在本试验顶层把显示 FIFO 推断成 **4 块 ERAM**
  （原上板工程是 800 个分布式 RAM mslice）。因此板上试验同时改变了
  “流水线结构”和“FIFO 存储实现”，若毛刺消失，仍需一次只改一项的
  对照构建才能定位。
