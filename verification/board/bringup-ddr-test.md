# DDR 最小读写测试上板步骤（2026-11-08）

> 目标：在 PH1P35MDG324 封装内 DDR2 512Mb x16 上完成
> **初始化/校准 → AXI 写 → AXI 读 → 逐字比对**，不接摄像头、不接 HDMI。
>
> 本文是操作步骤，不是结果。实测后写入
> `verification/board/evidence/20261108_ddr_test/README.md`。
>
> 位流：`build/bitstream/top_ddr_test.bit`
> 构建：`fpga/scripts/build_top_ddr_test.bat`

## 0. 原理与边界

- PH1P35MDG324 的 DDR 是**封装内** 16-bit 512Mb SDRAM（64 MB，1.5 V），
  不是板上外部颗粒；**没有 DDR 封装球位可以飞线/探针**。
- TD IP 的 `Integrated` 模式使用 DDR2 512Mb x16、MDG324 PHY 配置；
  参考工程同器件生成参数为 DDR2-1066（tCK=1876、CL=7、CWL=6）。
- 本测试用 C4 的 50 MHz 作为 IP `ref_clk`，PLL 配置为
  N=3/M=64/C=2/CLK3=21 → 533.33 MHz DDR 时钟。
- 测试只证明“DDR 控制器/PHY/存储单元能写入并读回已知 pattern”；
  不证明帧缓存带宽、双缓冲、摄像头实时性。

## 1. 准备

- 板卡 PH1P35_FT V1 / HX1P35B_FT_40P，器件 PH1P35MDG324。
- 只接 USB-JTAG 和电源；**不要接摄像头/HDMI**（本测试不需要）。
- 确认 50 MHz 有源晶振（C4）正常；这是唯一的板级时钟输入。
- 构建前先运行 `fpga/scripts/prepare_ddr_ip.sh` 生成 `build/ddr_ip/`
  （本地构建产物，不入库）。

## 2. 构建

```bat
cd fpga\scripts
build_top_ddr_test.bat
```

预期输出 `build/bitstream/top_ddr_test.bit`。构建日志中应无
`HDL-8007 ERROR`/black box；`read_hdl` 文件数应为 38（含 7 个 cal 文件）。

**2026-11-08 实际构建结果**：

- Setup WNS **+0.913 ns**，Hold WNS **+0.020 ns**（紧），3389 slices，
  31 DRAMHARDCON；
- 位流 SHA-256 `610b0b1f…`；
- `check_timing`：2 个 HIGH dummy node（PLL `pllreset`）、1 个 HIGH
  PLL 频率舍入告警（533.600 vs 533.333）、22 个无 input delay、
  49 个无 output delay；0 combinational loops；
- 证据：`verification/static/top_ddr_test_build_2026-11-08.md`。

## 3. 下载与 LED

Program SRAM，烧 `top_ddr_test.bit`。

| LED | 含义 | 预期 |
|---|---|---|
| LED1 | 50 MHz 心跳 | 1 Hz 闪 |
| LED2 | `ddrphy_rdy`（校准完成） | 上电后一段时间常亮 |
| LED3 | pattern PASS | LED2 亮后常亮 |
| LED4 | pattern FAIL/超时 | 熄灭 |

上电顺序：LED1 立即闪；LED2 可能延迟数十毫秒到数百毫秒
（PLL 锁定 + DDR 初始化/校准）；LED2 亮后 LED3 应在很短时间内亮。

## 4. 失败定位

### 4.1 LED1 不闪

- 位流未加载/时钟 C4 异常/电源；先烧已知可用的
  `top_hdmi_colorbar.bit` 确认板卡基本状态。

### 4.2 LED1 闪，LED2 一直不亮

按可能性从高到低：

1. **PLL/ref_clk**：50 MHz 参考与 IP PLL 参数不匹配；检查
   `PLL0_REFCLK_FREQ=50.0`、`REFCLK_DIV=3`、`FBKCLK_DIV=64`、
   `CLK2_DIV=2`、`CLK3_DIV=21`。
2. **校准未完成/失败**：`CAL_EN=1` 需要 cal RTL；确认构建包含
   `src/rtl/cal/*.v`，无 black box。
3. **速度档过高**：先试 `CAL_EN=0`（参考工程配置）或降 DDR2-800
   （`tCK=2500`，CL=6/CWL=5，PLL 按 400 MHz 重算），排除时序余量。
4. **复位/APB**：`sys_rst_n`/`apb_prst_n` 必须释放；APB 输入不能悬空
   （本设计已明确接 0）。
5. **IP 配置**：确认 `ph1p_mis_define.vh` 是 `DRAM_DDR2`、
   `DDR2_512M`、`DDR2_X16`、`DDR2_1066`、`PH1P_VCCIO_1V50`，
   且**没有** `MC0_MIS_AXI`（本测试用原生 `paxi_*`）。

### 4.3 LED2 亮，LED4 亮（FAIL）

- 看 `test_err_cnt`（构建后可加 UART/LA，或临时把 err_cnt 接到 LED）。
- 检查 `paxi_*` 连接/地址：本 IP 的 `paxi_awaddr/araddr` 是
  **字地址**（1 地址 = 128-bit beat），不是字节地址。
- 检查 AXI 握手：`awvalid/wvalid` 在 ready 后必须撤销；仿真已覆盖
  `READY_DELAY=0/2`。
- 检查 `paxi_rdata` 采样时刻：`rvalid` 有效时采样，`rready` 保持 1。
- 若只有个别 beat 错，可能是地址映射/位宽/字节序；先用 beat 0 单字
  写读，再扩大到 16 beat。

### 4.4 LED2/LED3 都亮，但后续帧缓存仍失败

- 最小测试只写 16 beat；帧缓存需要连续大批量读写、仲裁和 CDC，
  需另做 D3 阶段。

## 5. 证据归档

`verification/board/evidence/20261108_ddr_test/README.md`：

- 位流 SHA、构建日志/时序/QoR；
- LED1–LED4 实际状态（上电后 1 s / 10 s）；
- 是否 LED2 常亮、LED3 常亮；
- 失败时的参数变体（CAL_EN、tCK/CL、PLL）及结果；
- 照片/视频（可选）；
- 明确 PASS/FAIL/未完成。

## 6. 完成定义

- [ ] 构建无 ERROR/black box，位流生成。
- [ ] LED1 1 Hz 闪。
- [ ] LED2 常亮（`ddrphy_rdy`）。
- [ ] LED3 常亮（16 beat pattern 全部匹配）。
- [ ] LED4 熄灭。
- [ ] 证据 README 明确标记 PASS/FAIL。

最小测试 PASS 只证明 DDR 基本读写可用；**不代表** 640×480 帧缓存、
双缓冲或摄像头实时画面已通过。
