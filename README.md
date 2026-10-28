# PH1P35 × ATK-MC5640：DVP 图像采集与 HDMI 显示

> **当前状态（2026-10-28）：11 通道尝试失败，本分支只 PR、不合并。**
> 最小 SCCB Chip ID 工程已上板验证通过（0x5640）；DVP RTL、仿真、
> RGB565 配置/回读和 TD 构建均已通过。
>
> **2026-10-26 三通道时序（已通过）**：PCLK = **48.000 MHz**（不是旧文档的
> 50 MHz）；VSYNC 30 Hz / 33.333 ms，`0x4740=0x22` 实测 **高有效**；
> HREF 15 kHz / 66.665 µs，高 40 µs（1920 PCLK）、低 26.665 µs
> （1280 PCLK）；每帧 480 行，垂直消隐有一次 1.373 ms 长高。
>
> **HREF 极性仍有 A/B 两种解释**：低相位正好 1280 PCLK，16:24 的
> `HREF_ACTIVE_HIGH=0` + `EXPECTED_PIX=1280` 会因长度匹配而让 LED4 熄灭；
> 但高相位 1920 PCLK 也可能是“1280 有效 + 640 dummy”的高有效模式。
> **LED4 熄灭只证明长度/行数，不证明像素数据。** 必须用 D0–D7 彩条比较
> 低/高两相才能定极性；不要再用 LED4 单独宣布 DVP 成功。
>
> **2026-10-28 11 通道尝试（失败）**：13:58 采集中 HREF 包络仍是
> 15 kHz / 1280 字节，但 VSYNC 通道只有 4 ns 尖峰、D0–D7 全 0；
> 14:36 的 HREF 单测变成 **29.53 kHz**（30.856 µs 高 / 3.002 µs 低）。
> 现象/推测/复测步骤见
> [20261028_dvp_11ch](verification/board/evidence/20261028_dvp_11ch/README.md)。
> 首选推测：摄像头重新插拔/复位后回到默认 1280×960 时序，FPGA 没有重跑
> SCCB；接地/干扰能解释毛刺，但不能单独解释稳定的 29.53 kHz。
>
> **位流保存**：12:33 失败位流 SHA `893dc3fa…`，已复制为
> `top_dvp_test_fail_20261028_dbg_893dc3fa.bit`；16:24 原始位流
> SHA `506e01ad…` 已被 12:33 构建覆盖、无法找回，当前按同一 RTL/QoR
> 重建为 `top_dvp_test_20261026_rebuild.bit`（SHA `b6df6c18…`，
> **不是原始二进制**）。15:47 三通道采集用的 13:16 版（SHA `8f320bbd…`）
> 也已丢失，按同 RTL/QoR 重建为 `top_dvp_test_20261026_3ch_rebuild.bit`
> （SHA `fb3b3b84…`，Setup 10.245/Hold 0.054/800）。三个文件都留在
> `build/bitstream/`，不要互相覆盖：13:16 版复现三通道采集，16:24 版复现
> LED4 熄灭/HREF 低有效诊断。
>
> 下一步：**整机断电再上电** → 烧对应重建位流 → 抓 PCLK/HREF/VSYNC →
> 接好 D0–D7 抓低/高两相彩条。在 HREF 极性/数据相确定前，不改
> `0x3035/36/37`、`0x3108`、`0x503D`、`0x4300`、`0x4740`、`EXPECTED_PIX`。
> HDMI 未开始。
>
> **接线复核（2026-10-24）**：J2-30 = **GND**，J2-32 = **GPIOB_27（R6）**。
> 此前“GND/SCL 接反”的说法是误读原理图右侧标签造成的，**已撤回**；
> 当前以 [docs/hardware/wiring.md](docs/hardware/wiring.md) 和你提供的表为准。

## 1. 项目目标

在安路（Anlogic）PH1P35 FPGA 开发板上，通过 **8-bit DVP 并行接口**采集
正点原子 **ATK-MC5640** 摄像头图像，经 FPGA 完成必要的格式/时序处理后，
实时输出到 **HDMI 显示器**。

摄像头寄存器通过 **SCCB** 总线配置。

## 2. 硬件平台与数据链路

| 项目 | 内容 | 状态 |
|---|---|---|
| 开发板 | PH1P35_FT V1 / HX1P35B_FT_40P 系列 | 原理图已核对 |
| FPGA | 安路 **PH1P35MDG324** | 原理图 U48 标注 |
| 摄像头 | 正点原子 **ATK-MC5640 V1.2**（OV5640，8-bit DVP） | 原理图/官方 README 已核对 |
| 摄像头时钟 | 模组板载 24 MHz 晶振，FPGA 不输出 XCLK | 已确认 |
| 连接器 | **J2** IDC40；不使用 MIPI J9 | 已确认 |
| 供电 | 3.3 V：J2-29；GND：J2-30 | 已核对 |
| 显示 | HDMI 显示器 | 目标分辨率/刷新率待确认 |
| 配置总线 | SCCB（类 I²C） | 已确认 |

当前主线数据链路：

```text
             ┌──────────── SCCB: SCL / SDA（寄存器配置）────────────┐
             │                                                      ▼
      ┌──────┴──────┐   DVP: D[7:0] / PCLK / HSYNC(HREF) / VSYNC  ┌─────────────┐
      │  ATK-MC5640 │ ──────────────────────────────────────────► │  FPGA       │
      │  (DVP 8-bit)│                                            │  PH1P35     │
      └─────────────┘                                            └──────┬──────┘
                                                                        │
                                                           DVP 接收 / 同步对齐
                                                                        │
                                                           [图像处理（后续扩展）]
                                                                        │
                                                           帧缓存 / 跨时钟域（后续）
                                                                        │
                                                               HDMI / TMDS 编码
                                                                        │
                                                                  HDMI 显示器
```

**接口边界**：当前主线是 **DVP**。仓库中如保留 MIPI CSI-2 例程，仅作参考，
不属于当前数据链路，也不得作为本工程入口。

## 3. 当前进度

| 工作项 | 状态 | 证据/位置 |
|---|---|---|
| 目录与文档规范 | 已完成 | 本 README、`docs/README.md` |
| 板卡/摄像头原理图核对 | 已完成（J2-30=GND，J2-32=GPIOB_27） | `docs/hardware/wiring.md` §6 |
| 正式接线文档 | 已完成 | `docs/hardware/wiring.md` |
| 引脚约束 | 最小工程约束已完成并用于构建 | `fpga/constraints/top_cam_id.adc` |
| 用户报告实物接线 | 已完成（用户自述） | 待独立检查 |
| 万用表通断/短路检查 | **未完成** | `verification/board/wiring-check.md` |
| 独立供电/上电检查 | **未完成** | 同上 |
| 最小 RTL / TD 工程 | **已完成** | `fpga/rtl/top/top_cam_id.v`、`fpga/project/top_cam_id.al` |
| SCCB Chip ID 读取 | **已上板通过（0x5640）** | `verification/board/bringup-sccb-id.md` |
| TD 综合/布局布线/位流 | **已完成**（WNS +12.684 ns） | `build/bitstream/top_cam_id.bit` |
| 实物烧录与 LED 验证 | **已完成（用户报告）** | LED1 闪，LED2/3/4 常亮 |
| DVP 采集 RTL + 仿真 | **已完成**（24/48MHz，480 行帧） | `verification/static/dvp_capture_sim_2026-10-26.md` |
| RGB565 配置/回读 + TD 构建 | **已完成（仿真/构建）** | `ov5640_cfg.v`、`top_dvp_test.v`；当前 `top_dvp_test.bit` 是 12:33 失败构建 |
| DVP 上板三通道 | **时序已通过**（PCLK 48.000 MHz，VSYNC 30 fps 高有效，HREF 15 kHz）；**HREF 极性 A/B 未定**，LED4 只查长度不查数据 | `verification/board/evidence/20261026_dvp_three_channel/` |
| DVP 11 通道 / 彩条 | **2026-10-28 尝试失败**：HREF/VSYNC 不稳定、D0–D7 未取得；16:24 设计已重建待复测 | `verification/board/evidence/20261028_dvp_11ch/`；重建 SHA `b6df6c18...` |
| HDMI 显示 | **未开始** | 待后续 RTL |
| DDR 帧缓存 | **未开始** | 待架构确认 |

已知电气风险（详见 wiring.md §5）：

1. **SCCB 上拉缺失**：板卡与摄像头原理图均未画出 SCL/SDA 上拉电阻，
   需要补装 4.7 kΩ 或确认 FPGA 内部上拉足够。
2. **RESET/PWDN 默认电平未定**：两处均无外部上/下拉，FPGA 配置前可能浮空。
3. **摄像头 P1 符号编号偏移**：V1.2 原理图符号引脚号与官方物理排针表相差 2 位，
   上电前需核对模组 Pin 1 丝印。

## 4. 关键入口索引

| 用途 | 位置 | 现状 |
|---|---|---|
| **跨对话协作指南** | [AGENTS.md](AGENTS.md) | 已建立（单一事实来源） |
| **构建/调试 skill** | [.claude/skills/fpga-bringup/SKILL.md](.claude/skills/fpga-bringup/SKILL.md) | 已建立 |
| 任务与进度 | [TASKS.md](TASKS.md) | 已更新 |
| 文档索引 | [docs/README.md](docs/README.md) | 已建立 |
| **接线说明（当前有效）** | [docs/hardware/wiring.md](docs/hardware/wiring.md) | 已完成，含勘误 |
| **电气检查表** | [verification/board/wiring-check.md](verification/board/wiring-check.md) | 待执行 |
| **最小上板步骤** | [verification/board/bringup-sccb-id.md](verification/board/bringup-sccb-id.md) | 已上板通过（0x5640） |
| **DVP 阶段交接** | [docs/project/dvp-handoff.md](docs/project/dvp-handoff.md) | 下一阶段入口 |
| **本测试引脚约束** | [fpga/constraints/top_cam_id.adc](fpga/constraints/top_cam_id.adc) | 已用于构建 |
| 摄像头全量约束草案（DVP 阶段） | [fpga/constraints/camera_pinmap_draft.adc](fpga/constraints/camera_pinmap_draft.adc) | 草案，未绑定 DVP 顶层 |
| TD 工程入口 | [fpga/project/top_cam_id.al](fpga/project/top_cam_id.al) | 可打开查看 |
| 顶层 RTL | [fpga/rtl/top/top_cam_id.v](fpga/rtl/top/top_cam_id.v) | 已建立 |
| 仿真入口 | [fpga/sim/tb/tb_top_cam_id.v](fpga/sim/tb/tb_top_cam_id.v) | 已通过 |
| **一键构建** | [fpga/scripts/build_top_cam_id.bat](fpga/scripts/build_top_cam_id.bat) | 已实测 |
| 第三方参考 | `third_party/` | 仍为空 |

## 5. 仓库结构

```text
2026_10_OV5640/
├── README.md                 项目总览（本文件）
├── AGENTS.md                 跨对话协作指南（项目事实/规则/状态）
├── CLAUDE.md                 指向 AGENTS.md 的简短入口
├── TASKS.md                  任务清单、进度与待确认项
├── .claude/skills/           fpga-bringup 构建/调试 skill
├── .gitignore                构建产物、局部资料、编辑器文件
├── docs/
│   ├── README.md             文档索引与归档规则
│   ├── project/              目标、架构、环境、开发规范
│   ├── hardware/             板卡/FPGA 手册、原理图、wiring.md
│   ├── camera/               ATK-MC5640 手册、SCCB 寄存器、DVP 时序
│   ├── display/              HDMI/TMDS 规范、分辨率时序
│   └── debug/                调试记录、波形、问题分析
├── fpga/
│   ├── README.md             工程组织、TD 约定
│   ├── project/              TD 工程入口 top_cam_id.al
│   ├── rtl/                  top / camera / display / common
│   ├── constraints/          top_cam_id.adc/.sdc（本测试）+ DVP 草案
│   ├── ip/                   IP 配置与生成说明
│   ├── sim/                  tb_top_cam_id.v 与仿真产物
│   └── scripts/              build_top_cam_id.bat/.tcl
├── verification/
│   ├── README.md             三级验证规则
│   ├── board/                上板测试计划、wiring-check.md、证据
│   └── static/               静态检查结论
├── tools/                    环境检查、构建、烧写自动化
├── third_party/              厂商与第三方参考
├── archive/                  历史归档
└── build/                    构建产物（本地，不入库）
```

**为什么这样划分**

- 接线文档与代码分离：硬件事实在 `docs/hardware/`，约束在 `fpga/constraints/`，
  检查证据在 `verification/board/`，三者不混。
- 最小工程约束 `top_cam_id.adc` 已绑定顶层；`camera_pinmap_draft.adc` 保留给 DVP 阶段。
- 原厂 PDF 默认不入库（版权/再分发条件未确认），但保留在本地供核对。
- `build/` 与 `_local/` 为不入库区域，防止仓库膨胀。

## 6. 开发环境

| 项目 | 内容 |
|---|---|
| FPGA IDE | Anlogic Tang Dynasty (TD) **6.2.1** |
| TD 安装路径 | `<TD_HOME>`（示例，不写入仓库） |
| 目标器件 | PH1P35MDG324（原理图 U48） |
| 版本控制 | Git 仓库已初始化（`main` 分支） |
| 操作系统 | Windows 11 |

TD 自带资料：`doc/TD_User_Guide_V6.2.pdf`、
`doc/UG1310_PH1P_Libraries_Guide_for_HDL_Designs.pdf`、`board_designs/` 等。
厂商资料以本地安装为准，不复制进仓库。

## 7. 构建、下载与验证

### 7.1 现状：最小工程可构建

当前已有一个最小工程 `top_cam_id`：

- 50 MHz 时钟（C4）
- 4 个 LED（D10/E10/C6/D6，对应物理 LED1–LED4）
- SCCB（SCL=R6，SDA=T5）
- 摄像头 RESET（U7）、PWDN（U6）
- 读取 `0x300A/0x300B`，判断 Chip ID 是否为 `0x5640`

构建方式：

```bat
rem 首次使用：设置 TD 安装目录（示例）
setx TD_HOME "C:\path\to\TD_6.2.1"

cd /d <repo-root>
fpga\scripts\build_top_cam_id.bat
```

输出：`build\bitstream\top_cam_id.bit`。
本机已实测：综合/布局布线/位流通过，Setup WNS=+12.684 ns，Hold WNS=+0.047 ns。

**注意**：TD 6.2.1 项目模式在本机生成的 `run.bat` 调用了不存在的
`td_commands_prompt_commands_prompt.exe`，所以当前以命令行构建脚本为准；
`top_cam_id.al` 仅用于查看/编辑源文件。

### 7.2 下一阶段的上板顺序

已完成：

1. 电源、时钟、下载链路、四个 LED 球位验证。
2. SCCB 读 OV5640 Chip ID = `0x5640`（LED1 闪，LED2/3/4 常亮）。

下一步：

3. **DVP 接收 RTL + 真实时序仿真** —— 已完成（`dvp_capture.v`、
   `async_fifo_gray.v`、`dvp_status_monitor.v`、`tb_dvp_capture.v`）。
4. **OV5640 RGB565 配置/回读 + DVP 上板顶层** —— 已完成
   （`ov5640_cfg.v`、`ov5640_bringup.v`、`top_dvp_test.v`）；
   位流 `build/bitstream/top_dvp_test.bit`。
5. **上板三通道：时序通过**（PCLK **48.000 MHz**、15 kHz 行 / 30 Hz 帧）。
   LA CSV 显示 `0x22` 是 VSYNC **高有效**、`0x23` 是低有效；HREF 高
   40 µs = 1920 PCLK、低 26.665 µs = 1280 PCLK，每帧 1.373 ms 长高横跨
   VSYNC。**16:24 诊断位流**：`0x22` + `VSYNC_ACTIVE_HIGH=1`、
   `HREF_ACTIVE_HIGH=0`、`EXPECTED_PIX=1280`、480 行、`COLOR_BAR=1`。
   低相位正好 1280 PCLK，所以 LED4 熄灭；但**高有效 B 解释同样能通过
   长度检查**，不能据此证明低相位是有效彩条。
5a. **2026-10-28 11 通道尝试失败**：HREF/VSYNC 不稳定，14:36 HREF
   单测 29.53 kHz；推测摄像头重插/复位后回默认 1280×960、FPGA 未重跑
   SCCB。接地能解释毛刺，但不能单独解释稳定频率。见
   `verification/board/evidence/20261028_dvp_11ch/`。
6. 数据稳定后再做 HDMI 时序与显示；DDR 帧缓存暂不引入。

不建议直接跳到完整视频链路；先逐级证明 PCLK、同步信号和数据对齐。

### 7.3 验证分级（不可互相替代）

| 级别 | 位置 | 判定依据 |
|---|---|---|
| 仿真 | `fpga/sim/` | Testbench 断言/比对通过 |
| 静态检查 | `verification/static/` | lint、CDC、时序报告通过（含豁免说明） |
| 上板 | `verification/board/` | 接线检查 + 实际功能，附证据 |

**路径检查通过 ≠ 综合通过；综合通过 ≠ 时序收敛；时序收敛 ≠ 上板成功。**
**原理图核对通过 ≠ 实物接线正确；万用表通过 ≠ 摄像头能出图。**

### 7.4 构建产物与交付

- `build/` 按 `td/`、`reports/`、`bitstream/` 分子目录，整体不入库。
- 位流、布局布线数据库、时序报告默认不提交 Git。
- 交付版本用 Git tag + 发布说明固定：器件、TD 版本、commit、约束版本、位流校验和。
- 不建立 `release_v1/`、`release_final/` 之类的历史副本目录。

## 8. 新增资料放置规则

| 资料类型 | 放置位置 |
|---|---|
| 项目目标、架构、环境、开发规范 | `docs/project/` |
| 板卡/FPGA 手册、原理图、引脚定义 | `docs/hardware/` |
| 摄像头手册、SCCB 寄存器、DVP 时序 | `docs/camera/` |
| HDMI/TMDS 规范、分辨率时序 | `docs/display/` |
| 调试记录、波形、问题分析 | `docs/debug/` |
| 自研 RTL | `fpga/rtl/<domain>/` |
| 引脚/时序约束 | `fpga/constraints/` |
| IP 配置与生成说明 | `fpga/ip/` |
| Testbench | `fpga/sim/tb/` |
| 构建/仿真/烧写脚本 | `fpga/scripts/` 或 `tools/` |
| 厂商/第三方例程 | `third_party/<vendor>/<package>/` |
| 上板测试计划与证据 | `verification/board/` |
| 静态检查结论 | `verification/static/` |
| 废弃/历史方案 | `archive/`（必须登记原因） |
| 构建产物、日志、位流 | `build/`（本地，不入库） |
| 授权受限/超大文档 | 就近 `_local/`（已忽略）或保留原位并加入 `.gitignore` |

## 9. 工程约定

- 路径与文件名使用 **ASCII、小写 snake_case**；不使用空格、中文和日期后缀。
- 一个模块一个文件，文件名与模块名一致；顶层模块以 `top_` 开头。
- TD 工程引用使用**相对路径**；禁止写入本机绝对路径。
- 同一份代码/IP/配置只维护一份；变体用参数或独立目录，不复制。
- 未修改的厂商代码保持原样并登记来源；修改需另建 fork 并记录差异。
- 引脚约束必须来自原理图核对；不得用排针号代替 FPGA 球位。
- 不提交位流、布局布线数据库、日志、大型构建结果和受限厂商文档。

## 10. 待确认事项

1. **万用表检查**：按 `verification/board/wiring-check.md` 执行并填写实测值
   （GND=J2-30，SCL=J2-32，无需换线）。
2. **上电检查**：摄像头不接时先测 J2-29=3.3 V、J2-30=0 V、J2-11=5 V。
3. **摄像头 P1 Pin 1/电源脚**：核对模组丝印与官方 README 表。
4. **烧录最小位流**：按 `bringup-sccb-id.md` 执行，记录 LED 结果。
5. **SCCB 上拉**：当前 `.adc` 已启用 FPGA 内部上拉；若 LED1 不亮，补 4.7 kΩ 外部上拉。
6. **RESET/PWDN 默认电平**：是否需要外部 10 kΩ 上/下拉。
7. **PCLK 实际频率**：由 OV5640 寄存器配置决定，确定后再加时序约束。
8. **HDMI 目标分辨率/刷新率**及像素时钟。
9. **是否使用 DDR 帧缓存**及板上 DDR 型号。
10. 板卡原理图的公开/再分发许可（当前 PDF 仅本地保留，不入库）。

以上问题同步记录在 [TASKS.md](TASKS.md)。
