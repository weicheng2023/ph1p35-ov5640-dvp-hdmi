# DVP three-channel capture — 2026-10-26

## 1. Setup

- Board: PH1P35_FT V1 / HX1P35B_FT_40P, PH1P35MDG324.
- Camera: ATK-MC5640 (OV5640), 8-bit DVP.
- Bitstream: `build/bitstream/top_dvp_test.bit` (top_dvp_test, COLOR_BAR=0).
- Build evidence: `verification/static/top_dvp_test_build_2026-10-26.md`.
- Procedure: `verification/board/bringup-dvp-three-channel.md`.

Probes (as reported; **channel-to-pin mapping not yet confirmed**):

- PCLK should be J2-7 (F14).
- VSYNC should be J2-21 (K16).
- HREF should be J2-20 (K17).
- D0–D7 were not probed in this round.

## 2. LED observation

Reported by the user after programming:

- LED1: normal blink (1 Hz heartbeat).
- LED3: normal blink (frame counter toggling; frames are arriving).
- LED2: steady on (`cfg_ok`).
- LED4: steady on (error status).

Interpretation:

- LED2 on means the RGB565 configuration and key-register readback passed.
- LED3 toggling means the PCLK domain is capturing frame events.
- LED4 on is expected when the actual line/pixel count differs from the
  monitor's default `EXPECTED_PIX=1280`, `EXPECTED_LINES=480`, or when a line
  error / event-FIFO overflow occurs. It is not by itself a configuration
  failure.

## 3. LA screenshots

### 3.1 `la_frame_33ms.png` (frame-scale window)

Displayed measurements:

- One channel (blue): period about **33.33 ms** (30 Hz).
- Another channel (green): period **33.3331 ms**, **30 Hz**, duty **99.80%**.
- One channel (purple): appears steady high in this window.

### 3.2 `la_line_67us.png` (line-scale window)

Displayed measurements:

- One channel (blue): period **66.67 µs**, frequency **15 kHz**, duty **60.00%**.
- One channel (green): high time **40 µs**, period **66.67 µs**.

### 3.3 `la_50mhz_20ns.png` (PCLK-scale window)

Displayed measurements:

- One channel (blue): period **20 ns**, frequency **50 MHz**, duty **50.00%**.
- One channel (purple): 10 ns high / 20 ns period measurement visible.

## 4. Confirmed mapping and measurements (2026-10-26)

User-confirmed LA channel mapping:

| LA channel | Signal | J2 | FPGA ball |
|---|---|---|---|
| Channel 0 (D0) | **PCLK** | J2-7 | F14 |
| Channel 1 (D1) | **VSYNC** | J2-21 | K16 |
| Channel 2 (D2) | **HREF** | J2-20 | K17 |

Measured values:

| Item | Value | Notes |
|---|---|---|
| PCLK | **50 MHz** (20 ns, 50% duty) | Channel 0 |
| VSYNC period / frame rate | **33.33 ms / 30 Hz** | Channel 1 |
| VSYNC polarity | **Active low**: idle high, short low pulse | observed in frame-scale capture |
| HREF period / line rate | **66.67 µs / 15 kHz** | Channel 2 |
| HREF high time | **40 µs (60%)** | Channel 2 |
| HREF high in PCLK cycles | **2000** (40 µs × 50 MHz) | derived |
| Total lines per frame | **500** (33.33 ms / 66.67 µs) | derived |
| Active lines | expected 480; not independently counted this round | |

## 5. Result: PASS

The three-channel validation is considered **passed** (user confirmation):

- LED1 heartbeat and LED3 frame toggle are normal.
- LED2 is on: RGB565 configuration and key-register readback succeeded.
- LED4 was on with the first bitstream: the default `EXPECTED_PIX=1280` did not
  match the measured HREF-high count of 2000.
- After re-programming the rebuilt bitstream (`0x22`, 50 MHz SDC,
  `EXPECTED_PIX=2000`), **LED4 is still on**. The three-channel timing
  validation remains passed; the remaining mismatch is in the line/frame
  counter. The most likely cause is `EXPECTED_LINES=480` versus the capture
  counting ~500 HREF lines per frame (if HREF continues through vertical
  blanking), or another line-error sticky bit. This is open.
- PCLK, VSYNC and HREF are present, repeatable, and at expected 3.3 V/2.8 V
  logic levels.

## 6. Remaining discrepancy: HREF-high bytes vs active width

The measured line has **2000 PCLK-high cycles**, while the configured RGB565
active width is 640 pixels = **1280 bytes**. The extra 720 bytes are not yet
identified. They may be:

- OV5640 dummy/padding bytes inside HREF high;
- a different active width than the 640 written to 0x3808/0x3809;
- a format/byte-packing difference.

This is the next thing to resolve with D0–D7 and a color-bar pattern. It does
not invalidate the three-channel timing measurement.

## 7. Design updates from this measurement

- `0x4740` is now **`0x22`**: PCLK/HREF active high, **VSYNC active low**.
  The earlier `0x23` (VSYNC active high) did not match the measured waveform.
- `top_dvp_test.v` now uses `VSYNC_ACTIVE_HIGH=0`,
  `EXPECTED_PIX=HREF_PCLK=2000`, `EXPECTED_LINES=480`.
- `top_dvp_test.sdc` now constrains `cam_pclk` at **50 MHz**.
- The DVP capture TB now has polarity parameters; active-high, active-low
  VSYNC, and both-low combinations all pass.
- Bitstream rebuilt: Setup WNS **+10.245 ns**, Hold WNS **+0.054 ns**,
  800 slices (3.77%).

The rebuilt bitstream was re-programmed on 2026-10-26. LED4 remains on, so the
line/frame counter mismatch is still open.

## 8. Limitations

- D0–D7 were not probed; the 2000-vs-1280 byte question is open.
- VSYNC pulse width was not independently measured.
- No color-bar test yet.
- The updated bitstream still needs a board re-check (LED4 should clear if the
  line/frame counts now match).

## 9. Next steps

1. Diagnose LED4 with the rebuilt bitstream: confirm whether HREF runs through
   vertical blanking (capture line count ~500 vs active 480), and whether the
   monitor's line/frame error or `EXPECTED_LINES` is the cause.
2. Build a `COLOR_BAR=1` bitstream; probe D0–D7.
3. Verify RGB565 byte order and identify the active 1280-byte window inside the
   2000-byte HREF-high line.
4. Then move to HDMI timing.
