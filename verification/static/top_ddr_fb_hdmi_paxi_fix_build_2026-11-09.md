# DDR → HDMI PAXI 修复版构建（2026-11-09）

## 结果

TD 6.2.1（6.2.168116），PH1P35MDG324，Speed 3，顶层 `top_ddr_fb_hdmi`。
命令行完成综合、布局、布线、时序报告、check_timing 和 bitgen，进程退出码 0。

**上板结果：STAGE 2 — BOARD FUNCTIONAL PASS（2026-11-09，用户报告）。**
用户烧录本位流后确认 FPGA 内部测试图 → DDR → HDMI 成功显示。
LED 逐项状态、CRC/照片等细节未提供，记录见
[20261109 实物证据](../board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md)。
构建数值仍以本文件的报告为准。

- Setup WNS **+0.110 ns**，TNS 0，违例端点 0。
- Hold WNS **+0.020 ns**，TNS 0，违例端点 0，余量紧。
- 5283 slices（24.90%）、0 RAM、0 DSP、100 DRAMHARDCON。
- STA coverage 94.47%；Slow/Fast 均检查 Max/Min。

位流：`build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit`

```text
SHA-256 e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16
```

旧 `build/bitstream/top_ddr_fb_hdmi.bit` 完整保留，SHA 仍为
`3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`。
新构建脚本使用独立文件名，不覆盖旧位流。

## 约束检查的限制

`check_timing`：无时钟 0、时钟定义问题 0、无效约束 0、组合环 0；
仍有以下提示，**不宣称完整时序签核**：

- HIGH dummy node 项计数 2：LSLICE `ofb`、DDR PLL `pllreset` 悬空端点。
- HIGH PLL/buffer 项计数 1：DDR 时钟约束 533.599976 MHz 与 PLL 设置
  533.333333 MHz 的舍入差；报告还提示 PLL0 feedback path 在 local network，
  compensation delay 不可预测。
- MEDIUM：22 个输入、53 个输出未设 delay。

本轮未调整 SDC 来消除提示。构建前后 SHA 核对确认以下文件不变：
`fpga/rtl/ddr/ddr2_top.v`、`fpga/rtl/display/pll_hdmi.v`、
`fpga/constraints/top_ddr_fb_hdmi.sdc`、`build/ddr_ip/src/sdc/ddr2.sdc`。
CAL_EN=0、50 MHz 参考、HDMI PHY/视频时序保持原配置。

## 证据与复现

- 脚本：`fpga/scripts/build_top_ddr_fb_hdmi.bat/.tcl`。
- 完整日志：`build/top_ddr_fb_hdmi_paxi_fix_20261109_build.log`。
- 报告：`build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109_route.qor`、
  `top_ddr_fb_hdmi_paxi_fix_20261109_final_timing.rpt`、
  `top_ddr_fb_hdmi_paxi_fix_20261109_route.check_timing`。
- [必要行为回归 12/12 PASS](ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md)。
- [新位流上板说明](../board/bringup-ddr-fb-hdmi-paxi-fix.md)。

图像路径仍是 writer → DDR → reader → Gray FIFO → gearbox → HDMI。
状态错误色是本地产生的诊断背景；正常彩条不能绕过 DDR。
本轮没有完整 PHY 仿真、部分字节掩码专项、复杂 burst 或额外压力测试。
