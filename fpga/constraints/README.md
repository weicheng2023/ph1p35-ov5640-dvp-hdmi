# 约束文件说明

## 当前文件

| 文件 | 状态 | 说明 |
|---|---|---|
| `top_cam_id.adc` | **已用于构建** | 最小 SCCB Chip ID 工程：50MHz、LED、SCCB、RESET/PWDN |
| `top_cam_id.sdc` | **已用于构建** | 50MHz 时钟约束 |
| `camera_pinmap_draft.adc` | **草案，未绑定 DVP 顶层** | ATK-MC5640 DVP 全量引脚候选分配，留到 DVP 阶段 |

当前已有可构建的最小工程 `top_cam_id`，约束已通过 TD 综合/布局布线验证（无未约束 IO 报错）。
`camera_pinmap_draft.adc` 仍不能直接用于本测试顶层，因为它的端口名包含 PCLK/DVP。

## 草案的使用条件

`camera_pinmap_draft.adc` 用于未来的 DVP 顶层，建议端口名：

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

## 已验证 / 尚未验证

已验证：

- `top_cam_id.adc` 的 9 个端口均被 TD 分配，无未约束 IO；
- `top_cam_id.sdc` 的 50MHz 约束生效；
- 综合/布局布线/位流通过，Setup WNS +13.770 ns、Hold WNS +0.049 ns。

尚未验证：

- `camera_pinmap_draft.adc` 与未来 DVP 顶层的一致性。
- F14 作为 PCLK 时钟输入的资源和时序收敛情况。
- 实物接线（见 `verification/board/wiring-check.md`）。

约束通过只证明“端口与球位映射被工具接受”，不代表外部导线正确或功能正常。
