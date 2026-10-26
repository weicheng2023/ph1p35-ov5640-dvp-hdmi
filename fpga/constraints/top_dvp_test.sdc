# ============================================================================
# top_dvp_test.sdc
# top_dvp_test 时序约束
#
# 50MHz 系统时钟：C4，周期 20.000 ns。
#
# PCLK：2026-10-26 LA 实测为 50 MHz（20.000 ns，50% 占空比）。
# 不得为了“时序通过”把 PCLK 设成 false path。
#
# 输入延迟：摄像头到 FPGA 的 tCO + 47Ω/排线延迟仍未单独测量；
# 先用保守估计 10/2 ns，若时序或上板数据异常再收紧/调整。
# DVP 数据在 PCLK 域采样，不跨到 50MHz 域直接采样。
# ============================================================================

create_clock -name clk_50m  -period 20.000 [get_ports {clk_50m}]
create_clock -name cam_pclk -period 20.000 [get_ports {cam_pclk}]

# DVP 输入相对 PCLK 的到达时间（临时值）。
set_input_delay -clock cam_pclk -max 10.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]
set_input_delay -clock cam_pclk -min  2.000 [get_ports {cam_data[0] cam_data[1] cam_data[2] cam_data[3] cam_data[4] cam_data[5] cam_data[6] cam_data[7] cam_href cam_vsync}]

# PCLK 与 50MHz 无相位关系。事件 FIFO 用 Gray 指针同步，传输路径按异步处理。
# 这是有依据的 CDC 约束，不是掩盖采样问题的 false path。
set_clock_groups -asynchronous -group [get_clocks {clk_50m}] -group [get_clocks {cam_pclk}]
