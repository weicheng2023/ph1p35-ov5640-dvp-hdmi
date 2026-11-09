// Native PH1P PAXI contract model: 16-bit addresses, active-high mask.
`timescale 1ns/1ps
module ddr_axi_slave_model #(
    parameter integer ADDR_WIDTH = 25,
    parameter integer DATA_WIDTH = 128,
    parameter integer STRB_WIDTH = 16,
    parameter integer DEPTH = 1024,   // Number of 128-bit blocks
    parameter integer READY_DELAY = 0,
    parameter integer CORRUPT = 0,
    parameter integer CORRUPT_ADDR = 40
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [ADDR_WIDTH-1:0]    paxi_awaddr,
    input  wire                     paxi_awvalid,
    output wire                     paxi_awready,
    input  wire [DATA_WIDTH-1:0]    paxi_wdata,
    input  wire [STRB_WIDTH-1:0]    paxi_wstrb,
    input  wire                     paxi_wvalid,
    input  wire                     paxi_wlast,
    output wire                     paxi_wready,

    input  wire [ADDR_WIDTH-1:0]    paxi_araddr,
    input  wire                     paxi_arvalid,
    output wire                     paxi_arready,
    output reg  [DATA_WIDTH-1:0]    paxi_rdata,
    output reg                      paxi_rlast,
    output reg                      paxi_rvalid,
    input  wire                     paxi_rready
);


    // Contract model, not a PHY model. Native address units are 16-bit words.
    localparam integer WORDS_PER_BEAT = DATA_WIDTH / 16;
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] rd_addr, wr_addr;
    reg aw_pending, w_seen;
    reg protocol_error;
    integer aw_age, aw_wait, w_wait, ar_wait, rd_delay;
    integer i, b;
    initial begin
        for (i=0; i<DEPTH; i=i+1) mem[i] = 0;
    end

    assign paxi_awready = !aw_pending && (aw_wait == 0);
    assign paxi_wready = aw_pending && (w_wait == 0);
    assign paxi_arready = (ar_wait == 0) && (rd_delay == 0) && !paxi_rvalid;

    // Hold checks catch dropping VALID or changing payload under backpressure.
    reg aw_stall, w_stall, ar_stall;
    reg [ADDR_WIDTH-1:0] prev_aw, prev_ar;
    reg [DATA_WIDTH+STRB_WIDTH:0] prev_w;
    always @(posedge clk) begin
        if (rst_n) begin
            if (aw_stall && (!paxi_awvalid || paxi_awaddr !== prev_aw))
                $fatal(1, "AW changed while stalled");
            if (w_stall && (!paxi_wvalid || {paxi_wlast,paxi_wstrb,paxi_wdata} !== prev_w))
                $fatal(1, "W changed while stalled");
            if (ar_stall && (!paxi_arvalid || paxi_araddr !== prev_ar))
                $fatal(1, "AR changed while stalled");
        end
        aw_stall <= rst_n && paxi_awvalid && !paxi_awready;
        w_stall <= rst_n && paxi_wvalid && !paxi_wready;
        ar_stall <= rst_n && paxi_arvalid && !paxi_arready;
        prev_aw <= paxi_awaddr;
        prev_ar <= paxi_araddr;
        prev_w <= {paxi_wlast,paxi_wstrb,paxi_wdata};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pending <= 0;
            w_seen <= 0;
            protocol_error <= 0;
            aw_age <= 0;
            aw_wait <= READY_DELAY;
            w_wait <= 0;
            ar_wait <= READY_DELAY;
            rd_delay <= 0;
            paxi_rvalid <= 0;
            paxi_rlast <= 0;
            paxi_rdata <= 0;
        end else begin
            // Periodic AW/AR stalls and W stalls after AW acceptance ensure
            // the backpressure case really separates address/data handshakes.
            if (aw_wait == 0) aw_wait <= READY_DELAY;
            else aw_wait <= aw_wait - 1;
            if (ar_wait == 0) ar_wait <= READY_DELAY;
            else ar_wait <= ar_wait - 1;
            if (w_wait != 0) w_wait <= w_wait - 1;

            if (paxi_awvalid && paxi_awready) begin
                wr_addr <= paxi_awaddr;
                aw_pending <= 1;
                aw_age <= 0;
                w_seen <= 0;
                w_wait <= READY_DELAY;
                if ((paxi_awaddr % WORDS_PER_BEAT) != 0 ||
                    paxi_awaddr / WORDS_PER_BEAT >= DEPTH) begin
                    protocol_error <= 1;
                    $display("MODEL: invalid AW alignment/range addr=%0d",paxi_awaddr);
                end
            end
            if (aw_pending) begin
                aw_age <= aw_age + 1;
                if (paxi_wvalid) w_seen <= 1;
                // WVALID presentation, not WREADY acceptance, has a 2-cycle bound.
                if (!w_seen && !paxi_wvalid && aw_age >= 1)
                    $fatal(1, "W not presented within two clocks after AW");
            end
            if (paxi_wvalid && paxi_wready) begin
                if (!paxi_wlast) $fatal(1, "Expected single-beat WLAST");
                if ((wr_addr % WORDS_PER_BEAT) == 0 && wr_addr / WORDS_PER_BEAT < DEPTH)
                    for (b=0; b<STRB_WIDTH; b=b+1)
                        // One means MASKED (preserve byte), zero means WRITE.
                        if (!paxi_wstrb[b]) mem[wr_addr / WORDS_PER_BEAT][8*b +: 8] <= paxi_wdata[8*b +: 8];
                aw_pending <= 0;
            end
            if (paxi_arvalid && paxi_arready) begin
                rd_addr <= paxi_araddr;
                rd_delay <= 1;
                if ((paxi_araddr % WORDS_PER_BEAT) != 0 ||
                    paxi_araddr / WORDS_PER_BEAT >= DEPTH) begin
                    protocol_error <= 1;
                    $display("MODEL: invalid AR alignment/range addr=%0d",paxi_araddr);
                end
            end
            if (rd_delay != 0) begin
                rd_delay <= rd_delay-1;
                if (rd_delay == 1) begin
                    paxi_rvalid <= 1;
                    paxi_rlast <= 1;
                    if ((rd_addr % WORDS_PER_BEAT) != 0 || rd_addr / WORDS_PER_BEAT >= DEPTH)
                        paxi_rdata <= {DATA_WIDTH{1'bx}};
                    else paxi_rdata <= mem[rd_addr / WORDS_PER_BEAT] ^
                        ((CORRUPT && rd_addr == CORRUPT_ADDR) ? {{(DATA_WIDTH-1){1'b0}},1'b1} : {DATA_WIDTH{1'b0}});
                end
            end
            if (paxi_rvalid && paxi_rready) begin
                paxi_rvalid <= 0;
                paxi_rlast <= 0;
            end
        end
    end
endmodule
