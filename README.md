# PH1P35 × ATK-MC5640：DVP 图像采集与 HDMI 显示

> **当前状态（2026-10-24）**：最小 SCCB Chip ID 工程已建立。
> RTL 已通过 ModelSim 仿真；TD 6.2.1 已完成综合、布局布线、时序检查并生成位流。
> **尚未在实物上烧录验证**，DVP 采集和 HDMI 显示尚未开始。
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
| SCCB Chip ID 读取 | **RTL/仿真/位流完成，待上板** | `verification/board/bringup-sccb-id.md` |
| TD 综合/布局布线/位流 | **已完成**（WNS +13.770 ns） | `build/bitstream/top_cam_id.bit` |
| 实物烧录与 LED 验证 | **未完成** | 见 bringup 文档 |
| DVP 采集 | **未开始** | 待后续 RTL |
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
| 任务与进度 | [TASKS.md](TASKS.md) | 已更新 |
| 文档索引 | [docs/README.md](docs/README.md) | 已建立 |
| **接线说明（当前有效）** | [docs/hardware/wiring.md](docs/hardware/wiring.md) | 已完成，含勘误 |
| **电气检查表** | [verification/board/wiring-check.md](verification/board/wiring-check.md) | 待执行 |
| **最小上板步骤** | [verification/board/bringup-sccb-id.md](verification/board/bringup-sccb-id.md) | 待你在实物执行 |
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
├── TASKS.md                  任务清单、进度与待确认项
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
| 本机安装路径 | `D:\Software\Anlogic\TD_6.2.1` |
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
cd /d D:\Projects\02_Personal_Practice\2026_10_OV5640
fpga\scripts\build_top_cam_id.bat
```

输出：`build\bitstream\top_cam_id.bit`。
本机已实测：综合/布局布线/位流通过，Setup WNS=+13.770 ns，Hold WNS=+0.049 ns。

**注意**：TD 6.2.1 项目模式在本机生成的 `run.bat` 调用了不存在的
`td_commands_prompt_commands_prompt.exe`，所以当前以命令行构建脚本为准；
`top_cam_id.al` 仅用于查看/编辑源文件。

### 7.2 下一阶段的上板顺序

1. 完成 `verification/board/wiring-check.md` 的断电与供电检查。
2. 按 `verification/board/bringup-sccb-id.md` 构建并 Program SRAM。
3. 观察 LED：LED0 闪 + LED1/2/3 亮 = Chip ID 读取成功。
4. 通过后再实现 DVP 接收与 HDMI 输出。

不建议直接跳到完整视频链路；先证明电源、时钟、SCCB 和下载链路。

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
