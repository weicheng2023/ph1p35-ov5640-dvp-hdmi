# 约束文件说明

## 当前文件

| 文件 | 状态 | 说明 |
|---|---|---|
| `camera_pinmap_draft.adc` | **草案，未绑定顶层** | ATK-MC5640 DVP 引脚到 PH1P35MDG324 球位的候选分配 |

当前**没有**顶层 RTL、`.al` 工程或正式 `.adc`，因此本目录还没有可构建的约束集。

## 草案的使用条件

`camera_pinmap_draft.adc` 使用的是建议端口名：

```text
cam_pclk, cam_vsync, cam_href, cam_data[7:0],
cam_scl, cam_sda, cam_reset_n, cam_pwdn
```

只有在顶层 RTL 使用相同端口名（或先改约束中的端口名）后，才能加入 TD 工程。
端口不匹配时 TD 会报找不到对象，这是预期行为，不是约束错误。

## 约束语法依据

TD 6.2.1 自带例程使用：

```tcl
set_pin_assignment { port_name } { LOCATION = <ball>; IOSTANDARD = LVCMOS33; }
```

参考：`D:\Software\Anlogic\TD_6.2.1\board_designs\ANLOGIC\AP102\LED_AP102\source_code\constraints\LED.adc`

## 规则

- 只分配实际使用的信号；**GND、3.3V、NC 不分配为 GPIO**。
- 每个球位只能出现一次；迁移后必须检查重复占用。
- IOSTANDARD 由 Bank 电压决定：本项目使用的 BANK22/BANK32 均为 3.3 V，
  因此为 `LVCMOS33`。换板或改 Bank 电压时必须重查。
- PCLK 固定 `F14`；不得恢复旧的 D4 方案。
- 不在本阶段添加 `create_clock`：PCLK 频率取决于 OV5640 配置，尚未确认。
- 不为了让时序通过而添加 false path。
- `.adc` 通过只代表“端口名和球位语法正确”，**不代表外部接线正确**。

## 尚未验证

- 端口名与未来顶层的一致性（顶层尚不存在）。
- TD 中的 I/O 规划、重复球位检查、Bank 电压检查。
- F14 作为 PCLK 时钟输入的资源和时序收敛情况。
- 实物接线（见 `verification/board/wiring-check.md`）。

这些必须在顶层 RTL 和 TD 工程建立后，用实际综合/布局布线结果确认。
