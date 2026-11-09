# OV5640 单行 → HDMI 仿真证据（2026-11-08）

> 工具：ModelSim SE-64 2020.4
> 设计：`top_ov5640_line_to_hdmi` / `ov5640_line_to_hdmi_core`
> 位置：本地 `build/sim_line/`、`build/sim_core/`（不入库）
>
> 本文件记录**实际执行的仿真**。仿真通过 ≠ 真实摄像头/上板通过。

## 1. 仿真环境与边界

- 主仿真用行为 PLL/ODDR：
  - `fpga/sim/models/pll_hdmi_sim.v`（25.0/125.0 MHz）
  - `fpga/sim/models/ph1p_logic_oddr_sim.v`
- 相机流由 testbench 合成：**48 MHz PCLK**、HREF 高 1920 周期、
  低 1280 周期；RGB565 高字节在前。
- **SCCB bringup 不在本 TB 中重仿真**：`cfg_ok` 直接置 1。
  配置/回读由已有的 `tb_ov5640_bringup` 覆盖（本次未修改该模块）。
- 仿真证明的是数字逻辑/时序/字节顺序，不是真实相机、PLL 抖动或
  IO 电气。

## 2. `tb_ov5640_line_capture`

命令（示意）：

```tcl
vlib work
vlog -sv fpga/rtl/camera/ov5640_line_capture.v \
        fpga/rtl/common/line_buffer_dpram.v \
        fpga/sim/tb/tb_ov5640_line_capture.v
vsim -c -do "run -all; quit" work.tb_ov5640_line_capture
```

### 2.1 默认配置（CAP_START=0, SWAP=0）

```text
ok   long blanking line rejected, line_total_dbg=384
ok   valid line captured, line_bytes=1920 lines_seen=1
ok   all 640 RGB565 entries match (CAP_START=0 SWAP=0)
ok   buffer stayed frozen after the second line
TB: PASS - ov5640_line_capture (CAP_START=0 SWAP=0)
```

- 65,920 周期的垂直消隐 HREF 被 `LINE_MIN..LINE_MAX` 拒绝；
  `line_total_dbg` 是 16 位截断值（65,920 → 384），
  接受逻辑用的是 17 位 `line_total`。
- 有效行 1920 周期被接受，`line_bytes=1920`。
- 640 个 RGB565 像素逐项匹配 8 色条。
- 第二条有效行不会覆盖已冻结的缓存。

### 2.2 CAP_START=640（取高相位后半段）

```text
ok   all 640 RGB565 entries match (CAP_START=640 SWAP=0)
TB: PASS - ov5640_line_capture (CAP_START=640 SWAP=0)
```

预期是“前 320 像素来自彩条后半段 + 后 320 像素为 0x0000”；
这验证了窗口偏移参数，而不是“后半段全是 0”。

### 2.3 BYTE_SWAP=1

```text
ok   all 640 RGB565 entries match (CAP_START=0 SWAP=1)
TB: PASS - ov5640_line_capture (CAP_START=0 SWAP=1)
```

验证高/低字节交换参数；默认 `SWAP=0` 对应 `0x4300=0x61`
（高字节先出）。

## 3. `tb_top_ov5640_line_to_hdmi`

```text
ok   background rgb=000040 before capture
ok   capture_done=1 line_bytes=1920 lines_seen=1
ok   h=40 rgb=ffffff
ok   h=120 rgb=ffff00
ok   h=200 rgb=00ffff
ok   h=280 rgb=00ff00
ok   h=360 rgb=ff00ff
ok   h=440 rgb=ff0000
ok   h=520 rgb=0000ff
ok   h=600 rgb=000000
TB: PASS - top_ov5640_line_to_hdmi
```

检查点：

- 捕获前显示深蓝背景 `0x000040`；
- `capture_done` 后显示单行重复的 8 色条；
- RGB565→RGB888 的 8 个颜色值正确。

**未证明**：逐像素边界的 1-pixel 对齐。TB 检查的是 80 像素色条的
中心（40/120/…/600），一个 ±1 像素的读流水偏移不会改变中心颜色。
单行静态画面下 1-pixel 偏移视觉上无关；完整 480 行/实时画面阶段
需要单独验证逐像素对齐。

## 4. 配置回归（已有 TB，未修改）

`tb_ov5640_bringup`（SCCB_DIV=10，已有 testbench）在本次新设计前重跑，
确认配置表仍然产生：

```text
TB: PASS - cfg_ok=1, id=5640, geom=640x480, 4300=61, 4740=22, 503D=80
```

- `0x4300=0x61`：RGB565、高字节先；
- `0x4740=0x22`：按现有配置；
- `0x503D=0x80`：OV5640 内部彩条使能。

这证明的是**配置/回读路径**，不是真实像素数据；像素路径由
`tb_ov5640_line_capture`/`tb_top_ov5640_line_to_hdmi` 覆盖。

## 5. 未覆盖/未证明

- 真实 OV5640 的 D0–D7 数据、真实 HREF 有效窗口（A/B）；
- 真实 PCLK 48 MHz 的抖动/相位、输入建立/保持；
- SCCB 配置与回读（已有 `tb_ov5640_bringup`，本次未重跑）；
- 真实 ERAM 的写时序（TD 构建时序报告另行记录）；
- 板上显示器结果。

这些必须在 `verification/board/bringup-ov5640-line-hdmi.md` 中实测。
