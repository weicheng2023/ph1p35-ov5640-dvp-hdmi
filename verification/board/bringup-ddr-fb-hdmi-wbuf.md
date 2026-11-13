# DDR → HDMI 寄存器字缓冲（WBUF）试验上板说明（2026-11-09）

## 目的

在**不覆盖**已上板通过的
`top_ddr_fb_hdmi_paxi_fix_20261109.bit` 的前提下，单独烧录一个试验位流：

- 显示 FIFO 的 128-bit 字先锁进 `word_buf` 寄存器；
- 8:1 MUX 之后再加一级 RGB565 像素寄存器；
- RGB888 之后同步延迟 DE/HS/VS（共 2 个像素周期）。

用它判断色条右边缘“向右突出的短横毛刺、持续上滚”是否来自
“FIFO 头 → MUX → RGB565→RGB888 → TMDS 编码器”这一段组合逻辑。

**这是成因试验，不是修复声明。** 无论结果如何，不改写阶段 2 的
BOARD FUNCTIONAL PASS 记录。

## 位流

| 用途 | 位流 | SHA-256 |
|---|---|---|
| 对照（已上板通过，保留） | `build/bitstream/top_ddr_fb_hdmi_paxi_fix_20261109.bit` | `e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16` |
| 本次试验 | `build/bitstream/top_ddr_fb_hdmi_wbuf_20261109.bit` | `1f14bce535b429630ed22599a2b801f9d2f6cdd681da9e45019d110ee8c3ee7b` |

TD 6.2.1：Setup **+0.218 ns** / Hold **+0.020 ns**，4547 slices，
**4 ERAM**（显示 FIFO 被推断成 ERAM；原工程是 800 个分布式 RAM mslice）。
其余配置与对照完全相同：`CAL_EN=0`、50 MHz 参考、25/125 MHz HDMI PLL、
TMDS、视频时序、PAXI 协议、ADC/SDC、LED 语义。

## 操作

1. 只连接电源、HDMI 显示器、USB-JTAG；不需要摄像头和逻辑分析仪。
2. BitWizard → Refresh → 加入
   `top_ddr_fb_hdmi_wbuf_20261109.bit` → **Program SRAM** → Run。
3. 稳定后（约 10 s）记录：
   - LED1/2/3/4；
   - 画面是否完整（八色条、2 px 白边、左上标记、每 32 行网格）；
   - **色条右边缘毛刺是否仍然存在**；
   - 若存在，是否仍向上滚动、滚动速度是否变化。
   照片/视频文件名写入证据目录。
4. 如需对照，重新烧回 `top_ddr_fb_hdmi_paxi_fix_20261109.bit` 再看一次，
   确认两次观察条件（显示器输入、分辨率、线缆、环境温度）一致。

## 判读

| 观察 | 可写的结论 | 不能写的结论 |
|---|---|---|
| 毛刺消失，图像完整 | “寄存器字缓冲/ERAM 读端口这条路径与现象相关，值得继续隔离” | 不能直接说“组合逻辑时序就是根因”（本次同时改了 FIFO 存储实现） |
| 毛刺仍在，图像完整 | 显示 FIFO→MUX→编码器路径基本被排除；优先怀疑 DDR 读数据、TMDS 链路或显示器 | 不能排除寄存器路径（LUTRAM/ERAM 差异未隔离） |
| 出现纯色错误屏 | 按原 `bringup-ddr-fb-hdmi-paxi-fix.md` 的颜色表判读 | 不能把纯色屏算作毛刺结论 |
| 图像缺失/错位 | 先检查是否烧错位流、CRLF 构建是否完整；WBUF 理论上只把整幅画面相对同步延后 2 个像素，不应裁边 | 不要用 WBUF 位流覆盖对照位流 |

LED 语义与对照相同：LED1 心跳、LED2 DDR READY、LED3 整帧写完成、
LED4 锁存错误。

## 下一步（若毛刺仍在）

显示通路被排除后，剩下的最可疑项是 DDR 读数据本身：

- 阶段 2 的逐像素/CRC 校验只在**启动时**做一次；显示阶段持续读同一位流，
  没有运行期比对。可做一个“显示阶段并行比对”试验位流，任何 beat 与
  `fb_pattern` 不符就点灯/换色，用于区分 DDR 读错误与显示通路错误。
- `CAL_EN=0` 会绕过 PHY 训练，133.35 MHz 下 setup 余量只有约 0.1–0.2 ns；
  这类边缘读错误在平坦色块内看不出来，只在颜色跳变处（色条边界）显现，
  与观察到的位置特征吻合。**这只是假设，未验证。**

## 复现构建与仿真

构建：`fpga/scripts/build_top_ddr_fb_hdmi_wbuf.bat`
（tcl 必须 CRLF 行尾，见构建记录）。
仿真：`powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_wbuf.ps1`
（8/8 PASS，其中两例 307200 像素全帧逐点比对）。详见
[仿真记录](../static/ddr_fb_hdmi_wbuf_sim_2026-11-09.md) 与
[构建记录](../static/top_ddr_fb_hdmi_wbuf_build_2026-11-09.md)。
