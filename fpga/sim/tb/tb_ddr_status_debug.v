// ============================================================================
// tb_ddr_status_debug.v
//
// Verifies the debug status/timeout logic without the encrypted DDR IP:
//   1. PLL locked + READY high before timeout -> timeout stays 0
//   2. PLL locked + READY never high          -> timeout latches 1
//   3. PLL not locked + READY never high      -> pll_lock=0, timeout=1
//
// The timeout is shortened to 50 clk_50m cycles for simulation.
// ============================================================================
`timescale 1ns / 1ps

module tb_ddr_status_debug;

    localparam integer TIMEOUT = 50;

    reg  clk;
    reg  rst_n;
    reg  ddrphy_rst_n;
    reg  ddrphy_rdy;
    wire pll_lock;
    wire ready;
    wire timeout;

    integer errors;

    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    ddr_status_debug #(
        .TIMEOUT_CYCLES (TIMEOUT)
    ) dut (
        .clk_50m      (clk),
        .rst_n        (rst_n),
        .ddrphy_rst_n (ddrphy_rst_n),
        .ddrphy_rdy   (ddrphy_rdy),
        .pll_lock     (pll_lock),
        .ready        (ready),
        .timeout      (timeout)
    );

    task reset_dut;
        begin
            rst_n        = 1'b0;
            ddrphy_rst_n = 1'b0;
            ddrphy_rdy   = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        rst_n  = 1'b0;
        ddrphy_rst_n = 1'b0;
        ddrphy_rdy   = 1'b0;

        // Case 1: PLL + READY before timeout.
        reset_dut;
        ddrphy_rst_n = 1'b1;
        ddrphy_rdy   = 1'b1;
        repeat (10) @(posedge clk);
        if (pll_lock !== 1'b1 || ready !== 1'b1 || timeout !== 1'b0) begin
            $display("FAIL case1 pll=%b ready=%b timeout=%b", pll_lock, ready, timeout);
            errors = errors + 1;
        end else
            $display("ok   case1: PLL locked, READY high, no timeout");

        // Case 2: PLL locked, READY never high.
        reset_dut;
        ddrphy_rst_n = 1'b1;
        ddrphy_rdy   = 1'b0;
        repeat (TIMEOUT + 10) @(posedge clk);
        if (pll_lock !== 1'b1 || ready !== 1'b0 || timeout !== 1'b1) begin
            $display("FAIL case2 pll=%b ready=%b timeout=%b", pll_lock, ready, timeout);
            errors = errors + 1;
        end else
            $display("ok   case2: PLL locked, READY missing, timeout latched");

        // Case 3: neither PLL nor READY.
        reset_dut;
        ddrphy_rst_n = 1'b0;
        ddrphy_rdy   = 1'b0;
        repeat (TIMEOUT + 10) @(posedge clk);
        if (pll_lock !== 1'b0 || ready !== 1'b0 || timeout !== 1'b1) begin
            $display("FAIL case3 pll=%b ready=%b timeout=%b", pll_lock, ready, timeout);
            errors = errors + 1;
        end else
            $display("ok   case3: no PLL lock, no READY, timeout latched");

        if (errors == 0)
            $display("TB: PASS - ddr_status_debug");
        else
            $display("TB: FAIL - ddr_status_debug, errors=%0d", errors);

        $finish;
    end

endmodule
