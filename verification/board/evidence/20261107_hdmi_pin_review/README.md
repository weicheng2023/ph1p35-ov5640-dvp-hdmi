# 2026-11-07 HDMI1 引脚/方向/电气复核

> 本文件只记录**已经实际核对到的内容**。每条结论都标注证据等级；
> 不同等级不得互相替代，也不得把“原理图连接正确”当成“上板功能通过”。

## 1. 复核对象与方法

| 项目 | 内容 |
|---|---|
| 板卡 | PH1P35_FT V1 / HX1P35B_FT_40P |
| FPGA | PH1P35MDG324，Tang Dynasty 6.2.1 |
| 原理图（本地） | `docs/hardware/HX1P35B_FT_40P_2.pdf` = P01_FPGA（Sheet 2/11） |
| 原理图（本地） | `docs/hardware/HX1P35B_FT_40P_7.pdf` = P06_HDMI1（Sheet 8/11） |
| 原理图（本地） | `docs/hardware/HX1P35B_FT_40P_4.pdf` = P02_POWER（Sheet 4/11） |
| 文本提取 | `pdftotext -table`（xpdf 4.06）；**不使用 `-layout` 判引脚** |
| 高 DPI 裁剪 | `pdftoppm -r 300/400/600 -x -y -W -H`，逐段确认网络/二极管/电阻方向 |
| 工具资料 | `D:\Software\Anlogic\TD_6.2.1\arch\ph1p_macro.v`、`sim_release/ph1p/ph1p_logic_hrio.v` |
| 参考工程 | `build/ref/anlogic-ph1p35-vision`（第三方整理，**只读参考，不复制代码/IP**） |

### 1.1 证据等级定义

- **SCHEMATIC_CONFIRMED**：本地原理图 PDF 中直接读出的连接关系。
- **DATASHEET_CONFIRMED**：本地厂商数据手册/库文件中明确写出的参数或能力。
- **TOOL_CONFIRMED**：本地 TD 6.2.1 安装文件或实际工具命令验证的能力。
- **BOARD_MEASUREMENT_REQUIRED**：图纸不能证明，必须用万用表/示波器/上板实测。
- **UNRESOLVED**：目前没有足够依据，不能下结论。

## 2. TMDS / DDC / HPD 球位（SCHEMATIC_CONFIRMED）

`pdftotext -table docs/hardware/HX1P35B_FT_40P_2.pdf` 的 BANK32 行为：

```text
IO_R8P_32,T2            G16   HDMI1_D0_P
IO_R8N_32,T2            H16   HDMI1_D0_N
IO_R9P_32,T2            F17   HDMI1_D1_P
IO_R9N_32,T2            E18   HDMI1_D1_N
IO_R10P_32,T2_DQS_P     H14   HDMI1_D2_P
IO_R10N_32,T2_DQS_N     H13   HDMI1_D2_N
IO_R11P_32,GCLKIOT0,T2  C17   HDMI1_CLK_P
IO_R11N_32,GCLKIOC0,T2  D18   HDMI1_CLK_N
IO_R16P_32,T1_DQS_P     E15   HDMI1_SCL
IO_R16N_32,T1_DQS_N     F15   HDMI1_SDA
IO_R17P_32,T1           B17   HDMI1_HPD
```

同时用 150 dpi 整页图和 600 dpi 局部图目视复核了 BANK32 右侧这一列，
球位与网络名对齐一致。此前文档中的 H16/F17、E18/H14 等组合是
`-layout`/缩略图错行造成的，**已作废**。

结论：

- 四对差分信号是 **G16/H16、F17/E18、H14/H13、C17/D18**，不是跨对组合。
- `T2` 是 PH1P35 的 HR Bank 差分对标注；`IO_R11P/N` 还带 `GCLKIOT0/C0`。
- `VCCIO_32` 由 `VCC_3V3` 供电（P01_FPGA 中 VCC_3V3 → C401–C406 →
  VCCIO_32 的 A16/B13/D17/E14/G18/H15），因此 BANK32 是 3.3 V IO。
  **SCHEMATIC_CONFIRMED。**

## 3. HDMI1 方向：按 Source（输出）设计

以下均为 **SCHEMATIC_CONFIRMED**（只证明图纸连接，不证明实物电气）：

1. **+5V**：连接器 pin 18（`+5V POWER`）的网络是 `HDMI_A_5V`；该网络经
   D5（MBR0520）接到板载 `VCC_5V`。二极管方向为 VCC_5V → HDMI_A_5V，
   即**板卡向显示器提供 +5V**。这是 source 方向的直接证据。
2. **HPD**：连接器 pin 19（`HOT PLUG`）→ `HDMIA_HPD_LS` → R189 20K /
   R193 20K 分压 → `HDMIA_HPD` → R190 0R → `HDMI1_HPD` → FPGA B17；
   分压节点同时接 U46 的 EN。即 **HPD 由显示器驱动、FPGA 读取**。
3. **DDC**：Q15/Q16（AO3400）是双向电平转换。FPGA 侧
   `HDMI1_SDA/SCL` 由 `+3.3V_HDMI` 经 2.2K 上拉；连接器侧
   `HDMIA_SDA/SCL` 由 `HDMI_A_5V`（5V）经 2.2K 上拉；栅极经 10K 接
   `+3.3V_HDMI`。这是典型的 **3.3V ↔ 5V source 侧 DDC 电平转换**。
4. **TMDS**：四对 `HDMI1_*` 经 ESD 阵列 D2/D12（AZ1045-04F.R7G）后变为
   `HDMIA_*`，直接到 HDMI 连接器；没有 AC 耦合电容，没有外部串行器/驱动器。
5. **CEC**：连接器 pin 13 经 D4（BAS16XV2T1G）和 R188 27K 上拉到
   `+3.3V_HDMI`，**没有接到 FPGA**，本阶段不使用。

因此本板 HDMI1 按 **视频输出端（source）** 设计，可以继续做 TMDS 输出。
但这只是原理图方向证据，**不等于 HDMI 功能已经验证**。

## 4. 问题 A：TMDS 49.9 Ω 上拉网络

### 4.1 已确认的连接（SCHEMATIC_CONFIRMED）

- 8 个电阻 **R180–R187 = 49.9 Ω**。
- 每个电阻一端接一根 `HDMIA_*` TMDS 线（连接器侧，ESD 阵列之后），
  另一端全部汇到同一条竖线，向上接 **`+3.3V_HDMI`**。
- 也就是：**每根 TMDS 线各有一个 49.9 Ω 上拉到 +3.3V_HDMI**，
  包括 4 对的 P 和 N，共 8 个。不是串联电阻。

### 4.2 与 PH1P35 能力的关系

- **DATASHEET_CONFIRMED（工具库）**：`arch/ph1p_macro.v` 的
  `PH1P_PHY_HR_PAD` 支持 `IOTYPE = "TMDS33"`；`PH1P_PHY_HR_BANKREF`
  有 `TMDSTXEN` 参数。TD 6.2.1 确实提供 TMDS33 IO 标准和 TMDS 使能位。
- **TOOL_CONFIRMED（参考工程）**：第三方仓库在**同一器件
  PH1P35MDG324** 上把 `O_tmds_ch0_p/ch1_p/ch2_p/clk_p` 约束到
  G16/F17/H14/C17，`IOSTANDARD = TMDS33`，并且只约束 P 端；
  这说明该器件/工具链支持这种单端声明 + 差分对自动配对的用法。
- **UNRESOLVED**：本地 UG1310 库指南的文本提取没有给出 TMDS33 的
  输出电压摆幅/共模/终端要求；49.9 Ω 上拉到 3.3 V 是否与 PH1P35 的
  TMDS33 电流驱动完全匹配，图纸和库文件都不能单独证明。
- **判断**：49.9 Ω 上拉是电流型 TMDS 驱动器常见的板级偏置/终端网络，
  与 source 方向一致；参考工程也用 TMDS33。但不能据此宣称电气已经合格。

### 4.3 必须实测（BOARD_MEASUREMENT_REQUIRED）

- 断开显示器时，每根 TMDS 线对 GND 的静态电压（应为 0 V 或接近 0 V，
  取决于驱动器是否使能）。
- 接显示器、FPGA 输出彩条时，P/N 的共模电压和单端摆幅（高阻探头，
  不能直接用 50 Ω 终端探头加载）。
- `+3.3V_HDMI` 在 8 个 49.9 Ω 负载下的实际电压（见问题 C）。
- 若摆幅/共模明显不对，优先怀疑：TMDS33 配置未生效、P/N 配对错误、
  Bank 电压不是 3.3 V、Q17 未完全导通。

## 5. 问题 B：HDMI +5V、HPD 与 U46/D6 的保持效应

### 5.1 两个 5V 网络必须分开（SCHEMATIC_CONFIRMED）

| 网络 | 来源 | 去向 |
|---|---|---|
| `HDMI_A_5V` | `VCC_5V` 经 D5（MBR0520） | HDMI 连接器 pin 18（+5V POWER） |
| `HDMI_A0_5V` | `VCC_5V` → U46 TPS2051B（IN=pin5）→ OUT=pin1 → C293 → F3（PTS120630V012）→ C294 | 本页只看到它经 **D6** 回灌 HPD 线；没有看到它直接接连接器 pin 18 |

- **不要**把 `HDMI_A_5V` 和 `HDMI_A0_5V` 合并成一个网络。它们是两个
  独立的 net label，中间没有 0 Ω/跳线连接。
- U46 的 EN（pin4）由 HPD 分压节点 `HDMIA_HPD` 经 R190 0R 驱动；
  OC（pin3）经 R191 1K 上拉到 `+3.3V_HDMI`。

### 5.2 HPD 保持（锁存）效应

- D6（MBR0520）连接 `HDMI_A0_5V`（上，阳极）与 `HDMIA_HPD_LS`
  （下，阴极）；高 DPI 裁剪确认二极管三角朝下、阴极在下。
- 逻辑链：
  1. 显示器接入并拉高 HPD → 分压节点 `HDMIA_HPD` 高 → U46 EN 高；
  2. U46 输出 `HDMI_A0_5V` 高 → 经 D6 把 HPD 线继续拉高；
  3. 即使显示器拔掉，HPD 线仍被 D6 保持高 → U46 保持使能。
- **结论（SCHEMATIC_CONFIRMED）**：该网络存在 **HPD 状态保持/锁存**。
  后果是 FPGA 的 `HDMI1_HPD` 在首次接入后可能一直为高，**不能用来
  可靠检测拔出**；U46 的受控 5V 也可能保持到整机断电。
- **BOARD_MEASUREMENT_REQUIRED**：实测插入/拔出时 pin 19、B17、
  `HDMI_A0_5V` 的电压变化；确认锁存是否存在、断电后是否释放。

### 5.3 对本阶段的影响

- 第一版彩条**不依赖 HPD、不读 EDID**；HDMI +5V 由 D5 常供，
  显示器上电即可读到 +5V。
- 如果显示器黑屏，HPD 锁存会误导“已连接”判断；排查时应以
  +5V、TMDS 时钟、PLL lock、显示器输入源为准，不要只看 HPD。
- 不实现热插拔检测；需要重新插拔识别时，整机断电重上电。

## 6. 问题 C：DDC 与 +3.3V_HDMI 的上电顺序

### 6.1 已确认的连接（SCHEMATIC_CONFIRMED）

- Q17（AO3400）：pin3 接 `+3.3V_HDMI`，pin2 接 `VCC_3V3`，
  pin1（栅极）由 R201 1K 上拉到 `VCC_5V`、R200 100K 下拉到 GND，
  C297 10nF 栅源并联。
- 因此 **`+3.3V_HDMI` 是从 `VCC_3V3` 经 Q17 切换出来的**，
  使能条件是 `VCC_5V` 存在（栅极高）。
- `+3.3V_HDMI` 同时供给：8 个 49.9 Ω TMDS 上拉、Q15/Q16 的 FPGA 侧
  2.2K 上拉和 10K 栅极上拉、U46 OC 上拉、CEC 的 R188 27K。
- DDC 两侧上拉：FPGA 侧 3.3V（`+3.3V_HDMI`），连接器侧 5V
  （`HDMI_A_5V`）。

### 6.2 风险

- **启动顺序依赖**：`VCC_5V` 先到 → Q17 栅极高；`VCC_3V3` 后到 →
  `+3.3V_HDMI` 跟随。若 `VCC_5V` 不存在，TMDS 上拉和 DDC 上拉都没有
  偏置，HDMI 不会正常工作。本板 `VCC_5V` 是主输入，正常上电时存在；
  仍需实测确认。
- **Q17 的 Vgs 余量**：源极/漏极在 3.3 V 侧，栅极由 5 V 经 1K 上拉，
  Vgs 约 1.7 V。AO3400 在 Vgs=1.7 V 时处于弱开启边缘，带 8 个
  49.9 Ω 上拉 + DDC 上拉时 `+3.3V_HDMI` 可能被拉低。
  **BOARD_MEASUREMENT_REQUIRED**：测 `+3.3V_HDMI` 空载/带载电压；
  若明显低于 3.3 V，需要重新评估该开关电路（不要直接飞线）。
- **DDC 未使用时的状态**：FPGA 的 E15/F15 在本设计中不驱动；
  外部上拉会把两侧都保持高电平，属于正常 idle。若以后加 EDID，
  必须按 3.3V/5V 双向电平转换时序访问。

## 7. 工具/IP 调查结论

- **TOOL_CONFIRMED**：TD 6.2.1 安装目录 `ip/` 与 `ip/depot/` 中
  **没有 HDMI Transmitter IP**；`find -iname "*hdmi*"` 无结果。
- **TOOL_CONFIRMED**：第三方参考工程的
  `hdmi_1_4b_transmitter_core_wrapper.enc.v` 是**加密厂商 IP**，
  本地 TD 安装中没有对应文件；该仓库没有 LICENSE。**不复制、不修改、
  不破解、不再分发**。
- **结论**：方案 A（直接用厂商 HDMI IP 的 `VIDEO_TPG`）在本机**不可用**，
  不是“配置一下就能用”。转入方案 B：自写 DVI-compatible TMDS 编码器 +
  使用 TD 已提供的 `PH1P_LOGIC_ODDR` / PLL 原语。
- **TOOL_CONFIRMED**：`PH1P_LOGIC_ODDR` 的仿真模型端口注释明确：
  `d0 = posedge input data`，`d1 = negedge input data`。这决定串行化
  的 bit 顺序（d0 先输出）。
- **TOOL_CONFIRMED**：`PH1P_PHY_PLL` 参数范围 REFCLK_DIV/FBCLK_DIV/
  CLKCn_DIV 均为 1–128；参考工程的 VCO 计算可由
  `Fvco = FIN × FBCLK_DIV / REFCLK_DIV × 15` 复现
  （50/1×2×15=1500 → C0=1500/15=100；50/2×3×15=1125 →
  C0=1125/15=75、C1=1125/3=375）。

## 8. 本阶段仍然 UNRESOLVED / 必须实测的清单

| # | 项目 | 等级 | 下一步 |
|---|---|---|---|
| 1 | `+3.3V_HDMI` 实际电压（空载/带载） | BOARD_MEASUREMENT_REQUIRED | 万用表测 Q17 输出、R180 上端 |
| 2 | HDMI pin 18 实际 +5V | BOARD_MEASUREMENT_REQUIRED | 万用表测连接器 pin 18 对 GND |
| 3 | HPD 分压节点/FPGA B17 电压 | BOARD_MEASUREMENT_REQUIRED | 插入/拔出各测一次 |
| 4 | HPD 锁存是否存在 | BOARD_MEASUREMENT_REQUIRED | 拔出后测 pin 19 是否仍高 |
| 5 | TMDS P/N 共模与摆幅 | BOARD_MEASUREMENT_REQUIRED | 高阻探头测 R180 两端/连接器侧 |
| 6 | PH1P35 TMDS33 电气规范 | UNRESOLVED | 查 PH1P35 完整数据手册/向厂商确认 |
| 7 | `HDMI_A0_5V` 的最终用途 | UNRESOLVED | 全页/其他页搜索；目前只见 D6 回灌 |
| 8 | 640×480 的 PLL 配置 | TOOL 验证 25.0/125 MHz 可 lock；上板待验证 | 已改用 25.0 MHz + V total 521（59.981 Hz）；TD 构建通过，板测 LED2 |
| 9 | 显示器是否接受无 EDID 的 640×480@60 | BOARD_MEASUREMENT_REQUIRED | 接显示器观察 |

## 9. 明确没有声称的内容

- 没有声称 HDMI 已经上板通过。
- 没有声称 TMDS33 电气已经合格。
- 没有声称 HPD/DDC 实物行为与图纸完全一致。
- 没有声称第三方参考工程的加密 IP 可以在本机使用。
- 没有复制参考工程的 RTL/IP 到本仓库。
