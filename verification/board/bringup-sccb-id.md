# 最小上板验证：SCCB 读取 OV5640 Chip ID

> **目标**：在接好摄像头的前提下，验证 FPGA 下载链路、3.3 V 供电、
> RESET/PWDN、SCCB 总线和引脚约束。**不包含 DVP 采集和 HDMI 显示。**
>
> 当前状态：RTL 已通过 ModelSim 仿真；TD 已完成综合/布局布线/位流生成；
> **尚未在你的实物上烧录验证**。

## 1. 这个测试做什么

上电后：

1. FPGA 拉低 PWDN、拉低 RESET，保持约 10 ms；
2. 释放 RESET（拉高），等待约 20 ms；
3. 通过 SCCB 读寄存器 `0x300A` 和 `0x300B`；
4. 如果读回 `0x56`、`0x40`，说明 Chip ID = `0x5640`；
5. 用 4 个 LED 显示结果。

失败时每 1 秒自动重试，方便你检查接线/上拉后不必重新下载。

## 2. 涉及的文件

| 用途 | 路径 |
|---|---|
| 顶层 RTL | `fpga/rtl/top/top_cam_id.v` |
| SCCB 主机 | `fpga/rtl/camera/sccb_master.v` |
| Chip ID 读取/重试 | `fpga/rtl/camera/ov5640_id_reader.v` |
| 引脚约束（本测试） | `fpga/constraints/top_cam_id.adc` |
| 时钟约束 | `fpga/constraints/top_cam_id.sdc` |
| TD 工程（查看/编辑用） | `fpga/project/top_cam_id.al` |
| 命令行构建脚本 | `fpga/scripts/build_top_cam_id.tcl` |
| 一键构建（Windows） | `fpga/scripts/build_top_cam_id.bat` |
| Testbench | `fpga/sim/tb/tb_top_cam_id.v` |
| 构建产物 | `build/bitstream/top_cam_id.bit` |

## 3. 接线要求

**要接摄像头**。本测试只使用以下信号，但摄像头其余 DVP 线可以保持连接，
RTL 暂不读取它们：

| 信号 | ATK P1 | J2 | FPGA 球位 |
|---|---:|---:|---|
| GND | 1 | 30 | — |
| 3.3V | 2 | 29 | — |
| SCL | 3 | 32 | R6 |
| VSYNC | 4 | 21 | K16（本测试未用） |
| SDA | 5 | 33 | T5 |
| HREF | 6 | 20 | K17（本测试未用） |
| D0–D7 | 7–16 | 22–31 | 本测试未用 |
| RESET | 8 | 34 | U7 |
| PCLK | 15 | 7 | F14（本测试未用） |
| PWDN | 17 | 35 | U6 |
| NC | 18 | 不接 | — |

注意：

- **不要接 J2-11（5 V）**。
- 摄像头 3.3 V 接 J2-29，GND 接 J2-30。
- 上电前按 `verification/board/wiring-check.md` 做断电通断和短路检查。
- 本测试的 `.adc` 对 SCL/SDA 启用了 **FPGA 内部上拉**。
  如果 LED1 一直不亮，优先补 **4.7 kΩ 外部上拉** 到 3.3 V（SCL、SDA 各一个）。
- 摄像头先接好再上电，不要带电插拔。

## 4. 生成位流

### 4.1 推荐：双击 bat

1. 关闭正在占用工程的 TD 窗口。
2. 打开文件夹：
   `D:\Projects\02_Personal_Practice\2026_10_OV5640\fpga\scripts`
3. 双击 `build_top_cam_id.bat`。
4. 等待窗口出现：
   `=== DONE: top_cam_id.bit ===`
5. 检查文件是否存在：
   `D:\Projects\02_Personal_Practice\2026_10_OV5640\build\bitstream\top_cam_id.bit`

如果 TD 不在 `D:\Software\Anlogic\TD_6.2.1`，先在命令行设置：

```bat
set TD_HOME=你的TD安装目录
fpga\scripts\build_top_cam_id.bat
```

### 4.2 已实测结果（2026-10-24）

- TD 6.2.1 综合/布局布线通过。
- Setup WNS = **+13.196 ns**，Hold WNS = **+0.069 ns**。
- 资源：257 slices（1.21%）。
- 已生成位流：`build/bitstream/top_cam_id.bit`。

> 这是“工具流程通过”，**不是**“你的板子已经通过”。

## 5. 烧录到 FPGA

1. 用 USB 线连接开发板的 **AL-LINK-FT / Type-C 下载口**。
2. 打开 BitWizard：
   - 直接运行 `D:\Software\Anlogic\TD_6.2.1\bin\bw.exe`，或
   - TD 菜单 `Tools → BitWizard`（不同版本名称可能略有差异）。
3. 点击 **Refresh**，确认器件显示为 `PH1P35MDG324`。
4. 点击 **Add**，选择：
   `D:\Projects\02_Personal_Practice\2026_10_OV5640\build\bitstream\top_cam_id.bit`
5. 选择 **Program SRAM**（调试用，掉电丢失），点击 **Run**。
6. 等待进度到 100%。
7. 观察 4 个 LED。

第一次验证只用 **Program SRAM**，不要先写 Flash。
确认功能正常后，再考虑 `Program Flash` 固化。

## 6. LED 结果怎么看

板子上有 5 个可见 LED：**LED14 是电源指示灯（常亮正常，不受 FPGA 控制）**，
**LED1–LED4 才是四个用户灯**。FPGA 网络 `LED0..LED3` 分别对应物理
`LED1..LED4`：

| 物理 LED | FPGA 网络 | 含义 |
|---|---|---|
| LED1 | LED0 | 1 Hz 心跳闪烁：FPGA 已配置并在运行 |
| LED2 | LED1 | 至少完成过一次无 ACK 错误的 SCCB 读 |
| LED3 | LED2 | 读回高字节 == `0x56` |
| LED4 | LED3 | Chip ID 完整匹配 `0x5640` |

**成功**：LED1 闪烁，且 LED2、LED3、LED4 都亮。

### 6.1 四个用户灯全灭时的诊断

先排除“位流没配置成功”：

1. 重新打开 BitWizard，Refresh 确认器件是 `PH1P35MDG324`。
2. 选择 `build/bitstream/top_led_test.bit`（四灯常亮诊断位流），
   用 **Program SRAM** 下载并 Run。
3. 若 LED1–LED4 **全部常亮**：说明下载链路和 LED 球位正确，
   问题在 `top_cam_id` 的心跳/时钟/复位逻辑。
4. 若仍然全灭：位流没有真正配置成功，或板卡 LED 网络与原理图不符。
   检查 BitWizard 是否有 100% 进度、是否有 DONE 指示灯、
   USB 线/驱动，并重新 Program SRAM。

诊断位流可用以下命令重新生成：

```bat
fpga\scripts\build_top_led_test.bat
```

常见现象：

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 只有 LED1 闪 | 摄像头没供电 / SCL、SDA 没接对 / 没有上拉 / PWDN 仍为高 | 测 P1-2 对 P1-1 电压；查 SCL=P1-3→J2-32，SDA=P1-5→J2-33；补 4.7k 上拉 |
| LED1 不闪 | 位流没下载 / 时钟 D4 异常 | 重新 Program SRAM；先跑 top_led_test 诊断；检查 50MHz 晶振与 D4 |
| LED2 亮，LED3/4 不亮 | SCCB 通了，但 ID 不是 0x5640 | 确认模组是 OV5640；检查读寄存器时序 |
| LED2 周期性闪一下 | ACK 间歇成功 | 检查杜邦线长度、地线、上拉；缩短接线 |
| 全部常亮/异常 | 可能误把 5V 或 GND 接到信号 | 立即断电，重做 wiring-check |

## 7. 仿真复现

已用 ModelSim SE-64 2020.4 跑通：

```tcl
vlib work
vlog ../../fpga/rtl/camera/sccb_master.v \
     ../../fpga/rtl/camera/ov5640_id_reader.v \
     ../../fpga/rtl/top/top_cam_id.v \
     ../../fpga/sim/tb/tb_top_cam_id.v
vsim -c -do "run -all; quit" work.tb_top_cam_id
```

预期输出：

```text
TB: PASS - Chip ID matched (led=1110, id_hi=56, id_lo=40)
```

仿真中的 SCCB 从机模型返回 `0x56/0x40`，验证了读时序、ACK/NA 和重试逻辑，
但**不验证真实摄像头的上电时序和电气特性**。

## 8. TD 工程入口说明

- 可以打开 `fpga/project/top_cam_id.al` 查看源文件、约束和顶层名。
- 本机 TD 6.2.1 在项目模式下生成的 `run.bat` 调用了不存在的
  `td_commands_prompt_commands_prompt.exe`，导致 GUI 的 Run 流程无法直接运行。
  因此本仓库提供并实测了 `fpga/scripts/build_top_cam_id.tcl` 命令行流程。
- 如果以后 TD 修复了该问题，也可以在 GUI 中把 `top_cam_id` 设为顶层后运行；
  当前**以脚本构建为准**。

## 9. 本测试的边界

已验证：

- RTL 语法/协议仿真通过；
- TD 综合、布局布线、时序、位流生成通过；
- 引脚约束被 TD 接受（无未约束 IO 报错）。

未验证：

- 你的实物接线；
- 摄像头是否真的返回 `0x5640`；
- DVP 数据、PCLK 采样、HDMI 输出。

只有烧录后看到 **LED0 闪 + LED1/2/3 亮**，才能说这个最小测试在你的板子上通过。
