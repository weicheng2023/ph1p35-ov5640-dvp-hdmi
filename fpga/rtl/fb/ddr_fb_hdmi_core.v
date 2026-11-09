// ============================================================================
// ddr_fb_hdmi_core.v
//
// 640x480 RGB565 test image -> DDR frame buffer -> HDMI.
//
// Phase order (dhi_clk = DDR user clock):
//   WAIT  : wait ddrphy_rdy
//   SELF  : 16-beat native-paxi write/read self-check at native addresses 0..120 (step 8)
//   WRITE : generate 38400 beats (600 KiB) at native addresses 4096..311288 (step 8), plus CRC
//   DRAIN : conservative wait (NOT a write-completion claim)
//   VERIFY: read all 38400 beats, per-pixel expected compare + CRC
//   PREFILL: display reader fills 192 FIFO words
//   STREAM: continuous display read + 128-bit FIFO + 8:1 gearbox
//   ERROR : fatal self-check/write/verify error; HDMI shows category color
//
// Single-beat transactions only. AW/W are independent. One outstanding read.
// The FIFO is the only multi-bit CDC (Gray pointers, 128-bit x 256).
//
// CAL_EN=0 is selected in the board top; this is an EXPERIMENTAL config
// (PHY training bypassed). The self-check + full-frame readback CRC are the
// data evidence; they do not prove complete PHY calibration.
// ============================================================================
`timescale 1ns / 1ps

module ddr_fb_hdmi_core (
    input  wire        clk_50m,
    input  wire        rst_n,
    input  wire        dhi_clk,
    input  wire        ddrphy_rdy,

    // Native paxi master to the DDR wrapper
    output wire [24:0] paxi_awaddr,
    output wire        paxi_awvalid,
    input  wire        paxi_awready,
    output wire [127:0] paxi_wdata,
    output wire [15:0] paxi_wstrb,
    output wire        paxi_wvalid,
    output wire        paxi_wlast,
    input  wire        paxi_wready,
    output wire [24:0] paxi_araddr,
    output wire        paxi_arvalid,
    input  wire        paxi_arready,
    input  wire [127:0] paxi_rdata,
    input  wire        paxi_rlast,
    input  wire        paxi_rvalid,
    output wire        paxi_rready,

    // HDMI
    output wire        tmds_clk_p,
    output wire        tmds_d0_p,
    output wire        tmds_d1_p,
    output wire        tmds_d2_p,

    // Status
    output wire        ddr_ready_o,
    output wire        write_done_o,
    output wire        error_o,
    output wire        hdmi_lock_o
);

    // ------------------------------------------------------------------
    // Phase FSM (dhi_clk)
    // ------------------------------------------------------------------
    localparam [2:0] PH_WAIT    = 3'd0,
                     PH_SELF    = 3'd1,
                     PH_WRITE   = 3'd2,
                     PH_DRAIN   = 3'd3,
                     PH_VERIFY  = 3'd4,
                     PH_PREFILL = 3'd5,
                     PH_STREAM  = 3'd6,
                     PH_ERROR   = 3'd7;

    localparam integer DRAIN_CYCLES = 1024;

    reg [2:0]  phase;
    reg        self_start;
    reg        writer_start;
    reg        reader_start;
    reg        reader_mode;
    reg [31:0] drain_cnt;
    reg        fatal_dhi;
    reg        display_error_dhi;
    reg [3:0]  error_code;
    reg [1:0]  rst_dhi_sync;
    reg [1:0]  rdy_sync;

    wire rst_dhi_n = rst_dhi_sync[1];
    wire ddr_ready = rdy_sync[1];

    always @(posedge dhi_clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_dhi_sync <= 2'b00;
            rdy_sync     <= 2'b00;
        end else begin
            rst_dhi_sync <= {rst_dhi_sync[0], 1'b1};
            rdy_sync     <= {rdy_sync[0], ddrphy_rdy};
        end
    end

    // ------------------------------------------------------------------
    // Self-check / writer / reader
    // ------------------------------------------------------------------
    wire [24:0] self_awaddr;
    wire        self_awvalid, self_awready;
    wire [127:0] self_wdata;
    wire [15:0] self_wstrb;
    wire        self_wvalid, self_wlast, self_wready;
    wire [24:0] self_araddr;
    wire        self_arvalid, self_arready;
    wire [127:0] self_rdata;
    wire        self_rlast, self_rvalid, self_rready;
    wire        self_done, self_pass, self_fail;
    wire [7:0]  self_err_cnt;
    wire [24:0] self_err_addr;
    wire [127:0] self_exp_data, self_act_data;
    wire        self_rlast_err;

    ddr_axi_pattern_test #(
        .ADDR_WIDTH   (25),
        .DATA_WIDTH   (128),
        .STRB_WIDTH   (16),
        .N            (16),
        .BASE_ADDR    (0),
        .DRAIN_CYCLES (1024),
        .TIMEOUT      (24_000_000)
    ) u_self (
        .clk           (dhi_clk),
        .rst_n         (rst_dhi_n),
        .start         (self_start),
        .paxi_awaddr   (self_awaddr),
        .paxi_awvalid  (self_awvalid),
        .paxi_awready  (self_awready),
        .paxi_wdata    (self_wdata),
        .paxi_wstrb    (self_wstrb),
        .paxi_wvalid   (self_wvalid),
        .paxi_wlast    (self_wlast),
        .paxi_wready   (self_wready),
        .paxi_araddr   (self_araddr),
        .paxi_arvalid  (self_arvalid),
        .paxi_arready  (self_arready),
        .paxi_rdata    (self_rdata),
        .paxi_rlast    (self_rlast),
        .paxi_rvalid   (self_rvalid),
        .paxi_rready   (self_rready),
        .done          (self_done),
        .pass          (self_pass),
        .fail          (self_fail),
        .err_cnt       (self_err_cnt),
        .err_addr      (self_err_addr),
        .exp_data      (self_exp_data),
        .act_data      (self_act_data),
        .rlast_err     (self_rlast_err)
    );

    wire [24:0] wr_awaddr;
    wire        wr_awvalid, wr_awready;
    wire [127:0] wr_wdata;
    wire [15:0] wr_wstrb;
    wire        wr_wvalid, wr_wlast, wr_wready;
    wire        writer_write_done;
    wire [31:0] writer_crc_expected;
    wire        writer_error;

    fb_writer #(
        .ADDR_WIDTH    (25),
        .BASE_ADDR     (4096),
        .BEATS_PER_ROW (80),
        .ROWS          (480),
        .TOTAL_BEATS   (38400),
        .TIMEOUT       (24_000_000)
    ) u_writer (
        .clk           (dhi_clk),
        .rst_n         (rst_dhi_n),
        .start         (writer_start),
        .paxi_awaddr   (wr_awaddr),
        .paxi_awvalid  (wr_awvalid),
        .paxi_awready  (wr_awready),
        .paxi_wdata    (wr_wdata),
        .paxi_wstrb    (wr_wstrb),
        .paxi_wvalid   (wr_wvalid),
        .paxi_wlast    (wr_wlast),
        .paxi_wready   (wr_wready),
        .write_done    (writer_write_done),
        .crc_expected  (writer_crc_expected),
        .error         (writer_error)
    );

    wire [24:0] rd_araddr;
    wire        rd_arvalid, rd_arready;
    wire [127:0] rd_rdata;
    wire        rd_rlast, rd_rvalid, rd_rready;
    wire        reader_fifo_wr_en;
    wire [127:0] reader_fifo_wr_data;
    wire        fifo_wr_full;
    wire        reader_fifo_wr_overflow;
    wire        reader_prefill_done;
    wire        reader_verify_done;
    wire        reader_crc_ok;
    wire [31:0] reader_crc_actual;
    wire        reader_err_valid;
    wire [18:0] reader_err_pixel;
    wire [24:0] reader_err_addr;
    wire [15:0] reader_err_exp, reader_err_act;
    wire        reader_error, reader_busy, reader_rlast_err;

    fb_reader #(
        .ADDR_WIDTH    (25),
        .BASE_ADDR     (4096),
        .BEATS_PER_ROW (80),
        .ROWS          (480),
        .TOTAL_BEATS   (38400),
        .PREFILL_WORDS (192),
        .TIMEOUT       (24_000_000)
    ) u_reader (
        .clk            (dhi_clk),
        .rst_n          (rst_dhi_n),
        .start          (reader_start),
        .mode           (reader_mode),
        .paxi_araddr    (rd_araddr),
        .paxi_arvalid   (rd_arvalid),
        .paxi_arready   (rd_arready),
        .paxi_rdata     (rd_rdata),
        .paxi_rlast     (rd_rlast),
        .paxi_rvalid    (rd_rvalid),
        .paxi_rready    (rd_rready),
        .fifo_wr_en     (reader_fifo_wr_en),
        .fifo_wr_data   (reader_fifo_wr_data),
        .fifo_wr_full   (fifo_wr_full),
        .fifo_wr_overflow (reader_fifo_wr_overflow),
        .prefill_done   (reader_prefill_done),
        .verify_done    (reader_verify_done),
        .crc_ok         (reader_crc_ok),
        .crc_actual     (reader_crc_actual),
        .crc_expected   (writer_crc_expected),
        .err_valid      (reader_err_valid),
        .err_pixel      (reader_err_pixel),
        .err_addr       (reader_err_addr),
        .err_exp        (reader_err_exp),
        .err_act        (reader_err_act),
        .error          (reader_error),
        .busy           (reader_busy),
        .rlast_err      (reader_rlast_err)
    );

    // ------------------------------------------------------------------
    // Paxi mux: exactly one of self/writer/reader owns the bus.
    // ------------------------------------------------------------------
    reg        self_awready_m, self_wready_m, self_arready_m;
    reg [127:0] self_rdata_m;
    reg        self_rlast_m, self_rvalid_m;
    reg        wr_awready_m, wr_wready_m;
    reg        rd_arready_m;
    reg [127:0] rd_rdata_m;
    reg        rd_rlast_m, rd_rvalid_m;

    reg [24:0] m_awaddr;
    reg        m_awvalid;
    reg [127:0] m_wdata;
    reg [15:0] m_wstrb;
    reg        m_wvalid, m_wlast;
    reg [24:0] m_araddr;
    reg        m_arvalid;
    reg        m_rready;

    always @* begin
        self_awready_m = 1'b0;
        self_wready_m  = 1'b0;
        self_arready_m = 1'b0;
        self_rdata_m   = 128'd0;
        self_rlast_m   = 1'b0;
        self_rvalid_m  = 1'b0;
        wr_awready_m   = 1'b0;
        wr_wready_m    = 1'b0;
        rd_arready_m   = 1'b0;
        rd_rdata_m     = 128'd0;
        rd_rlast_m     = 1'b0;
        rd_rvalid_m    = 1'b0;

        m_awaddr  = 25'd0;
        m_awvalid = 1'b0;
        m_wdata   = 128'd0;
        m_wstrb   = 16'd0;
        m_wvalid  = 1'b0;
        m_wlast   = 1'b0;
        m_araddr  = 25'd0;
        m_arvalid = 1'b0;
        m_rready  = 1'b0;

        case (phase)
            PH_SELF: begin
                m_awaddr      = self_awaddr;
                m_awvalid     = self_awvalid;
                m_wdata       = self_wdata;
                m_wstrb       = self_wstrb;
                m_wvalid      = self_wvalid;
                m_wlast       = self_wlast;
                m_araddr      = self_araddr;
                m_arvalid     = self_arvalid;
                m_rready      = self_rready;
                self_awready_m = paxi_awready;
                self_wready_m  = paxi_wready;
                self_arready_m = paxi_arready;
                self_rdata_m   = paxi_rdata;
                self_rlast_m   = paxi_rlast;
                self_rvalid_m  = paxi_rvalid;
            end
            PH_WRITE: begin
                m_awaddr     = wr_awaddr;
                m_awvalid    = wr_awvalid;
                m_wdata      = wr_wdata;
                m_wstrb      = wr_wstrb;
                m_wvalid     = wr_wvalid;
                m_wlast      = wr_wlast;
                wr_awready_m = paxi_awready;
                wr_wready_m  = paxi_wready;
            end
            PH_VERIFY, PH_PREFILL, PH_STREAM: begin
                m_araddr     = rd_araddr;
                m_arvalid    = rd_arvalid;
                m_rready     = rd_rready;
                rd_arready_m = paxi_arready;
                rd_rdata_m   = paxi_rdata;
                rd_rlast_m   = paxi_rlast;
                rd_rvalid_m  = paxi_rvalid;
            end
            default: begin
                // Bus idle (WAIT, DRAIN, ERROR)
            end
        endcase
    end

    assign paxi_awaddr  = m_awaddr;
    assign paxi_awvalid = m_awvalid;
    assign paxi_wdata   = m_wdata;
    assign paxi_wstrb   = m_wstrb;
    assign paxi_wvalid  = m_wvalid;
    assign paxi_wlast   = m_wlast;
    assign paxi_araddr  = m_araddr;
    assign paxi_arvalid = m_arvalid;
    assign paxi_rready  = m_rready;

    assign self_awready = self_awready_m;
    assign self_wready  = self_wready_m;
    assign self_arready = self_arready_m;
    assign self_rdata   = self_rdata_m;
    assign self_rlast   = self_rlast_m;
    assign self_rvalid  = self_rvalid_m;
    assign wr_awready   = wr_awready_m;
    assign wr_wready    = wr_wready_m;
    assign rd_arready   = rd_arready_m;
    assign rd_rdata     = rd_rdata_m;
    assign rd_rlast     = rd_rlast_m;
    assign rd_rvalid    = rd_rvalid_m;

    // ------------------------------------------------------------------
    // Display FIFO (128-bit x 256 words = 2048 pixels) + gearbox
    // ------------------------------------------------------------------
    wire        fifo_rd_en;
    wire [127:0] fifo_rd_data;
    wire        fifo_rd_empty;
    wire [15:0] img565;
    wire        underflow;

    // HDMI clock/reset nets are needed by the FIFO read side below.
    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;
    wire rst_pixel_n = rst_n && pll_lock;

    // underflow is a sticky pixel-domain flag; sync it to dhi_clk only for
    // the phase/status logic. The red-screen mux uses the pixel-domain flag.
    reg  uf_p1, uf_p2;
    always @(posedge dhi_clk or negedge rst_dhi_n) begin
        if (!rst_dhi_n) begin
            uf_p1 <= 1'b0;
            uf_p2 <= 1'b0;
        end else begin
            uf_p1 <= underflow;
            uf_p2 <= uf_p1;
        end
    end
    wire underflow_dhi = uf_p2;


    async_fifo_gray #(
        .DATA_WIDTH (128),
        .ADDR_WIDTH (8)
    ) u_fifo (
        .wr_clk      (dhi_clk),
        .wr_rst_n    (rst_dhi_n),
        .wr_en       (reader_fifo_wr_en),
        .wr_data     (reader_fifo_wr_data),
        .wr_full     (fifo_wr_full),
        .wr_overflow (reader_fifo_wr_overflow),
        .rd_clk      (pixel_clk),
        .rd_rst_n    (rst_pixel_n),
        .rd_en       (fifo_rd_en),
        .rd_data     (fifo_rd_data),
        .rd_empty    (fifo_rd_empty)
    );

    // ------------------------------------------------------------------
    // HDMI PLL / timing / video
    // ------------------------------------------------------------------
    pll_hdmi u_hdmi_pll (
        .clk_50m    (clk_50m),
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .lock       (pll_lock)
    );

    wire hdmi_rst = ~pll_lock;

    wire [9:0] hcount;
    wire [9:0] vcount;
    wire       de;
    wire       hs;
    wire       vs;

    video_timing u_timing (
        .pixel_clk (pixel_clk),
        .rst       (hdmi_rst),
        .hcount    (hcount),
        .vcount    (vcount),
        .de        (de),
        .hs        (hs),
        .vs        (vs)
    );

    // Prefill/VSYNC-aligned video start.
    reg prefill_p1, prefill_p2;
    reg vs_q;
    reg video_valid;

    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            prefill_p1 <= 1'b0;
            prefill_p2 <= 1'b0;
        end else begin
            prefill_p1 <= reader_prefill_done;
            prefill_p2 <= prefill_p1;
        end
    end

    wire vs_fall = vs_q && !vs;

    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            vs_q        <= 1'b1;
            video_valid <= 1'b0;
        end else begin
            vs_q <= vs;
            if (prefill_p2 && vs_fall)
                video_valid <= 1'b1;
        end
    end

    pixel_gearbox u_gearbox (
        .pixel_clk     (pixel_clk),
        .rst_n         (rst_pixel_n),
        .video_valid   (video_valid),
        .de            (de),
        .fifo_rd_data  (fifo_rd_data),
        .fifo_rd_empty (fifo_rd_empty),
        .fifo_rd_en    (fifo_rd_en),
        .rgb565        (img565),
        .underflow     (underflow)
    );

    wire [23:0] img888;
    rgb565_to_rgb888 u_cvt (
        .rgb565 (img565),
        .rgb888 (img888)
    );

    // Fatal/display-error CDC to the pixel domain for the red screen.
    reg fatal_p1, fatal_p2;
    reg derr_p1, derr_p2;
    // Each category is a sticky single-bit flag with its own 2FF CDC.
    // Avoid sampling a multi-bit error code asynchronously.
    reg self_error_p1, self_error_p2;
    reg verify_error_p1, verify_error_p2;

    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            fatal_p1 <= 1'b0;
            fatal_p2 <= 1'b0;
            derr_p1  <= 1'b0;
            derr_p2  <= 1'b0;
            self_error_p1 <= 1'b0;
            self_error_p2 <= 1'b0;
            verify_error_p1 <= 1'b0;
            verify_error_p2 <= 1'b0;
        end else begin
            fatal_p1 <= fatal_dhi;
            fatal_p2 <= fatal_p1;
            derr_p1  <= display_error_dhi;
            derr_p2  <= derr_p1;
            self_error_p1 <= fatal_dhi && (error_code == 4'd1);
            self_error_p2 <= self_error_p1;
            verify_error_p1 <= fatal_dhi && (error_code == 4'd3);
            verify_error_p2 <= verify_error_p1;
        end
    end

    // Red=self test, magenta=frame verify, yellow=FIFO/stream,
    // orange=writer error; dark blue=waiting. Image data comes only from FIFO.
    wire [23:0] rgb = (derr_p2 || underflow) ? 24'hFFFF00 :
                      self_error_p2 ? 24'hFF0000 :
                      verify_error_p2 ? 24'hFF00FF :
                      fatal_p2 ? 24'hFF8000 :
                      (!video_valid ? 24'h000040 : img888);

    // ------------------------------------------------------------------
    // TMDS chain (same proven modules)
    // ------------------------------------------------------------------
    wire [9:0] tmds_ch0;
    wire [9:0] tmds_ch1;
    wire [9:0] tmds_ch2;

    tmds_encoder u_enc_b (
        .clk  (pixel_clk),
        .rst  (hdmi_rst),
        .din  (rgb[7:0]),
        .ctrl ({vs, hs}),
        .de   (de),
        .dout (tmds_ch0)
    );

    tmds_encoder u_enc_g (
        .clk  (pixel_clk),
        .rst  (hdmi_rst),
        .din  (rgb[15:8]),
        .ctrl (2'b00),
        .de   (de),
        .dout (tmds_ch1)
    );

    tmds_encoder u_enc_r (
        .clk  (pixel_clk),
        .rst  (hdmi_rst),
        .din  (rgb[23:16]),
        .ctrl (2'b00),
        .de   (de),
        .dout (tmds_ch2)
    );

    wire load;

    serial_load_gen u_load (
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .rst        (hdmi_rst),
        .load       (load)
    );

    localparam [9:0] TMDS_CLK_PATTERN = 10'b0000011111;

    tmds_serializer u_ser_clk (
        .serial_clk (serial_clk),
        .rst        (hdmi_rst),
        .load       (load),
        .din        (TMDS_CLK_PATTERN),
        .serial_out (tmds_clk_p)
    );

    tmds_serializer u_ser_ch0 (
        .serial_clk (serial_clk),
        .rst        (hdmi_rst),
        .load       (load),
        .din        (tmds_ch0),
        .serial_out (tmds_d0_p)
    );

    tmds_serializer u_ser_ch1 (
        .serial_clk (serial_clk),
        .rst        (hdmi_rst),
        .load       (load),
        .din        (tmds_ch1),
        .serial_out (tmds_d1_p)
    );

    tmds_serializer u_ser_ch2 (
        .serial_clk (serial_clk),
        .rst        (hdmi_rst),
        .load       (load),
        .din        (tmds_ch2),
        .serial_out (tmds_d2_p)
    );

    // ------------------------------------------------------------------
    // Phase control
    // ------------------------------------------------------------------
    always @(posedge dhi_clk or negedge rst_dhi_n) begin
        if (!rst_dhi_n) begin
            phase             <= PH_WAIT;
            self_start        <= 1'b0;
            writer_start      <= 1'b0;
            reader_start      <= 1'b0;
            reader_mode       <= 1'b0;
            drain_cnt         <= 32'd0;
            fatal_dhi         <= 1'b0;
            display_error_dhi <= 1'b0;
            error_code        <= 4'd0;
        end else begin
            self_start   <= 1'b0;
            writer_start <= 1'b0;
            reader_start <= 1'b0;

            case (phase)
                PH_WAIT: begin
                    if (ddr_ready) begin
                        self_start <= 1'b1;
                        phase      <= PH_SELF;
                    end
                end

                PH_SELF: begin
                    if (self_done) begin
                        if (self_pass) begin
                            writer_start <= 1'b1;
                            phase        <= PH_WRITE;
                        end else begin
                            fatal_dhi  <= 1'b1;
                            error_code <= 4'd1;
                            phase      <= PH_ERROR;
                        end
                    end else if (self_fail) begin
                        fatal_dhi  <= 1'b1;
                        error_code <= 4'd1;
                        phase      <= PH_ERROR;
                    end
                end

                PH_WRITE: begin
                    if (writer_write_done) begin
                        drain_cnt <= 32'd0;
                        phase     <= PH_DRAIN;
                    end else if (writer_error) begin
                        fatal_dhi  <= 1'b1;
                        error_code <= 4'd2;
                        phase      <= PH_ERROR;
                    end
                end

                PH_DRAIN: begin
                    // Conservative drain; the readback verify is the proof.
                    if (drain_cnt >= (DRAIN_CYCLES - 1)) begin
                        reader_mode  <= 1'b0;
                        reader_start <= 1'b1;
                        phase        <= PH_VERIFY;
                    end else begin
                        drain_cnt <= drain_cnt + 32'd1;
                    end
                end

                PH_VERIFY: begin
                    if (reader_verify_done) begin
                        if (reader_crc_ok) begin
                            reader_mode  <= 1'b1;
                            reader_start <= 1'b1;
                            phase        <= PH_PREFILL;
                        end else begin
                            fatal_dhi  <= 1'b1;
                            error_code <= 4'd3;
                            phase      <= PH_ERROR;
                        end
                    end else if (reader_error) begin
                        fatal_dhi  <= 1'b1;
                        error_code <= 4'd3;
                        phase      <= PH_ERROR;
                    end
                end

                PH_PREFILL: begin
                    if (reader_prefill_done) begin
                        phase <= PH_STREAM;
                    end else if (reader_error) begin
                        display_error_dhi <= 1'b1;
                        error_code        <= 4'd4;
                        phase             <= PH_STREAM;
                    end
                end

                PH_STREAM: begin
                    if (reader_error) begin
                        display_error_dhi <= 1'b1;
                        error_code        <= 4'd4;
                    end
                end

                PH_ERROR: begin
                    // Hold; HDMI error color; no more paxi transactions.
                end

                default: phase <= PH_ERROR;
            endcase

            if (reader_fifo_wr_overflow) begin
                display_error_dhi <= 1'b1;
                error_code        <= 4'd4;
            end
            if (underflow_dhi) begin
                display_error_dhi <= 1'b1;
                error_code        <= 4'd4;
            end
        end
    end

    // ------------------------------------------------------------------
    // Status + debug (ChipWatcher can probe the *_dbg signals)
    // ------------------------------------------------------------------
    (* keep *) wire [24:0]  dbg_self_err_addr  = self_err_addr;
    (* keep *) wire [127:0] dbg_self_exp_data  = self_exp_data;
    (* keep *) wire [127:0] dbg_self_act_data  = self_act_data;
    (* keep *) wire [7:0]   dbg_self_err_cnt   = self_err_cnt;
    (* keep *) wire         dbg_self_rlast_err = self_rlast_err;
    (* keep *) wire         dbg_self_pass      = self_pass;

    (* keep *) wire [31:0]  dbg_crc_expected   = writer_crc_expected;
    (* keep *) wire [31:0]  dbg_crc_actual     = reader_crc_actual;
    (* keep *) wire         dbg_crc_ok         = reader_crc_ok;

    (* keep *) wire         dbg_frame_err_valid = reader_err_valid;
    (* keep *) wire [18:0]  dbg_frame_err_pixel = reader_err_pixel;
    (* keep *) wire [24:0]  dbg_frame_err_addr  = reader_err_addr;
    (* keep *) wire [15:0]  dbg_frame_err_exp   = reader_err_exp;
    (* keep *) wire [15:0]  dbg_frame_err_act   = reader_err_act;

    (* keep *) wire         dbg_fifo_underflow = underflow;
    (* keep *) wire         dbg_fifo_overflow  = reader_fifo_wr_overflow;
    (* keep *) wire         dbg_write_done     = writer_write_done;
    (* keep *) wire         dbg_verify_done    = reader_verify_done;
    (* keep *) wire         dbg_prefill_done   = reader_prefill_done;
    (* keep *) wire [3:0]   dbg_error_code     = error_code;
    (* keep *) wire [2:0]   dbg_phase          = phase;

    assign ddr_ready_o  = ddr_ready;
    assign write_done_o = writer_write_done;
    assign error_o      = fatal_dhi || display_error_dhi || underflow;
    assign hdmi_lock_o  = pll_lock;

endmodule
