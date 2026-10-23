# PH1P35 × ATK-MC5640：DVP 图像采集与 HDMI 显示

> **当前状态（2026-10-21）**：目录骨架阶段。仓库内尚无 RTL、约束和 TD 工程，
> 因此**目前没有可构建入口，构建与上板验证均未开始**。
> 原始素材尚未进入本工作区，迁移与验证任务见 [TASKS.md](TASKS.md)。

## 1. 项目目标

在安路（Anlogic）PH1P35 FPGA 开发板上，通过 **8-bit DVP 并行接口**采集
正点原子 **ATK-MC5640** 摄像头图像，经 FPGA 完成必要的格式/时序处理后，
实时输出到 **HDMI 显示器**。

摄像头寄存器通过 **SCCB** 总线配置。

## 2. 硬件平台与数据链路

| 项目 | 内容 | 状态 |
|---|---|---|
| FPGA | 安路 PH1P35 系列 | 具体器件型号、封装、速度等级**待确认** |
| 开发板 | PH1P35 开发板 | 型号、版本、原理图**待归档** |
| 摄像头 | 正点原子 ATK-MC5640，8-bit DVP 并行输出，SCCB 配置 | 接口类型已确认 |
| 显示 | HDMI 显示器 | 目标分辨率、刷新率**待确认** |
| 配置总线 | SCCB（类 I²C） | 已确认 |

当前主线数据链路：

```text
                    ┌──────────── SCCB: SCL / SDA（寄存器配置）────────────┐
                    │                                                      ▼
             ┌──────┴──────┐   DVP: D[7:0] / PCLK / HSYNC / VSYNC   ┌─────────────┐
             │  ATK-MC5640 │ ────────────────────────────────────► │  FPGA       │
             │  (DVP 8-bit)│ ◄──────────── XCLK（如模块需要）────── │  PH1P35     │
             └─────────────┘                                        └──────┬──────┘
                                                                           │
                                                              DVP 接收 / 位宽与同步对齐
                                                                           │
                                                              [图像处理（后续扩展）]
                                                                           │
                                                              帧缓存 / 跨时钟域（后续）
                                                                           │
                                                                  HDMI / TMDS 编码
                                                                           │
                                                                     HDMI 显示器
```

**接口边界（重要）**：本项目主线是 **DVP**。
仓库中如保留 MIPI CSI-2 摄像头例程，**仅作参考**，不属于当前数据链路，
也不得被误当作本工程入口。详见 [third_party/README.md](third_party/README.md)。

## 3. 开发环境

| 项目 | 内容 |
|---|---|
| FPGA IDE | Anlogic Tang Dynasty (TD) **6.2.1** |
| 本机安装路径 | `D:\Software\Anlogic\TD_6.2.1` |
| 目标器件 | 待确认（以开发板与 TD 工程设置为准） |
| 版本控制 | **未在 PATH 或常见安装路径找到 Git**（2026-10-21 检查；待提供 `git.exe` 路径） |
| 操作系统 | Windows 11 |

TD 自带资料位于安装目录下：

- `doc/TD_User_Guide_V6.2.pdf`
- `doc/UG1310_PH1P_Libraries_Guide_for_HDL_Designs.pdf`
- `board_designs/`、`template/`、`ip/`

厂商资料以本地安装为准，**不复制进仓库**，避免重复与版本漂移。

> **Git 缺失的影响**：无法使用 `git mv` 保留迁移历史，也无法核验 Git 状态。
> 安装 Git 并初始化仓库后才能完成“可追溯迁移”和回退点。见 TASKS.md 的 Q2。

## 4. 仓库结构

```text
2026_10_OV5640/
├── README.md                 项目总览（本文件）
├── TASKS.md                  任务清单、进度与待确认项
├── .gitignore                构建产物、局部资料、编辑器文件
├── docs/                     技术文档
│   ├── README.md             文档索引与归档规则
│   ├── project/              目标、架构、环境、开发规范
│   ├── hardware/             开发板/FPGA 手册、原理图、引脚定义
│   ├── camera/               ATK-MC5640 手册、SCCB 寄存器、DVP 时序
│   ├── display/              HDMI/TMDS 规范、分辨率与像素时钟
│   └── debug/                调试记录、波形、问题分析
├── fpga/                     FPGA 工程
│   ├── README.md             工程组织、TD 约定与构建流程
│   ├── project/              TD 工程入口（.al）
│   ├── rtl/
│   │   ├── top/              顶层与板级集成
│   │   ├── camera/           SCCB、DVP 接收、摄像头配置
│   │   ├── display/          HDMI/TMDS 输出
│   │   └── common/           时钟复位、CDC、FIFO 等公共逻辑
│   ├── constraints/          引脚（.adc）与时序（.sdc）约束
│   ├── ip/                   IP 配置与生成说明
│   ├── sim/                  Testbench 与仿真脚本
│   └── scripts/              工程生成、仿真与构建脚本
├── verification/             验证
│   ├── README.md             三级验证规则
│   ├── board/                上板测试计划、步骤与证据
│   └── static/               静态检查结论（lint/CDC/时序）
├── tools/                    环境检查、构建、烧写等自动化
├── third_party/              厂商与第三方参考
│   ├── README.md             来源、许可证与修改登记规则
│   ├── anlogic/              安路官方例程
│   └── alientek/             正点原子例程（含 MIPI 参考，仅参考）
├── archive/                  历史归档（登记后进入）
└── build/                    构建产物（本地生成，不入库）
```

**为什么这样划分**

- `docs / fpga / verification / tools / third_party` 各自对应一种职责，
  边界清晰，避免“所有东西堆在工程目录里”。
- 仿真放在 `fpga/sim/`，与 RTL 同属设计输入，路径稳定；
  上板证据放 `verification/board/`，与源码演进解耦。
- `third_party/` 独立于 `fpga/rtl/`，未修改的厂商代码不与应用代码混放；
  需要修改时另建 fork 或纳入 `rtl/` 并登记。
- `build/` 与 `_local/` 明确为**不入库**区域，防止仓库膨胀。

## 5. 关键入口索引

| 用途 | 位置 | 现状 |
|---|---|---|
| 任务与进度 | [TASKS.md](TASKS.md) | 已建立 |
| 文档索引 | [docs/README.md](docs/README.md) | 已建立 |
| TD 工程入口 | `fpga/project/*.al` | **尚未导入** |
| 顶层 RTL | `fpga/rtl/top/` | 待创建 |
| 引脚/时序约束 | `fpga/constraints/` | 待导入 |
| 仿真入口 | `fpga/sim/tb/` | 待建立 |
| 构建脚本 | `fpga/scripts/`、`tools/` | 待建立 |
| 第三方参考 | `third_party/` | 待导入 |
| 上板验证 | `verification/board/` | 待建立 |

## 6. 构建、下载与验证

### 6.1 现状

**当前没有 TD 工程文件，无法构建。**
本节将在原始工程导入、路径修复完成后补全，并以实际执行结果为准。

### 6.2 预期构建流程（待工程导入后实测）

1. 安装 Git，初始化仓库并建立初始提交（回退点）。
2. 用 TD 6.2.1 打开 `fpga/project/<project>.al`。
3. 核对器件型号、顶层模块、源文件列表、约束文件与 IP 生成物。
4. 综合 → 布局布线 → 生成位流；产物输出到 `build/`，不入库。
5. 记录 TD 版本、器件型号、约束版本与 commit，保证可复现。
6. 通过下载器烧写，按 `verification/board/` 的步骤上板验证。

> 具体 TD 批处理命令、下载器型号与烧写参数，待硬件与工程确认后写入
> `tools/README.md` 和 `fpga/README.md`，不凭猜测填写。

### 6.3 验证分级（不可互相替代）

| 级别 | 位置 | 判定依据 |
|---|---|---|
| 仿真验证 | `fpga/sim/` | Testbench 断言/比对通过 |
| 静态检查 | `verification/static/` | lint、CDC、时序报告通过（含豁免说明） |
| 上板验证 | `verification/board/` | DVP 采集且 HDMI 实际显示正确，附证据 |

**路径检查通过 ≠ 综合通过；综合通过 ≠ 时序收敛；时序收敛 ≠ 上板成功。**

### 6.4 构建产物与交付

- `build/` 建议按 `td/`、`reports/`、`bitstream/` 分子目录，整体不入库。
- 位流、布局布线数据库、时序报告属于构建产物，**默认不提交 Git**。
- 需要交付的版本用 **Git tag + 发布说明**固定：记录器件型号、TD 版本、
  commit、约束版本与位流校验和；位流单独存放或发布，不堆进仓库。
- 不建立 `release_v1/`、`release_final/` 之类的历史副本目录。

## 7. 新增资料放置规则

| 资料类型 | 放置位置 |
|---|---|
| 项目目标、架构、环境、开发规范 | `docs/project/` |
| FPGA/开发板手册、原理图、引脚定义 | `docs/hardware/` |
| 摄像头模块手册、SCCB 寄存器、DVP 时序 | `docs/camera/` |
| HDMI/TMDS 规范、分辨率时序 | `docs/display/` |
| 调试记录、波形截图、问题分析 | `docs/debug/` |
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
| 授权受限/超大文档 | 就近 `_local/`（已忽略，仅本地） |

## 8. 工程约定

- 路径与文件名使用 **ASCII、小写 snake_case**；不使用空格、中文和日期后缀。
- 版本由 Git 管理，不建立 `xxx_v2_final_20261021` 之类的副本。
- 一个模块一个文件，**文件名与模块名一致**；顶层模块以 `top_` 开头。
- TD 工程引用使用**相对路径**；禁止把本机绝对路径写入工程文件。
- 同一份代码/IP/配置只维护一份；需要变体时用参数或独立目录，不复制。
- 未修改的厂商代码保持原样并登记来源；修改需另建 fork 并记录差异。
- 仿真、静态检查、上板证据分开存放，结论必须附证据与复现步骤。
- 不提交位流、布局布线数据库、日志和大型构建结果；IP 只提交可复现的配置
  （生成物按 `fpga/README.md` §4 处理）。

## 9. 待确认事项

1. **原始素材位置**：当前工作区为空；用户确认素材在其他磁盘路径，待提供绝对路径。
2. **Git 路径**：用户确认本机已有 Git，但未在 PATH 或常见安装路径找到，
   待提供 `git.exe` 绝对路径（用于初始化仓库、`git mv` 与回退点）。
3. PH1P35 **具体器件型号**、开发板型号/版本。
4. 摄像头模块的**传感器型号、DVP 接线、默认分辨率与像素时钟**。
5. HDMI **目标分辨率/刷新率**及像素时钟。
6. 是否使用 **DDR 帧缓存**及板上 DDR 型号。
7. MIPI 参考例程的**来源与许可证**，是否允许入库。

以上问题同步记录在 [TASKS.md](TASKS.md) 的阻塞项中。
