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

SCCB Chip ID **0x5640 is verified on board**. Next: DVP capture
(PCLK/VSYNC/HREF, then D0–D7). HDMI and DDR are not started.

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

## Build

```bat
cd /d <repo-root>
fpga\scripts\build_top_cam_id.bat
```

- TD 6.2.1 command-line flow, not the GUI Run (its generated `run.bat` is broken).
- Output: `build/bitstream/top_cam_id.bit`.
- Design-specific reports: `top_cam_id_route.qor`, `top_cam_id_final_timing.rpt`.

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

## Debug ladder

Do not skip levels.

1. **LED heartbeat**: LED1 blinks → clock C4 and configuration are alive.
2. **Four LEDs**: `top_led_test.bit` → all physical LED1–4 on.
3. **Pin path**: `top_sccb_pin_test.bit` → SCL/SDA toggle on J2-32/33.
4. **Protocol**: `top_cam_id.bit` → LED2/3/4 on; logic analyzer decode
   `0x3C W 30 0A [SR] 0x3C R 56` and `30 0B ... 40`.
5. **DVP**: capture PCLK/VSYNC/HREF first; configure registers if no output.

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
