# DDR Frame Buffer → HDMI TD 构建证据（2026-11-08）

> **历史记录：已被 2026-11-09 PAXI 修复版取代。**
> 本位流实际烧录后为整屏红、LED3 灭、LED4 亮；根因是 PAXI 地址单位
> 和写掩码极性。最终通过版见
> `top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md` 和
> `../board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`。
> 以下构建数值保留为诊断历史。
>
> 工具：Tang Dynasty 6.2.1（v6.2.168116）
> 器件：PH1P35MDG324 / speed 3
> 顶层：`top_ddr_fb_hdmi`（独立工程，未改动任何既有顶层）
> 位流（本地，不入库）：`build/bitstream/top_ddr_fb_hdmi.bit`
> SHA-256：`3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`
>
> **配置声明**：本顶层实例化 `ddr2 #(.CAL_EN(0))`。CAL_EN=0 是**实验
> 配置**，绕过 PHY 训练；本构建、仿真通过和上板 READY/CRC 都不能宣称
> “完整 PHY 校准通过”。数据可靠性只由 16-beat 自检与整帧读回 CRC 证明。

## 1. 构建命令

```text
/path/to/TD_6.2.1/bin/td_commands_prompt.exe \
  fpga/scripts/build_top_ddr_fb_hdmi.tcl
```

或双击 `fpga/scripts/build_top_ddr_fb_hdmi.bat`（需设置 `TD_HOME`）。

## 2. 设计组成

| 模块 | 作用 |
|---|---|
| `top_ddr_fb_hdmi` | 板级顶层：BUFG、POR、心跳、`ddr2`（CAL_EN=0）、TMDS、LED |
| `ddr_fb_hdmi_core` | 阶段 FSM：自检 → 写帧 → DRAIN → 读回校验 → 预充 → 显示 |
| `ddr_axi_pattern_test` | 16-beat 最小自检（BASE=0，DRAIN=1024） |
| `fb_writer` | 38400 个单拍 128-bit 写（BASE=4096，80 beat/行）+ 期望 CRC |
| `fb_reader` | 整帧读回逐像素比对 + 实际数据 CRC；显示模式写 FIFO |
| `async_fifo_gray` | 128-bit × 256，Gray 指针跨 `dhi_clk` → `pixel_clk` |
| `pixel_gearbox` | FIFO 头 128-bit → 8 × RGB565，DE 对齐 |
| `fb_pattern` / `crc32_16` | 确定性测试图 / CRC-32/ISO-HDLC |
| `pll_hdmi` + HDMI 链路 | 复用已上板验证的 25/125 MHz PLL、时序、TMDS |

DDR IP：`build/ddr_ip/`（TD `MIS_DDRF6F1D0P0_1.1` Integrated，
DDR2 512Mb x16、MDG324、50 MHz ref、PLL N=3/M=64/C=2/CLK3=21），
由 `fpga/scripts/prepare_ddr_ip.sh` 组装，**不入库**。

## 3. 时序与资源（routed）

```text
Setup WNS        : +0.163 ns
Setup TNS        :  0.000 ns
Violated S-EP    :  0
Hold WNS         : +0.021 ns   (紧)
Hold TNS         :  0.000 ns
Violated H-EP    :  0
Slices           :  5116  (24.11%)
RAMs / DSPs      :  0 / 0
DRAMHARDCON      :  100      (in-package DDR PHY)
```

时钟：
`u_ddr2/usr_clk` 133.351 MHz（dhi_clk）、`clk_50m` 50 MHz、
`pixel_clk` 25 MHz、`serial_clk` 125 MHz、`u_ddr2/mcu_clk` 50.798、
`u_ddr2/ctl_clk` 133.351、`u_ddr2/ddr_clk` 533.618、`u_ddr2/ref_clk` 133.351。

`check_timing` HIGH 级：
- no clock = **0**；
- invalid constraint = **0**（见 §4）；
- dummy node = 2（1 个 PH1P_PHY_LSLICE 未用输出、2 个 PLL `pllreset`
  悬空——与既有 DDR 构建相同，属厂商模板/未用端口）；
- PLL 频率舍入 1 项：`u_ddr2/ddr_clk` 约束 533.599976 vs PLL 533.333333
  （TD 内部舍入，既有 DDR 构建同样存在）；
- MEDIUM：22 个 input / 53 个 output 无 input/output delay（封装内 DDR
  引脚 + LED/TMDS 慢速输出，沿用已上板彩条工程的策略）。

## 4. SDC / CDC 审计（重点）

- `top_ddr_fb_hdmi.sdc`：`create_clock clk_50m` 20 ns + `derive_clocks`；
  用 `rename_clock` 把 HDMI PLL 输出命名为 `pixel_clk`/`serial_clk`。
- **未新增**设计级 `set_clock_groups`。TD 6.2.1 会把
  `{usr_clk} vs {pixel_clk serial_clk}` 的二组异步声明判为
  **invalid（与厂商 IP SDC 的单组声明冗余）**；实验确认后没有保留它。
- DDR 时钟关系保持厂商 IP SDC：
  - 厂商自带 `set_clock_groups -asynchronous -group [get_clocks mcu_clk]`；
  - `prepare_ddr_ip.sh` 追加的单组
    `{ddr_clk usr_clk ctl_clk mcu_clk ref_clk}`（用于切断 PHY
    init/cal 的 `usr_clk -> clk_50m` 路径，是最小 DDR 测试构建的既有修复）。
- 本设计自身唯一的跨域路径（已逐项审计）：
  1. `async_fifo_gray` 的 Gray 指针同步与双时钟 FIFO 存储；
  2. 2FF 同步器：`ddrphy_rdy`、`reader_prefill_done`、`underflow`、
     `fatal_dhi`、`display_error_dhi`；
  3. `rst_n`（clk_50m POR）只作为其他域的异步复位，不作数据。
  没有共享计数器或多 bit 数据总线跨越 `usr_clk ↔ pixel_clk`；
  `pixel_clk`/`serial_clk` 与 `clk_50m` 保持同步关系并被正常时序分析
  （TMDS 编码器 → serializer load 路径在报告内）。

对照实验（已执行，未保留为最终构建）：
- 删除厂商单组并改用二组显式声明 → `check_timing` 0 invalid，但
  厂商 IP 内部约束未生效，Setup **-2.467 ns** / Hold **-0.723 ns**，
  44 个 setup 违约（DDR init/复位恢复路径）。说明**不能**用设计级
  二组声明替代厂商 IP SDC；已回退到 §4 的最终方案。

## 5. 构建产物

| 文件 | 说明 |
|---|---|
| `top_ddr_fb_hdmi.bit` | 位流，SHA-256 见文件头 |
| `top_ddr_fb_hdmi_route.qor` | 布线后 QoR |
| `top_ddr_fb_hdmi_final_timing.rpt` | 最终时序 |
| `top_ddr_fb_hdmi_route.check_timing` | check_timing 明细 |
| `top_ddr_fb_hdmi_netlist.csv` | 网表 |

全部位于 `build/bitstream/`（git-ignored）。既有位流
`top_hdmi_colorbar.bit`、`top_ov5640_line_to_hdmi.bit`、
`top_ddr_test.bit`、`top_ddr_debug.bit`、`top_ddr_debug_cal0.bit`
均未被覆盖。

## 6. 未证明

- CAL_EN=0 下真实 PHY 的建立/保持窗口与长期稳定性；
- 真实 DDR 存储单元在温度/电压变化下的保持力；
- 真实 HDMI 显示器上的画面与 FIFO 行为；
- 板上 LED 结果（需按 `verification/board/bringup-ddr-fb-hdmi.md` 实测）。
