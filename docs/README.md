# 文档索引与归档规则

本目录只放**说明性资料**：手册、原理图、接口/时序说明、设计说明与调试记录。
代码、约束、工程文件和构建产物不放这里。

## 1. 目录职责

| 目录 | 内容 | 典型文件 |
|---|---|---|
| `project/` | 项目目标、系统架构、数据链路、环境、开发规范、决策记录 | `architecture.md`、`environment.md`、`decisions.md` |
| `hardware/` | PH1P35 器件手册、开发板手册、原理图、引脚与电源说明 | `wiring.md`、板卡原理图、pinout |
| `camera/` | ATK-MC5640 模块手册、传感器手册、SCCB 寄存器、DVP 时序与接线 | 模块手册、寄存器表 |
| `display/` | HDMI/TMDS 规范、分辨率与像素时钟、显示器兼容性记录 | 时序表、调试记录 |
| `debug/` | 上电/采集/显示调试记录、波形截图、问题定位过程 | 调试日志、截图 |

> 上板**测试计划与通过证据**不放 `debug/`，放 `verification/board/`。
> 两者的区别：`debug/` 记录“为什么/怎么排查”，`verification/` 记录“是否达标”。

## 2. 文件命名

- 使用 **ASCII、小写 snake_case**，不加空格和中文。
- 厂商文档：`<vendor>_<document>_<rev>.pdf`
  例：`alientek_atk_mc5640_user_manual_v1.0.pdf`
- 自研说明：`<topic>.md`，优先 Markdown，便于 diff 与链接。
- 日期只用于**证据/记录**，不用于制造版本副本；
  版本演进交给 Git，不写 `final_v2_20261021`。

## 3. 文档与实现的关联

- 设计说明必须用**相对路径**链接到对应源码、约束或验证证据。
- 不在文档中整段复制 RTL；引用文件与模块名即可，避免两份内容漂移。
- 文档中的引脚名、信号名、模块名必须与 RTL/约束一致。

## 4. 受限与超大资料

- 授权受限、超大或不宜再分发的资料，放到**同级 `_local/`** 目录：
  `docs/camera/_local/xxx.pdf`。
- `_local/` 已被根目录 `.gitignore` 忽略，仅本地保留。
- 在对应目录的说明或本索引登记“本地存放、未入库”，让其他开发者知道缺失原因。
- 不提交厂商安装包、IDE 离线包、完整 SDK、超大原始视频。

## 5. 当前状态（2026-11-09）

已导入并核对：

| 文件 | 内容 | 入库 |
|---|---|---|
| `hardware/wiring.md` | 当前有效的 ATK-MC5640 → PH1P35 J2 接线表 + **HDMI1 引脚/方向**（§8）、电气注意事项、核对结果 | 是 |
| `camera/README.md` | OV5640 资料链接、关键寄存器、极性矛盾与再分发约束 | 是 |
| `display/README.md` | HDMI 彩条架构、25.0/125 MHz 时钟、TMDS 编码/串行化、仿真/构建状态、上板步骤 | 是 |
| `display/ov5640_line_to_hdmi.md` | OV5640 单行采集 → 双时钟 RAM → HDMI 的设计、1920/1280 调查、A/B、验证状态 | 是 |
| `display/ddr-investigation.md` | 板载 DDR/帧缓存调查：TD IP、AXI/APB、容量/带宽、乒乓方案、待确认项 | 是 |
| `display/ddr-framebuffer-bringup.md` | 阶段 2 DDR 帧缓存：PAXI 地址/掩码、数据路径、逐层验证、CAL_EN=0 边界 | 是 |
| `project/next-session-prompt.md` | Stage 3（OV5640 → DDR → HDMI 实时帧）完整交接与启动 Prompt | 是 |
| `hardware/HX1P35B_FT_40P_*.pdf` | PH1P35_FT V1 板卡原理图（原厂） | **否，本地保留** |
| `hardware/DS1300_PH1P_Datasheet.pdf` | PH1P 器件数据手册（原厂） | **否，本地保留** |
| `camera/ATK-MC5640_V1.2.pdf` | 摄像头模块原理图（原厂） | **否，本地保留** |
| OV5640 Product Specification V2.03 | 传感器寄存器/DVP 时序手册（在线链接见 `camera/README.md`） | **否，仅引用链接** |
| ALIENTEK OV5640 FPGA 驱动 V1.0 | RGB565 初始化参考（在线链接见 `camera/README.md`） | **否，仅引用链接** |

原厂 PDF 的版权/再分发条件未确认，已在 `.gitignore` 中排除，仅本地参考。
官方摄像头资料：<https://github.com/alientek-module/CAMERA-module_ATK-MC5640>

后续导入资料时：

1. 先按上表分类，不确定的文件标记“待确认”，不要凭文件名猜测。
2. 记录来源、版本和是否允许入库。
3. 更新本索引与根 README 的入口表。
