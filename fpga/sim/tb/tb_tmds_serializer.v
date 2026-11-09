// ============================================================================
// tb_tmds_serializer.v
// Self-checking testbench for the 10:1 DDR TMDS serializer.
//
// Sends known 10-bit characters, captures the serial output on both edges
// of serial_clk after the 2-cycle pipeline, and checks that the received
// order is din[0], din[1], ... din[9] (DVI LSB-first).
//
// Uses the behavioural PH1P_LOGIC_ODDR model:
//   d0 is the posedge bit, d1 is the negedge bit, both sampled at posedge.
// ============================================================================
`timescale 1ns / 1ps

module tb_tmds_serializer;

    reg        serial_clk;
    reg        rst;
    reg        load;
    reg  [9:0] din;
    wire       serial_out;

    integer errors;

    tmds_serializer dut (
        .serial_clk (serial_clk ),
        .rst        (rst        ),
        .load       (load       ),
        .din        (din        ),
        .serial_out (serial_out )
    );

    initial serial_clk = 1'b0;
    always #4.000 serial_clk = ~serial_clk;   // 125 MHz

    task send_and_check(input [9:0] w);
        integer i;
        reg [9:0] cap;
        begin
            @(negedge serial_clk);
            din  = w;
            load = 1'b1;
            @(negedge serial_clk);
            load = 1'b0;

            // Load was sampled at the posedge between the two negedges.
            // Skip two serial cycles of pipeline latency.
            @(posedge serial_clk);
            @(posedge serial_clk);

            for (i = 0; i < 5; i = i + 1) begin
                #1 cap[2*i]   = serial_out;   // posedge bit
                @(negedge serial_clk);
                #1 cap[2*i+1] = serial_out;   // negedge bit
                @(posedge serial_clk);
            end

            if (cap !== w) begin
                $display("FAIL din=%b -> serial=%b", w, cap);
                errors = errors + 1;
            end else begin
                $display("ok   din=%b -> serial=%b", w, cap);
            end
        end
    endtask

    initial begin
        errors = 0;
        rst    = 1'b1;
        load   = 1'b0;
        din    = 10'd0;

        repeat (4) @(posedge serial_clk);
        rst = 1'b0;
        repeat (2) @(posedge serial_clk);

        send_and_check(10'b1011001110);
        send_and_check(10'b0000011111);   // TMDS clock pattern (5 ones first)
        send_and_check(10'b0100000000);
        send_and_check(10'b1111111111);
        send_and_check(10'b0010110101);

        if (errors == 0)
            $display("TB: PASS - tmds_serializer");
        else
            $display("TB: FAIL - tmds_serializer, errors=%0d", errors);

        $finish;
    end

endmodule
