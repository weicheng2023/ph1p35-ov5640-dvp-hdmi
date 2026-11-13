// ============================================================================
// tb_video_timing.v
// Full-frame 640x480@60 timing check at the real 25.0 MHz pixel clock.
//
// Checks over exactly one 800 x 521 frame:
//   - DE high for 640 x 480 = 307,200 pixel clocks
//   - HSYNC low for 96 clocks per line (96 x 521 = 50,016)
//   - VSYNC low for 2 lines (2 x 800 = 1,600)
//   - H/V counter ranges and sync positions
//   - HSYNC/VSYNC are active low
//
// No camera, no DVP, no DDR. This is the real video timing, not a
// shortened frame.
// ============================================================================
`timescale 1ns / 1ps

module tb_video_timing;

    reg         pixel_clk;
    reg         rst;
    wire [9:0]  hcount;
    wire [9:0]  vcount;
    wire        de;
    wire        hs;
    wire        vs;

    integer cyc;
    integer de_cnt;
    integer hs_cnt;
    integer vs_cnt;
    integer errors;

    video_timing dut (
        .pixel_clk (pixel_clk ),
        .rst       (rst       ),
        .hcount    (hcount    ),
        .vcount    (vcount    ),
        .de        (de        ),
        .hs        (hs        ),
        .vs        (vs        )
    );

    initial pixel_clk = 1'b0;
    always #20.000 pixel_clk = ~pixel_clk;   // 25.0 MHz (period 40.000 ns)

    always @(posedge pixel_clk) begin
        #1;
        if (!rst) begin
            cyc = cyc + 1;

            if (hcount > 10'd799) begin
                $display("FAIL hcount=%0d out of range", hcount);
                errors = errors + 1;
            end
            if (vcount > 10'd520) begin
                $display("FAIL vcount=%0d out of range", vcount);
                errors = errors + 1;
            end
            if (de !== ((hcount < 10'd640) && (vcount < 10'd480))) begin
                $display("FAIL de mismatch at h=%0d v=%0d de=%b", hcount, vcount, de);
                errors = errors + 1;
            end
            if (hs !== ~((hcount >= 10'd656) && (hcount < 10'd752))) begin
                $display("FAIL hs mismatch at h=%0d hs=%b", hcount, hs);
                errors = errors + 1;
            end
            if (vs !== ~((vcount >= 10'd490) && (vcount < 10'd492))) begin
                $display("FAIL vs mismatch at v=%0d vs=%b", vcount, vs);
                errors = errors + 1;
            end

            if (de) de_cnt = de_cnt + 1;
            if (!hs) hs_cnt = hs_cnt + 1;
            if (!vs) vs_cnt = vs_cnt + 1;

            if (cyc == 416800) begin
                if (hcount !== 10'd799 || vcount !== 10'd520) begin
                    $display("FAIL frame end: h=%0d v=%0d", hcount, vcount);
                    errors = errors + 1;
                end
                if (de_cnt != 307200) begin
                    $display("FAIL de_cnt=%0d expected=307200", de_cnt);
                    errors = errors + 1;
                end
                if (hs_cnt != 50016) begin
                    $display("FAIL hs_cnt=%0d expected=50016", hs_cnt);
                    errors = errors + 1;
                end
                if (vs_cnt != 1600) begin
                    $display("FAIL vs_cnt=%0d expected=1600", vs_cnt);
                    errors = errors + 1;
                end

                if (errors == 0)
                    $display("TB: PASS - video_timing, 1 frame = 800x521, de=307200, hs_low=50016, vs_low=1600");
                else
                    $display("TB: FAIL - video_timing, errors=%0d", errors);

                $finish;
            end
        end
    end

    initial begin
        cyc    = 0;
        de_cnt = 0;
        hs_cnt = 0;
        vs_cnt = 0;
        errors = 0;
        rst    = 1'b1;
        repeat (4) @(posedge pixel_clk);
        rst = 1'b0;
    end

endmodule
