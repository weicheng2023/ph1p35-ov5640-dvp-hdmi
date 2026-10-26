# DVP capture simulation — 2026-10-26

## 1. Scope

This is **simulation evidence**, not board evidence. It validates:

- PCLK-domain sampling of D[7:0]/HREF/VSYNC;
- RGB565 byte pairing (high byte first) and byte-sequence correctness;
- line/frame/pixel counters and event generation;
- Gray-pointer asynchronous event FIFO from PCLK to 50 MHz;
- 50 MHz event monitor and error flags;
- setup/hold sensitivity of the chosen sampling edge.

It does **not** validate:

- the actual OV5640 register configuration or readback;
- the actual PCLK frequency, HREF/VSYNC polarity, or blanking widths;
- the color-bar data path on the board;
- TD synthesis/place/route/timing;
- anything on hardware.

## 2. Files

| File | Role |
|---|---|
| `fpga/rtl/common/async_fifo_gray.v` | dual-clock Gray-pointer FIFO |
| `fpga/rtl/camera/dvp_capture.v` | PCLK-domain capture and counters |
| `fpga/rtl/camera/dvp_status_monitor.v` | 50 MHz event consumer/checker |
| `fpga/sim/tb/tb_dvp_capture.v` | real-timing camera model and checker |

## 3. Tool and commands

Tool: ModelSim SE-64 2020.4.

Run from `build/sim`:

```tcl
vlib work
vlog ../../fpga/rtl/common/async_fifo_gray.v \
     ../../fpga/rtl/camera/dvp_capture.v \
     ../../fpga/rtl/camera/dvp_status_monitor.v \
     ../../fpga/sim/tb/tb_dvp_capture.v
vsim -c -do "run -all; quit" work.tb_dvp_capture
```

Quick regression (real PCLK and line length, smaller frame):

```tcl
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
     -do "run -all; quit" work.tb_dvp_capture
```

Mutation tests (must FAIL):

```tcl
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
     -do "run -all; quit" work.tb_dvp_capture +LAUNCH_POSEDGE
vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 -gINVERT_DUT_PCLK=1 \
     -do "run -all; quit" work.tb_dvp_capture
```

## 4. Results

### 4.1 Quick regression, 24 MHz

Parameters: `PCLK_PERIOD=41.667 ns`, `H_ACTIVE=1280`, `V_ACTIVE=16`,
`V_BACK=2`, `V_FRONT=1`.

```text
TB: PASS - frames=3 lines_in_frame=0 pix_min=1280 pix_max=1280 events=35
          bytes_err=0 setup_err=0 hold_err=0
```

### 4.2 Quick regression, 48 MHz

Parameters: `PCLK_PERIOD=20.833 ns`, other parameters as above.

```text
TB: PASS - frames=3 lines_in_frame=0 pix_min=1280 pix_max=1280 events=35
          bytes_err=0 setup_err=0 hold_err=0
```

### 4.2b Measured 50 MHz and polarity regressions

After the board measurement (PCLK 50 MHz, HREF active high, VSYNC active low),
16-line quick runs at `PCLK_PERIOD=20.0 ns`:

| HREF polarity | VSYNC polarity | Result |
|---|---|---|
| high | high | PASS |
| high | **low (board)** | PASS |
| low | low | PASS |

All with `bytes_err=0 setup_err=0 hold_err=0`.

### 4.3 Full frame, 24 MHz

Parameters: `PCLK_PERIOD=41.667 ns`, `H_ACTIVE=1280`, `H_BLANK=300`,
`V_ACTIVE=480`, `V_BACK=18`, `V_FRONT=6`, `STARTUP_FRAMES=1`.

```text
TB: PASS - frames=3 lines_in_frame=0 pix_min=1280 pix_max=1280 events=963
          bytes_err=0 setup_err=0 hold_err=0
Time: 66626563336 ps
```

`events=963` = 3 frame-start events + 2 complete frames × 480 line events.
`lines_in_frame=0` at the end because the third frame-start event has just
reset it; `frame_ok=1` confirms the previous frame's line count.

Note: the first version of this TB omitted horizontal blanking between active
lines (it only used `H_BLANK` for vertical blanking lines). The results above
are from the corrected TB where the line period is `H_ACTIVE + H_BLANK`.

### 4.3b Full board-like frame, measured 50 MHz

Parameters matching the 2026-10-26 LA capture:

- `PCLK_PERIOD=20.0 ns` (50 MHz)
- `H_ACTIVE=2000`, `H_BLANK=1333` (line period 3333 PCLK = 66.66 µs)
- `V_ACTIVE=480`, `V_BACK=14`, `V_FRONT=4`, `VSYNC_WIDTH=2*line`
  (500 lines/frame = 33.33 ms)
- `VSYNC_ACTIVE_HIGH=0` (measured active low)

```text
TB: PASS - frames=3 lines_in_frame=0 pix_min=2000 pix_max=2000 events=963
          bytes_err=0 setup_err=0 hold_err=0
Time: 66660770 ns
```

This is the closest RTL-level reproduction of the measured board timing.

### 4.4 Mutation: data launched on the sampling edge

```text
TB: FAIL - ... bytes_err=0 setup_err=0 hold_err=40836 events=35
```

The byte sequence still happens to be correct because the data is stable for a
full period; the setup/hold monitor catches the hold violation. This is the
intended result.

### 4.5 Mutation: DUT samples on the opposite edge

`-gINVERT_DUT_PCLK=1`:

```text
TB: FAIL - ... bytes_err=0 setup_err=0 hold_err=40836 events=35
```

Again the sequence checker alone would not catch it; the hold monitor does.

## 5. Assumptions and limitations

These values are **placeholder assumptions**, not board measurements:

- Board measurement 2026-10-26: PCLK = **50 MHz**, HREF active high
  (40 µs high = 2000 PCLK), VSYNC active low (30 Hz). The TB now also runs at
  `PCLK_PERIOD=20.0 ns` and with both polarities.
- The TB now inserts `H_BLANK` PCLK cycles between active lines, so the line
  period is `H_ACTIVE + H_BLANK`. The earlier version did not; do not use its
  timing numbers as line-period evidence.
- `H_ACTIVE = 1280` is the configured RGB565 active width (640 pixels). The
  board's HREF high actually carries 2000 PCLK; the 720-byte difference
  (dummy/padding vs different width) is not modeled or resolved yet.
- Section 4.3b uses the measured board structure: 3333 PCLK/line, 500
  lines/frame, 50 MHz, VSYNC active low.
- `V_ACTIVE = 480`, `V_BACK = 18`, `V_FRONT = 6` remain test structure for the
  24 MHz full-frame run; the board-like run uses 14/4.
- `T_SETUP_NS = T_HOLD_NS = 5 ns`; the OV5640 DVP AC table has not been
  transcribed into the TB yet.
- The camera model is a source-synchronous RTL model; it does not model
  metastability, ringing, or board skew.

The full 480-line run uses real PCLK frequency and a realistic line/frame
structure, but the blanking values are derived from the datasheet's example
timing table and must be replaced with measured values.

## 6. Next steps

Done since this document was first written:

1. `ov5640_cfg.v` + readback, `top_dvp_test.v`, constraints and TD bitstream.
2. Board three-channel measurement: PCLK 50 MHz, HREF active high, VSYNC
   active low, ~500 lines/frame.
3. Simulation re-run with the measured values (section 4.3b).

Next:

4. Add the color-bar mode (`0x503D=0x80`), probe D0–D7, and verify RGB565 byte
   order.
5. Resolve the 2000-byte HREF-high vs 1280-byte active width.
6. Then HDMI timing.
