// ============================================================================
// tb_ddr_axi_pattern_test.v
//
// Self-checking simulation of the AXI pattern master against a behavioural
// DDR AXI slave model. The encrypted vendor DDR IP is not simulated; this
// verifies the master FSM/handshake/comparator only.
//
// Two configurations:
//   CORRUPT=0 -> expect PASS, err_cnt=0
//   CORRUPT=1 -> expect FAIL, err_cnt>0 (the model flips beat 5)
//
// READY_DELAY exercises the ready/valid handshake (0 and 2).
// ============================================================================
`timescale 1ns / 1ps

module tb_ddr_axi_pattern_test;

    parameter integer CORRUPT     = 0;
    parameter integer READY_DELAY = 0;
    parameter integer LEGACY_STEP = 0;
    parameter integer LEGACY_MASK = 0;

    reg         clk;
    reg         rst_n;
    reg         start;

    wire [24:0]  awaddr;
    wire         awvalid;
    wire         awready;
    wire [127:0] wdata;
    wire [15:0]  wstrb;
    wire         wvalid;
    wire         wlast;
    wire         wready;
    wire [24:0]  araddr;
    wire         arvalid;
    wire         arready;
    wire [127:0] rdata;
    wire         rlast;
    wire         rvalid;
    wire         rready;

    wire         done;
    wire         pass;
    wire         fail;
    wire [7:0]   err_cnt;

    integer errors;
    integer i;

    // 133.33 MHz MC clock
    initial clk = 1'b0;
    always #3.75 clk = ~clk;

    ddr_axi_pattern_test #(
        .ADDR_WIDTH (25),
        .DATA_WIDTH (128),
        .STRB_WIDTH (16),
        .N          (16),
        .ADDR_STEP  (LEGACY_STEP ? 1 : 8),
        .TIMEOUT    (100_000)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .paxi_awaddr  (awaddr),
        .paxi_awvalid (awvalid),
        .paxi_awready (awready),
        .paxi_wdata   (wdata),
        .paxi_wstrb   (wstrb),
        .paxi_wvalid  (wvalid),
        .paxi_wlast   (wlast),
        .paxi_wready  (wready),
        .paxi_araddr  (araddr),
        .paxi_arvalid (arvalid),
        .paxi_arready (arready),
        .paxi_rdata   (rdata),
        .paxi_rlast   (rlast),
        .paxi_rvalid  (rvalid),
        .paxi_rready  (rready),
        .done         (done),
        .pass         (pass),
        .fail         (fail),
        .err_cnt      (err_cnt)
    );

    ddr_axi_slave_model #(
        .ADDR_WIDTH  (25),
        .DATA_WIDTH  (128),
        .STRB_WIDTH  (16),
        .READY_DELAY (READY_DELAY),
        .CORRUPT     (CORRUPT)
    ) u_model (
        .clk          (clk),
        .rst_n        (rst_n),
        .paxi_awaddr  (awaddr),
        .paxi_awvalid (awvalid),
        .paxi_awready (awready),
        .paxi_wdata   (wdata),
        .paxi_wstrb   (LEGACY_MASK ? 16'hFFFF : wstrb),
        .paxi_wvalid  (wvalid),
        .paxi_wlast   (wlast),
        .paxi_wready  (wready),
        .paxi_araddr  (araddr),
        .paxi_arvalid (arvalid),
        .paxi_arready (arready),
        .paxi_rdata   (rdata),
        .paxi_rlast   (rlast),
        .paxi_rvalid  (rvalid),
        .paxi_rready  (rready)
    );

    initial begin
        errors = 0;
        rst_n  = 1'b0;
        start  = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        start = 1'b1;

        // Wait for a result, with a simulation timeout much shorter than
        // the DUT's 100k-cycle watchdog.
        for (i = 0; i < 20000 && !(done || fail); i = i + 1)
            @(posedge clk);

        if (!(done || fail)) begin
            $display("FAIL: timeout waiting for done/fail");
            errors = errors + 1;
        end else if (CORRUPT || LEGACY_STEP || LEGACY_MASK) begin
            if (pass !== 1'b0 || fail !== 1'b1 || err_cnt == 0) begin
                $display("FAIL: corrupt case pass=%b fail=%b err_cnt=%0d",
                         pass, fail, err_cnt);
                errors = errors + 1;
            end else begin
                $display("ok   corrupt detected, err_cnt=%0d", err_cnt);
            end
        end else begin
            if (pass !== 1'b1 || fail !== 1'b0 || err_cnt != 0) begin
                $display("FAIL: normal case pass=%b fail=%b err_cnt=%0d",
                         pass, fail, err_cnt);
                errors = errors + 1;
            end else begin
                $display("ok   all beats matched (READY_DELAY=%0d)", READY_DELAY);
            end
        end

        if (u_model.protocol_error !== (LEGACY_STEP != 0)) begin
            $display("FAIL alignment detection"); errors = errors + 1;
        end
        if (LEGACY_MASK && u_model.mem[0] !== 128'd0) begin
            $display("FAIL masked write modified memory"); errors = errors + 1;
        end
        if (errors == 0)
            $display("TB: PASS - ddr_axi_pattern_test (CORRUPT=%0d READY_DELAY=%0d)",
                     CORRUPT, READY_DELAY);
        else
            $display("TB: FAIL - ddr_axi_pattern_test, errors=%0d", errors);

        if (errors != 0) $fatal(1,"Test failed");
        $finish;
    end

endmodule
