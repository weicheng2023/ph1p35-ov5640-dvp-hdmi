// ============================================================================
// tb_top_hdmi_colorbar.v
// Integration testbench for the independent HDMI color-bar top.
//
// Uses:
//   fpga/sim/models/pll_hdmi_sim.v        (25.0 / 125 MHz, lock after 10 us)
//   fpga/sim/models/ph1p_logic_oddr_sim.v (behavioural ODDR)
//
// Checks:
//   - PLL lock and reset release
//   - 8 color-bar values at the centre of each 80-pixel bar on line 0
//   - TMDS control characters on channel 0 during HSYNC/VSYNC blanking
//   - TMDS serial outputs are toggling (not stuck)
//
// This is NOT a substitute for the real PLL/IO electrical validation.
// ============================================================================
`timescale 1ns / 1ps

module tb_top_hdmi_colorbar;

    reg  clk_50m;
    wire [3:0] led;
    wire tmds_clk_p;
    wire tmds_d0_p;
    wire tmds_d1_p;
    wire tmds_d2_p;

    integer errors;
    integer clk_edges;
    integer data_edges;

    reg prev_clk_p;
    reg prev_d0_p;

    top_hdmi_colorbar dut (
        .clk_50m    (clk_50m    ),
        .led        (led        ),
        .tmds_clk_p (tmds_clk_p ),
        .tmds_d0_p  (tmds_d0_p  ),
        .tmds_d1_p  (tmds_d1_p  ),
        .tmds_d2_p  (tmds_d2_p  )
    );

    initial clk_50m = 1'b0;
    always #10 clk_50m = ~clk_50m;   // 50 MHz

    // Count transitions on the TMDS clock and data outputs.
    initial begin
        clk_edges  = 0;
        data_edges = 0;
        prev_clk_p = 1'b0;
        prev_d0_p  = 1'b0;
    end

    always @(tmds_clk_p) begin
        if (!dut.rst && (tmds_clk_p !== prev_clk_p)) begin
            clk_edges = clk_edges + 1;
            prev_clk_p = tmds_clk_p;
        end
    end

    always @(tmds_d0_p) begin
        if (!dut.rst && (tmds_d0_p !== prev_d0_p)) begin
            data_edges = data_edges + 1;
            prev_d0_p = tmds_d0_p;
        end
    end

    task check_rgb(input [9:0] h, input [23:0] exp);
        begin
            while (!(dut.hcount == h && dut.vcount == 10'd0 && dut.de))
                @(posedge dut.pixel_clk);
            #1;
            if (dut.rgb !== exp) begin
                $display("FAIL h=%0d rgb=%06h expected=%06h", h, dut.rgb, exp);
                errors = errors + 1;
            end else begin
                $display("ok   h=%0d rgb=%06h", h, dut.rgb);
            end
        end
    endtask

    task check_ctrl(input [9:0] h, input [9:0] v, input [9:0] exp);
        begin
            while (!(dut.hcount == h && dut.vcount == v))
                @(posedge dut.pixel_clk);
            #1;
            if (dut.tmds_ch0 !== exp) begin
                $display("FAIL ctrl h=%0d v=%0d ch0=%b expected=%b", h, v, dut.tmds_ch0, exp);
                errors = errors + 1;
            end else begin
                $display("ok   ctrl h=%0d v=%0d ch0=%b", h, v, dut.tmds_ch0);
            end
        end
    endtask

    initial begin
        errors = 0;

        // Wait for PLL lock and reset release.
        wait (dut.pll_lock === 1'b1);
        wait (dut.rst === 1'b0);
        $display("PLL locked, reset released at t=%0t", $time);

        if (led[1] !== 1'b1) begin
            $display("FAIL LED2 (pll_lock) is not high");
            errors = errors + 1;
        end

        // Line 0: the 8 bars are 80 pixels wide; sample their centres.
        check_rgb(10'd40,  24'hFFFFFF);   // white
        check_rgb(10'd120, 24'hFFFF00);   // yellow
        check_rgb(10'd200, 24'h00FFFF);   // cyan
        check_rgb(10'd280, 24'h00FF00);   // green
        check_rgb(10'd360, 24'hFF00FF);   // magenta
        check_rgb(10'd440, 24'hFF0000);   // red
        check_rgb(10'd520, 24'h0000FF);   // blue
        check_rgb(10'd600, 24'h000000);   // black

        // Channel 0 control characters.
        // v=0, h=700: HSYNC low, VSYNC high -> ctrl {1,0} -> 0101010100
        check_ctrl(10'd700, 10'd0, 10'b0101010100);
        // v=490, h=40: HSYNC high, VSYNC low -> ctrl {0,1} -> 0010101011
        check_ctrl(10'd40, 10'd490, 10'b0010101011);
        // v=490, h=700: HSYNC low, VSYNC low -> ctrl {0,0} -> 1101010100
        check_ctrl(10'd700, 10'd490, 10'b1101010100);
        // v=480, h=100: both high (vertical front porch) -> ctrl {1,1} -> 1010101011
        check_ctrl(10'd100, 10'd480, 10'b1010101011);

        // Let the serial outputs run for 2 us and check they toggle.
        #2000;
        $display("TMDS clock edges=%0d, channel0 edges=%0d", clk_edges, data_edges);
        if (clk_edges < 20) begin
            $display("FAIL TMDS clock is not toggling");
            errors = errors + 1;
        end
        if (data_edges < 10) begin
            $display("FAIL TMDS data channel 0 is not toggling");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB: PASS - top_hdmi_colorbar");
        else
            $display("TB: FAIL - top_hdmi_colorbar, errors=%0d", errors);

        $finish;
    end

endmodule
