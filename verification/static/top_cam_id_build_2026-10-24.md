# top_cam_id 构建与仿真记录（2026-10-24）

## 环境

- TD：Tang Dynasty 6.2.1（6.2.168116）
- 器件：PH1P35MDG324，Speed -3
- 仿真器：ModelSim SE-64 2020.4
- 顶层：`top_cam_id`

## 1. ModelSim 仿真

命令（在 `build/sim` 下）：

```tcl
vlib work
vlog ../../fpga/rtl/camera/sccb_master.v \
     ../../fpga/rtl/camera/ov5640_id_reader.v \
     ../../fpga/rtl/top/top_cam_id.v \
     ../../fpga/sim/tb/tb_top_cam_id.v
vsim -c -do "run -all; quit" work.tb_top_cam_id
```

结果：

```text
TB: PASS - Chip ID matched (led=1110, id_hi=56, id_lo=40)
Errors: 0, Warnings: 0
```

说明：testbench 内含行为级 SCCB 从机模型，返回 `0x56/0x40`。
验证了 START/STOP、8 位收发、ACK/NA、重复起始和重试逻辑；
**不验证真实摄像头的电气特性**。

## 2. TD 构建

构建命令：

```bat
cd /d D:\Projects\02_Personal_Practice\2026_10_OV5640
fpga\scripts\build_top_cam_id.bat
```

流程：`read_hdl → read_adc → optimize_rtl → read_sdc → optimize_gate →
legalize_phy_inst → place → route → bitgen`。

结果：

| 项目 | 结果 |
|---|---|
| 综合/布局布线 | 通过 |
| 未约束 IO | 0（9/9 端口已分配） |
| Setup WNS | **+13.196 ns** |
| Setup TNS | 0.000 ns |
| Hold WNS | **+0.069 ns** |
| Hold TNS | 0.000 ns |
| Slices | 257（1.21%） |
| 位流 | `build/bitstream/top_cam_id.bit`（约 1.8 MB） |
| 时序报告 | `build/bitstream/final_timing.rpt` |
| QoR | `build/bitstream/route.qor` |

## 3. 约束检查

- `top_cam_id.adc`：9 个端口全部分配，无重复球位。
- `top_cam_id.sdc`：50 MHz 时钟约束生效（Clock Summary 50.000 MHz）。
- `camera_pinmap_draft.adc` 未参与本测试（DVP 阶段使用）。

## 4. 已知限制

- TD 项目模式在本机生成的 `run.bat` 调用了不存在的
  `td_commands_prompt_commands_prompt.exe`，GUI Run 流程不可用；
  当前使用命令行脚本构建。
- 未执行上板烧录；LED 结果待实物验证。
- 未执行 DVP 采集、HDMI 输出、DDR 帧缓存。

## 5. 结论

工具链层面已通过：RTL 可综合、约束可接受、时序收敛、位流可生成。
这**不等于**实物接线正确或摄像头已响应；上板结论必须另附证据。
