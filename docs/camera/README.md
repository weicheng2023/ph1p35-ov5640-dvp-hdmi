# OV5640 资料、寄存器与引用

> 本文件记录 DVP 阶段使用的传感器资料、寄存器依据和版权/再分发约束。
> 引脚仍以 [`docs/hardware/wiring.md`](../hardware/wiring.md) 为唯一来源。

## 1. 外部资料

| 资料 | 版本/日期 | 用途 | 入库 |
|---|---|---|---|
| OV5640 Product Specification | V2.03 / 2011-05-26 | 寄存器定义、DVP 时序、默认值 | **否** |
| ALIENTEK OV5640 FPGA 驱动（正点原子） | V1.0 / 2020-05-04 | RGB565 初始化表、SCCB/DVP 参考实现 | **否** |
| ATK-MC5640 模块原理图 | V1.2 / 2022-10-21 | 模组连接、24MHz 晶振 | **否，本地保留** |

链接：

- OV5640 数据手册（Toradex 镜像）：
  <https://docs1.toradex.com/103996-omnivision-ov5640-datasheet.pdf>
- 参考工程（含 ALIENTEK OV5640 驱动）：
  <https://github.com/maojinxiang/FPGA-ANLU-National-First-Prize>

### 1.1 再分发约束

- OV5640 规格书标明再分发限制。**不要把完整 PDF 提交到公开仓库。**
- ALIENTEK 例程带版权声明。**不要整段复制其 Verilog 到本仓库。**
- 需要本地副本时放到 `docs/camera/_local/`（已被 `.gitignore` 忽略），
  或放在仓库外的临时目录；只引用链接、寄存器值和核对结论。
- 本项目自己的 RTL、测试平台和文档可以入库；引用第三方资料时注明来源和版本。

## 2. 已核对的关键寄存器

以下结论来自 OV5640 Product Specification V2.03；实际写入值仍需回读和上板实测确认。

| 寄存器 | 值 | 含义 | 依据 |
|---|---:|---|---|
| `0x4300` | `0x61` | RGB565，输出序列 `0x1`：第一字节 `{R[4:0],G[5:3]}`，第二字节 `{G[2:0],B[4:0]}` | 表 7-15 sheet 2 |
| `0x503D` | `0x80` | 使能 Pre-ISP 彩条（bit7=1，bit[3:2]=00 标准 8 色条，bit[1:0]=00 color bar） | 表 7-21 |
| `0x503D` | `0x00` | 关闭彩条，正常图像 | 表 7-21 |
| `0x4740` | 默认 `0x20` | bit5=1 PCLK 高有效；bit1=0 HREF **低有效**；bit0=0 VSYNC **低有效** | 表 7-18 sheet 3 |
| `0x4740` | **本项目 `0x22`** | PCLK 高有效、HREF **高有效**、VSYNC **低有效** | 2026-10-26 LA 实测 |
| `0x3036` | `0x3C` | PLL multiplier（参考表值，未证明等于 24MHz PCLK） | ALIENTEK V1.0 |
| `0x3035` | `0x11` | 系统时钟分频等（参考表值） | ALIENTEK V1.0 |
| `0x3037` | `0x13` | PLL root/pre-divider（参考表值） | ALIENTEK V1.0 |
| `0x3108` | `0x01` | PCLK root divider 等（参考表值） | ALIENTEK V1.0 |
| `0x3808/0x3809` | 参数 | DVP 输出水平宽度 | 表 7-7 / 参考表 |
| `0x380A/0x380B` | 参数 | DVP 输出垂直高度 | 表 7-7 / 参考表 |

### 2.1 极性：已实测确认（2026-10-26）

实测结果：

- **HREF 高有效**：周期 66.67 µs，高电平 40 µs（约 60%）。
- **VSYNC 低有效**：周期 33.33 ms（30 Hz），空闲高、短低脉冲。
- PCLK 50 MHz，20 ns，50% 占空比。

因此本项目的配置表**显式写 `0x4740 = 0x22`**：
bit5=1 PCLK 高有效、bit1=1 HREF 高有效、bit0=0 VSYNC 低有效。

- 此前尝试的 `0x23`（VSYNC 高有效）与 LA 波形不符，已废弃。
- 复位默认 `0x20` 的 HREF 低有效不采用。
- `dvp_capture.v` 在 `top_dvp_test.v` 中使用
  `HREF_ACTIVE_HIGH=1`、`VSYNC_ACTIVE_HIGH=0`。
- 配置完成后回读 `0x4740`，期望 `0x22`。
- 以后改极性时，配置、回读期望值、`dvp_capture` 参数三者必须一起改；
  不要改计数器去“凑”。

### 2.2 时钟/帧率：已实测（2026-10-26）

- 实测 PCLK = **50 MHz**；ALIENTEK 注释的“48 MHz”不准确。
- 实测 VSYNC = **30 Hz**（33.33 ms），HREF = **15 kHz**（66.67 µs），
  每帧约 **500 行**（33.33 ms / 66.67 µs）。
- HREF 高电平 = **40 µs = 2000 个 PCLK**。
- 配置的 RGB565 有源宽度是 640 像素 = 1280 字节；HREF 高却有 2000 字节。
  多出的 720 字节可能是 dummy/padding，也可能是实际宽度不同；
  下一轮用彩条 + D0–D7 确认。
- 仿真/约束使用实测值；`EXPECTED_PIX=2000`、`EXPECTED_LINES=480`。
  若后续确认有源窗口是 1280 字节，再把计数器/显示逻辑改成只取有源部分。

## 3. 配置表使用原则

- 以 ALIENTEK V1.0 的 RGB565 表为**初始化参考**，逐条核对来源和副作用。
- 本项目自己的 `ov5640_cfg.v` 使用自己的表格式和状态机；不复制参考工程的
  Verilog 结构或注释。
- 与参考表的有意差异必须记录：
  - 增加 `0x4740 = 0x22`（显式极性：PCLK/HREF 高、VSYNC 低）；
  - 彩条测试用 `0x503D = 0x80`，正常模式 `0x00`；
  - 分辨率/总行场参数作为模块参数，默认值在实测后确定；
  - 参考表开头的 `0x300A/0x300B = 0` 哑写不纳入，除非确认其作用。
- 配置完成后读回关键寄存器：`0x300A/0x300B`、`0x4300`、`0x4740`、
  `0x3808~0x380B`、`0x503D`、`0x3035~0x3037`、`0x3108`。
  读回不匹配时置错误标志，不要静默继续。

## 4. 本地资料登记

| 文件 | 位置 | 状态 |
|---|---|---|
| OV5640 Product Specification V2.03 | `docs/camera/_local/`（建议） | 本地保留，不入库 |
| ALIENTEK 参考工程 | 仓库外临时目录或 `third_party/_local/` | 只读参考，不入库 |
| ATK-MC5640 V1.2 原理图 | `docs/camera/ATK-MC5640_V1.2.pdf` | 本地保留，不入库 |

`.gitignore` 已忽略 `**/_local/`、`docs/camera/ATK-MC5640_V1.2.pdf` 和 `build/`。
