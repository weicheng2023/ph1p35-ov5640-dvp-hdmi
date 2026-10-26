# top_dvp_test build — 2026-10-26

## 1. Scope

This is a TD 6.2.1 build result, not board evidence. The bitstream has not been
programmed on the board at the time of writing.

The design includes:

- power-up/reset + OV5640 Chip ID read (`ov5640_id_reader`);
- RGB565 configuration + readback (`ov5640_cfg`, `ov5640_cfg_rom`);
- PCLK-domain DVP capture + Gray-pointer event FIFO + 50 MHz monitor;
- LED status: heartbeat, `cfg_ok`, frame toggle, error.

## 2. Build

Command:

```bat
set TD_HOME=<TD 6.2.1 install>
fpga\scripts\build_top_dvp_test.bat
```

or directly:

```bat
td_commands_prompt.exe fpga/scripts/build_top_dvp_test.tcl
```

Outputs (git-ignored):

- `build/bitstream/top_dvp_test.bit`
- `build/bitstream/top_dvp_test_route.qor`
- `build/bitstream/top_dvp_test_final_timing.rpt`

## 3. Results

| Metric | Value |
|---|---|
| Device | PH1P35MDG324, speed 3 |
| Slices | 800 (3.77%) |
| RAMs / DSPs | 0 / 0 |
| Setup WNS | **+10.245 ns** |
| Hold WNS | **+0.054 ns** (tight, but no violations) |
| `clk_50m` | 50.000 MHz |
| `cam_pclk` | **50.000 MHz (measured, 20.000 ns)** |
| Period-check WNS | no violations |

The first build (2026-10-26, before the board measurement) used a provisional
48 MHz PCLK constraint: Setup +11.108 ns, Hold +0.050 ns, 813 slices. The final
build uses the measured **50 MHz** PCLK and the corrected VSYNC polarity.

Input delays remain provisional: `-max 10 ns`, `-min 2 ns` relative to
`cam_pclk`. Update after a dedicated camera-to-FPGA arrival measurement.

The `set_clock_groups -asynchronous` constraint was accepted by TD; no
unconstrained cross-domain path was reported.

## 4. Configuration deviations

- The generated table has 249 entries (reference 250 entries, minus the two
  dummy `0x300A/0x300B` writes, plus explicit `0x4740`).
- `0x4740=0x22`: PCLK/HREF active high, **VSYNC active low**. This matches the
  2026-10-26 LA capture. The earlier `0x23` did not match the VSYNC waveform.
- `0x503D` is `0x80` when `COLOR_BAR=1`, otherwise `0x00`.
- `0x3808..0x380F` come from `H_PIX`, `V_PIX`, `H_TOTAL`, `V_TOTAL`.
  Current defaults: 640, 480, 1600, 1000. The measured PCLK is 50 MHz; the
  measured HREF-high count is 2000 PCLK, so `EXPECTED_PIX` is now 2000 while
  the configured active width remains 640 (1280 bytes). The 720-byte
  difference is unresolved (dummy/padding vs different width).
- The 1 ms delay after `0x3008=0x82` is implemented in `ov5640_cfg.v`.
- `top_dvp_test.v` uses `VSYNC_ACTIVE_HIGH=0` and `EXPECTED_PIX=HREF_PCLK=2000`.

## 5. Verification done before build

- `tb_ov5640_bringup.v`: PASS at `SCCB_DIV=10`; checks Chip ID 0x5640,
  0x4300=0x61, 0x4740=0x22, 0x3808/09=0x02/0x80, 0x380A/0B=0x01/0xE0,
  0x503D=0x00, and PLL readback values.
- `tb_top_cam_id.v`: PASS at `SCCB_DIV=250` (existing regression).
- `tb_dvp_capture.v`: PASS for the full 480-line frame at 24 MHz and for the
  board-like full frame at 50 MHz (2000-byte lines, 3333 PCLK/line,
  VSYNC active low); setup/hold mutations fail as intended.

## 6. Not verified

- D0–D7 byte order and the active 1280-byte window inside the 2000-byte
  HREF-high line.
- Whether the extra 720 bytes are dummy/padding or a different active width.
- Color-bar data.
- HDMI/DDR (out of scope).

The three-channel timing (PCLK/VSYNC/HREF) is now verified on board; see
`verification/board/evidence/20261026_dvp_three_channel/`.

## 7. Next step

1. The rebuilt `top_dvp_test.bit` was re-programmed on 2026-10-26. **LED4 is
   still on**: the line/frame counter still mismatches. Likely
   `EXPECTED_LINES=480` vs ~500 HREF lines/frame, or a sticky line error.
   Diagnose before the color-bar test.
2. Build a `COLOR_BAR=1` bitstream and probe D0–D7 to resolve the active width
   and byte order.
