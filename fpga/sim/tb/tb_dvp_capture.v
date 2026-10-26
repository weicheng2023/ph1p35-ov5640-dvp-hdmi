// ============================================================================
// tb_dvp_capture.v
// Real-timing DVP capture testbench.
//
// What is modelled:
//   - PCLK at a parameterised frequency (default 24 MHz; override with -g).
//   - A separate 50 MHz system clock. The two clocks are asynchronous and have
//     a non-integer ratio.
//   - HREF high for H_ACTIVE PCLK cycles per active line.
//   - VSYNC pulse of VSYNC_WIDTH PCLK cycles (default 2 line periods), with
//     vertical back/front porch lines.
//   - RGB565 byte stream: even byte index = high byte, odd = low byte. The
//     pixel value is a running counter so byte swaps and bit reversals are
//     visible.
//   - Data/HREF/VSYNC change DATA_SKEW ns after the launching PCLK edge.
//     The DUT samples on the rising edge, so the normal mode launches on the
//     falling edge and gives a realistic setup window.
//
// Checks:
//   - Every sampled byte matches the expected RGB565 stream.
//   - Every line event has pix_cnt == H_ACTIVE and no error flags.
//   - Frame/line ordering and lines-per-frame match.
//   - Event FIFO does not overflow.
//
// Mutation tests (both must FAIL):
//   +LAUNCH_POSEDGE              model launches data just after the active
//                                rising edge (hold violation)
//   -gINVERT_DUT_PCLK=1          DUT samples on the falling edge while the
//                                model still launches 3 ns after the falling
//                                edge (hold violation)
//   The byte-sequence checker may still see the correct bytes in these cases,
//   because the data remains stable for a full period. The setup/hold monitor
//   is what catches the bad sampling edge. This is intentional: RTL simulation
//   does not model metastability, so the timing contract must be asserted.
//
// Run (ModelSim, from build/sim):
//   vlib work
//   vlog ../../fpga/rtl/common/async_fifo_gray.v \
//        ../../fpga/rtl/camera/dvp_capture.v \
//        ../../fpga/rtl/camera/dvp_status_monitor.v \
//        ../../fpga/sim/tb/tb_dvp_capture.v
//   vsim -c -do "run -all; quit" work.tb_dvp_capture
//
// Quick regression (small frame, real PCLK and line length):
//   vsim -c -gV_ACTIVE=16 -gV_BACK=2 -gV_FRONT=1 \
//        -do "run -all; quit" work.tb_dvp_capture
// ============================================================================
`timescale 1ns / 1ps

module tb_dvp_capture;

    // ------------------------------------------------------------------
    // Test scenario parameters.
    //
    // PCLK_PERIOD, H_ACTIVE and the blanking values are NOT measured board
    // values yet. They are realistic placeholders derived from the OV5640
    // datasheet and the RGB565 640x480 target. The board measurement will
    // replace them; do not treat this test as proof of 640x480 @ 30 fps.
    // ------------------------------------------------------------------
    parameter real    PCLK_PERIOD = 41.667; // 24 MHz
    parameter integer H_ACTIVE    = 1280;   // PCLK cycles, 640 RGB565 pixels
    parameter integer H_BLANK     = 300;    // HREF low PCLK cycles
    parameter integer V_ACTIVE    = 480;
    parameter integer V_BACK      = 18;
    parameter integer V_FRONT     = 6;
    parameter real    DATA_SKEW   = 3.0;    // ns after the launch edge
    // Setup/hold window required at the DUT sampling edge. These are
    // conservative placeholders until the OV5640 DVP AC table is recorded.
    parameter real    T_SETUP_NS  = 5.0;
    parameter real    T_HOLD_NS   = 5.0;
    // Mutation knob: invert the DUT's PCLK so it samples on the wrong edge.
    // The camera model still launches on the original falling edge. This must
    // make the timing checker fail (hold violation).
    parameter integer INVERT_DUT_PCLK = 0;
    // Polarity of the camera model and the DUT. The 2026-10-26 LA capture
    // measured HREF active high and VSYNC active low; run both combinations.
    parameter integer HREF_ACTIVE_HIGH  = 1;
    parameter integer VSYNC_ACTIVE_HIGH = 1;

    localparam integer LINE_PCLK   = H_ACTIVE + H_BLANK;
    localparam integer VSYNC_WIDTH = 2 * LINE_PCLK;

    // ------------------------------------------------------------------
    // Clocks and DUT signals
    // ------------------------------------------------------------------
    reg pclk = 1'b0;
    always #(PCLK_PERIOD/2.0) pclk = ~pclk;

    reg clk = 1'b0;
    always #10 clk = ~clk; // 50 MHz

    // Normal: DUT samples on the rising edge, matching the camera model.
    // Mutation: invert the DUT clock so it samples on the falling edge.
    wire dut_pclk = INVERT_DUT_PCLK ? ~pclk : pclk;

    reg        rst_n   = 1'b0;
    reg        cap_en  = 1'b0;
    reg  [7:0] cam_data = 8'h00;
    reg        cam_href = 1'b0;
    reg        cam_vsync = 1'b0;

    // Idle levels for the selected polarity, before the first frame.
    initial begin
        cam_href  = HREF_ACTIVE_HIGH  ? 1'b0 : 1'b1;
        cam_vsync = VSYNC_ACTIVE_HIGH ? 1'b0 : 1'b1;
    end

    wire [63:0] evt_data;
    wire        evt_wr;
    wire        evt_full;
    wire        evt_overflow;
    wire        pclk_rst_n;

    wire        sample_valid;
    wire [7:0]  sample_data;

    wire [63:0] evt_rd_data;
    wire        evt_empty;
    wire        evt_rd_en;
    wire        fifo_overflow;

    wire [15:0] mon_frame_cnt;
    wire [15:0] mon_line_cnt;
    wire [15:0] mon_lines_in_frame;
    wire [15:0] mon_pix_min;
    wire [15:0] mon_pix_max;
    wire        mon_line_ok;
    wire        mon_frame_ok;
    wire        mon_err_sticky;
    wire [7:0]  mon_last_err;
    wire [31:0] mon_evt_count;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    dvp_capture #(
        .HREF_ACTIVE_HIGH  (HREF_ACTIVE_HIGH),
        .VSYNC_ACTIVE_HIGH (VSYNC_ACTIVE_HIGH),
        .STARTUP_FRAMES    (1),
        .EXPECTED_PIX      (H_ACTIVE),
        .EXPECTED_LINES    (V_ACTIVE)
    ) dut (
        .pclk             (dut_pclk),
        .rst_n            (rst_n),
        .cap_en           (cap_en),
        .dvp_d            (cam_data),
        .dvp_href         (cam_href),
        .dvp_vsync        (cam_vsync),
        .evt_data         (evt_data),
        .evt_wr           (evt_wr),
        .evt_full         (evt_full),
        .evt_overflow     (evt_overflow),
        .frame_cnt        (),
        .line_cnt         (),
        .pix_cnt          (),
        .line_pix_cnt     (),
        .startup_cnt      (),
        .active           (),
        .frame_start_pulse(),
        .err_flags        (),
        .sample_valid     (sample_valid),
        .sample_data      (sample_data),
        .pclk_rst_n_o     (pclk_rst_n)
    );

    // ------------------------------------------------------------------
    // Event FIFO: PCLK write side, 50 MHz read side
    // ------------------------------------------------------------------
    async_fifo_gray #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (4)
    ) u_evt_fifo (
        .wr_clk      (dut_pclk),
        .wr_rst_n    (pclk_rst_n),
        .wr_en       (evt_wr),
        .wr_data     (evt_data),
        .wr_full     (evt_full),
        .wr_overflow (fifo_overflow),
        .rd_clk      (clk),
        .rd_rst_n    (rst_n),
        .rd_en       (evt_rd_en),
        .rd_data     (evt_rd_data),
        .rd_empty    (evt_empty)
    );

    // ------------------------------------------------------------------
    // 50 MHz monitor
    // ------------------------------------------------------------------
    dvp_status_monitor #(
        .EXPECTED_PIX   (H_ACTIVE),
        .EXPECTED_LINES (V_ACTIVE)
    ) u_mon (
        .clk            (clk),
        .rst_n          (rst_n),
        .evt_data       (evt_rd_data),
        .evt_empty      (evt_empty),
        .evt_rd_en      (evt_rd_en),
        .frame_cnt      (mon_frame_cnt),
        .line_cnt       (mon_line_cnt),
        .lines_in_frame (mon_lines_in_frame),
        .pix_min        (mon_pix_min),
        .pix_max        (mon_pix_max),
        .line_ok        (mon_line_ok),
        .frame_ok       (mon_frame_ok),
        .err_sticky     (mon_err_sticky),
        .last_err       (mon_last_err),
        .evt_count      (mon_evt_count)
    );

    // ------------------------------------------------------------------
    // Camera model
    // ------------------------------------------------------------------
    integer launch_posedge;
    integer verbose;
    integer y;
    integer byte_errors;
    integer chk_index;
    integer chk_count;
    integer i;

    initial begin
        launch_posedge = $test$plusargs("LAUNCH_POSEDGE");
        verbose        = $test$plusargs("VERBOSE");
        byte_errors    = 0;
        chk_index      = 0;
        chk_count      = 0;
        $display("TB: launch_posedge=%0d INVERT_DUT_PCLK=%0d",
                 launch_posedge, INVERT_DUT_PCLK);
    end

    function [7:0] expected_byte(input integer line_idx, input integer byte_idx);
        reg [31:0] pix;
        begin
            // Non-zero base so a one-byte shift is visible immediately.
            pix = (line_idx * (H_ACTIVE/2) + (byte_idx/2) + 32'h00001234) & 32'h0000FFFF;
            expected_byte = ((byte_idx % 2) == 0) ? pix[15:8] : pix[7:0];
        end
    endfunction

    task drive_byte(input [7:0] data, input href);
        begin
            if (launch_posedge) begin
                @(posedge pclk);
                #(DATA_SKEW);
            end else begin
                @(negedge pclk);
                #(DATA_SKEW);
            end
            cam_data = data;
            cam_href = HREF_ACTIVE_HIGH ? href : ~href;
        end
    endtask

    task drive_vsync_pulse;
        integer n;
        begin
            @(negedge pclk);
            #(DATA_SKEW);
            cam_vsync = VSYNC_ACTIVE_HIGH ? 1'b1 : 1'b0;
            cam_href  = HREF_ACTIVE_HIGH  ? 1'b0 : 1'b1;
            cam_data  = 8'h00;
            // Total active width = VSYNC_WIDTH PCLK cycles.
            for (n = 1; n < VSYNC_WIDTH; n = n + 1) @(negedge pclk);
            #(DATA_SKEW);
            cam_vsync = VSYNC_ACTIVE_HIGH ? 1'b0 : 1'b1;
        end
    endtask

    task drive_blank_line;
        integer n;
        begin
            @(negedge pclk);
            #(DATA_SKEW);
            cam_href = HREF_ACTIVE_HIGH ? 1'b0 : 1'b1;
            cam_data = 8'h00;
            // Total blank line = LINE_PCLK PCLK cycles.
            for (n = 1; n < LINE_PCLK; n = n + 1) @(negedge pclk);
        end
    endtask

    task drive_active_line(input integer line_idx);
        integer b;
        begin
            for (b = 0; b < H_ACTIVE; b = b + 1) begin
                drive_byte(expected_byte(line_idx, b), 1'b1);
            end
            // HREF low for H_BLANK PCLK cycles (horizontal blanking), so the
            // line period is H_ACTIVE + H_BLANK = LINE_PCLK.
            drive_byte(8'h00, 1'b0);
            for (b = 1; b < H_BLANK; b = b + 1) @(negedge pclk);
        end
    endtask

    initial begin
        wait (rst_n);
        wait (cap_en);
        #(PCLK_PERIOD * 4.0);
        forever begin
            drive_vsync_pulse();
            for (i = 0; i < V_BACK; i = i + 1) drive_blank_line();
            for (y = 0; y < V_ACTIVE; y = y + 1) drive_active_line(y);
            for (i = 0; i < V_FRONT; i = i + 1) drive_blank_line();
        end
    end

    // ------------------------------------------------------------------
    // Reset and enable
    // ------------------------------------------------------------------
    initial begin
        rst_n  = 1'b0;
        cap_en = 1'b0;
        #200;
        rst_n = 1'b1;
        #200;
        cap_en = 1'b1;
    end

    // ------------------------------------------------------------------
    // Setup/hold window monitor.
    // RTL simulation cannot model metastability, so a byte-sequence checker
    // alone cannot tell "sampled on the wrong edge" from "sampled at the
    // trailing edge of a valid window". These checks make the timing contract
    // explicit: data must be stable T_SETUP_NS before and T_HOLD_NS after
    // every DUT sampling edge.
    // ------------------------------------------------------------------
    integer  setup_errors;
    integer  hold_errors;
    integer  timing_en;
    realtime last_data_change;
    realtime last_sample_time;

    initial begin
        setup_errors     = 0;
        hold_errors      = 0;
        timing_en        = 0;
        last_data_change = -1.0e9;
        last_sample_time = -1.0e9;
    end

    always @(cam_data) begin
        if (timing_en && (($realtime - last_sample_time) < T_HOLD_NS)) begin
            hold_errors = hold_errors + 1;
        end
        last_data_change = $realtime;
    end

    always @(posedge dut_pclk) begin
        if (timing_en && (($realtime - last_data_change) < T_SETUP_NS)) begin
            setup_errors = setup_errors + 1;
        end
        last_sample_time = $realtime;
    end

    initial begin
        wait (rst_n);
        wait (cap_en);
        #(PCLK_PERIOD * 40.0);
        timing_en = 1;
    end

    // ------------------------------------------------------------------
    // Sampled-byte checker (checks at posedge + 1 ns, after DUT NBA updates)
    // ------------------------------------------------------------------
    function [7:0] expected_stream_byte(input integer idx);
        reg [31:0] pix;
        begin
            pix = ((idx / 2) + 32'h00001234) & 32'h0000FFFF;
            expected_stream_byte = ((idx % 2) == 0) ? pix[15:8] : pix[7:0];
        end
    endfunction

    always @(posedge pclk) begin
        #1;
        if (dut.frame_start_pulse) begin
            if (verbose && (chk_count < 4)) begin
                $display("TB: frame_start, chk_index was %0d", chk_index);
            end
            chk_index = 0;
        end else if (sample_valid) begin
            if (verbose && (chk_count < 8)) begin
                $display("TB: sample %0d idx=%0d got=%02h exp=%02h",
                         chk_count, chk_index, sample_data,
                         expected_stream_byte(chk_index));
            end
            chk_count = chk_count + 1;
            if (sample_data !== expected_stream_byte(chk_index)) begin
                byte_errors = byte_errors + 1;
                if (byte_errors <= 8) begin
                    $display("TB: byte mismatch idx=%0d got=%02h exp=%02h",
                             chk_index, sample_data, expected_stream_byte(chk_index));
                end
            end
            chk_index = chk_index + 1;
        end
    end

    // ------------------------------------------------------------------
    // Pass/fail
    // ------------------------------------------------------------------
    initial begin
        $display("TB: start (PCLK_PERIOD=%0.3f ns, H_ACTIVE=%0d, H_BLANK=%0d, LINE_PCLK=%0d, VSYNC_WIDTH=%0d, V_ACTIVE=%0d, V_BACK=%0d, V_FRONT=%0d)",
                 PCLK_PERIOD, H_ACTIVE, H_BLANK, LINE_PCLK, VSYNC_WIDTH,
                 V_ACTIVE, V_BACK, V_FRONT);
        wait (rst_n);
        wait (cap_en);
        wait (mon_frame_cnt == 16'd3);
        #(PCLK_PERIOD * 8.0);

        if ((mon_pix_min == H_ACTIVE) &&
            (mon_pix_max == H_ACTIVE) &&
            mon_line_ok &&
            mon_frame_ok &&
            !mon_err_sticky &&
            !evt_overflow &&
            !fifo_overflow &&
            (byte_errors == 0) &&
            (setup_errors == 0) &&
            (hold_errors == 0) &&
            (mon_evt_count > 0)) begin
            $display("TB: PASS - frames=%0d lines_in_frame=%0d pix_min=%0d pix_max=%0d events=%0d bytes_err=%0d setup_err=%0d hold_err=%0d",
                     mon_frame_cnt, mon_lines_in_frame, mon_pix_min, mon_pix_max,
                     mon_evt_count, byte_errors, setup_errors, hold_errors);
        end else begin
            $display("TB: FAIL - frame=%0d lines=%0d pix_min=%0d pix_max=%0d line_ok=%b frame_ok=%b err=%b last_err=%02h evt_ovf=%b fifo_ovf=%b bytes_err=%0d setup_err=%0d hold_err=%0d events=%0d",
                     mon_frame_cnt, mon_lines_in_frame, mon_pix_min, mon_pix_max,
                     mon_line_ok, mon_frame_ok, mon_err_sticky, mon_last_err,
                     evt_overflow, fifo_overflow, byte_errors,
                     setup_errors, hold_errors, mon_evt_count);
        end
        $finish;
    end

    initial begin
        #(6.0 * PCLK_PERIOD * LINE_PCLK * (V_ACTIVE + V_BACK + V_FRONT + 2));
        $display("TB: FAIL - timeout (frame=%0d lines=%0d events=%0d bytes_err=%0d)",
                 mon_frame_cnt, mon_lines_in_frame, mon_evt_count, byte_errors);
        $finish;
    end

endmodule
