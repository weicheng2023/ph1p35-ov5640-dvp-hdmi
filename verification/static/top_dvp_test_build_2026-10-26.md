# top_dvp_test build — 2026-10-26

> **2026-10-28 correction.** PCLK is **48.000 MHz**, not 50 MHz; HREF high is
> **40 µs = 1920 PCLK**, low is **26.665 µs = 1280 PCLK** (not 2000 PCLK).
> HREF polarity is still **A/B unresolved**: low 1280 PCLK (active low) vs high
> 1920 PCLK = 1280 active + 640 dummy (datasheet active high). The 16:24
> original binary (SHA `506e01ad…`) was overwritten by the 2026-10-28 12:33
> debug build; a same-RTL/QoR rebuild is
> `build/bitstream/top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18…`,
> not bit-identical). The 16:24 LED4-off report only proves the length check,
> not pixel data; see `verification/board/evidence/20261028_dvp_11ch/`.

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
| `cam_pclk` | SDC 50.000 MHz; **measured 48.000 MHz (20.833 ns)** |
| Period-check WNS | no violations |

The first build (2026-10-26, before the board measurement) used a provisional
48 MHz PCLK constraint: Setup +11.108 ns, Hold +0.050 ns, 813 slices. The final
build uses a conservative **50 MHz** PCLK constraint (measured 48.000 MHz) and
the corrected VSYNC polarity.

Input delays remain provisional: `-max 10 ns`, `-min 2 ns` relative to
`cam_pclk`. Update after a dedicated camera-to-FPGA arrival measurement.

The `set_clock_groups -asynchronous` constraint was accepted by TD; no
unconstrained cross-domain path was reported.

## 4. Configuration deviations

- The generated table has 249 entries (reference 250 entries, minus the two
  dummy `0x300A/0x300B` writes, plus explicit `0x4740`).
- `0x4740=0x22`: PCLK/HREF active high; **VSYNC active HIGH** on this module
  (idle low, 66.665 µs high pulse). `0x23` measured **active low** (idle high,
  low pulse). The bit0 effect is **inverted** relative to the datasheet.
  The current bitstream uses `0x22` + `VSYNC_ACTIVE_HIGH=0`, which is
  inconsistent; the next build must use `0x22` + parameter 1 or `0x23` +
  parameter 0.
- `0x503D` is `0x80` when `COLOR_BAR=1`, otherwise `0x00`.
- `0x3808..0x380F` come from `H_PIX`, `V_PIX`, `H_TOTAL`, `V_TOTAL`.
  Current defaults: 640, 480, 1600, 1000. Historical note: this 13:16 build
  used `EXPECTED_PIX=2000` on the assumption of 50 MHz / 2000-PCLK HREF high.
  **Corrected 2026-10-28:** PCLK 48.000 MHz; HREF high 1920 PCLK, low 1280
  PCLK. The low phase is exactly the 1280 active bytes (A), but the high-phase
  "1280 active + 640 dummy" interpretation (B) is not excluded. See the top
  note and the 2026-10-28 evidence.
- The 1 ms delay after `0x3008=0x82` is implemented in `ov5640_cfg.v`.
- `top_dvp_test.v` uses `VSYNC_ACTIVE_HIGH=0` and `EXPECTED_PIX=HREF_PCLK=2000`.
  The parameter/config pair is being corrected; `EXPECTED_LINES=480` is
  confirmed by the LA (480 HREF rises per frame).

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

1. LED4 cause identified from the 2026-10-26 CSV: the VSYNC polarity pair is
   inconsistent (`0x22` is active high, parameter 0), and HREF has a 1.373 ms
   long high during vertical blanking that spans the VSYNC pulse. The line
   count is **480**, not 500. Fix the polarity pair and add blanking handling.
2. Build a `COLOR_BAR=1` bitstream and probe D0–D7 to locate the active window
   inside the 2000-byte HREF high, resolve the 2000-vs-1280 byte question, and
   verify RGB565 byte order. Then rebuild and re-check LED4.

## 8. Diagnostic build — 2026-10-26 16:24

Requested diagnostic: keep `0x4740=0x22`, set VSYNC active high, test HREF
active low, expect 1280 bytes/line, keep 480 lines, enable color bar.

| Item | Value |
|---|---|
| Bitstream | original was `build/bitstream/top_dvp_test.bit`; now preserved/rebuilt as `top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18…`) |
| Built | **2026-10-26 16:24:00** |
| Size | 1,789,487 bytes (1,748 KiB; fixed device image size) |
| SHA-256 | `506e01ad1a2a442894ef92c5e4db398344becbdd4d26154ff81c743de5cca07a` |
| `COLOR_BAR` | **1** (`0x503D=0x80`) |
| VSYNC | **active high** (`VSYNC_ACTIVE_HIGH=1`, measured `0x22`) |
| HREF | **active low** (`HREF_ACTIVE_HIGH=0`, first test) |
| `EXPECTED_PIX` | **1280** (640 RGB565 pixels) |
| `EXPECTED_LINES` | **480** |
| QoR | Setup +10.381 ns, Hold +0.038 ns, 800 slices (3.77%) |

Simulation before build:

- `tb_ov5640_bringup.v` with `COLOR_BAR=1`: PASS; `0x4740=0x22`,
  `0x503D=0x80`, 640x480.
- `tb_dvp_capture.v` at 50 MHz, HREF active low, VSYNC active high, 1280-byte
  lines: PASS (`pix_min=pix_max=1280`, 0 errors).

Predicted board behavior:

- LED2 on: color-bar config + readback passed.
- LED3 toggling: 480 active-low lines/frame are being counted.
- The 1.373 ms HREF blanking **high** is inactive with HREF active low, so it
  should no longer produce a 65,920-byte line or VSYNC-in-HREF error.
- LED4: at 48 MHz the HREF low phase is **26.665 µs = 1280 PCLK**, exactly
  `EXPECTED_PIX=1280`, so the length check passes. **User report (2026-10-26):
  LED4 off.** This does not prove the low phase contains valid pixels: if HREF
  is actually active high (datasheet `0x22` bit1=1), the low phase is blanking
  and the length check still passes. Compare D0–D7 in both phases for the
  8-color bar; do not treat LED4 as proof.
