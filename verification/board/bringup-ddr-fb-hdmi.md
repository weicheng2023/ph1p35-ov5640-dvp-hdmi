# DDR Frame Buffer → HDMI 上板步骤（2026-11-08）

> **已由 2026-11-09 PAXI 修复版替代。** 本页为旧版本历史说明，旧地址/掩码存在问题。
> 本轮请按 [新上板说明](bringup-ddr-fb-hdmi-paxi-fix.md) 操作，勿下载旧位流。

> 目标：FPGA 内部 640×480 RGB565 测试图 → 单拍 128-bit 写入 DDR →
> 整帧读回逐像素 + CRC 校验 → 连续读 → 异步 FIFO → 8:1 gearbox →
> 已验证 HDMI 链路 → 显示器完整图像。
>
> 位流：`build/bitstream/top_ddr_fb_hdmi.bit`
> SHA-256：`3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`
> 配置：`ddr2 #(.CAL_EN(0))` —— **实验配置，PHY 训练被绕过**。
> READY/CRC 通过也不等于“完整 PHY 校准通过”。
>
> 构建记录：`verification/static/top_ddr_fb_hdmi_build_2026-11-08.md`
> 仿真记录：`verification/static/ddr_fb_hdmi_sim_2026-11-08.md`
> 构建脚本：`fpga/scripts/build_top_ddr_fb_hdmi.bat`
> 保存实测结果：`verification/board/evidence/20261108_ddr_fb_hdmi/README.md`

## 1. 准备

- 只接电源、HDMI 显示器、USB-JTAG；**不接摄像头**。
- 器件 PH1P35MDG324；C4 50 MHz 有源晶振。
- 构建前先运行 `fpga/scripts/prepare_ddr_ip.sh`（生成 `build/ddr_ip/`）。
- **不要覆盖**既有已验证位流（彩条 / 单行 / DDR test / DDR debug）。

## 2. 构建 / 确认位流

```bat
cd fpga\scripts
build_top_ddr_fb_hdmi.bat
```

产物：`build/bitstream/top_ddr_fb_hdmi.bit`。
烧录前核对 SHA-256 与上表一致。

## 3. LED 定义

| LED | 信号 | 含义 |
|---|---|---|
| LED1 | 50 MHz 心跳 | 时钟/位流/电源基本正常 |
| LED2 | `ddrphy_rdy`（2FF 到 dhi_clk） | DDR 报告 READY |
| LED3 | `write_done` | 38400 beat 全部握手完成 + 期望 CRC 就绪（**不代表**物理写入完成） |
| LED4 | `error_o` | 自检/整帧读回 CRC/FIFO/流错误（锁存） |

## 4. 启动顺序与预期画面

1. 上电后 LED1 闪烁；LED2 应在 DDR READY 后亮。
2. 核心先做 16-beat 自检 → 写整帧 → 保守 DRAIN → 整帧读回校验。
3. 校验通过后 FIFO 预充 192 个 128-bit 字；在下一个 VSYNC 边界开始
   有效视频。**在此之前显示器应为深蓝背景（`0x000040`）**，不是图像。
4. 若自检/写/校验/流错误：**整个画面为红色**，LED4 亮；HDMI 不会
   显示测试图。
5. 正常时显示：
   - 8 条竖条：白/黄/青/绿/品红/红/蓝/黑，每条 80 px；
   - 2 px 白色边框；
   - 左上角 16×16 红白棋盘方向标记；
   - 每 32 行一条灰色横线。

## 5. 上板记录表（请填写）

| 项目 | 实测 |
|---|---|
| 位流 SHA-256 | |
| 1 s 时 LED1/2/3/4 | |
| 10 s 时 LED1/2/3/4 | |
| 显示器是否出现深蓝背景 | |
| 是否出现测试图 | |
| 8 色顺序/方向是否正确 | |
| 边框/方向标记/网格是否正确 | |
| 是否有撕裂/错行/闪烁/彩点 | |
| 是否出现红色错误画面 | |
| 备注（照片文件名/时间） | |

照片/短视频请放入
`verification/board/evidence/20261108_ddr_fb_hdmi/`（或记录本地路径）。

## 6. LED 组合判断

| LED1 | LED2 | LED3 | LED4 | 判断 | 下一步 |
|---|---|---|---|---|---|
| 灭 | — | — | — | 时钟/位流/电源 | 先用已验证彩条位流确认板卡 |
| 闪 | 灭 | 灭 | 灭 | READY 尚未到（无超时输出） | 等 2 s；查 C4/POR |
| 闪 | 灭 | 灭 | 亮 | DDR 未 READY / 自检未开始 | 用 `top_ddr_debug` 复核；CAL_EN=0 已知可达 READY |
| 闪 | 亮 | 灭 | 亮 | 自检/写帧/读回失败，或 FIFO/流错误 | 画面应为红色；用 ChipWatcher 看 `error_code` |
| 闪 | 亮 | 亮 | 亮 | 写帧完成但读回 CRC/逐像素不符 | 记录 `dbg_frame_err_*`，按地址定位 |
| 闪 | 亮 | 亮 | 灭 | 自检 + 写 + 读回 + 流通过 | 检查 HDMI 图像内容/行列/颜色 |

> 即使 LED3/4 全对，也只证明 **CAL_EN=0 实验配置下**本帧数据读回一致；
> 不证明 PHY 校准通过、长期可靠性或温度/电压余量。

## 7. ChipWatcher 建议观察点（TD 6.2.1）

`ddr_fb_hdmi_core` 内已保留（`(* keep *)`）：

- `dbg_self_pass`、`dbg_self_err_cnt`、`dbg_self_err_addr`、
  `dbg_self_exp_data`、`dbg_self_act_data`；
- `dbg_crc_expected` / `dbg_crc_actual` / `dbg_crc_ok`；
- `dbg_frame_err_valid` / `dbg_frame_err_pixel` / `dbg_frame_err_addr` /
  `dbg_frame_err_exp` / `dbg_frame_err_act`；
- `dbg_fifo_underflow` / `dbg_fifo_overflow`；
- `dbg_write_done` / `dbg_verify_done` / `dbg_prefill_done`；
- `dbg_error_code[3:0]`、`dbg_phase[2:0]`。

`error_code`：1=自检失败，2=写帧超时/错误，3=读回校验失败，4=显示流错误
（FIFO overflow / underflow / reader error）。正常期望
`crc_expected == crc_actual == 0xF53A4D4F`（同 RTL/图像；若图像生成或
CRC 实现修改，以仿真值为准）。

## 8. 边界与未证明

- 本阶段只验证 **测试图 → DDR → HDMI**；不接摄像头、不改 DVP。
- 不声称完整 DDR PHY 校准、压力测试、长时间稳定性。
- 不覆盖任何既有验证位流；不提交位流/厂商 PDF/构建产物。
