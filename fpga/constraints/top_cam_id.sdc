# top_cam_id 时序约束
# 50MHz 有源晶振，周期 20ns；来源：P04_DIG_LED / P08_EX_DEVICE 的 U31。
create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]

# 说明：
# - 本工程没有 PCLK/DVP 接口，因此不添加摄像头像素时钟约束。
# - SCCB 是低速控制总线，不作为时序路径约束对象。
