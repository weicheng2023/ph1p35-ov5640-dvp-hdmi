# DDR AXI 读写测试仿真证据（2026-11-08）

> 工具：ModelSim SE-64 2020.4
> 设计：`ddr_axi_pattern_test`（AXI 主机 FSM/比对）
> 模型：`ddr_axi_slave_model`（行为 AXI 从机，不是加密 DDR IP）
> 位置：本地 `build/sim_ddr/`（不入库）
>
> 本文件记录**实际执行的仿真**。它只证明 AXI 主机 FSM/握手/比对逻辑，
> **不证明**真实 DDR 的初始化、校准或存储单元。

## 1. 仿真边界

- 真实 DDR IP（`ph1p_ddrmc_wrapper_63f4ac254419` + 加密 MC/PHY）
  **没有**行为模型，未在本仿真中实例化。
- `ddr_axi_slave_model` 按 TD 简化 AXI 端口实现：
  - 字地址（1 地址 = 1 个 128-bit beat）；
  - 写：`awvalid/awready` + `wdata/wstrb/wvalid/wready`，无 B 通道；
  - 读：`arvalid/arready` + `rdata/rlast/rvalid/rready`。
- `READY_DELAY` 参数给 `awready/wready/arready` 加反压，验证主机的
  valid 保持/撤销；`CORRUPT` 参数在读到 beat 5 时翻转 1 bit，验证
  比对器能报错。

## 2. 命令

```tcl
vlib work
vlog -sv fpga/rtl/ddr/ddr_axi_pattern_test.v \
        fpga/sim/models/ddr_axi_slave_model.v \
        fpga/sim/tb/tb_ddr_axi_pattern_test.v
vsim -c -gCORRUPT=0 -gREADY_DELAY=0 -do "run -all; quit" work.tb_ddr_axi_pattern_test
vsim -c -gCORRUPT=0 -gREADY_DELAY=2 -do "run -all; quit" work.tb_ddr_axi_pattern_test
vsim -c -gCORRUPT=1 -gREADY_DELAY=0 -do "run -all; quit" work.tb_ddr_axi_pattern_test
```

## 3. 结果

```text
=== CORRUPT=0 READY_DELAY=0 ===
ok   all beats matched (READY_DELAY=0)
TB: PASS - ddr_axi_pattern_test (CORRUPT=0 READY_DELAY=0)

=== CORRUPT=0 READY_DELAY=2 ===
ok   all beats matched (READY_DELAY=2)
TB: PASS - ddr_axi_pattern_test (CORRUPT=0 READY_DELAY=2)

=== CORRUPT=1 READY_DELAY=0 ===
ok   corrupt detected, err_cnt=1
TB: PASS - ddr_axi_pattern_test (CORRUPT=1 READY_DELAY=0)
```

- 正常/反压两种握手下 16 个 128-bit beat 全部匹配；
- 故意翻转 1 bit 时 `err_cnt=1`，测试判 FAIL；
- 主机 FSM 的 `awvalid/wvalid/arvalid` 在握手后撤销，未出现重复 beat。

## 4. 未覆盖/未证明

- 真实 DDR PHY 的 `ddrphy_rdy` 校准时间/结果；
- 真实 MC 的 AXI 时序、outstanding、地址映射；
- 真实 DDR 存储单元的保持/串扰/刷新；
- 板上 LED 结果。

这些必须在 `verification/board/bringup-ddr-test.md` 中实测。
