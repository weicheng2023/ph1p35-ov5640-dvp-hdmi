# DDR Frame Buffer → HDMI 集成仿真证据（2026-11-08）

> **历史记录：已被 2026-11-09 PAXI 修复版取代。**
> 本轮模型按“1 地址 = 1 个 128-bit beat”建模并忽略写掩码，和当时 DUT
> 犯了相同假设，因此 PASS **不能证明**真实 MIS 接口正确。真实地址单位
> 是 16-bit word（块步长 8），写掩码高有效（全写 `0000`）。最终验证见
> `ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`。
>
> 工具：ModelSim SE-64 2020.4
> 设计：`ddr_fb_hdmi_core`（自检 + 写帧 + 读回校验 + FIFO + HDMI）
> 模型：`ddr_axi_slave_model`（行为 paxi 从机，65536 beat 存储）
> 位置：本地 `build/sim_fb/`（不入库）
>
> 本文件记录**实际执行的仿真**。它只证明数字路径（FSM、地址、
> 数据打包、FIFO CDC、HDMI 行列映射、CRC/比对），**不证明**真实
> DDR PHY 的校准或存储可靠性。

## 1. 仿真边界

- 加密 DDR IP 没有行为模型，未实例化；`ddrphy_rdy` 由 TB 在复位后
  拉高，`dhi_clk` 用 133.33 MHz 行为时钟。
- `pll_hdmi` / `PH1P_LOGIC_ODDR` 使用 `fpga/sim/models/` 的行为模型；
  它们不验证真实 PLL 的环路/抖动。
- FIFO 是真实 `async_fifo_gray`（128-bit × 256），跨
  `dhi_clk` → `pixel_clk`。
- 帧缓存基地址 4096，38400 beat，每 beat 8 个 RGB565 像素。

## 2. 命令

```tcl
vlib work
vlog fpga/rtl/ddr/fb_pattern.v \
     fpga/rtl/ddr/crc32_16.v \
     fpga/rtl/ddr/fb_writer.v \
     fpga/rtl/ddr/fb_reader.v \
     fpga/rtl/ddr/pixel_gearbox.v \
     fpga/rtl/ddr/ddr_axi_pattern_test.v \
     fpga/rtl/common/async_fifo_gray.v \
     fpga/rtl/display/rgb565_to_rgb888.v \
     fpga/rtl/display/video_timing.v \
     fpga/rtl/display/tmds_encoder.v \
     fpga/rtl/display/serial_load_gen.v \
     fpga/rtl/display/tmds_serializer.v \
     fpga/sim/models/pll_hdmi_sim.v \
     fpga/sim/models/ph1p_logic_oddr_sim.v \
     fpga/sim/models/ddr_axi_slave_model.v \
     fpga/rtl/fb/ddr_fb_hdmi_core.v \
     fpga/sim/tb/tb_ddr_fb_hdmi_core.v

vsim -c -do "run -all; quit" work.tb_ddr_fb_hdmi_core
vsim -c -gREADY_DELAY=2 -do "run -all; quit" work.tb_ddr_fb_hdmi_core
vsim -c -gCORRUPT=1 -gCORRUPT_ADDR=4100 -do "run -all; quit" work.tb_ddr_fb_hdmi_core
```

## 3. 结果（3/3 PASS）

```text
=== 正常 (READY_DELAY=0, CORRUPT=0) ===
ok   self-check pass
ok   frame write accepted, crc_expected=f53a4d4f
crc_actual=f53a4d4f crc_expected=f53a4d4f crc_ok=1 err_valid=0 err_addr=0
ok   full-frame readback CRC match
ok   h=0   v=10 rgb=ffffff
ok   h=3   v=10 rgb=ff0000
ok   h=40  v=10 rgb=ffffff
ok   h=120 v=10 rgb=ffff00
ok   h=200 v=10 rgb=00ffff
ok   h=280 v=10 rgb=00ff00
ok   h=360 v=10 rgb=ff00ff
ok   h=440 v=10 rgb=ff0000
ok   h=520 v=10 rgb=0000ff
ok   h=600 v=10 rgb=000000
ok   h=40  v=32 rgb=848284
ok   h=40  v=33 rgb=ffffff
ok   no underflow/overflow/error
TB: PASS - ddr_fb_hdmi_core
Errors: 0, Warnings: 0

=== 反压 (READY_DELAY=2, CORRUPT=0) ===
ok   self-check pass
ok   frame write accepted, crc_expected=f53a4d4f
crc_actual=f53a4d4f crc_expected=f53a4d4f crc_ok=1 err_valid=0 err_addr=0
ok   full-frame readback CRC match
ok   h=0 v=10 rgb=ffffff
ok   h=3 v=10 rgb=ff0000
ok   h=40 v=10 rgb=ffffff
ok   h=120 v=10 rgb=ffff00
ok   h=200 v=10 rgb=00ffff
ok   h=280 v=10 rgb=00ff00
ok   h=360 v=10 rgb=ff00ff
ok   h=440 v=10 rgb=ff0000
ok   h=520 v=10 rgb=0000ff
ok   h=600 v=10 rgb=000000
ok   h=40 v=32 rgb=848284
ok   h=40 v=33 rgb=ffffff
ok   no underflow/overflow/error
TB: PASS - ddr_fb_hdmi_core
Errors: 0, Warnings: 0

=== 注入错误 (CORRUPT=1, CORRUPT_ADDR=4100) ===
ok   self-check pass
ok   frame write accepted, crc_expected=f53a4d4f
crc_actual=306b3f2a crc_expected=f53a4d4f crc_ok=0 err_valid=1 err_addr=4100
ok   corruption detected at addr=4100
ok   aborted in PH_ERROR, display never started
TB: PASS - ddr_fb_hdmi_core
Errors: 0, Warnings: 0
```

## 4. 结论与未覆盖

- 16-beat 前置自检 PASS。
- 38400 beat 写帧完成，`write_done` 只表示握手完成 + 期望 CRC 就绪，
  物理写入完成由读回证明。
- 整帧读回：逐像素与 `fb_pattern` 一致，读侧 CRC 由**实际读回数据**
  计算，`crc_actual == crc_expected == 0xF53A4D4F`（正常/反压两种）。
- 在帧内 beat 4100 注入 1 bit 错误：`err_addr=4100`、`err_valid=1`、
  `crc_actual=0x306B3F2A` ≠ expected，核心进入 `PH_ERROR`，HDMI 不启动。
- HDMI 第一帧 line 10 的边框/方向标记/8 色竖条位置全部正确；
  line 32 为网格灰，line 33 恢复白条（行列映射正确）。
- FIFO 未出现 underflow/overflow；`video_valid` 在预充后由 VSYNC
  下降沿对齐启动。
- 未证明：真实 DDR PHY 初始化/校准、真实 MC 的读写完成语义、
  真实存储单元保持力、真实 PLL 抖动、板上显示器结果。
