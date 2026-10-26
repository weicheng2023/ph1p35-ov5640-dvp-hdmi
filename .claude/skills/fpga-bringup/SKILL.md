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
have passed. **DVP three-channel board capture passed 2026-10-26:** PCLK
50 MHz, HREF active high (15 kHz, 40 µs = 2000 PCLK), VSYNC active low
(30 Hz). Next: color bar + D0–D7 byte order. HDMI and DDR are not started.

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
4. **Polarity (measured):** HREF active high, VSYNC active low. Write
   `0x4740 = 0x22` explicitly and read it back. The capture instance uses
   `HREF_ACTIVE_HIGH=1`, `VSYNC_ACTIVE_HIGH=0`. Do not use `0x23`; it did not
   match the 2026-10-26 LA waveform. See `docs/camera/README.md` §2.1.

## Build

```bat
cd /d <repo-root>
fpga\scripts\build_top_cam_id.bat
fpga\scripts\build_top_dvp_test.bat
```

- TD 6.2.1 command-line flow, not the GUI Run (its generated `run.bat` is broken).
- `top_cam_id.bit`: minimal SCCB/ID design.
- `top_dvp_test.bit`: OV5640 RGB565 config + DVP capture + LEDs.
- Design-specific reports: `<top>_route.qor`, `<top>_final_timing.rpt`.
- `top_dvp_test.sdc` uses the measured **50 MHz** PCLK. Input delays
  (10/2 ns) are still provisional.

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

## Debug ladder

Do not skip levels.

1. **LED heartbeat**: LED1 blinks → clock C4 and configuration are alive.
2. **Four LEDs**: `top_led_test.bit` → all physical LED1–4 on.
3. **Pin path**: `top_sccb_pin_test.bit` → SCL/SDA toggle on J2-32/33.
4. **Protocol**: `top_cam_id.bit` → LED2/3/4 on; logic analyzer decode
   `0x3C W 30 0A [SR] 0x3C R 56` and `30 0B ... 40`.
5. **DVP three-channel (done 2026-10-26)**: PCLK 50 MHz, HREF active high,
   VSYNC active low. Next: rebuild with `COLOR_BAR=1` and probe D0–D7.
   Follow `verification/board/bringup-dvp-three-channel.md`; evidence in
   `verification/board/evidence/20261026_dvp_three_channel/`.

## Critical pins

- Clock **C4** (not D4).
- LEDs **D10/E10/C6/D6** → physical LED1–4. **A5 is GPIOA32**, not LED.
- SCL R6/J2-32; SDA T5/J2-33; RESET U7/J2-34; PWDN U6/J2-35.
- GND J2-30; 3.3V J2-29; **J2-11 is 5 V**.
- PCLK F14/J2-7; VSYNC K16/J2-21; HREF K17/J2-20.
- Full table: `docs/hardware/wiring.md`.

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
- Do not commit PDFs, bitstreams, TD logs, `build/`, or generated databases.

## When done

1. Run simulation and TD build.
2. Update `TASKS.md` checkboxes and change log.
3. Add board evidence under `verification/board/evidence/YYYYMMDD_topic/`.
4. Update `README.md` status if a milestone changed.
5. Commit with a focused message; follow the session's attribution rules.
