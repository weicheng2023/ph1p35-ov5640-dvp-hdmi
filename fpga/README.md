# FPGA 工程说明

> **当前状态（2026-10-24）**：已有最小 SCCB Chip ID 工程
> （`rtl/top/top_cam_id.v` + `rtl/camera/sccb_master.v` + `ov5640_id_reader.v`）。
> ModelSim 仿真通过；TD 综合/布局布线/位流通过；**尚未上板**。
> 构建入口：`scripts/build_top_cam_id.bat`。

## 1. 目录职责

| 目录 | 职责 | 入库 |
|---|---|---|
| `project/` | TD 工程入口（`.al`）与必须随工程保存的配置 | 是 |
| `rtl/top/` | 顶层、板级集成、模块互联 | 是 |
| `rtl/camera/` | SCCB 配置、DVP 接收、同步与位宽对齐 | 是 |
| `rtl/display/` | HDMI/TMDS 编码、视频时序生成 | 是 |
| `rtl/common/` | 时钟/复位、CDC、FIFO 等与具体外设无关的逻辑 | 是 |
| `constraints/` | 引脚/时序约束；`top_cam_id.adc/.sdc` 已用于最小工程，`camera_pinmap_draft.adc` 留给 DVP 阶段 | 是 |
| `ip/` | IP 配置、生成说明、版本记录 | 配置入库，生成物按 §4 |
| `sim/` | Testbench、测试向量、仿真脚本与日志 | TB 入库，波形/日志不入库 |
| `scripts/` | 工程生成、仿真、构建与报告收集脚本；当前含 `build_top_cam_id.bat/.tcl` | 是 |

## 2. 依赖方向

```text
rtl/top  ──►  rtl/camera
         ──►  rtl/display
         ──►  rtl/common
```

- `camera/` 与 `display/` **不得互相实例化**；跨域协调放在 `top/`。
- 通用逻辑下沉到 `common/`，避免复制。
- 未来图像处理模块出现时再建 `rtl/video/`；多摄像头时在 `rtl/camera/`
  内按实例拆分，不提前建立空层级。

## 3. 编码与命名约定

- 文件与模块名一致，使用小写 snake_case；一个文件一个模块。
- 顶层模块以 `top_` 开头，例如 `top_ph1p35_dvp_hdmi`。
- 时钟、复位、跨时钟域信号命名带明确后缀/前缀（如 `_pclk`、`_rst_n`）。
- 不修改既有逻辑来“适配目录”；目录迁移不得改变功能。

## 4. TD 工程与生成物

- 工程入口统一在 `project/`，工程内引用使用**相对路径**。
- 约束文件命名与顶层对应，如 `top_ph1p35_dvp_hdmi.adc` / `.sdc`。
  （TD 6.2.1 实际支持的后缀与写法以工程导入后验证为准。）
- **构建产物**（位流、布局布线数据库、报告、日志）统一输出到根目录
  `build/`，不入库。
- **IP 策略**：
  - 配置文件与生成说明必须入库，保证可复现；
  - 生成 RTL/网表如为复现所必需，入库并在 `ip/README.md` 记录
    生成工具版本与步骤；否则放 `build/ip/` 并由脚本重新生成；
  - 不在多个目录保存同一份 IP 输出。
- 若 TD 强制把中间文件写在工程目录，迁移时核对其路径，并用 `.gitignore`
  排除，不要用“复制一份工程”解决路径问题。

## 5. 构建流程（已实测）

### 5.1 推荐：命令行脚本

```bat
cd /d D:\Projects\02_Personal_Practice\2026_10_OV5640
fpga\scripts\build_top_cam_id.bat
```

脚本调用 TD 6.2.1 的 `td_commands_prompt.exe`，依次执行：
`read_hdl → read_adc → optimize_rtl → read_sdc → optimize_gate → place → route → bitgen`。

输出：

- `build/bitstream/top_cam_id.bit`
- `build/bitstream/top_cam_id_final_timing.rpt`
- `build/bitstream/top_cam_id_route.qor`

本机实测（2026-10-24）：Setup WNS +13.966 ns，Hold WNS +0.079 ns，
257 slices（1.21%）。

### 5.2 TD 工程入口

`project/top_cam_id.al` 可用于查看/编辑源文件。注意本机 TD 6.2.1 在项目模式
生成的 `run.bat` 调用了不存在的 `td_commands_prompt_commands_prompt.exe`，
所以 GUI Run 流程当前不可用；**以 5.1 脚本为准**。

### 5.3 下载

位流生成后，按 `verification/board/bringup-sccb-id.md` 用 BitWizard
Program SRAM。首次验证不要先写 Flash。

## 6. 导入既有工程时的检查清单

- [ ] 器件型号、封装、速度等级
- [ ] 顶层模块名与文件
- [ ] 源文件列表是否包含绝对路径
- [ ] 约束文件是否齐全（引脚、时序、时钟）
- [ ] IP 生成物位置与可复现性
- [ ] 工程内是否引用工程目录之外的文件
- [ ] 位流/报告输出目录
- [ ] 迁移前后文件哈希一致（除路径修复外）
