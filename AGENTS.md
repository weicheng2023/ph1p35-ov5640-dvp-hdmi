# AGENTS.md

> Canonical project guide for any AI/agent session working in this repository.
> Read this before changing RTL, constraints, docs, or making verification claims.
> **Last updated: 2026-11-09**

## 1. Mission

Build a working pipeline:

```text
ATK-MC5640 (OV5640, 8-bit DVP) -> PH1P35 FPGA -> HDMI display
```

Board: PH1P35_FT V1 / HX1P35B_FT_40P, device **PH1P35MDG324**.
Tools: Anlogic Tang Dynasty **6.2.1**; ModelSim SE-64 2020.4 for simulation.

## 2. Current state

**2026-11-09 superseding DDR update — STAGE 2 BOARD FUNCTIONAL PASS
(user report):** native PAXI address units are 16-bit words, ADDR_STEP=8 for
128-bit blocks, active-high write mask=0000 for full writes. AW accepted ->
WVALID next cycle (hold until WREADY). Behavioural model now checks
alignment, mask and handshake; old +1 / FFFF rejected. 12 required ModelSim
cases PASS; CRC `F53A4D4F`. DDR-source pixel mutation exposed a gearbox FIFO
pop one-cycle delay; fixed without changing HDMI PHY, timing, PLL, CAL_EN=0,
50 MHz reference or SDC. Final bitstream:
`top_ddr_fb_hdmi_paxi_fix_20261109.bit`, SHA
`e83d9c544b9a0fd3d8ed547f0ada82eb95be19a4693c2431bf4f069d72ba5a16`,
TD Setup +0.110 / Hold +0.020 ns, 5283 slices; check_timing warnings remain.
The user programmed it and confirmed the FPGA test image -> DDR -> HDMI
display. LED/CRC/photo details were not provided; record it as
**USER-REPORTED BOARD FUNCTIONAL PASS**, not as full PHY calibration.
Old 2026-11-08 +1/FFFF version failed on board (red screen, LED3 off,
LED4 on); keep as diagnostic history. Use
`verification/board/bringup-ddr-fb-hdmi-paxi-fix.md`; sim evidence
`verification/static/ddr_fb_hdmi_paxi_fix_sim_2026-11-09.md`; board evidence
`verification/board/evidence/20261109_ddr_fb_hdmi_paxi_fix/README.md`.

| Milestone | Status |
|---|---|
| Schematic / wiring documentation | Done |
| Minimal TD project + build flow | Done |
| SCCB Chip ID read | **Verified on board: 0x5640** |
| DVP capture RTL + simulation | **Passed (24 MHz full 480-line frame; 48/50 MHz quick regressions)** |
| RGB565 config + readback | **Simulation passed; TD build passed** |
| DVP board three-channel | **Re-verified 2026-11-06:** VSYNC 30 Hz/33.333 ms, HREF 15 kHz/40 µs high; PCLK needs 200/250 MS/s (50 MS/s aliases) |
| DVP counter sanity (LED4) | 16:24 `HREF_ACTIVE_HIGH=0` + 1280 LED4 off (user report), but **LED4 checks length only, not pixel data** |
| HREF polarity | **Unresolved A/B:** low phase = 1280 PCLK; high = 1920 PCLK. Must compare D0–D7 in both phases |
| DVP diagnostic build (HREF low + color bar) | 16:24 original SHA `506e01ad…` overwritten; rebuilt same RTL/QoR as `top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18…`); color-bar copy `top_dvp_test_20261106_colorbar.bit` |
| DVP 3-channel recheck (2026-11-06) | **Passed:** `2026_11_6_PCLK_VSYNK_HREF.atkdl`; 30 Hz VSYNC, 15 kHz HREF, 480 lines; 50 MS/s PCLK alias only |
| DVP 11-channel / camera color bar | **Paused:** 3-channel sync recheck passed; camera color bar is deferred, not the current task |
| HDMI display color bar | **User-reported board PASS (2026-11-08):** FPGA internal 8-bar displayed. Evidence is the user's verbal report; **no photo/log/voltage/LA data**. |
| OV5640 line -> HDMI | **PARTIAL PASS (2026-11-08 user report):** single-line capture and HDMI display connected; LEDs correct; image is one repeated line but shows a left black band + right light blue/purple, **not** the expected 8-bar pattern; pixel correctness unconfirmed. Setup +6.027 ns / Hold +0.020 ns, 821 slices, 1 ERAM. |
| HDMI output (camera path) | Single-line PARTIAL PASS (image connected, pixels unconfirmed); full camera frame path not started |
| DDR frame buffer | **CAL_EN=1: LED1 blink, LED2 on, LED3 off, LED4 on** (READY missing). **CAL_EN=0 control board: LED1 blink, LED2 on, LED3 on, LED4 off** → READY reachable with PHY training bypassed; data reliability NOT proven. No calibration-failure cause claimed. |
| DDR frame buffer -> HDMI test image | **STAGE 2 — BOARD FUNCTIONAL PASS (2026-11-09 user report).** Independent `top_ddr_fb_hdmi` (`CAL_EN=0`, experimental): 16-beat self-check → 38400 single-beat 128-bit writes → full-frame readback pixel compare + actual-data CRC → prefill → VSYNC-aligned display. PAXI ADDR_STEP=8, active-high mask `0000`, WVALID one cycle after AW. Final bitstream `e83d9c54…`, Setup +0.110 / Hold +0.020 ns, 5283 slices. User confirmed the test image displays; LED/CRC details not provided. |

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

**DVP three-channel verified on board (timing):** PCLK **48.000 MHz**, not
50 MHz. The 0.5 s capture has 24,000,131 rises = 48.000 MHz; 20 ns was the
sampling quantization. VSYNC is 30 Hz / 33.333 ms; `0x22` produces
**active-high** VSYNC (idle low, 66.665 µs high), while `0x23` produces
**active-low**. The `0x4740[0]` effect is **inverted** relative to the
datasheet on this module. HREF is 15 kHz / 66.665 µs; high 40 µs =
**1920 PCLK**, low 26.665 µs = **1280 PCLK**. Line count is **480**
HREF rises/frame, not 500. Evidence:
`verification/board/evidence/20261026_dvp_three_channel/`.

**HREF polarity is still unresolved (A/B).** LED4 off on the 16:24 build
(`HREF_ACTIVE_HIGH=0`, `EXPECTED_PIX=1280`, user report) only proves the
line length/line count match, not that pixels are valid. Two interpretations
both pass the length check:

- A. HREF active low: the 1280-PCLK low phase is the 1280 active bytes; the
  1920-PCLK high phase is blanking.
- B. HREF active high (datasheet `0x22` bit1=1): the first 1280 bytes of the
  1920-PCLK high phase are active, the last 640 are dummy; the 1280-PCLK low
  phase is blanking. The active-low build would capture blanking and still
  see 1280 bytes.

Do not declare HREF polarity/data success from LED4 alone. Capture D0–D7 and
compare both HREF phases for the 8-color bar.

**2026-10-28 11-channel attempt failed.** The 13:58 capture still shows the
15 kHz / 1280-byte HREF envelope (active-low assumption) but CH2 has 12–16 ns
PCLK crosstalk during the high phase, CH1 is only 4 ns spikes (not VSYNC),
and D0–D7 are all zero. The 14:36 HREF-only capture is a stable **29.53 kHz**
(30.856 µs high / 3.002 µs low / 33.858 µs period). This is a different state,
not jitter inside one capture. Leading hypothesis: the camera was re-plugged/
reset and reverted to its default 1280×960 timing (~41.5 MHz, 30.8 fps);
`ov5640_bringup` only configures once, so the FPGA did not re-run SCCB.
Grounding can explain the glitches but cannot by itself synthesize a stable
29.53 kHz. Evidence:
`verification/board/evidence/20261028_dvp_11ch/README.md`.

**2026-11-06 three-channel recheck passed.** `2026_11_6_PCLK_VSYNK_HREF.atkdl`
(50 MS/s, 200 ms, 3 channels, threshold 1.6 V) shows VSYNC **30 Hz /
33.333 ms / 66.66 µs high**, HREF **15 kHz / 39.997 µs high / 26.66 µs low**,
479 normal lines/frame (480 effective). The 2026-10-28 29.53 kHz anomaly did
**not** reproduce. Caveat: 50 MS/s is below Nyquist for 48 MHz; PCLK appears
as a **2 MHz alias** and is only consistent with 48 MHz, not a direct
measurement. The color-bar capture must use **200/250 MS/s**. Evidence:
`verification/board/evidence/20261106_dvp_3ch_recheck/README.md`.

**Bitstreams (local, gitignored):** the 12:33 failed debug build (SHA
`893dc3fa…`) is preserved as `top_dvp_test_fail_20261028_dbg_893dc3fa.bit`.
The original 16:24 binary (SHA `506e01ad…`) was overwritten by the 12:33
build and is not recoverable; it was rebuilt from the same RTL/QoR as
`top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18…`, Setup +10.381 ns /
Hold +0.038 ns / 800 slices). This is **not bit-identical** to the original.
The color-bar copy is `top_dvp_test_20261106_colorbar.bit` (same SHA). Do not
overwrite these files.

**DVP is paused; the current task is the independent HDMI color bar (no camera).**
The camera color-bar test (D0–D7 both HREF phases) is deferred. Do not change
camera registers or DVP RTL during this phase.

**2026-11-07 HDMI color-bar design (sim/build passed, board not run):**

- HDMI1 is a **source/output**: the board supplies +5V on connector pin 18
  through D5 (MBR0520); HPD is driven by the sink and read by the FPGA;
  DDC is level-shifted from 3.3V (FPGA) to 5V (connector). Schematic
  evidence: `verification/board/evidence/20261107_hdmi_pin_review/`.
- TMDS pairs (corrected, `pdftotext -table` + high-DPI crops):
  **G16/H16 (D0), F17/E18 (D1), H14/H13 (D2), C17/D18 (CLK)**.
  `VCCIO_32 = VCC_3V3`. Do not use the old H16/F17, E18/H14 combinations.
- Board has **8 x 49.9 Ω pull-ups to `+3.3V_HDMI`**, one per TMDS line.
  `HDMI_A_5V` (D5 -> pin 18) and `HDMI_A0_5V` (U46 -> F3 -> D6) are
  **different nets**. D6 feeds `HDMI_A0_5V` back into HPD, so **HPD can
  latch high** after the first plug-in; power-cycle to re-test "unplugged".
  `+3.3V_HDMI` is switched from `VCC_3V3` by Q17 (gate pulled up by
  `VCC_5V`); its loaded voltage must be measured.
- **No local HDMI Transmitter IP** exists in TD 6.2.1. The third-party
  `.enc` HDMI core is not copied, modified or redistributed. The design is
  a self-written DVI-compatible TMDS encoder + 10:1 DDR serializer using
  `PH1P_LOGIC_ODDR`, with `PH1P_PHY_PLL_V2` generating 25.0 MHz / 125 MHz
  from 50 MHz (C0 feedback, VCO=1250 MHz).
- RTL: `fpga/rtl/display/` + `fpga/rtl/top/top_hdmi_colorbar.v`.
  Constraints: `top_hdmi_colorbar.adc/.sdc`. Build:
  `fpga/scripts/build_top_hdmi_colorbar.bat`.
- Simulation (4/4 PASS): `verification/static/hdmi_colorbar_sim_2026-11-07.md`.
  TD build: `verification/static/top_hdmi_colorbar_build_2026-11-07.md`
  (Setup +5.170 ns / Hold +0.054 ns / 107 slices, 0.50%).
  `check_timing` HIGH-severity items are 0; the only MEDIUM item is
  8 outputs without output delay (4 LEDs + 4 TMDS). There is a
  `PHY-5016 PLL clkc ... not driving a clock-capable IO` warning; the
  routed clk1 paths reach `opclk` and meet timing, but the IO must be
  confirmed on the board.
- **Board test is NOT done.** Follow
  `verification/board/bringup-hdmi-colorbar.md`; record results in
  `verification/board/evidence/20261107_hdmi_colorbar/`. Never mark PASS
  before the monitor actually shows the 8 bars.
- Bitstream (local, gitignored): `build/bitstream/top_hdmi_colorbar.bit`,
  SHA-256 `60fb0d0de3aabe36285e1d3cb6ea82bff5e88e271ae18f6374081931c908ef63`.
- **2026-11-08 board result (USER REPORT):** the user programmed
  `top_hdmi_colorbar.bit` and the monitor displayed the FPGA internal
  8 bars. **No photo, log, voltage or LA data was provided.** Record this
  as a user-reported PASS only; it does not prove the camera path, the
  TMDS electrical margins, or the exact monitor mode. Evidence:
  `verification/board/evidence/20261107_hdmi_colorbar/README.md`.
- **2026-11-08 board result (USER REPORT, PARTIAL PASS):** the user
  programmed `top_ov5640_line_to_hdmi.bit`; LED1 heartbeat, LED2 cfg_ok,
  LED3 capture_done, LED4 off all matched. The HDMI monitor showed one
  camera line repeated over 480 rows, but the picture was a wide black
  band on the left and a large light-blue/purple area on the right, **not
  the expected OV5640 internal 8-color bar**. Pixel content, byte order,
  HREF A/B window and +/-1-pixel alignment remain **unconfirmed**. The
  user chose to stop color-bar/LA debugging and move to DDR. Record this
  as PARTIAL PASS only:
  `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`.
- **Current task: stage 2 DDR frame buffer.** Do not rewrite the proven
  PLL/TMDS/HDMI timing. First build an independent DDR init/calibration/
  read-write test; then FPGA test image -> DDR -> HDMI; then OV5640 ->
  DDR double buffer -> HDMI. DDR hardware is now confirmed below; the
  remaining unknown is board calibration, not the part type.
- **2026-11-08 implementation (sim/build passed; board PARTIAL PASS):**
  - `fpga/rtl/camera/ov5640_line_capture.v`: PCLK byte counter,
    `CAPTURE_START` window (0 or 640), RGB565 high/low pairing,
    `BYTE_SWAP`, `LINE_MIN/MAX` blanking filter, one write-pipeline
    register, `capture_done` freeze.
  - `fpga/rtl/common/line_buffer_dpram.v`: 640x16 dual-clock RAM,
    inferred as 1 ERAM.
  - `fpga/rtl/display/rgb565_to_rgb888.v`,
    `fpga/rtl/top/ov5640_line_to_hdmi_core.v`,
    `fpga/rtl/top/top_ov5640_line_to_hdmi.v`.
  - Sim 3/3 PASS: 65,920-cycle blanking rejected, 1920-cycle line accepted,
    CAP_START 0/640, BYTE_SWAP, core 8 bars.
    Evidence: `verification/static/ov5640_line_to_hdmi_sim_2026-11-08.md`.
  - TD build: 50/48.001/25/125 MHz; Setup **+6.027 ns**, Hold
    **+0.020 ns** (tight), 821 slices, 1 ERAM. `check_timing` has one
    HIGH dummy node `cam_sda.ts` (SCCB inout; the same code passed the
    board Chip-ID read), one MEDIUM `cam_sda` no input delay, and 12
    MEDIUM no-output-delay (4 TMDS + 4 LEDs + 4 camera controls).
    Evidence: `verification/static/top_ov5640_line_to_hdmi_build_2026-11-08.md`.
  - Bitstream (local): `build/bitstream/top_ov5640_line_to_hdmi.bit`,
    SHA-256 `67eec013651ccdde7291e3e26d1ec1a506e92111076651f0a49cf7ff0e3222cd`.
  - **Board result: PARTIAL PASS (user report).** See
    `verification/board/evidence/20261108_ov5640_line_hdmi/README.md`.
    Single-line display connected; pixel content not proven.
  - DDR report: `docs/display/ddr-investigation.md` (updated). Datasheet
    §2.12 confirms PH1P35MDG324 has **in-package 16-bit 512Mb SDRAM**
    (64 MB, VCCIO_DDR 1.5 V); there is no external DDR chip page. The TD
    IP `MIS_DDRF6F1D0P0_1.1` `Integrated` mode for MDG324 selects
    **DDR2 512Mb x16** (`DDR2_512M`, `DDR2_X16`,
    `ddrphy_cfg_rom_MDG324.txt`, `ap111_ddr2_x16_324.adc`). Reference
    project `build/ref/anlogic-ph1p35-vision` targets the same device;
    its cfg ROM/matrix files are byte-identical to the TD MDG324 files
    and use `DDR2_1066`, tCK=1876, CL=7, CWL=6. Board calibration and
    read/write are still **BOARD_MEASUREMENT_REQUIRED**.
  - **2026-11-08 minimal DDR test (sim/build passed; board result + debug):**
    `fpga/rtl/ddr/ddr2_top.v` (50 MHz ref, PLL N=3/M=64/C=2/CLK3=21,
    CAL_EN=1), `fpga/rtl/ddr/ddr_axi_pattern_test.v` (native `paxi_*`,
    16 x 128-bit write/read/compare), `fpga/rtl/top/top_ddr_test.v`.
    ModelSim 3/3 PASS (normal, READY_DELAY=2, CORRUPT=1). TD: Setup
    **+0.913 ns**, Hold **+0.020 ns** (tight), 3389 slices, 0 RAM,
    31 DRAMHARDCON; bitstream SHA
    `610b0b1fe491ded30d8837a8d12ecef7a31780303161d81d32cdda7473751fd5`.
    A vendor PHY `usr_clk -> clk_50m` CDC path was mis-reported as a
    synchronous path; appending a single-group `set_clock_groups` for
    `ddr_clk/usr_clk/ctl_clk/mcu_clk/ref_clk` to the IP SDC fixed it
    (before: Setup -1.390 / Hold -0.239). `check_timing` still has the
    vendor PLL dummy nodes, a 533.600-vs-533.333 rounding warning, and
    22/49 no input/output delays (in-package DDR/slow outputs).
    Evidence: `verification/static/top_ddr_test_build_2026-11-08.md`,
    `verification/static/ddr_test_sim_2026-11-08.md`; board steps
    `verification/board/bringup-ddr-test.md`; evidence dir
    `verification/board/evidence/20261108_ddr_test/`.
  - **2026-11-08 board result (USER):** `top_ddr_test.bit` (SHA
    `610b0b1f…`) programmed; LED1 blinks, **LED2/LED3/LED4 all off**.
    This is consistent with `ddrphy_rdy` never high: `ddr_ready=0` keeps
    the pattern FSM in `ST_IDLE`, and `ST_IDLE` intentionally has no
    timeout, so LED4 cannot light. `ddrphy_rst_n` was not brought out, so
    PLL-lock vs calibration could not be distinguished. Do **not** claim a
    calibration-failure cause yet.
  - **2026-11-08 debug top:** `top_ddr_debug` + `ddr_status_debug`:
    LED1 heartbeat, LED2=`ddrphy_rst_n` (2FF), LED3=`ddrphy_rdy` (2FF),
    LED4=independent 50 MHz 1 s timeout (latched); AXI/APB tied off; no
    transactions; explicit `PH1P_LOGIC_BUFG`. Status sim 3/3 PASS. TD:
    Setup **+1.446 ns**, Hold **+0.020 ns**, 1960 slices, 7
    DRAMHARDCON; bitstream SHA
    `03339cf5905009f7c037fc44fd7bec44e775fb29dbbac47de8912865ceef0d46`.
    `check_timing` still reports 6 HIGH no-clock SCLK nets (including
    `ddrphy_fiu_wrapper/apb_pclk`), one PLL dummy node, the 533.600 vs
    533.333 rounding warning, and `USR-6133` (primary clock on the PLL
    internal refclk). This is **not** a timing sign-off; do not hide it.
    Use `DDR_CAL0=1` for the CAL_EN=0 control only if LED2=1/LED3=0/
    LED4=1; CAL_EN=0 does not prove data reliability.
  - **2026-11-08 CAL_EN=1 board result (USER):** LED1 blink, LED2 on,
    LED3 off, LED4 on (checked >10 s). So `ddrphy_rst_n` is released but
    `ddrphy_rdy` never arrives within 1 s. **CAL_EN=0 control built:**
    `top_ddr_debug_cal0.bit`, SHA
    `f3facdf8130d8a2d905b2684e6b06b9259ac73742fd21b0ec7033a23ba73c1a0`,
    Setup +2.073 / Hold +0.021 ns, 1290 slices, 7 DRAMHARDCON. Only
    `CAL_EN` changed 1→0 via `-define DDR_CAL0`; PLL/ref/tCK/CL/CWL/
    reset/SDC/LED/AXI-APB unchanged; the 1960→1290 slice difference is
    the omitted `if (CAL_EN == 1'b1)` cal generate block. Cal RTL files
    remain in the 38-file list. Original `top_ddr_test.bit`
    (`610b0b1f…`) and `top_ddr_debug.bit` (`03339cf5…`) preserved.
    `check_timing` CAL0: 4 HIGH no-clock (CAL1 6; SDC unchanged),
    1 PLL dummy, 533.600 vs 533.333, USR-6133; not a timing sign-off.
    **CAL0 board result (USER): LED1 blink, LED2 on, LED3 on, LED4 off**
    → READY is reachable only with PHY training bypassed. This does not
    prove data reliability; the self-check + frame readback CRC below are
    the data evidence.
    Evidence: `verification/static/top_ddr_debug_cal0_build_2026-11-08.md`,
    `verification/board/bringup-ddr-debug.md`,
    `verification/board/evidence/20261108_ddr_debug/`,
    `docs/display/ddr-debug.md`.
  - **2026-11-08 first DDR frame-buffer implementation (historical; failed on
    board, superseded 2026-11-09):**
    independent `top_ddr_fb_hdmi` (no camera, no changes to existing tops)
    with `ddr2 #(.CAL_EN(0))` (EXPERIMENTAL; training bypassed).
    Flow: 16-beat native-paxi self-check -> 38400 single-beat 128-bit writes
    (frame base beat 4096, 80 beats/row, 600 KiB) -> conservative 1024-cycle
    DRAIN (not a write-completion claim) -> full-frame readback with
    per-pixel compare against `fb_pattern` and CRC-32 computed from the
    **actual read data** -> FIFO prefill 192 words -> `video_valid` armed on
    a VSYNC falling edge -> 128-bit x 256 async FIFO (Gray pointers) ->
    8:1 gearbox -> proven 640x480 HDMI/TMDS chain.
    RTL: `fpga/rtl/ddr/{fb_pattern,crc32_16,fb_writer,fb_reader,pixel_gearbox}.v`,
    `fpga/rtl/fb/ddr_fb_hdmi_core.v`, `fpga/rtl/top/top_ddr_fb_hdmi.v`.
    ModelSim 3/3 PASS: normal and `READY_DELAY=2` both
    `crc_actual=crc_expected=0xF53A4D4F`; injected 1-bit error at beat 4100
    gives `err_addr=4100`, `crc_actual=0x306B3F2A`, `error_code=3`, no video
    start. HDMI first-frame checks at line 10/32/33 (8 bars, border, marker,
    grid) pass; no underflow/overflow.
    TD: Setup **+0.163 ns**, Hold **+0.021 ns** (tight), 5116 slices
    (24.11%), 0 RAM, 0 DSP, 100 DRAMHARDCON; `check_timing` HIGH: no-clock 0,
    invalid constraint 0, 2 dummy nodes (unused PHY output + dangling
    `pllreset`), 533.600-vs-533.333 rounding; MEDIUM 22 input / 53 output
    no-delay. Bitstream SHA
    `3cde314aec03dd68756628172a0bbc73e478b304091f9b436838f7998723ed58`.
    SDC audit: the only `usr_clk <-> pixel_clk` crossings are the Gray FIFO
    and 2FF synchronizers; a design-level two-group async constraint is
    reported INVALID/redundant by TD against the vendor IP single group, and
    replacing the vendor group makes vendor IP timing fail (Setup -2.467).
    Do not remove the vendor IP group to "clean up" warnings.
    Evidence: `verification/static/ddr_fb_hdmi_sim_2026-11-08.md`,
    `verification/static/top_ddr_fb_hdmi_build_2026-11-08.md`;
    board steps `verification/board/bringup-ddr-fb-hdmi.md`; evidence dir
    `verification/board/evidence/20261108_ddr_fb_hdmi/` (failed: red screen,
    LED3 off, LED4 on). **Do not claim DDR/PHY calibration passed from this
    build.**

  - **2026-11-09 PAXI fix + board pass (current):** the 128-bit PAXI address
    step is **8** native 16-bit words (not 1), and the write mask is
    **active-high** (`16'h0000` = write all bytes; `1` = masked). AW must be
    accepted first; WVALID follows one cycle later and is held until WREADY.
    The behavioural model now enforces alignment, mask polarity, AW->W
    timing, backpressure payload stability; the old +1/FFFF cases fail.
    A DDR-source pixel mutation test exposed a gearbox FIFO pop one cycle
    late at 8-pixel block boundaries; fixed in `pixel_gearbox.v`.
    Error screens: red=self-check, orange=writer, magenta=readback/CRC,
    yellow=FIFO/stream, dark blue=waiting; image comes only from the FIFO.
    Final bitstream SHA `e83d9c54…`; **user confirmed the complete test image
    -> DDR -> HDMI displays on board (2026-11-09, USER-REPORTED FUNCTIONAL
    PASS).** Keep CAL_EN=0/50 MHz/PLL/TMDS/SDC unchanged; no full PHY
    calibration or long-term reliability claim.

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
`top_dvp_test_final_timing.rpt`.

HDMI color-bar top (independent, no camera):

```bat
fpga\scripts\build_top_hdmi_colorbar.bat
```

Outputs: `build/bitstream/top_hdmi_colorbar.bit`,
`top_hdmi_colorbar_route.qor`, `top_hdmi_colorbar_final_timing.rpt`,
`top_hdmi_colorbar_route.check_timing`. The build script runs
`derive_clocks` in the SDC and uses `PH1P_PHY_PLL_V2`.

OV5640 single-line -> HDMI top:

```bat
fpga\scripts\build_top_ov5640_line_to_hdmi.bat
```

Outputs: `build/bitstream/top_ov5640_line_to_hdmi.bit`,
`top_ov5640_line_to_hdmi_route.qor`,
`top_ov5640_line_to_hdmi_final_timing.rpt`,
`top_ov5640_line_to_hdmi_route.check_timing`.
`cam_pclk` is constrained at **48 MHz (20.833 ns)** for this design.

`cam_pclk` is constrained at **50 MHz**
(conservative; measured **48.000 MHz**); input delays (10/2 ns) are still
provisional. The 2026-10-26 16:24 diagnostic was Setup +10.381 ns / Hold
+0.038 ns / 800 slices, SHA-256 `506e01ad...cca07a`; that binary was
overwritten on 2026-10-28 12:33 and is rebuilt as
`top_dvp_test_20261026_rebuild.bit` (SHA `b6df6c18...`, not bit-identical).

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

### HDMI color-bar simulation

The HDMI design uses **behavioural** PLL/ODDR models, not the encrypted
vendor models:

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

Expected: `TB: PASS - top_hdmi_colorbar`. The separate encoder,
serializer and full-frame timing TBs are listed in
`verification/static/hdmi_colorbar_sim_2026-11-07.md`.
Do **not** compile `fpga/rtl/display/pll_hdmi.v` together with
`pll_hdmi_sim.v` (both define module `pll_hdmi`).

PLL configuration check against TD's own functional model:

```tcl
vlog -sv $TD_HOME/sim_release/ph1p/ph1p_phy_pll_v2.v \
         fpga/sim/tb/tb_pll_vendor.v
vsim -c -do "run -all; quit" work.tb_pll_vendor
```

Expected: `TB: PASS - pll_vendor (25.0/125.0 MHz, lock)`. The model is a
functional configuration check, not silicon jitter/lock evidence.

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
Run also with `-gCAP_START=640` and `-gSWAP=1`.

Core integration (behavioural PLL/ODDR models):

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

Expected: `TB: PASS - top_ov5640_line_to_hdmi`. The SCCB bring-up is
**not** re-simulated here (`cfg_ok` is tied high); it is covered by
`tb_ov5640_bringup`. The synthetic camera stream is 48 MHz, HREF high
1920 / low 1280, with the 65,920-cycle blanking line tested separately.

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
3. **Three-channel passed (2026-10-26):** PCLK **48.000 MHz**; HREF 15 kHz /
   66.665 µs, high 40 µs = 1920 PCLK, low 26.665 µs = 1280 PCLK; VSYNC 30 Hz /
   33.333 ms. `0x22` is measured **active high** (idle low, 66.665 µs high);
   `0x23` is **active low**. The bit0 effect is inverted vs the datasheet. Line
   count is **480** HREF rises/frame; one HREF high is 1.373 ms (vertical
   blanking) and spans the VSYNC pulse. Evidence:
   `verification/board/evidence/20261026_dvp_three_channel/`.
4. **2026-10-28 11-channel attempt failed:** HREF/VSYNC unstable; D0–D7 not
   captured. The 14:36 HREF-only capture is 29.53 kHz, likely the camera
   default 1280×960 mode after a reset/re-plug, not grounding alone. See
   `verification/board/evidence/20261028_dvp_11ch/README.md`.
5. **2026-11-06 three-channel recheck passed:** VSYNC 30 Hz/33.333 ms,
   HREF 15 kHz/39.997 µs high; 50 MS/s PCLK is a 2 MHz alias. The 29.53 kHz
   anomaly did not reproduce. See
   `verification/board/evidence/20261106_dvp_3ch_recheck/README.md`.
6. **DVP paused after the 2026-11-06 recheck.** The camera color-bar test
   (D0–D7 both phases) is deferred; do not continue it now.
7. **HDMI color bar + single-line camera path are done/PARTIAL.**
   HDMI color bar: user-reported board PASS. OV5640 single-line -> HDMI:
   PARTIAL PASS (image connected, pixel content unconfirmed).
8. **Current: stage 2 DDR frame buffer.** Confirmed in-package DDR2
   512Mb x16; next is an independent init/calibration/AXI read-write
   test, then FPGA test image -> DDR -> HDMI, then OV5640 live.
   Entry: `docs/display/ddr-investigation.md`; prompt:
   `docs/project/next-session-prompt.md`.

Polarity (measured 2026-10-26 by LA CSV):

- `0x4740=0x23` -> VSYNC **active low** (idle high, 66.665 µs low pulse).
- `0x4740=0x22` -> VSYNC **active high** (idle low, 66.665 µs high pulse).
- The `0x4740[0]` effect is **inverted relative to the datasheet** on this
  module/board. Use a consistent pair: `0x23` + `VSYNC_ACTIVE_HIGH=0`, or
  `0x22` + `VSYNC_ACTIVE_HIGH=1`. The earlier `0x22` + 0 was wrong; the
  16:24 diagnostic build uses `0x22` + 1.
- **HREF polarity is unresolved (A/B):** the low phase is 26.665 µs =
  **1280 PCLK**, the high phase is 40 µs = **1920 PCLK**. A. active low:
  low phase is the 1280 active bytes. B. active high (datasheet `0x22` bit1=1):
  high phase = 1280 active + 640 dummy; low phase is blanking. Both let
  `EXPECTED_PIX=1280` pass, so LED4 off is not proof. Capture D0–D7 in both
  phases and look for the 8-color bar.
- HREF is high for **1.373 ms** during vertical blanking and spans the VSYNC
  pulse; do not treat VSYNC-during-HREF as a fatal error, and do not count the
  long high as a 65,920-byte line.
- See `docs/camera/README.md` §2.1. Do not change config, readback expectation,
  and capture parameter independently.

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
docs/display/README.md            HDMI color-bar architecture/status
fpga/rtl/display/video_timing.v   640x480 timing generator
fpga/rtl/display/color_bar.v      8 vertical bars
fpga/rtl/display/tmds_encoder.v   TMDS 8b/10b encoder
fpga/rtl/display/tmds_serializer.v 10:1 DDR serializer (PH1P_LOGIC_ODDR)
fpga/rtl/display/serial_load_gen.v shared per-pixel load pulse
fpga/rtl/display/pll_hdmi.v       25.0/125 MHz PLL (PH1P_PHY_PLL_V2)
fpga/rtl/top/top_hdmi_colorbar.v  independent HDMI color-bar top
fpga/constraints/top_hdmi_colorbar.adc/.sdc
fpga/scripts/build_top_hdmi_colorbar.*
fpga/sim/models/pll_hdmi_sim.v    behavioural PLL (simulation only)
fpga/sim/models/ph1p_logic_oddr_sim.v behavioural ODDR (simulation only)
fpga/sim/tb/tb_tmds_encoder.v
fpga/sim/tb/tb_tmds_serializer.v
fpga/sim/tb/tb_video_timing.v
fpga/sim/tb/tb_top_hdmi_colorbar.v
docs/display/ov5640_line_to_hdmi.md   single-line camera->HDMI design
docs/display/ddr-investigation.md      DDR/frame-buffer investigation
fpga/rtl/camera/ov5640_line_capture.v  PCLK line capture/window/filter
fpga/rtl/common/line_buffer_dpram.v    640x16 dual-clock line RAM
fpga/rtl/display/rgb565_to_rgb888.v    RGB565 expansion
fpga/rtl/top/ov5640_line_to_hdmi_core.v line buffer + proven HDMI
fpga/rtl/top/top_ov5640_line_to_hdmi.v  board top (camera + HDMI)
fpga/constraints/top_ov5640_line_to_hdmi.adc/.sdc
fpga/scripts/build_top_ov5640_line_to_hdmi.*
fpga/sim/tb/tb_ov5640_line_capture.v
fpga/sim/tb/tb_top_ov5640_line_to_hdmi.v
verification/board/bringup-sccb-id.md
verification/board/bringup-dvp-three-channel.md
verification/board/bringup-hdmi-colorbar.md
verification/board/bringup-ov5640-line-hdmi.md
verification/board/evidence/      board captures
verification/board/evidence/20261107_hdmi_pin_review/
verification/board/evidence/20261107_hdmi_colorbar/
verification/board/evidence/20261108_ov5640_line_hdmi/
verification/static/              build/timing/simulation summaries
verification/static/dvp_capture_sim_2026-10-26.md
verification/static/top_dvp_test_build_2026-10-26.md
verification/static/hdmi_colorbar_sim_2026-11-07.md
verification/static/top_hdmi_colorbar_build_2026-11-07.md
verification/static/ov5640_line_to_hdmi_sim_2026-11-08.md
verification/static/top_ov5640_line_to_hdmi_build_2026-11-08.md
```
