# DDR → HDMI PAXI 修复仿真（2026-11-09）

## 范围与依据

只修复现有 `top_ddr_fb_hdmi` 数据通路，不搭建官方 DDR2 全 PHY 仿真平台。
依据本机 TD 6.2.1 `doc/IPUG/IPUG034_PH1P_MIS_IP_Guide.pdf` v1.2
第 13–14、18–20 页，以及同型号 Lab1 的读写地址 `+8` 和零写掩码。
本记录是行为模型验证，不是硬件或训练成功证据。

## 改动

- 三个主机模块 `ddr_axi_pattern_test`、`fb_writer`、`fb_reader` 默认
  `ADDR_STEP=8`；`BASE_ADDR`、PAXI 地址和错误快照均为 **16-bit word 单位**。
- 自检 16 个块的起始地址为 0、8、…、120。
- 帧基地址仍为原数值 4096，现在明确为原生 word 地址（字节偏移 8192）。
  38400 个 128-bit 块起始地址到 311288；末字为 311295。
  每行 80 块，跨度 640 words = 1280 bytes，总计 614400 bytes。
- 所有全块写掩码为 `16'h0000`；1 表示屏蔽对应字节。
- WDATA 在 AW 前准备好；AW 接受后第 1 个周期提供 WVALID/WLAST，
  不等待 WREADY。反压时保持数据/VALID，分别记录 AW/W 接受，完成后才启动下一块。
  IPUG034 的“两周期”按写数据提供时刻检查，不把从机 WREADY 延迟当作主机迟发。
- 行为模型按 `native_addr/8` 索引 128-bit 块，对齐/越界检测独立于 DUT 参数；
  AW 独立锁存，W 高有效掩码逐字节保留/写入；内存初始化为零，避免全屏蔽写误通过。
  增加 AW/W/AR 反压稳定性及 AW 后两周期内 WVALID 的断言。
- 错误色：自检红、写帧橙、整帧读回/CRC 品红、FIFO/显示流黄；等待深蓝。
  分类经单比特 2FF 跨域，不直接异步采样多位 error_code。
- DDR 数据来源测试暴露原 gearbox 的 FIFO pop 晚一拍：每个块边界首像素重复旧块。
  将 pop 改为消费像素 7 的同一边沿有效，未改 PLL、TMDS 或视频时序。

## 复现

```powershell
powershell -ExecutionPolicy Bypass -File fpga/scripts/sim_ddr_fb_paxi_fix.ps1
```

ModelSim SE-64 2020.4；50 MHz 系统、133.33 MHz DDR 用户时钟、25/125 MHz
HDMI 行为 PLL/ODDR。运行现有两个 testbench，未新建测试顶层。
日志：`build/sim_ddr_fb_paxi_fix/`。

## 结果：12/12 PASS

1. `normal.log`：16 块读写一致。
2. `pressure.log`：READY_DELAY=2；AW、W 分离接受，无稳定性/两周期断言错误。
3. `corrupt.log`：原生地址 40（第 5 块）翻转 1 bit，自检报错。
4. `old_step.log`：注入 ADDR_STEP=1；模型报告未对齐，14 块比较失败，负例通过。
5. `old_mask.log`：强制掩码 FFFF；内存保持零，16 块比较失败，负例通过。
6. `frame_normal.log`：完整写入和逐像素读回，CRC actual=expected=F53A4D4F；
   HDMI 边框、标记、8 色条、网格及 39/40/41、79/80 块边界检查通过。
7. `frame_pressure.log`：READY_DELAY=2；同样 CRC 和图像检查通过，无 FIFO 错误。
8. `frame_corrupt.log`：原生地址 4128（帧内第 4 块）翻转 1 bit；
   CRC actual=306B3F2A，err_addr=4128，error_code=3，品红屏，不启动正常视频。
9. `self_corrupt.log`：自检错误，error_code=1，红屏，不写帧、不启动视频。
10. `fifo_underflow.log`：正常显示后强制 FIFO 空直到实际 underflow 置位，
    error_code=4，黄屏。
11. `fifo_overflow.log`：注入 overflow 状态，error_code=4，黄屏。
    此项验证错误传播/显示，不声称覆盖 FIFO 满时的全部写入边界。
12. `ddr_source.log`：校验通过后仅修改模型内存中的像素 (40,10)，白变绿；
    HDMI 同像素变绿，相邻 (39,10)/(41,10) 仍白，证明显示数据来自 DDR/FIFO。
    仅 testbench 注入，不进入位流。

编译 0 errors/0 warnings；7 个集成用例 0 errors/0 warnings。
5 个自检用例存在原 testbench 未连接 err_addr/exp_data/act_data/rlast_err 的
5 条端口警告（无功能错误）。这些输出不参与该 testbench 判定，集成顶层已连接。

初次错误显示测试早于 HDMI 模型 10 us 锁定，已将测试检查移到锁定后；
初次单像素来源检查检出 gearbox 边界错误，修复后重跑全部 7 个集成用例通过。
未开展部分字节掩码专项测试、复杂 burst、压力或完整 PHY 级仿真。
