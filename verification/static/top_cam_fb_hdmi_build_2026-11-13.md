# Stage 3 TD 构建记录：top_cam_fb_hdmi

> 日期：2026-11-13
> 工具：Tang Dynasty 6.2.1，器件 PH1P35MDG324（speed -3）
> 顶层：`fpga/rtl/top/top_cam_fb_hdmi.v`
> 结论：**构建/布局布线/位流通过；Setup +0.184 ns / Hold +0.020 ns，
> 0 个违约端点。** 这不等于完整时序签核，也不证明 DDR PHY 校准。

## 1. 位流

| 项目 | 值 |
|---|---|
| 文件 | `build/bitstream/top_cam_fb_hdmi.bit`（本地，gitignore） |
| SHA-256 | `787b26ee9bd6e7e171e74a0947df6cd793b657838d282d05c4e8f9fe88ace15e` |
| 大小 | 1,789,490 字节 |
| 参数 | **`HREF_ACTIVE_HIGH=0`**（2026-11-13 极性修复；见 §5.1） |
| 时序/资源 | Setup +0.404 / Hold +0.020 ns，0 违约端点，6952 slices |

### HREF 极性修复（2026-11-13）

首个 Stage 3 位流（`HREF_ACTIVE_HIGH=1`，SHA `a25a2ac9…`）上板为
“左黑 + 右浅蓝”，与 2026-11-08 单行版一致。根因分析（
`docs/camera/README.md` §2.1a）：数据手册 `0x4740` bit1=HREF 极性，
默认 `0x20` 为低有效；正点原子参考驱动用默认 `0x20` + HREF 高电平采集，
说明本模组引脚极性与 datasheet 相反。我们写 `0x22`（bit1=1）→ 引脚
HREF **低有效**；低相位实测 1280 PCLK = 640 像素。原设计用
`HREF_ACTIVE_HIGH=1`，抓到的是 1920 PCLK 消隐高相位。

修复只改 `HREF_ACTIVE_HIGH` 1→0，摄像头配置/DDR/HDMI/SDC 不变。
旧位流保留为 `build/bitstream/top_cam_fb_hdmi_hrefhigh_20261113.bit`
（SHA `a25a2ac9…`）。**上板结果待用户实测。**

### 摄像头内部彩条诊断位流（`-define CAM_COLOR_BAR`，HREF 低有效）

| 项目 | 值 |
|---|---|
| 文件 | `build/bitstream/top_cam_fb_hdmi_colorbar.bit` |
| SHA-256 | `76d2ec77e46fc2675f4d6dbee6ddddc086d44ce86752cff4598a3fdf931f50ab` |
| 差异 | 只把 `0x503D` 写成 `0x80`（内部彩条）；采集/DDR/HDMI 相同 |
| 时序/资源 | Setup +0.820 / Hold +0.020 ns，0 违约端点，6933 slices |

实景位流未被覆盖。旧的 HREF 高有效彩条位流保留为
`build/bitstream/top_cam_fb_hdmi_colorbar_hrefhigh_20261113.bit`
（SHA `616242ff…`，Setup +0.623 / 6922 slices）。

## 2. 时序（routed）

| 时钟 | 频率 | Setup WNS | Hold WNS |
|---|---|---|---|
| `u_ddr2/usr_clk` (dhi_clk) | 133.351 MHz | **+0.184 ns**（全局最差） | +0.021 ns |
| `cam_pclk` | 48.001 MHz | +8.841 ns | +0.055 ns |
| `clk_50m` | 50.000 MHz | +10.768 ns | +0.020 ns |
| `pixel_clk` | 25.000 MHz | +13.799 ns | +0.054 ns |
| `serial_clk` | 125.000 MHz | +5.244 ns | +0.057 ns |

- Setup TNS 0，Hold TNS 0，**0 个违约端点**。
- 与阶段 2 相同，全局最差 setup 在 `usr_clk`（CAL_EN=0、未训练的 PHY
  用户时钟域）；像素域余量很大，不是当前瓶颈。

## 3. 资源

| 项目 | 值 |
|---|---|
| Slices | 6920（32.62%） |
| RAMs | 0 |
| DSPs | 0 |
| DRAMHARDCON | 191 |

说明：两个异步 FIFO 与 640×16 行 RAM 仍映射为分布式 RAM（0 RAM），
与阶段 2 一致；`pixel_gearbox` 依赖的 FIFO 首字直通（组合读）行为
与仿真模型一致。**这一点在本构建中未被“改映射成 ERAM”引入差异。**

## 4. `check_timing` 结果（不作完整签核）

- HIGH：no clock 0、clock definition 0、invalid constraint 0、
  combinational loop 0、soft FIFO exception 0；
  **3 个 dangling（dummy）节点**（与阶段 2 的未用 PHY 输出/悬空
  `pllreset` 同类）；PLL/clock buffer 检查 0 问题。
- HIGH/信息：`ddr_clk` 533.600 vs 533.333 MHz PLL 舍入提示（厂商 IP
  既有）。
- MEDIUM：23 个输入端口、57 个输出端口未设 IO delay
  （封装内 DDR、LED、TMDS 等慢速/无外部时序规格输出）。
- `SCLK`/`primary clock on internal refclk` 类提示与阶段 2 相同，
  未通过改 SDC 隐藏。

## 5. 与阶段 2 的差异

- 新增摄像头 DVP 输入域（`cam_pclk` 已声明与系统/HDMI 时钟组异步；
  跨域只有 Gray FIFO、2FF 电平与异步复位）。
- 显示 FIFO 增加写域 `wr_empty`，用于帧末排空检测（不改变原有端口
  行为；阶段 2 12 例回归 12/12 PASS）。
- DDR PAXI 地址步长/掩码/握手语义未改；DDR IP、PLL、CAL_EN=0、
  HDMI PLL/TMDS/视频时序未改。
- 未被修改：用户另行实验的 WBUF 路径
  （`pixel_gearbox_wbuf.v`、`top_ddr_fb_hdmi_wbuf.*`）保持原样。

## 6. 复现

```bat
fpga\scripts\build_top_cam_fb_hdmi.bat
```

摄像头内部彩条版本（只改 `0x503D`，不覆盖本实景位流）：

```bat
set CAM_COLOR_BAR=1
fpga\scripts\build_top_cam_fb_hdmi.bat
rem 输出 build\bitstream\top_cam_fb_hdmi_colorbar.bit
```

依赖：`build/ddr_ip/` 由 `fpga/scripts/prepare_ddr_ip.sh` 生成（不入库）。

## 7. 未决

- 上板功能未测（见 `verification/board/bringup-cam-fb-hdmi.md`）。
- 阶段 2 彩条“色块右缘短横毛刺、向上滚动”未定位；本阶段先观察
  实时画面下是否仍存在，不修改 DDR 侧代码。
- `CAL_EN=0` 为实验配置，不证明完整 PHY 校准或长期稳定性。
