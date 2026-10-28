# DVP three-channel capture — 2026-10-26

> **2026-10-28 correction.** The timing in this file is still valid, but three
> labels need correction:
>
> - PCLK is **48.000 MHz**, not 50 MHz. The 0.5 s capture has 24,000,131
>   rises = 48.000 MHz; 20 ns was the 200 MS/s quantization. The SDC 50 MHz
>   constraint is conservative.
> - HREF high is **40 µs = 1920 PCLK**, low is **26.665 µs = 1280 PCLK**
>   (at 48 MHz), not 2000 PCLK.
> - **HREF polarity is not proven.** The 1280-PCLK low phase allows
>   `HREF_ACTIVE_HIGH=0` + `EXPECTED_PIX=1280` to pass, but the 1920-PCLK high
>   phase could be "1280 active + 640 dummy" (datasheet active high). LED4 off
>   on the 16:24 build only proves the length check, not pixel data. The
>   2026-10-28 11-channel attempt failed to resolve this; see
>   `verification/board/evidence/20261028_dvp_11ch/README.md` §3.4.
>
> The 16:24 original binary (SHA `506e01ad…`) was overwritten by the
> 2026-10-28 12:33 debug build. A same-RTL/QoR rebuild is
> `build/bitstream/top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18…`),
> not bit-identical. The 13:16 bitstream used for this 15:47 capture (SHA
> `8f320bbd…`) is also overwritten; its same-RTL/QoR rebuild is
> `build/bitstream/top_dvp_test_20261026_3ch_rebuild.bit` (SHA `fb3b3b84…`,
> Setup +10.245 ns / Hold +0.054 ns / 800 slices). Use the 3ch rebuild to
> re-test this capture; use the 16:24 rebuild for the HREF-low/color-bar
> diagnostic.

## 1. Setup

- Board: PH1P35_FT V1 / HX1P35B_FT_40P, PH1P35MDG324.
- Camera: ATK-MC5640 (OV5640), 8-bit DVP.
- Bitstream: `build/bitstream/top_dvp_test.bit`, 2026-10-26 13:16:11,
  SHA-256 `8f320bbd...e8bd` (`0x4740=0x22`, 50 MHz SDC,
  `VSYNC_ACTIVE_HIGH=0`, `EXPECTED_PIX=2000`).
- Raw LA export: `verification/LA/DVP_10_26_15_47.csv` (2.3 GB, local only;
  not committed). 200 MHz, 95.367432 M samples, 0.5 s, 48,003,864 rows.
- Analysis scripts: `tools/analyze_la_csv.pl`,
  `tools/find_long_href.pl`.

## 2. LED observation

- LED1: 1 Hz heartbeat.
- LED2: steady on (`cfg_ok`, configuration + readback passed).
- LED3: frame toggle (frames are arriving).
- LED4: steady on (error sticky).

## 3. Old 0x23 observation (before this CSV)

- Old config `0x4740=0x23`, old capture parameter `VSYNC_ACTIVE_HIGH=1`.
- LA showed VSYNC **idle high, short low pulse** (active low), which already
  contradicted the datasheet bit0=1 = active high definition.
- That old bitstream had LED2 on, LED3 toggling, LED4 on (then attributed to
  `EXPECTED_PIX=1280` vs the measured 2000 HREF-high bytes).

## 4. New 0x22 CSV result (definitive)

Channel mapping: Ch0 = PCLK (J2-7), Ch1 = VSYNC (J2-21), Ch2 = HREF (J2-20).

| Item | Measured |
|---|---|
| PCLK | **50 MHz** (rise period ~20 ns; 24,000,131 rises in 0.5 s) |
| VSYNC initial level | **1** (capture starts during a high pulse) |
| VSYNC high | **66.665 µs** (n=15) |
| VSYNC low | **33.266 ms** (n=15) |
| VSYNC period | **33.333 ms** (30 Hz) |
| VSYNC polarity | **Active high**: idle low, 66.665 µs high pulse |
| HREF typical high | **39.995–40 µs** (60% of the line) |
| HREF low | **26.665–26.670 µs** |
| HREF period | **66.665 µs** (15 kHz) |
| HREF-high PCLK, typical | **~2000** (min 1920; max 65920 outlier) |
| HREF rises per frame | **480** (between VSYNC rises; 15 full intervals) |
| Long HREF high | **1.373 ms once per frame** |
| Long HREF high vs VSYNC | starts **240 µs before VSYNC rise**, ends
  **1.066 ms after VSYNC fall**; the VSYNC pulse is inside HREF high |

### 4.1 Polarity inversion

- Old `0x23`: idle high, short low → **active low**.
- New `0x22`: idle low, short high → **active high**.
- The OV5640/ATK module behaves **inverted** relative to the datasheet
  `0x4740[0]` definition (bit0=1 documented active high, measured active low;
  bit0=0 documented active low, measured active high). The ST driver
  observation (active-low VSYNC) matches the old `0x23` measurement.
- Therefore the FPGA parameter must match the measured pin:
  - `0x23` + `VSYNC_ACTIVE_HIGH=0` (active low), or
  - `0x22` + `VSYNC_ACTIVE_HIGH=1` (active high).
- The current bitstream uses `0x22` + `VSYNC_ACTIVE_HIGH=0`, so the FPGA
  treats the pin as active low while it is actually active high. The
  normalized `vsync_act = ~pin` is high for most of the frame; the frame
  boundary is taken at the **pin fall** (end of the high pulse).

### 4.2 Why LED4 is on

This is **not** a 480-vs-500 line-count problem:

- HREF rises per frame is exactly **480** between VSYNC edges.
- The HREF long high is one of those 480 HREF pulses, not an extra 500th line.
- The long high spans the VSYNC pulse and the vertical blanking. It produces a
  line event with ~65,920 PCLK (instead of the normal ~2000), so
  `EXPECTED_PIX=2000` flags a line-length error.
- In addition, the normalized `vsync_rise` occurs at the pin fall, which is
  **inside** the long HREF high. `dvp_capture`'s `vsync_mid_line` check
  therefore sets every frame.
- Both errors are sticky, so LED4 stays on.

The long HREF high likely contains the last active line's data at its start
(before the VSYNC pulse) followed by vertical blanking. The exact active
window needs D0–D7 and a color-bar pattern to confirm.

## 5. Result

- Three-channel timing (PCLK/VSYNC/HREF) is **confirmed** and the capture is
  producing frames.
- The earlier "480 vs 500" hypothesis is **disproven**: the line count is 480.
- The remaining issues are:
  1. VSYNC polarity pair mismatch (`0x22` active high vs parameter 0).
  2. HREF is high during the VSYNC/vertical blanking; the capture treats the
     long high as a line and flags VSYNC-during-HREF.
- The 2000-byte HREF-high vs 640-pixel/1280-byte active width is still open.

## 6. Design implications / next actions

1. Choose one consistent VSYNC polarity pair:
   - `0x23` + `VSYNC_ACTIVE_HIGH=0` (matches the old/ST active-low behavior), or
   - `0x22` + `VSYNC_ACTIVE_HIGH=1` (minimal change to the current config).
   Do not leave `0x22` + parameter 0.
2. Do **not** change `EXPECTED_LINES` to 500; keep 480.
3. Handle the vertical-blanking HREF high in `dvp_capture`:
   - do not flag VSYNC-during-HREF as a fatal error when HREF is high for the
     known blanking window;
   - clamp/ignore the long high's extra bytes (or classify it as blanking)
     after the active window is identified with D0–D7.
4. Build `COLOR_BAR=1`; capture D0–D7 + PCLK/HREF/VSYNC (11 channels; the LA
   supports up to 32) and inspect:
   - whether the first 2000 bytes of the long HREF high are valid color-bar
     data;
   - the RGB565 byte order;
   - where the 1280-byte active window sits inside the 2000-byte HREF high.
5. Rebuild with the corrected polarity/blanking handling and re-check LED4.

### 6.1 Diagnostic build — 2026-10-26 16:24

Per user request, keep `0x4740=0x22`, set VSYNC active high, test HREF active
low first, expect 1280 bytes/line, keep 480 lines, enable color bar.

| Item | Value |
|---|---|
| Bitstream | `build/bitstream/top_dvp_test.bit` |
| Built | **2026-10-26 16:24:00** |
| Size | 1,789,487 bytes (1,748 KiB; fixed image size) |
| SHA-256 | `506e01ad1a2a442894ef92c5e4db398344becbdd4d26154ff81c743de5cca07a` |
| `COLOR_BAR` | 1 (`0x503D=0x80`) |
| `VSYNC_ACTIVE_HIGH` | 1 (`0x22` measured active high) |
| `HREF_ACTIVE_HIGH` | 0 (active-low test) |
| `EXPECTED_PIX` | 1280 |
| `EXPECTED_LINES` | 480 |

Simulation passed: color-bar config readback `0x503D=0x80`; HREF-active-low /
VSYNC-active-high capture at 50 MHz with 1280-byte lines.

Predicted LED4:

- The 1.373 ms HREF blanking high is **inactive** with HREF active low, so it
  should no longer be counted as a 65,920-byte line and `vsync_mid_line`
  should not trigger.
- At 48 MHz the low phase is **26.665 µs = 1280 PCLK**, exactly the
  `EXPECTED_PIX=1280` value (the earlier ~1333 figure used 50 MHz). So the
  length check should pass.
- **User report (2026-10-26): LED4 off.** This proves the low phase contains
  1280 PCLK, **not** that those 1280 bytes are valid pixel data. If HREF is
  actually active high (datasheet `0x22` bit1=1), the low phase is blanking
  and this is a false pass. The color-bar/D0–D7 two-phase comparison is still
  required; see `verification/board/evidence/20261028_dvp_11ch/README.md` §3.4.

## 7. Limitations

- The raw CSV is 2.3 GB and is kept local only; it is not committed.
- The LA sample grid is 5 ns; PCLK edge periods show 20–21 ns quantization.
- D0–D7 were not captured; the active data position inside the long HREF high
  is not yet known.
- The ST driver/register inversion is an empirical observation on this
  module/board, not a datasheet guarantee.
