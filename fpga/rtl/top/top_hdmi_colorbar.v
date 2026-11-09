// ============================================================================
// top_hdmi_colorbar.v
// Independent HDMI color-bar source: PH1P35 -> HDMI1, no camera, no DDR.
//
// Video: 640x480@59.981 Hz, RGB888, 8 vertical bars (80 px each).
// TMDS : DVI-compatible (no audio, no InfoFrame, no HDCP, no EDID read).
//
// Board: PH1P35_FT V1 / HX1P35B_FT_40P, PH1P35MDG324
//   clk_50m      : C4
//   LEDs         : D10/E10/C6/D6 -> physical LED1..4
//   TMDS D0_P    : G16 (channel 0: Blue + HSYNC/VSYNC)
//   TMDS D1_P    : F17 (channel 1: Green)
//   TMDS D2_P    : H14 (channel 2: Red)
//   TMDS CLK_P   : C17
//
// LEDs:
//   LED1: 1 Hz heartbeat (50 MHz domain)
//   LED2: PLL lock
//   LED3: design out of reset
//   LED4: frame tick (~0.94 Hz)
//
// The N-side TMDS balls (H16/E18/H13/D18) are inferred by TD from the
// TMDS33 P-side constraint; they are not separate top-level ports.
// ============================================================================
`timescale 1ns / 1ps

module top_hdmi_colorbar (
    input  wire       clk_50m,
    output wire [3:0] led,

    output wire       tmds_clk_p,
    output wire       tmds_d0_p,
    output wire       tmds_d1_p,
    output wire       tmds_d2_p
);

    // ------------------------------------------------------------------
    // PLL and reset
    // ------------------------------------------------------------------
    wire pixel_clk;     // 25.0 MHz
    wire serial_clk;    // 125 MHz
    wire pll_lock;

    pll_hdmi u_pll (
        .clk_50m    (clk_50m    ),
        .pixel_clk  (pixel_clk  ),
        .serial_clk (serial_clk ),
        .lock       (pll_lock   )
    );

    // Hold the design in reset until the PLL locks, then stretch by
    // 8 pixel clocks. rst is active high.
    wire rst_async = ~pll_lock;
    reg  [3:0] rst_cnt;

    always @(posedge pixel_clk or posedge rst_async) begin
        if (rst_async)
            rst_cnt <= 4'd0;
        else if (!rst_cnt[3])
            rst_cnt <= rst_cnt + 4'd1;
    end

    wire rst = ~rst_cnt[3];

    // ------------------------------------------------------------------
    // Video timing and color bars
    // ------------------------------------------------------------------
    wire [9:0] hcount;
    wire [9:0] vcount;
    wire       de;
    wire       hs;
    wire       vs;
    wire [23:0] rgb;

    video_timing u_timing (
        .pixel_clk (pixel_clk ),
        .rst       (rst       ),
        .hcount    (hcount    ),
        .vcount    (vcount    ),
        .de        (de        ),
        .hs        (hs        ),
        .vs        (vs        )
    );

    color_bar u_bar (
        .hcount (hcount ),
        .de     (de     ),
        .rgb    (rgb    )
    );

    // ------------------------------------------------------------------
    // Three TMDS encoders
    //   channel 0 : Blue   + {VSYNC,HSYNC}
    //   channel 1 : Green  + 2'b00
    //   channel 2 : Red    + 2'b00
    // ------------------------------------------------------------------
    wire [9:0] tmds_ch0;
    wire [9:0] tmds_ch1;
    wire [9:0] tmds_ch2;

    tmds_encoder u_enc_b (
        .clk  (pixel_clk   ),
        .rst  (rst         ),
        .din  (rgb[7:0]    ),
        .ctrl ({vs, hs}    ),
        .de   (de          ),
        .dout (tmds_ch0    )
    );

    tmds_encoder u_enc_g (
        .clk  (pixel_clk   ),
        .rst  (rst         ),
        .din  (rgb[15:8]   ),
        .ctrl (2'b00       ),
        .de   (de          ),
        .dout (tmds_ch1    )
    );

    tmds_encoder u_enc_r (
        .clk  (pixel_clk   ),
        .rst  (rst         ),
        .din  (rgb[23:16]  ),
        .ctrl (2'b00       ),
        .de   (de          ),
        .dout (tmds_ch2    )
    );

    // ------------------------------------------------------------------
    // 10:1 serializers (one shared load pulse keeps all lanes aligned)
    // ------------------------------------------------------------------
    wire load;

    serial_load_gen u_load (
        .pixel_clk  (pixel_clk  ),
        .serial_clk (serial_clk ),
        .rst        (rst        ),
        .load       (load       )
    );

    // Clock channel: five 1s then five 0s per pixel -> 25.0 MHz TMDS clock.
    localparam [9:0] TMDS_CLK_PATTERN = 10'b0000011111;

    tmds_serializer u_ser_clk (
        .serial_clk (serial_clk          ),
        .rst        (rst                 ),
        .load       (load                ),
        .din        (TMDS_CLK_PATTERN    ),
        .serial_out (tmds_clk_p          )
    );

    tmds_serializer u_ser_ch0 (
        .serial_clk (serial_clk  ),
        .rst        (rst         ),
        .load       (load        ),
        .din        (tmds_ch0    ),
        .serial_out (tmds_d0_p   )
    );

    tmds_serializer u_ser_ch1 (
        .serial_clk (serial_clk  ),
        .rst        (rst         ),
        .load       (load        ),
        .din        (tmds_ch1    ),
        .serial_out (tmds_d1_p   )
    );

    tmds_serializer u_ser_ch2 (
        .serial_clk (serial_clk  ),
        .rst        (rst         ),
        .load       (load        ),
        .din        (tmds_ch2    ),
        .serial_out (tmds_d2_p   )
    );

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    reg [25:0] hb_cnt;
    reg        hb;

    always @(posedge clk_50m) begin
        if (hb_cnt == 26'd24_999_999) begin
            hb_cnt <= 26'd0;
            hb     <= ~hb;
        end else begin
            hb_cnt <= hb_cnt + 26'd1;
        end
    end

    reg        vs_q;
    reg  [5:0] frame_cnt;

    always @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            vs_q      <= 1'b1;
            frame_cnt <= 6'd0;
        end else begin
            vs_q <= vs;
            if (vs_q && !vs)
                frame_cnt <= frame_cnt + 6'd1;
        end
    end

    assign led[0] = hb;            // 1 Hz heartbeat
    assign led[1] = pll_lock;      // PLL lock
    assign led[2] = ~rst;          // out of reset
    assign led[3] = frame_cnt[5];  // ~0.94 Hz frame tick

endmodule
