---
name: fpga-bringup
description: Continue the PH1P35 + ATK-MC5640 (OV5640) DVP/HDMI FPGA project. Use for TD 6.2.1 builds, ModelSim runs, SCCB/DVP debugging, pin/constraint changes, or recording board evidence.
---

# FPGA bring-up

## Before acting

1. Read `AGENTS.md` — canonical facts, rules, pitfalls.
2. Read `TASKS.md` — current milestone and blockers.
3. Read `docs/hardware/wiring.md` before touching pins.
4. State the current milestone and what you are about to verify.

## Current milestone

SCCB Chip ID **0x5640 is verified on board**. DVP capture RTL, real-timing
simulation, RGB565 configuration/readback, `top_dvp_test.v` and the TD build
have passed. **DVP three-channel timing re-verified 2026-11-06:**
`2026_11_6_PCLK_VSYNK_HREF.atkdl` (50 MS/s, 200 ms) shows VSYNC **30 Hz /
33.333 ms / 66.66 µs high**, HREF **15 kHz / 39.997 µs high / 26.66 µs low**,
479 normal lines/frame (480 effective). The 2026-10-28 29.53 kHz anomaly did
**not** reproduce. PCLK at 50 MS/s is a **2 MHz alias** (undersampled); direct
48.000 MHz evidence is the 200/250 MS/s capture. `0x4740=0x22` is VSYNC
**active high**; `0x23` is active low. **HREF polarity is unresolved (A/B):**
low phase = 1280 PCLK; high phase = 1920 PCLK. The 16:24
`HREF_ACTIVE_HIGH=0` + `EXPECTED_PIX=1280` LED4-off report only proves the
length check, not pixel data. **DVP is paused; the camera color-bar test is
deferred.**

**HDMI display color bar (no camera, no DDR): USER-REPORTED board PASS
(2026-11-08).** Sim/build passed; the user programmed
`top_hdmi_colorbar.bit` and saw the FPGA internal 8 bars. **No photo/log/
voltage/LA data was provided.** Treat it as a user-reported milestone, not
as independent electrical/protocol evidence.

**OV5640 single-line -> HDMI: PARTIAL PASS (2026-11-08 user report).**
RTL/sim/TD build passed; the user programmed the bitstream. LED1/2/3/4 all
matched. The monitor showed one camera line repeated over 480 rows, but
the picture was a wide black band on the left and a large light-blue/purple
area on the right, **not the expected OV5640 internal 8-color bar**. Pixel
content, byte order, HREF A/B and +/-1-pixel alignment are unconfirmed.
The user paused color-bar/LA debugging. Evidence:
`verification/board/evidence/20261108_ov5640_line_hdmi/README.md`.

- `ov5640_line_capture` captures the first 1280 bytes of the HREF-active
  phase (`CAPTURE_START=640` selects the other half), rejects the
  1.373 ms/65,900-byte blanking HREF by line length, and freezes the
  640x16 dual-clock ERAM after `STARTUP_LINES` valid lines.
- Sim 3/3 PASS; TD Setup +6.027 ns, Hold **+0.020 ns (tight)**, 821
  slices, 1 ERAM. `check_timing` has one HIGH dummy node
  `cam_sda.ts` (SCCB inout; the same code passed the board Chip-ID read)
  and 12 MEDIUM no-output-delay.
- Bitstream (local): `build/bitstream/top_ov5640_line_to_hdmi.bit`,
  SHA-256 `67eec013651ccdde7291e3e26d1ec1a506e92111076651f0a49cf7ff0e3222cd`.
- **Current task: Stage 3 (OV5640 → DDR double buffer → HDMI live).**
  Stage 2 test-image frame buffer is complete (see the 2026-11-09 block
  below). Datasheet §2.12 confirms
  PH1P35MDG324 has in-package **DDR2-class 512Mb x16** (64 MB, 1.5 V);
  the TD IP `Integrated` mode selects `DDR2_512M/DDR2_X16` with
  `ddrphy_cfg_rom_MDG324`. The minimal native-`paxi_*` 16-beat pattern
  test was sim/build passed (SHA `610b0b1f…`) and **board-tested by the
  user: LED1 blinks, LED2/LED3/LED4 all off**. This is consistent with
  `ddrphy_rdy` never high: the pattern FSM waits in `ST_IDLE` (no
  timeout there), and `ddrphy_rst_n` was not brought out. Do not claim a
  calibration-failure cause. A **debug bitstream** now exposes
  LED2=`ddrphy_rst_n` (2FF), LED3=`ddrphy_rdy` (2FF), LED4=independent
  50 MHz 1 s timeout, with AXI/APB tied off and no transactions; SHA
  `03339cf5…`. **Board: LED1 blink, LED2 on, LED3 off, LED4 on**
  (>10 s): PLL/reset released, `ddrphy_rdy` missing. **CAL_EN=0 control
  built** (only CAL_EN changed): `top_ddr_debug_cal0.bit`, SHA
  `f3facdf8…`, Setup +2.073 / Hold +0.021 ns, 1290 slices (CAL1 1960;
  omitted `if (CAL_EN==1)` cal block). PLL/ref/tCK/CL/CWL/reset/SDC/LED/
  AXI-APB unchanged; 38-file IP list same; only `-define DDR_CAL0`.
  `check_timing` CAL0: 4 HIGH no-clock (CAL1 6; SDC unchanged), PLL
  dummy/533.600-vs-533.333, `USR-6133`; not a timing sign-off. Original
  `top_ddr_test.bit` (`610b0b1f…`) and `top_ddr_debug.bit` (`03339cf5…`)
  preserved. **CAL0 board (USER): LED1 blink, LED2 on, LED3 on, LED4 off**
  → READY reachable with PHY training bypassed; data reliability unproven.
  Evidence:
  `verification/static/top_ddr_debug_cal0_build_2026-11-08.md`,
  `verification/static/top_ddr_debug_build_2026-11-08.md`,
  `verification/board/bringup-ddr-debug.md`, `docs/display/ddr-debug.md`.
  Report: `docs/display/ddr-investigation.md`.

**DDR frame buffer -> HDMI: STAGE 2 — BOARD FUNCTIONAL PASS (2026-11-09,
user report).** Independent `top_ddr_fb_hdmi` (existing tops untouched),
`ddr2 #(.CAL_EN(0))` — EXPERIMENTAL, training bypassed. Flow: 16-beat
self-check → 38400 single-beat 128-bit writes (base word address 4096,
80 beats/row) → conservative DRAIN → full-frame readback with per-pixel
compare + CRC-32 of the **actual read data** → FIFO prefill 192 →
VSYNC-aligned `video_valid` → 128×256 Gray FIFO → 8:1 gearbox → proven HDMI.

Critical interface rules (do not regress):
- Native PAXI address unit is a **16-bit word**; a 128-bit beat advances
  `ADDR_STEP=8`, **not 1**.
- Write mask is **active-high**: `16'h0000` writes all bytes; `1` masks
  (preserves) that byte. The old `16'hFFFF` wrote nothing.
- AW must be accepted first; WVALID is presented one cycle later and held
  until WREADY. AW/W handshakes are independent.
- The behavioural model enforces alignment/mask/AW→W timing; old +1/FFFF
  cases now fail. It also exposed a gearbox FIFO pop one cycle late at
  8-pixel boundaries — fixed by popping on pixel 7's edge.

Regression: 12/12 PASS; normal CRC `0xF53A4D4F`; injected self/frame/FIFO
faults produce the intended red/orange/magenta/yellow screens. TD: Setup
**+0.110 / Hold +0.020 ns**, 5283 slices, 0 RAM, 0 DSP, 100
DRAMHARDCON; final bitstream SHA
`e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`.
SDC: a design-level two-group async constraint is INVALID/redundant in TD
6.2.1; do not remove the vendor IP SDC group (doing so → Setup -2.467 ns).
The only `usr_clk↔pixel_clk` crossings are the Gray FIFO + 2FF syncs.
Evidence: `verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`,
`verification/static/top_ddr_fb_hdmi_paxi_fix_build_2026-11-09.md`,
`verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`,
`docs/display/ddr-framebuffer-bringup.md`. LED/CRC/photo details were not
provided; do not claim full PHY calibration or long-term reliability.

- HDMI1 is a **source**: board supplies +5V on pin 18 through D5; HPD is
  read by the FPGA; DDC is 3.3V↔5V level-shifted.
- TMDS pairs: **G16/H16 (D0), F17/E18 (D1), H14/H13 (D2), C17/D18 (CLK)**,
  `IOSTANDARD = TMDS33`, `VCCIO_32 = VCC_3V3`. Do not use the old
  H16/F17, E18/H14 combinations.
- 8×49.9 Ω pull-ups to `+3.3V_HDMI`; `HDMI_A_5V` and `HDMI_A0_5V` are
  separate nets; D6 latches HPD high after first plug-in.
- TD 6.2.1 has **no HDMI TX IP**; the third-party `.enc` core is not used.
  The design is a self-written DVI-compatible TMDS encoder + 10:1 DDR
  serializer (`PH1P_LOGIC_ODDR`) with `PH1P_PHY_PLL_V2`
  (VCO 1250 MHz, 25.0 MHz pixel / 125 MHz serial).
- Sim 4/4 PASS; TD build Setup **+5.170 ns**, Hold **+0.054 ns**,
  107 slices. `check_timing` HIGH items 0; 8 outputs have no output delay
  (MEDIUM: 4 LEDs + 4 TMDS). Known `PHY-5016` warning about PLL clkc /
  clock-capable IO; routed clk1 reaches `opclk` and meets timing.
- Bitstream (local): `build/bitstream/top_hdmi_colorbar.bit`,
  SHA-256 `60fb0d0de3aabe36285e1d3cb6ea82bff5e88e271ae18f6374081931c908ef63`.
- **Board: USER-REPORTED PASS (2026-11-08).** The monitor showed the FPGA
  internal 8 bars. Evidence is the user's verbal report only:
  `verification/board/evidence/20261107_hdmi_colorbar/`. Keep this bitstream
  and design as the HDMI regression baseline. Never upgrade a user report
  to independent electrical/protocol evidence.

The original 16:24 DVP binary (SHA `506e01ad…`) was overwritten; the
rebuild is not bit-identical. The 12:33 failed build is preserved as
`top_dvp_test_fail_20261028_dbg_893dc3fa.bit`.

## Starting DVP: read this first

Read `docs/project/dvp-handoff.md` before writing DVP RTL.

1. **Short pulses:** PCLK can be faster than the 50MHz system clock; HREF/VSYNC
   widths are in PCLK cycles. Latch single-cycle events; use async FIFO/handshake
   for multi-bit CDC. Do not repeat the SCCB `start` pulse mistake.
2. **PDF alignment:** `-layout`/thumbnails have already caused one-row-off pin
   errors (J2 GND/SCL, clock C4 vs D4, LED A5). Use `pdftotext -table` +
   high-DPI crops + capability/silkscreen cross-checks.
3. **Simulation fidelity:** use real PCLK frequency, real blanking/pulse widths,
   real CDC/reset. Do not use DIV=2 or a simplified same-clock model and call it
   verified. A simplification that hides timing bugs is invalid evidence.
4. **Polarity (measured 2026-10-26; HREF still A/B):** `0x4740=0x23` gives
   VSYNC **active low**; `0x4740=0x22` gives **active high**. The bit0 effect
   is inverted vs the datasheet. Use a consistent pair: `0x23` +
   `VSYNC_ACTIVE_HIGH=0`, or `0x22` + `VSYNC_ACTIVE_HIGH=1`. HREF is **not
   proven**: low phase = 1280 PCLK (A. active low = valid data; high 1920 =
   blanking) or high phase = 1280 active + 640 dummy (B. datasheet active
   high; low 1280 = blanking). Both let `EXPECTED_PIX=1280` pass, so LED4 off
   is not proof. Compare D0–D7 in both phases for the 8-color bar. Also: HREF
   is high for 1.373 ms during vertical blanking and spans VSYNC; do not count
   it as a 65,920-byte line or flag VSYNC-in-HREF as fatal. See
   `docs/camera/README.md` §2.1 and the 2026-10-28 evidence.

## Build

```bat
cd /d <repo-root>
fpga\scripts\build_top_cam_id.bat
fpga\scripts\build_top_dvp_test.bat
fpga\scripts\build_top_hdmi_colorbar.bat
fpga\scripts\build_top_ov5640_line_to_hdmi.bat
```

- TD 6.2.1 command-line flow, not the GUI Run (its generated `run.bat` is broken).
- `top_cam_id.bit`: minimal SCCB/ID design.
- `top_dvp_test.bit`: OV5640 RGB565 config + DVP capture + LEDs.
- `top_hdmi_colorbar.bit`: independent 640×480@60 8-bar HDMI source.
- `top_ov5640_line_to_hdmi.bit`: camera internal color bar -> single-line
  ERAM -> the proven HDMI chain.
- Design-specific reports: `<top>_route.qor`, `<top>_final_timing.rpt`;
  the HDMI build also runs `check_timing` and `write_csv`.
- `top_dvp_test.sdc` uses a conservative **50 MHz** PCLK constraint; the
  measured PCLK is **48.000 MHz**. Input delays (10/2 ns) are provisional.
- 2026-10-26 16:24 diagnostic: original SHA-256 `506e01ad...cca07a`,
  Setup +10.381 ns, Hold +0.038 ns, 800 slices. The original binary was
  overwritten by the 2026-10-28 12:33 debug build; rebuild from the same RTL:
  `build/bitstream/top_dvp_test_20261026_rebuild.bit`, SHA `b6df6c18...`,
  same QoR, **not bit-identical**. Color-bar copy:
  `top_dvp_test_20261106_colorbar.bit` (same SHA). The 13:16 three-channel
  rebuild is `top_dvp_test_20261026_3ch_rebuild.bit` (SHA `fb3b3b84...`,
  Setup 10.245/Hold 0.054/800). Keep the 12:33 failed build as
  `top_dvp_test_fail_20261028_dbg_893dc3fa.bit`; do not overwrite.

Diagnostics:

- `fpga/scripts/build_top_led_test.tcl` -> four LEDs steady on.
- `fpga/scripts/build_top_sccb_pin_test.tcl` -> SCL/SDA toggle without protocol.

## Simulate

```tcl
cd build/sim
vlib work
vlog ../../fpga/rtl/camera/sccb_master.v \
     ../../fpga/rtl/camera/ov5640_id_reader.v \
     ../../fpga/rtl/top/top_cam_id.v \
     ../../fpga/sim/tb/tb_top_cam_id.v
vsim -c -do "run -all; quit" work.tb_top_cam_id
```

Expected: `TB: PASS - Chip ID matched (led=1110, id_hi=56, id_lo=40)`.
The TB uses `SCCB_DIV=250`; keep it that way to catch divider-tick bugs.

### DVP capture simulation

```tcl
cd build/sim
vlib work
vlog ../../fpga/rtl/common/async_fifo_gray.v \
     ../../fpga/rtl/camera/dvp_capture.v \
     ../../fpga/rtl/camera/dvp_status_monitor.v \
     ../../fpga/sim/tb/tb_dvp_capture.v
vsim -c -do "run -all; quit" work.tb_dvp_capture
```

Expected full-frame result (24 MHz placeholder, 480 lines, 1280 PCLK/line):

```text
TB: PASS - frames=3 ... pix_min=1280 pix_max=1280 events=963
          bytes_err=0 setup_err=0 hold_err=0
```

Quick regression (keeps real PCLK and line length, reduces frame):

```tcl
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
     -do "run -all; quit" work.tb_dvp_capture
```

Polarity regressions (all must PASS):

```tcl
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 -gVSYNC_ACTIVE_HIGH=0 \
     -do "run -all; quit" work.tb_dvp_capture
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
     -gHREF_ACTIVE_HIGH=0 -gVSYNC_ACTIVE_HIGH=0 \
     -do "run -all; quit" work.tb_dvp_capture
```

Mutation tests must FAIL via the setup/hold monitor:

```tcl
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
     -do "run -all; quit" work.tb_dvp_capture +LAUNCH_POSEDGE
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 -gINVERT_DUT_PCLK=1 \
     -do "run -all; quit" work.tb_dvp_capture
```

Do not treat the 24 MHz / 1280 / 480 numbers as measured. See
`verification/static/dvp_capture_sim_2026-10-26.md` and
`docs/camera/README.md`.

### Config/readback simulation

Compile the bring-up path once (the DVP files can stay in `work`):

```tcl
vlog ../../fpga/rtl/camera/sccb_master.v \
     ../../fpga/rtl/camera/ov5640_id_reader.v \
     ../../fpga/rtl/camera/ov5640_cfg_rom.v \
     ../../fpga/rtl/camera/ov5640_cfg.v \
     ../../fpga/rtl/camera/ov5640_bringup.v \
     ../../fpga/sim/tb/tb_ov5640_bringup.v
vsim -c -do "run -all; quit" work.tb_ov5640_bringup
```

Expected:

```text
TB: PASS - cfg_ok=1, id=5640, geom=640x480, 4300=61, 4740=23, 503D=00
```

This TB uses `SCCB_DIV=10` for speed. The DIV=250 protocol regression is
`tb_top_cam_id.v`; keep both.

### HDMI color-bar simulation

```tcl
cd build/sim_hdmi
vlib work
vlog -sv ../../fpga/sim/models/pll_hdmi_sim.v \
     ../../fpga/sim/models/ph1p_logic_oddr_sim.v \
     ../../fpga/rtl/display/video_timing.v \
     ../../fpga/rtl/display/color_bar.v \
     ../../fpga/rtl/display/tmds_encoder.v \
     ../../fpga/rtl/display/tmds_serializer.v \
     ../../fpga/rtl/display/serial_load_gen.v \
     ../../fpga/rtl/top/top_hdmi_colorbar.v \
     ../../fpga/sim/tb/tb_top_hdmi_colorbar.v
vsim -c -do "run -all; quit" work.tb_top_hdmi_colorbar
```

Expected: `TB: PASS - top_hdmi_colorbar`.

Separate TBs:

```tcl
vlog -sv ../../fpga/rtl/display/tmds_encoder.v \
       ../../fpga/sim/tb/tb_tmds_encoder.v
vsim -c -do "run -all; quit" work.tb_tmds_encoder

vlog -sv ../../fpga/rtl/display/video_timing.v \
       ../../fpga/sim/tb/tb_video_timing.v
vsim -c -do "run -all; quit" work.tb_video_timing
```

`tb_video_timing` runs a **full 800×521 frame** and expects
`de=307200, hs_low=50016, vs_low=1600`.

PLL configuration check with TD's vendor functional model:

```tcl
vlog -sv $TD_HOME/sim_release/ph1p/ph1p_phy_pll_v2.v \
         fpga/sim/tb/tb_pll_vendor.v
vsim -c -do "run -all; quit" work.tb_pll_vendor
```

Expected: `TB: PASS - pll_vendor (25.0/125.0 MHz, lock)`.
Do **not** compile `fpga/rtl/display/pll_hdmi.v` together with
`pll_hdmi_sim.v` (both define module `pll_hdmi`). The behavioural models
do not validate the real PLL loop filter or IO electrical behaviour; the
vendor model only checks the configuration/lock trend.

### OV5640 single-line -> HDMI simulation

```tcl
cd build/sim_line
vlib work
vlog -sv ../../fpga/rtl/camera/ov5640_line_capture.v \
     ../../fpga/rtl/common/line_buffer_dpram.v \
     ../../fpga/sim/tb/tb_ov5640_line_capture.v
vsim -c -do "run -all; quit" work.tb_ov5640_line_capture
```

Expected: `TB: PASS - ov5640_line_capture (CAP_START=0 SWAP=0)`.
Also run `-gCAP_START=640` and `-gSWAP=1`.

Core integration (behavioural PLL/ODDR, `cfg_ok` tied high):

```tcl
cd build/sim_core
vlib work
vlog -sv ../../fpga/sim/models/pll_hdmi_sim.v \
     ../../fpga/sim/models/ph1p_logic_oddr_sim.v \
     ../../fpga/rtl/display/video_timing.v \
     ../../fpga/rtl/display/rgb565_to_rgb888.v \
     ../../fpga/rtl/display/tmds_encoder.v \
     ../../fpga/rtl/display/tmds_serializer.v \
     ../../fpga/rtl/display/serial_load_gen.v \
     ../../fpga/rtl/camera/ov5640_line_capture.v \
     ../../fpga/rtl/common/line_buffer_dpram.v \
     ../../fpga/rtl/top/ov5640_line_to_hdmi_core.v \
     ../../fpga/sim/tb/tb_top_ov5640_line_to_hdmi.v
vsim -c -do "run -all; quit" work.tb_top_ov5640_line_to_hdmi
```

Expected: `TB: PASS - top_ov5640_line_to_hdmi`.
The SCCB bring-up is **not** re-simulated here; it is covered by
`tb_ov5640_bringup`.

## Debug ladder

Do not skip levels.

1. **LED heartbeat**: LED1 blinks → clock C4 and configuration are alive.
2. **Four LEDs**: `top_led_test.bit` → all physical LED1–4 on.
3. **Pin path**: `top_sccb_pin_test.bit` → SCL/SDA toggle on J2-32/33.
4. **Protocol**: `top_cam_id.bit` → LED2/3/4 on; logic analyzer decode
   `0x3C W 30 0A [SR] 0x3C R 56` and `30 0B ... 40`.
5. **DVP three-channel (timing done 2026-10-26)**: PCLK **48.000 MHz**,
   HREF 15 kHz, VSYNC 30 Hz; `0x22` active high / `0x23` active low;
   480 lines/frame; 1.373 ms HREF blanking high spans VSYNC. `HREF_ACTIVE_HIGH`
   is **A/B unresolved** (low 1280 PCLK vs high 1920 PCLK); LED4 off only
   proves the length check. Follow `verification/board/bringup-dvp-three-channel.md`;
   evidence in `verification/board/evidence/20261026_dvp_three_channel/`.
6. **2026-10-28 11-channel failed, 2026-11-06 3-channel recheck passed**:
   the `.atkdl` shows VSYNC 30 Hz/33.333 ms and HREF 15 kHz/39.997 µs high;
   the 29.53 kHz anomaly did not reproduce. At 50 MS/s PCLK is a 2 MHz alias.
   **DVP is now paused**; the camera color-bar test is deferred.
7. **HDMI color bar (2026-11-08, USER-REPORTED board PASS)**:
   - Schematic: HDMI1 is a source; TMDS pairs G16/H16, F17/E18, H14/H13,
     C17/D18; 8×49.9 Ω to `+3.3V_HDMI`; HPD can latch high via D6.
   - RTL: `fpga/rtl/display/` + `top_hdmi_colorbar.v`; TD build
     Setup +5.170/Hold +0.054 ns, 107 slices.
   - The user programmed `top_hdmi_colorbar.bit` and saw the FPGA internal
     8 bars. No photo/log/voltage; keep it as a user-reported milestone and
     the HDMI regression baseline.
   - If a future build is black: check +5V pin 18, `+3.3V_HDMI`/Q17, LED2,
     C17 TMDS clock, then monitor input/EDID. Do not use a normal LA on TMDS.
8. **OV5640 line -> HDMI (current)**: camera internal color bar
   (`0x503D=0x80`) -> DVP D0-D7 -> capture first 1280 bytes of the
   HREF-active phase -> 640x16 dual-clock line RAM -> RGB565->RGB888 ->
   the proven HDMI chain. Reject the 1.373 ms vertical-blanking HREF by
   line length. Do not touch the camera config registers or the DVP RTL
   unless the simulation is rerun.

## Critical pins

- Clock **C4** (not D4).
- LEDs **D10/E10/C6/D6** → physical LED1–4. **A5 is GPIOA32**, not LED.
- SCL R6/J2-32; SDA T5/J2-33; RESET U7/J2-34; PWDN U6/J2-35.
- GND J2-30; 3.3V J2-29; **J2-11 is 5 V**.
- PCLK F14/J2-7; VSYNC K16/J2-21; HREF K17/J2-20.
- HDMI1 TMDS: D0 **G16/H16**, D1 **F17/E18**, D2 **H14/H13**,
  CLK **C17/D18** (`TMDS33`, `VCCIO_32=3.3V`).
- HDMI1 DDC: SCL **E15**, SDA **F15**; HPD **B17** (not used in v1).
- Full table: `docs/hardware/wiring.md` §8.

## SCCB facts

- Address 7-bit `0x3C` = write `0x78` / read `0x79`.
- Read uses **repeated START**, 50 kHz in `top_cam_id`.
- Address/data bytes may ACK; the final read **NACK is the NA bit**, not an error.
- The design stops in `S_OK` after success; SCL/SDA idle high is normal.

## Do not regress

- Do not swap clock back to D4 or LEDs to E10/C6/D6/A5.
- Do not sample a one-cycle `start` only on a divided tick; use `start_pending`.
- Do not treat SCCB NA as failure.
- Do not trust `pdftotext -layout` or thumbnails for pin mapping; use `-table`
  + high-DPI crop + board test.
- Do not simplify PCLK/VSYNC/HREF timing in simulation just to make it pass.
- Do not use the old HDMI cross-pairs H16/F17 or E18/H14; the correct pairs
  are G16/H16, F17/E18, H14/H13, C17/D18.
- Do not copy or modify the third-party encrypted HDMI core; no local
  HDMI TX IP exists.
- Do not treat HPD as a reliable hot-plug indicator: D6 can latch it high.
- Do not mark the HDMI color bar PASS until the monitor shows the 8 bars.
- Do not commit PDFs, bitstreams, TD logs, `build/`, or generated databases.

## When done

1. Run simulation and TD build.
2. Update `TASKS.md` checkboxes and change log.
3. Add board evidence under `verification/board/evidence/YYYYMMDD_topic/`.
4. Update `README.md` status if a milestone changed.
5. HDMI work: also update `docs/display/README.md`,
   `verification/static/hdmi_colorbar_sim_2026-11-07.md`,
   `verification/static/top_hdmi_colorbar_build_2026-11-07.md`,
   and `verification/board/bringup-hdmi-colorbar.md`.
6. Commit with a focused message; follow the session's attribution rules.
