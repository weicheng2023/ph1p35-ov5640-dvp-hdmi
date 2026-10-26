// ============================================================================
// tb_ov5640_bringup.v
// Configuration/readback testbench for ov5640_bringup.
//
// The SCCB slave model stores writes in a register file and returns them on
// readback. This verifies:
//   - power/reset + Chip ID read (0x5640)
//   - the RGB565 table is written
//   - 0x4740=0x22, 0x4300=0x61, 0x3808..0x380B=640x480, 0x503D by COLOR_BAR
//   - the config sequencer's readback path and cfg_ok
//
// SCCB_DIV is small here to keep simulation fast. The real protocol regression
// at DIV=250 remains tb_top_cam_id.v; keep both.
// ============================================================================
`timescale 1ns / 1ps

module tb_ov5640_bringup;

    reg clk = 1'b0;
    always #10 clk = ~clk; // 50 MHz

    reg rst_n = 1'b0;

    wire       cam_scl;
    tri1       cam_sda;      // bus pull-up
    wire       cam_reset_n;
    wire       cam_pwdn;

    wire       id_match;
    wire       cfg_ok;
    wire       cfg_error;
    wire [7:0] rb_id_hi;
    wire [7:0] rb_id_lo;
    wire [7:0] rb_4300;
    wire [7:0] rb_4740;
    wire [7:0] rb_503d;
    wire [12:0] rb_width;
    wire [12:0] rb_height;
    wire [7:0] rb_3035;
    wire [7:0] rb_3036;
    wire [7:0] rb_3037;
    wire [7:0] rb_3108;
    wire [7:0] cfg_idx;

    localparam integer H_PIX     = 640;
    localparam integer V_PIX     = 480;
    localparam integer H_TOTAL   = 1600;
    localparam integer V_TOTAL   = 1000;
    localparam integer COLOR_BAR = 0;

    ov5640_bringup #(
        .SCCB_DIV           (10),       // fast test; protocol TB uses 250
        .PWRUP_CYCLES       (20),
        .RESET_WAIT_CYCLES  (20),
        .RETRY_CYCLES       (200),
        .SCCB_TIMEOUT       (200_000),
        .RESET_DELAY_CYCLES (50),
        .H_PIX              (H_PIX),
        .V_PIX              (V_PIX),
        .H_TOTAL            (H_TOTAL),
        .V_TOTAL            (V_TOTAL),
        .COLOR_BAR          (COLOR_BAR)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .cam_scl     (cam_scl),
        .cam_sda     (cam_sda),
        .cam_reset_n (cam_reset_n),
        .cam_pwdn    (cam_pwdn),
        .id_match    (id_match),
        .cfg_ok      (cfg_ok),
        .cfg_error   (cfg_error),
        .rb_id_hi    (rb_id_hi),
        .rb_id_lo    (rb_id_lo),
        .rb_4300     (rb_4300),
        .rb_4740     (rb_4740),
        .rb_503d     (rb_503d),
        .rb_width    (rb_width),
        .rb_height   (rb_height),
        .rb_3035     (rb_3035),
        .rb_3036     (rb_3036),
        .rb_3037     (rb_3037),
        .rb_3108     (rb_3108),
        .cfg_idx     (cfg_idx)
    );

    // ------------------------------------------------------------------
    // SCCB slave model
    // ------------------------------------------------------------------
    reg [7:0] regs [0:65535];

    reg        sda_drive = 1'b0;
    reg        sda_o     = 1'b1;
    assign cam_sda = sda_drive ? sda_o : 1'bz;

    reg [1:0]  mode;       // 0=idle, 1=write, 2=read
    reg [2:0]  byte_idx;
    reg [7:0]  rx;
    reg [3:0]  bitcnt;
    reg [15:0] reg_addr;
    reg [7:0]  tx;
    reg        scl_d;
    reg        sda_d;

    initial begin
        mode     = 2'd0;
        byte_idx = 3'd0;
        rx       = 8'd0;
        bitcnt   = 4'd0;
        reg_addr = 16'h0000;
        tx       = 8'd0;
        scl_d    = 1'b1;
        sda_d    = 1'b1;

        // Chip ID registers are read-only in the real sensor; the model
        // returns them for every read.
        regs[16'h300A] = 8'h56;
        regs[16'h300B] = 8'h40;
    end

    always @(posedge clk) begin
        scl_d <= cam_scl;
        sda_d <= cam_sda;

        // START / STOP detection (SCL high while SDA changes)
        if (cam_scl && scl_d) begin
            if (sda_d && !cam_sda) begin
                mode      <= 2'd1;
                byte_idx  <= 3'd0;
                bitcnt    <= 4'd0;
                rx        <= 8'd0;
                sda_drive <= 1'b0;
            end
            if (!sda_d && cam_sda) begin
                mode      <= 2'd0;
                bitcnt    <= 4'd0;
                sda_drive <= 1'b0;
            end
        end

        // SCL rising edge: sample / process a byte
        if (cam_scl && !scl_d) begin
            if (mode == 2'd1) begin
                if (bitcnt < 4'd8) begin
                    rx     <= {rx[6:0], cam_sda};
                    bitcnt <= bitcnt + 4'd1;
                end else begin
                    bitcnt <= 4'd0;
                    if (byte_idx == 3'd0) begin
                        if (rx[7:1] == 7'h3C) begin
                            if (rx[0] == 1'b0) begin
                                mode     <= 2'd1;
                                byte_idx <= 3'd1;
                            end else begin
                                mode <= 2'd2;
                                tx   <= regs[reg_addr];
                            end
                        end else begin
                            mode <= 2'd0;
                        end
                    end else if (byte_idx == 3'd1) begin
                        reg_addr[15:8] <= rx;
                        byte_idx       <= 3'd2;
                    end else if (byte_idx == 3'd2) begin
                        reg_addr[7:0] <= rx;
                        byte_idx      <= 3'd3;
                    end else begin
                        // Write data byte.
                        regs[reg_addr] <= rx;
                        byte_idx       <= 3'd3;
                    end
                end
            end else if (mode == 2'd2) begin
                if (bitcnt < 4'd8) begin
                    bitcnt <= bitcnt + 4'd1;
                end else begin
                    bitcnt <= 4'd0;
                    mode   <= 2'd0;
                end
            end
        end

        // SCL falling edge: drive ACK or read data
        if (!cam_scl && scl_d) begin
            if (mode == 2'd1 && bitcnt == 4'd8) begin
                sda_drive <= 1'b1;
                sda_o     <= 1'b0;     // ACK
            end else if (mode == 2'd2 && bitcnt < 4'd8) begin
                sda_drive <= 1'b1;
                sda_o     <= tx[7];
                tx        <= {tx[6:0], 1'b0};
            end else begin
                sda_drive <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Reset and check
    // ------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;
    end

    integer errors;

    initial begin
        errors = 0;
        $display("TB: start");
        wait (id_match);
        $display("TB: id_match=1");

        wait (cfg_ok || cfg_error);
        #2000;

        if (!cfg_ok || cfg_error) begin
            errors = errors + 1;
            $display("TB: cfg did not complete cleanly: cfg_ok=%b cfg_error=%b cfg_idx=%0d",
                     cfg_ok, cfg_error, cfg_idx);
        end

        if (regs[16'h4300] !== 8'h61) begin errors = errors + 1; $display("TB: 4300=%02h exp 61", regs[16'h4300]); end
        if (regs[16'h4740] !== 8'h22) begin errors = errors + 1; $display("TB: 4740=%02h exp 22", regs[16'h4740]); end
        if (regs[16'h3808] !== 8'h02) begin errors = errors + 1; $display("TB: 3808=%02h exp 02", regs[16'h3808]); end
        if (regs[16'h3809] !== 8'h80) begin errors = errors + 1; $display("TB: 3809=%02h exp 80", regs[16'h3809]); end
        if (regs[16'h380A] !== 8'h01) begin errors = errors + 1; $display("TB: 380A=%02h exp 01", regs[16'h380A]); end
        if (regs[16'h380B] !== 8'hE0) begin errors = errors + 1; $display("TB: 380B=%02h exp E0", regs[16'h380B]); end
        if (regs[16'h503D] !== (COLOR_BAR ? 8'h80 : 8'h00)) begin
            errors = errors + 1;
            $display("TB: 503D=%02h exp %02h", regs[16'h503D], COLOR_BAR ? 8'h80 : 8'h00);
        end
        if (regs[16'h3035] !== 8'h11) begin errors = errors + 1; $display("TB: 3035=%02h exp 11", regs[16'h3035]); end
        if (regs[16'h3036] !== 8'h3C) begin errors = errors + 1; $display("TB: 3036=%02h exp 3C", regs[16'h3036]); end
        if (regs[16'h3037] !== 8'h13) begin errors = errors + 1; $display("TB: 3037=%02h exp 13", regs[16'h3037]); end
        if (regs[16'h3108] !== 8'h01) begin errors = errors + 1; $display("TB: 3108=%02h exp 01", regs[16'h3108]); end

        if ((rb_width != H_PIX) || (rb_height != V_PIX)) begin
            errors = errors + 1;
            $display("TB: readback geometry %0dx%0d exp %0dx%0d",
                     rb_width, rb_height, H_PIX, V_PIX);
        end
        if ((rb_4300 !== 8'h61) || (rb_4740 !== 8'h22) ||
            (rb_503d !== (COLOR_BAR ? 8'h80 : 8'h00))) begin
            errors = errors + 1;
            $display("TB: readback 4300=%02h 4740=%02h 503D=%02h",
                     rb_4300, rb_4740, rb_503d);
        end
        if ((rb_id_hi !== 8'h56) || (rb_id_lo !== 8'h40)) begin
            errors = errors + 1;
            $display("TB: readback id=%02h%02h exp 5640", rb_id_hi, rb_id_lo);
        end

        if (errors == 0) begin
            $display("TB: PASS - cfg_ok=1, id=%02h%02h, geom=%0dx%0d, 4300=%02h, 4740=%02h, 503D=%02h",
                     rb_id_hi, rb_id_lo, rb_width, rb_height,
                     rb_4300, rb_4740, rb_503d);
        end else begin
            $display("TB: FAIL - %0d errors", errors);
        end
        $finish;
    end

    initial begin
        #(50_000_000); // 50 ms
        $display("TB: FAIL - timeout (id_match=%b cfg_ok=%b cfg_error=%b cfg_idx=%0d)",
                 id_match, cfg_ok, cfg_error, cfg_idx);
        $finish;
    end

endmodule
