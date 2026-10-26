# AGENTS.md

> Canonical project guide for any AI/agent session working in this repository.
> Read this before changing RTL, constraints, docs, or making verification claims.
> **Last updated: 2026-10-24**

## 1. Mission

Build a working pipeline:

```text
ATK-MC5640 (OV5640, 8-bit DVP) -> PH1P35 FPGA -> HDMI display
```

Board: PH1P35_FT V1 / HX1P35B_FT_40P, device **PH1P35MDG324**.
Tools: Anlogic Tang Dynasty **6.2.1**; ModelSim SE-64 2020.4 for simulation.

## 2. Current state

| Milestone | Status |
|---|---|
| Schematic / wiring documentation | Done |
| Minimal TD project + build flow | Done |
| SCCB Chip ID read | **Verified on board: 0x5640** |
| DVP capture RTL + simulation | **Passed (24 MHz full 480-line frame; 48/50 MHz quick regressions)** |
| RGB565 config + readback | **Simulation passed; TD build passed** |
| DVP board three-channel | **Passed (timing): PCLK 50 MHz, HREF active high, VSYNC active low, 30 fps** |
| DVP counter sanity (LED4) | **Open: LED4 still on after the 2000-byte rebuild** |
| DVP color bar / D0–D7 | Not started (next) |
| HDMI output | Not started |
| DDR frame buffer | Not started |

Board evidence:

- LED1 blinks (heartbeat), LED2/3/4 steady on.
- Logic analyzer decode:
  - `0x3C W 0x30 0x0A [SR] 0x3C R 0x56 NA`
  - `0x3C W 0x30 0x0B [SR] 0x3C R 0x40 NA`
- Evidence: `verification/board/evidence/20261024_sccb_chip_id/`

DVP capture simulation (not board evidence):
`verification/static/dvp_capture_sim_2026-10-26.md`.
Config/readback + TD build:
`verification/static/top_dvp_test_build_2026-10-26.md`.

**DVP three-channel verified on board:** PCLK 50 MHz, HREF active high
(15 kHz, 40 µs high = 2000 PCLK), VSYNC active low (30 Hz, 33.33 ms),
~500 lines/frame. Evidence:
`verification/board/evidence/20261026_dvp_three_channel/`.

**Open:** after re-programming the rebuilt bitstream (`0x22`, 50 MHz,
`EXPECTED_PIX=2000`), **LED4 is still on**. The timing validation passed, but
the line/frame counter still mismatches; likely `EXPECTED_LINES=480` vs ~500
HREF lines/frame, or a sticky line error.

**Next: diagnose LED4, then color bar + D0–D7 byte order**, and resolve why
HREF high carries 2000 bytes while the configured active RGB565 width is 640
pixels (1280 bytes). Bitstream: `build/bitstream/top_dvp_test.bit`.
Procedure: `verification/board/bringup-dvp-three-channel.md`.
See also §10 and `docs/camera/README.md`.

## 3. Read order

1. This file.
2. `README.md` — project overview and current status.
3. `TASKS.md` — checkboxes, blockers, change log.
4. `docs/hardware/wiring.md` — canonical pin/wiring table.
5. `verification/board/bringup-sccb-id.md` — current board bring-up procedure.
6. `verification/static/top_cam_id_build_2026-10-24.md` — last verified build results.
7. `.claude/skills/fpga-bringup/SKILL.md` — build/debug workflow.

## 4. Source of truth

| Topic | File |
|---|---|
| Wiring / pins | `docs/hardware/wiring.md` |
| Progress / blockers | `TASKS.md` |
| Build workflow | `fpga/README.md` + skill |
| Board evidence | `verification/board/evidence/` |
| Timing/build results | `verification/static/` |
| Project rules | this file |

Do not create a second pin table elsewhere. Link to `wiring.md` instead.

## 5. Critical pin facts (do not regress)

These have already caused bugs. Full table: `docs/hardware/wiring.md`.

| Signal | FPGA ball | Connector |
|---|---|---|
| 50 MHz clock | **C4** | — |
| User LED0..3 | **D10, E10, C6, D6** | physical LED1..4 |
| SCCB SCL | R6 | J2-32 |
| SCCB SDA | T5 | J2-33 |
| Camera RESET | U7 | J2-34 |
| Camera PWDN | U6 | J2-35 |
| Camera GND | — | J2-30 |
| Camera 3.3V | — | J2-29 |
| DVP PCLK | F14 | J2-7 |
| DVP VSYNC | K16 | J2-21 |
| DVP HREF | K17 | J2-20 |
| DVP D0..D7 | K15, K13, L15, L16, P10, P9, P8, R7 | J2-22..28, J2-31 |

Other facts:

- **A5 is GPIOA32, not a user LED.**
- **LED14 is the power indicator**, not FPGA-controlled.
- **J2-11 is 5 V**; never connect camera 3.3 V there.
- Camera P1: 1 GND, 2 3.3V, 3 SCL, 4 VSYNC, 5 SDA, 6 HREF, 7 D0,
  8 RESET, 9 D2, 10 D1, 11 D4, 12 D3, 13 D6, 14 D5, 15 PCLK, 16 D7,
  17 PWDN, 18 NC.

## 6. Build, simulate, program

### Build

```bat
rem one-time: point to your TD 6.2.1 install
setx TD_HOME "C:\path\to\TD_6.2.1"

cd /d <repo-root>
fpga\scripts\build_top_cam_id.bat
```

Outputs (git-ignored):

- `build/bitstream/top_cam_id.bit`
- `build/bitstream/top_cam_id_route.qor`
- `build/bitstream/top_cam_id_final_timing.rpt`

DVP config/capture top:

```bat
fpga\scripts\build_top_dvp_test.bat
```

Outputs: `build/bitstream/top_dvp_test.bit`, `top_dvp_test_route.qor`,
`top_dvp_test_final_timing.rpt`. `cam_pclk` is constrained at the measured
**50 MHz**; input delays (10/2 ns) are still provisional. Latest QoR:
Setup +10.245 ns, Hold +0.054 ns, 800 slices.

The script calls `td_commands_prompt.exe` and runs
`read_hdl -> read_adc -> optimize_rtl -> read_sdc -> optimize_gate -> place -> route -> bitgen`.

### Simulation

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
The testbench uses **SCCB_DIV=250** to match hardware timing.

Config/readback: `fpga/sim/tb/tb_ov5640_bringup.v` (DIV=10 for speed) checks
0x4300=0x61, 0x4740=0x22, 640x480 geometry and readback.
DVP capture: `fpga/sim/tb/tb_dvp_capture.v`; results in
`verification/static/dvp_capture_sim_2026-10-26.md`. It now parameterises
HREF/VSYNC polarity; active-high, active-low VSYNC, and both-low combinations
pass (quick 16-line runs).

### Program

BitWizard (`TD/bin/bw.exe`) -> Refresh -> Add bit file -> **Program SRAM** -> Run.
Use Program Flash only after SRAM verification.

### Known tool limitation

TD 6.2.1 on this machine generates a broken project `run.bat`
(`td_commands_prompt_commands_prompt.exe`). Do **not** rely on GUI Run.
Use the command-line build scripts. `top_cam_id.al` is for viewing/editing.

TD may rewrite `<Project Path="...">` to an absolute path when opened.
Restore `Path="."` before committing the `.al`.

## 7. Verification rules

Never conflate these levels:

1. Schematic checked.
2. ModelSim simulation passed.
3. TD synthesis/place/route/timing passed.
4. Bitstream generated.
5. Programmed on board.
6. Functional result observed with evidence.

A claim at level N does not imply level N+1.

### Current LED semantics (top_cam_id)

| Physical LED | Meaning |
|---|---|
| LED1 | 1 Hz heartbeat |
| LED2 | SCCB read transaction completed |
| LED3 | high byte == 0x56 |
| LED4 | full Chip ID == 0x5640 |

After a successful one-shot read the design stops in `S_OK`; **SCL/SDA idle high is normal**.
Arm the logic analyzer before reset to capture the burst.

### Evidence

Put board evidence under:

```text
verification/board/evidence/YYYYMMDD_<topic>/
```

Each evidence directory needs a `README.md` with setup, date, bitstream,
capture settings, observed result, and limitations. Do not fabricate measurements.

## 8. Collaboration protocol

- Start every session by reading this file and `TASKS.md`; state the current milestone.
- Update `TASKS.md` checkboxes and change log when something is actually verified.
- Update `README.md` status when a milestone changes.
- Keep docs in Chinese, identifiers/paths in ASCII.
- Keep RTL comments ASCII to avoid tool encoding differences.
- Do not commit PDFs, bitstreams, TD logs, `build/`, or generated databases.
- Use relative paths in docs and project files.
- Do not duplicate pin tables; link to `docs/hardware/wiring.md`.
- Do not change verified RTL behavior without re-running simulation, TD build,
  and (where applicable) board verification.
- Commit messages: `<type>: <summary>`; follow the session's attribution rules.
- Before changing pin mappings, verify with:
  `pdftotext -table` on the schematic + high-DPI crop + board test.
  Do not trust `-layout` or a thumbnail alone.

## 9. Pitfalls learned

1. **Start pulse across divider ticks**: the SCCB master only sampled `start`
   on the divider tick; the reader pulsed it for one 50 MHz cycle. At DIV=250
   the pulse was missed. Fixed with `start_pending`. Simulation must use DIV=250.
2. **SCCB final NACK is NA**, not an error. OV5640 does ACK address/data bytes
   in the captured transactions.
3. **Read uses repeated START**; do not insert STOP between register address and read.
4. **SCCB is 50 kHz** in `top_cam_id` for margin.
5. **One-shot success leaves SCL/SDA high**; that is idle, not a hang.
6. **LED/clock labels in the PDF are offset** in `-layout`/thumbnails.
   `-table` and high-DPI crops are authoritative.
7. **Report filenames must be per-design**; otherwise one build overwrites another's QoR.

## 10. Next milestone: DVP

**Detailed handoff: `docs/project/dvp-handoff.md`.** Read it before starting.

Three rules for this stage:

1. **Short pulses / short-duration signals matter.**
   PCLK may be faster than the 50MHz system clock; HREF/VSYNC widths are measured
   in PCLK cycles. Do not sample a one-cycle pulse only on a divided tick.
   Latch/synchronize single-cycle events; use an async FIFO/handshake for
   multi-bit data across PCLK/system domains. The SCCB `start` bug is the warning.
2. **Re-check PDF pin alignment.**
   `-layout`/thumbnails have already produced one-row-off errors (J2 GND/SCL,
   clock C4 vs D4, LED A5). Use `pdftotext -table` + high-DPI crops +
   pin-capability/board-silkscreen cross-checks. Update `wiring.md`, never create
   a second pin table.
3. **Simulation must reproduce real timing.**
   Use the real PCLK frequency, real HREF/VSYNC blanking/pulse widths, and real
   CDC/reset behavior. Do not use DIV=2 or a simplified same-clock model and call
   it verified. A testbench that only passes because timing was simplified is
   not evidence.

Order of work:

1. **Done:** DVP receiver (`dvp_capture.v`), asynchronous event FIFO, 50 MHz
   monitor, and a real-timing testbench. See
   `verification/static/dvp_capture_sim_2026-10-26.md`.
2. **Done:** RGB565 configuration/readback (`ov5640_cfg.v`,
   `ov5640_cfg_rom.v`), explicit `0x4740=0x22`, `top_dvp_test.v`, constraints,
   TD build and bitstream. See
   `verification/static/top_dvp_test_build_2026-10-26.md`.
3. **Three-channel passed (2026-10-26):** PCLK 50 MHz; HREF active high,
   15 kHz / 66.67 µs / 40 µs high = 2000 PCLK; VSYNC active low, 30 Hz /
   33.33 ms; ~500 lines/frame. Config `0x4740=0x22`; capture uses
   `HREF_ACTIVE_HIGH=1`, `VSYNC_ACTIVE_HIGH=0`; SDC uses 50 MHz.
   Evidence: `verification/board/evidence/20261026_dvp_three_channel/`.
4. **Next:** rebuild with `COLOR_BAR=1`, probe D0–D7, verify RGB565 byte order,
   and resolve the 2000-byte HREF-high vs 1280-byte active width. Then HDMI.
5. HDMI output after DVP data is stable. DDR frame buffer is out of scope for now.

Polarity (measured 2026-10-26): **HREF active high, VSYNC active low**. The
configuration writes `0x4740=0x22`; the earlier `0x23` (VSYNC active high)
did not match the LA waveform. The `dvp_capture` instance uses
`HREF_ACTIVE_HIGH=1`, `VSYNC_ACTIVE_HIGH=0`. See
`docs/camera/README.md` §2.1. Do not change these three places independently.

References: datasheet and ALIENTEK links are recorded in
`docs/camera/README.md`; the PDF and third-party code stay out of the public
repository.

Acceptance for DVP: repeatable frame/line counters and data that matches a known
camera configuration, with real-timing simulation + board evidence.

## 11. File map

```text
AGENTS.md                         this guide
README.md                         overview / status
TASKS.md                          tasks / blockers / change log
.claude/skills/fpga-bringup/      reusable build/debug skill
docs/hardware/wiring.md           canonical wiring/pin table
docs/project/dvp-handoff.md       DVP stage handoff and warnings
docs/camera/README.md             OV5640 refs, registers, redistribution rules
docs/hardware/*.pdf               vendor schematics (local, ignored)
fpga/rtl/top/top_cam_id.v         current bring-up top
fpga/rtl/camera/sccb_master.v     SCCB master
fpga/rtl/camera/ov5640_id_reader.v power-up + ID read
fpga/rtl/camera/dvp_capture.v     PCLK-domain DVP capture + counters
fpga/rtl/camera/dvp_status_monitor.v  50 MHz event monitor
fpga/rtl/common/async_fifo_gray.v Gray-pointer CDC event FIFO
fpga/rtl/camera/ov5640_cfg.v      RGB565 config + readback sequencer
fpga/rtl/camera/ov5640_cfg_rom.v  generated config table (249 entries)
fpga/rtl/camera/ov5640_bringup.v  power/ID/config wrapper
fpga/rtl/top/top_dvp_test.v       DVP board bring-up top
fpga/constraints/top_cam_id.adc   minimal SCCB/ID constraints
fpga/constraints/top_dvp_test.adc/.sdc  DVP board constraints
fpga/scripts/build_top_cam_id.*   SCCB/ID build flow
fpga/scripts/build_top_dvp_test.* DVP board build flow
fpga/sim/tb/tb_top_cam_id.v       SCCB/ID testbench
fpga/sim/tb/tb_ov5640_bringup.v   config/readback testbench
fpga/sim/tb/tb_dvp_capture.v      real-timing DVP testbench
verification/board/bringup-sccb-id.md
verification/board/bringup-dvp-three-channel.md
verification/board/evidence/      board captures
verification/static/              build/timing/simulation summaries
verification/static/dvp_capture_sim_2026-10-26.md
verification/static/top_dvp_test_build_2026-10-26.md
```
