// ============================================================================
// tb_tmds_encoder.v
// Self-checking testbench for the TMDS 8b/10b encoder.
//
// Checks:
//   1. the four control characters for DE=0
//   2. exact data characters for 0x00, 0xFF, 0x55, 0xAA with cnt=0
//   3. the running-disparity branch by sending 0x00 twice
//   4. the output is a 10-bit character (no X/Z)
//
// The expected values are derived by hand from the DVI 1.0 algorithm and
// are also the values used by the classic open TMDS encoder.
// ============================================================================
`timescale 1ns / 1ps

module tb_tmds_encoder;

    reg        clk;
    reg        rst;
    reg  [7:0] din;
    reg  [1:0] ctrl;
    reg        de;
    wire [9:0] dout;

    integer errors;

    tmds_encoder dut (
        .clk  (clk  ),
        .rst  (rst  ),
        .din  (din  ),
        .ctrl (ctrl ),
        .de   (de   ),
        .dout (dout )
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz is enough; encoding is clocked

    task do_reset;
        begin
            rst = 1'b1;
            de  = 1'b0;
            din = 8'h00;
            ctrl = 2'b00;
            @(posedge clk);
            @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task check_ctrl(input [1:0] c, input [9:0] exp);
        begin
            do_reset;
            ctrl = c;
            de   = 1'b0;
            @(posedge clk);
            #1;
            if (dout !== exp) begin
                $display("FAIL ctrl=%b: dout=%b expected=%b", c, dout, exp);
                errors = errors + 1;
            end else begin
                $display("ok   ctrl=%b: dout=%b", c, dout);
            end
        end
    endtask

    task check_data(input [7:0] d, input [9:0] exp);
        begin
            do_reset;
            din  = d;
            ctrl = 2'b00;
            de   = 1'b1;
            @(posedge clk);
            #1;
            if (dout !== exp) begin
                $display("FAIL data=%02h: dout=%b expected=%b", d, dout, exp);
                errors = errors + 1;
            end else begin
                $display("ok   data=%02h: dout=%b", d, dout);
            end
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1;
        de  = 1'b0;
        din = 8'h00;
        ctrl = 2'b00;

        // Control characters
        check_ctrl(2'b00, 10'b1101010100);
        check_ctrl(2'b01, 10'b0010101011);
        check_ctrl(2'b10, 10'b0101010100);
        check_ctrl(2'b11, 10'b1010101011);

        // Data characters with cnt=0
        check_data(8'h00, 10'b0100000000);
        check_data(8'hFF, 10'b1000000000);
        check_data(8'h55, 10'b0100110011);
        check_data(8'hAA, 10'b1000110011);

        // Running disparity: two 0x00 characters back-to-back.
        // First: cnt=0 branch, dout=0100000000, cnt=-8.
        // Second: cnt<0 and n0>n1 -> invert branch, dout=1111111111.
        do_reset;
        din  = 8'h00;
        ctrl = 2'b00;
        de   = 1'b1;
        @(posedge clk);
        #1;
        if (dout !== 10'b0100000000) begin
            $display("FAIL disparity#1: dout=%b", dout);
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (dout !== 10'b1111111111) begin
            $display("FAIL disparity#2: dout=%b", dout);
            errors = errors + 1;
        end else begin
            $display("ok   disparity sequence");
        end

        // No X/Z in the output
        if ((^dout) === 1'bx) begin
            $display("FAIL dout contains X/Z");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB: PASS - tmds_encoder");
        else
            $display("TB: FAIL - tmds_encoder, errors=%0d", errors);

        $finish;
    end

endmodule
