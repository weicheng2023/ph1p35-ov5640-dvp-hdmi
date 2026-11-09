// ============================================================================
// ov5640_line_to_hdmi_core.v
// OV5640 single-line capture -> dual-clock line buffer -> proven HDMI chain.
//
// Data path:
//   cam_pclk domain: D0-D7 + HREF -> ov5640_line_capture -> 640 x 16 RAM
//   pixel_clk domain: RAM -> RGB565->RGB888 -> TMDS encoder -> serializer
//
// The HDMI timing/PLL/TMDS logic is the already-proven color-bar chain.
// The camera config/SCCB bring-up is kept outside this core so the core can
// be simulated with a synthetic camera and cfg_ok=1.
//
// Display behavior:
//   - Until a valid camera line is captured: dark blue background.
//   - After capture: the captured line is repeated on all 480 active lines.
//   - capture_done freezes the line buffer; the camera cannot overwrite it.
// ============================================================================
`timescale 1ns / 1ps

module ov5640_line_to_hdmi_core #(
    parameter integer HREF_ACTIVE_HIGH = 1,
    parameter integer CAPTURE_START    = 0,
    parameter integer BYTE_SWAP        = 0,
    parameter integer STARTUP_LINES    = 1,
    parameter integer TIMEOUT_CYCLES   = 16_000_000
) (
    input  wire        clk_50m,
    input  wire        rst_n,          // 50 MHz power-on reset
    input  wire        cfg_ok,         // camera config + readback OK

    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,

    output wire        tmds_clk_p,
    output wire        tmds_d0_p,
    output wire        tmds_d1_p,
    output wire        tmds_d2_p,

    output wire        pll_lock_o,
    output wire        capture_done_o,
    output wire        capture_error_o,
    output wire [15:0] line_bytes_o,
    output wire [15:0] lines_seen_o,
    output wire [7:0]  dbg_state_o
);

    // ------------------------------------------------------------------
    // HDMI PLL and timing (unchanged from the proven color-bar design)
    // ------------------------------------------------------------------
    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;

    pll_hdmi u_pll (
        .clk_50m    (clk_50m    ),
        .pixel_clk  (pixel_clk  ),
        .serial_clk (serial_clk ),
        .lock       (pll_lock   )
    );

    wire hdmi_rst = ~pll_lock;

    wire [9:0] hcount;
    wire [9:0] vcount;
    wire       de;
    wire       hs;
    wire       vs;

    video_timing u_timing (
        .pixel_clk (pixel_clk ),
        .rst       (hdmi_rst  ),
        .hcount    (hcount    ),
        .vcount    (vcount    ),
        .de        (de        ),
        .hs        (hs        ),
        .vs        (vs        )
    );

    // ------------------------------------------------------------------
    // Camera line capture (PCLK domain) and dual-clock line buffer
    // ------------------------------------------------------------------
    wire [9:0]  wr_addr;
    wire [15:0] wr_data;
    wire        wr_en;

    wire        capture_done;
    wire        capture_error;
    wire [15:0] line_bytes;
    wire [15:0] lines_seen;
    wire [15:0] line_total_dbg;
    wire [7:0]  dbg_state;

    ov5640_line_capture #(
        .HREF_ACTIVE_HIGH (HREF_ACTIVE_HIGH ),
        .PIXELS           (640             ),
        .CAPTURE_START    (CAPTURE_START    ),
        .BYTE_SWAP        (BYTE_SWAP        ),
        .LINE_MIN         (1200            ),
        .LINE_MAX         (2200            ),
        .STARTUP_LINES    (STARTUP_LINES    ),
        .TIMEOUT_CYCLES   (TIMEOUT_CYCLES   )
    ) u_cap (
        .pclk          (cam_pclk    ),
        .rst_n         (rst_n       ),
        .cap_en        (cfg_ok      ),
        .dvp_d         (cam_data    ),
        .dvp_href      (cam_href    ),
        .dvp_vsync     (cam_vsync   ),
        .wr_addr       (wr_addr     ),
        .wr_data       (wr_data     ),
        .wr_en         (wr_en       ),
        .capture_done  (capture_done),
        .capture_error (capture_error),
        .line_bytes    (line_bytes  ),
        .lines_seen    (lines_seen  ),
        .line_total_dbg(line_total_dbg),
        .dbg_state     (dbg_state   )
    );

    // Read one pixel ahead so the synchronous RAM output aligns with the
    // encoder's registered input at the current hcount. Wrap at 639 so the
    // first pixel of the next displayed line is pixel 0.
    wire [9:0] raddr = (hcount < 10'd639) ? (hcount + 10'd1) : 10'd0;

    wire [15:0] rgb565_rd;

    line_buffer_dpram #(
        .ADDR_WIDTH (10),
        .DATA_WIDTH (16)
    ) u_line_ram (
        .wr_clk  (cam_pclk  ),
        .wr_en   (wr_en     ),
        .wr_addr (wr_addr   ),
        .wr_data (wr_data   ),
        .rd_clk  (pixel_clk ),
        .rd_addr (raddr     ),
        .rd_data (rgb565_rd )
    );

    wire [23:0] rgb_cam;

    rgb565_to_rgb888 u_cvt (
        .rgb565 (rgb565_rd ),
        .rgb888 (rgb_cam   )
    );

    // capture_done is PCLK-domain; synchronize it into the pixel domain.
    reg [1:0] done_sync;

    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) done_sync <= 2'b00;
        else          done_sync <= {done_sync[0], capture_done};
    end

    wire cam_ready = done_sync[1];

    // Dark blue background before the first valid line is captured.
    wire [23:0] rgb = cam_ready ? rgb_cam : 24'h000040;

    // ------------------------------------------------------------------
    // TMDS encoders (channel 0: Blue + sync, channel 1: Green, channel 2: Red)
    // ------------------------------------------------------------------
    wire [9:0] tmds_ch0;
    wire [9:0] tmds_ch1;
    wire [9:0] tmds_ch2;

    tmds_encoder u_enc_b (
        .clk  (pixel_clk  ),
        .rst  (hdmi_rst   ),
        .din  (rgb[7:0]   ),
        .ctrl ({vs, hs}   ),
        .de   (de         ),
        .dout (tmds_ch0   )
    );

    tmds_encoder u_enc_g (
        .clk  (pixel_clk  ),
        .rst  (hdmi_rst   ),
        .din  (rgb[15:8]  ),
        .ctrl (2'b00      ),
        .de   (de         ),
        .dout (tmds_ch1   )
    );

    tmds_encoder u_enc_r (
        .clk  (pixel_clk  ),
        .rst  (hdmi_rst   ),
        .din  (rgb[23:16] ),
        .ctrl (2'b00      ),
        .de   (de         ),
        .dout (tmds_ch2   )
    );

    // ------------------------------------------------------------------
    // Serializers (shared load pulse)
    // ------------------------------------------------------------------
    wire load;

    serial_load_gen u_load (
        .pixel_clk  (pixel_clk  ),
        .serial_clk (serial_clk ),
        .rst        (hdmi_rst   ),
        .load       (load       )
    );

    localparam [9:0] TMDS_CLK_PATTERN = 10'b0000011111;

    tmds_serializer u_ser_clk (
        .serial_clk (serial_clk          ),
        .rst        (hdmi_rst           ),
        .load       (load                ),
        .din        (TMDS_CLK_PATTERN    ),
        .serial_out (tmds_clk_p          )
    );

    tmds_serializer u_ser_ch0 (
        .serial_clk (serial_clk  ),
        .rst        (hdmi_rst    ),
        .load       (load        ),
        .din        (tmds_ch0    ),
        .serial_out (tmds_d0_p   )
    );

    tmds_serializer u_ser_ch1 (
        .serial_clk (serial_clk  ),
        .rst        (hdmi_rst    ),
        .load       (load        ),
        .din        (tmds_ch1    ),
        .serial_out (tmds_d1_p   )
    );

    tmds_serializer u_ser_ch2 (
        .serial_clk (serial_clk  ),
        .rst        (hdmi_rst    ),
        .load       (load        ),
        .din        (tmds_ch2    ),
        .serial_out (tmds_d2_p   )
    );

    // ------------------------------------------------------------------
    // Status outputs (camera/status are PCLK-domain; the top synchronizes
    // them for slow LEDs)
    // ------------------------------------------------------------------
    assign pll_lock_o      = pll_lock;
    assign capture_done_o  = capture_done;
    assign capture_error_o = capture_error;
    assign line_bytes_o    = line_bytes;
    assign lines_seen_o    = lines_seen;
    assign dbg_state_o     = dbg_state;

endmodule
