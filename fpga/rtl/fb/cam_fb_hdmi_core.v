// ============================================================================
// cam_fb_hdmi_core.v
//
// Stage 3 integration: OV5640 DVP -> PCLK FIFO -> DDR double buffer ->
// display FIFO -> proven HDMI/TMDS chain.
//
// Data path:
//   cam_pclk  : ov5640_frame_capture -> 129-bit async FIFO (Gray pointers)
//   dhi_clk   : cam_fb_writer -> PAXI write into ping-pong buffer
//               cam_fb_reader -> PAXI read -> 128-bit display async FIFO
//   pixel_clk : pixel_gearbox -> RGB565->RGB888 -> TMDS
//
// Startup sequence (dhi_clk):
//   1. wait for ddrphy_rdy;
//   2. 16-beat native-PAXI self-check (same contract as Stage 2);
//   3. run the camera writer and display reader forever.
// The PAXI contract is unchanged: 16-bit-word addresses, ADDR_STEP=8,
// active-high write mask 16'h0000, AW first then W one cycle later.
//
// Ping-pong (no tearing):
//   - the writer writes buffer wr_idx only when the display is not reading
//     it (buf_free); otherwise the camera frame is dropped by the capture
//     module (the header is never pushed);
//   - the reader reads one complete frame per display frame and waits until
//     the display FIFO is empty before starting the next pass. The FIFO
//     empties exactly on the last active pixel, so the buffer index switch
//     happens in vertical blanking.
//
// CAL_EN=0 (set in the board top) is an EXPERIMENTAL configuration: PHY
// training is bypassed. The self-check and the visible image are the data
// evidence; they do not prove complete PHY calibration.
// ============================================================================
`timescale 1ns / 1ps

module cam_fb_hdmi_core #(
    parameter integer HREF_ACTIVE_HIGH  = 1,
    parameter integer VSYNC_ACTIVE_HIGH = 1,
    parameter integer CAPTURE_START     = 0,
    parameter integer BYTE_SWAP         = 0,
    parameter integer PIXELS            = 640,
    parameter integer V_ACTIVE          = 480,
    parameter integer BASE_ADDR         = 4096,
    parameter integer FRAME_STRIDE      = 307200,
    parameter integer TOTAL_BEATS       = 38400,
    parameter integer PREFILL_WORDS     = 192
) (
    input  wire        clk_50m,
    input  wire        rst_n,
    input  wire        cfg_ok,

    // Camera DVP (PCLK domain)
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,

    // DDR controller interface
    input  wire        dhi_clk,
    input  wire        ddrphy_rdy,

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
    output wire        self_pass_o,
    output wire        frame_valid_o,
    output wire        capture_error_o,
    output wire        error_o,
    output wire        hdmi_lock_o
);

    // ------------------------------------------------------------------
    // dhi_clk reset and READY synchronizers
    // ------------------------------------------------------------------
    reg [1:0] rst_dhi_sync;
    reg [1:0] rdy_sync;

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
    // Phase FSM
    // ------------------------------------------------------------------
    localparam [1:0] PH_WAIT  = 2'd0,
                     PH_SELF  = 2'd1,
                     PH_RUN   = 2'd2,
                     PH_ERROR = 2'd3;

    reg [1:0] phase;
    reg       self_start;

    wire self_done, self_pass, self_fail;

    always @(posedge dhi_clk or negedge rst_dhi_n) begin
        if (!rst_dhi_n) begin
            phase       <= PH_WAIT;
            self_start  <= 1'b0;
        end else begin
            self_start  <= 1'b0;
            case (phase)
                PH_WAIT: begin
                    if (ddr_ready) begin
                        self_start <= 1'b1;
                        phase      <= PH_SELF;
                    end
                end
                PH_SELF: begin
                    if (self_done) begin
                        if (self_pass) phase <= PH_RUN;
                        else           phase <= PH_ERROR;
                    end else if (self_fail) begin
                        phase <= PH_ERROR;
                    end
                end
                PH_RUN: begin
                    // Forever.
                end
                PH_ERROR: begin
                    // Hold; PAXI is idle.
                end
                default: phase <= PH_ERROR;
            endcase
        end
    end

    wire run = (phase == PH_RUN);

    // ------------------------------------------------------------------
    // 16-beat native-PAXI self-check
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
        .err_cnt       (),
        .err_addr      (),
        .exp_data      (),
        .act_data      (),
        .rlast_err     ()
    );

    // ------------------------------------------------------------------
    // Ping-pong indices (all in dhi_clk)
    // ------------------------------------------------------------------
    reg [0:0] complete_idx;
    reg       complete_valid;
    reg [0:0] disp_idx;
    reg       disp_valid;

    wire [0:0] writer_done_idx;
    wire       writer_frame_done;
    wire [0:0] wr_idx;
    wire       writer_busy;
    wire       reader_pass_done;

    wire switch_now = disp_valid && reader_pass_done && complete_valid &&
                      (complete_idx != disp_idx);
    wire [0:0] eff_idx = !disp_valid ? complete_idx
                                     : (switch_now ? complete_idx : disp_idx);

    // Base for the pass that starts this cycle. `pass_done` is asserted by
    // the reader for one cycle; the core resolves the switch combinationally
    // so the reader latches the new base on that same edge.
    wire [24:0] pass_base = BASE_ADDR + (eff_idx ? FRAME_STRIDE : 0);

    wire [0:0] reader_busy_idx = disp_valid ? disp_idx : complete_idx;

    always @(posedge dhi_clk or negedge rst_dhi_n) begin
        if (!rst_dhi_n) begin
            complete_idx   <= 1'b0;
            complete_valid <= 1'b0;
            disp_idx       <= 1'b0;
            disp_valid     <= 1'b0;
        end else begin
            if (writer_frame_done) begin
                complete_idx   <= writer_done_idx;
                complete_valid <= 1'b1;
            end
            if (reader_pass_done) begin
                disp_valid <= 1'b1;
                disp_idx   <= eff_idx;
            end
        end
    end

    // The writer may only start a frame in the buffer the display is not
    // using. The camera capture module samples this level at VSYNC.
    wire buf_free = run && !writer_busy && (wr_idx != reader_busy_idx);

    // ------------------------------------------------------------------
    // Camera capture + PCLK -> dhi_clk beat FIFO
    // ------------------------------------------------------------------
    // cap_en is a 50 MHz level; the capture module synchronizes it to PCLK.
    reg [1:0] ddr_ready_50;
    reg [1:0] self_pass_50;

    always @(posedge clk_50m) begin
        if (!rst_n) begin
            ddr_ready_50 <= 2'b00;
            self_pass_50 <= 2'b00;
        end else begin
            ddr_ready_50 <= {ddr_ready_50[0], ddr_ready};
            self_pass_50 <= {self_pass_50[0], (phase == PH_RUN)};
        end
    end

    wire cap_en = cfg_ok && ddr_ready_50[1] && self_pass_50[1];

    wire        cam_fifo_wr_en;
    wire [128:0] cam_fifo_wr_data;
    wire        cam_fifo_wr_full;
    wire        cam_fifo_wr_overflow;
    wire [128:0] cam_fifo_rd_data;
    wire        cam_fifo_rd_empty;
    wire        cam_fifo_wr_empty;
    wire        cam_fifo_rd_en;

    wire        cam_frame_active;
    wire [15:0] cam_lines;
    wire [15:0] cam_frames;
    wire        cam_capture_error;
    wire [7:0]  cam_dbg_state;

    ov5640_frame_capture #(
        .HREF_ACTIVE_HIGH  (HREF_ACTIVE_HIGH),
        .VSYNC_ACTIVE_HIGH (VSYNC_ACTIVE_HIGH),
        .PIXELS            (PIXELS),
        .V_ACTIVE          (V_ACTIVE),
        .BEATS_PER_LINE    (PIXELS / 8),
        .CAPTURE_START     (CAPTURE_START),
        .BYTE_SWAP         (BYTE_SWAP)
    ) u_capture (
        .pclk            (cam_pclk),
        .rst_n           (rst_n),
        .cap_en          (cap_en),
        .buf_free        (buf_free),
        .dvp_d           (cam_data),
        .dvp_href        (cam_href),
        .dvp_vsync       (cam_vsync),
        .fifo_wr_en      (cam_fifo_wr_en),
        .fifo_wr_data    (cam_fifo_wr_data),
        .fifo_wr_full    (cam_fifo_wr_full),
        .frame_active_o  (cam_frame_active),
        .lines_captured_o(cam_lines),
        .frames_started_o(cam_frames),
        .capture_error_o (cam_capture_error),
        .dbg_state_o     (cam_dbg_state)
    );

    async_fifo_gray #(
        .DATA_WIDTH (129),
        .ADDR_WIDTH (8)
    ) u_cam_fifo (
        .wr_clk      (cam_pclk),
        .wr_rst_n    (rst_n),
        .wr_en       (cam_fifo_wr_en),
        .wr_data     (cam_fifo_wr_data),
        .wr_full     (cam_fifo_wr_full),
        .wr_empty    (cam_fifo_wr_empty),
        .wr_overflow (cam_fifo_wr_overflow),
        .rd_clk      (dhi_clk),
        .rd_rst_n    (rst_dhi_n),
        .rd_en       (cam_fifo_rd_en),
        .rd_data     (cam_fifo_rd_data),
        .rd_empty    (cam_fifo_rd_empty)
    );

    // ------------------------------------------------------------------
    // DDR writer / reader
    // ------------------------------------------------------------------
    wire [24:0] wr_awaddr;
    wire        wr_awvalid, wr_awready;
    wire [127:0] wr_wdata;
    wire [15:0] wr_wstrb;
    wire        wr_wvalid, wr_wlast, wr_wready;
    wire        writer_error;

    cam_fb_writer #(
        .ADDR_WIDTH   (25),
        .BASE_ADDR    (BASE_ADDR),
        .FRAME_STRIDE (FRAME_STRIDE),
        .ADDR_STEP    (8),
        .TOTAL_BEATS  (TOTAL_BEATS),
        .TIMEOUT      (24_000_000)
    ) u_writer (
        .clk            (dhi_clk),
        .rst_n          (rst_dhi_n),
        .run            (run),
        .fifo_rd_data   (cam_fifo_rd_data),
        .fifo_rd_empty  (cam_fifo_rd_empty),
        .fifo_rd_en     (cam_fifo_rd_en),
        .buf_free       (buf_free),
        .paxi_awaddr    (wr_awaddr),
        .paxi_awvalid   (wr_awvalid),
        .paxi_awready   (wr_awready),
        .paxi_wdata     (wr_wdata),
        .paxi_wstrb     (wr_wstrb),
        .paxi_wvalid    (wr_wvalid),
        .paxi_wlast     (wr_wlast),
        .paxi_wready    (wr_wready),
        .frame_done     (writer_frame_done),
        .frame_done_idx (writer_done_idx),
        .wr_idx         (wr_idx),
        .busy           (writer_busy),
        .error          (writer_error),
        .beats_dbg      ()
    );

    wire [24:0] rd_araddr;
    wire        rd_arvalid, rd_arready;
    wire [127:0] rd_rdata;
    wire        rd_rlast, rd_rvalid, rd_rready;
    wire        reader_fifo_wr_en;
    wire [127:0] reader_fifo_wr_data;
    wire        fifo_wr_full;
    wire        fifo_wr_empty;
    wire        reader_fifo_wr_overflow;
    wire        reader_prefill_done;
    wire        reader_error;

    cam_fb_reader #(
        .ADDR_WIDTH    (25),
        .ADDR_STEP     (8),
        .TOTAL_BEATS   (TOTAL_BEATS),
        .PREFILL_WORDS (PREFILL_WORDS),
        .TIMEOUT       (24_000_000)
    ) u_reader (
        .clk             (dhi_clk),
        .rst_n           (rst_dhi_n),
        .run             (complete_valid),
        .pass_base       (pass_base),
        .fifo_wr_full    (fifo_wr_full),
        .fifo_wr_empty   (fifo_wr_empty),
        .paxi_araddr     (rd_araddr),
        .paxi_arvalid    (rd_arvalid),
        .paxi_arready    (rd_arready),
        .paxi_rdata      (rd_rdata),
        .paxi_rlast      (rd_rlast),
        .paxi_rvalid     (rd_rvalid),
        .paxi_rready     (rd_rready),
        .fifo_wr_en      (reader_fifo_wr_en),
        .fifo_wr_data    (reader_fifo_wr_data),
        .prefill_done    (reader_prefill_done),
        .pass_done       (reader_pass_done),
        .busy            (),
        .error           (reader_error),
        .beats_dbg       (),
        .rlast_err       ()
    );

    // ------------------------------------------------------------------
    // PAXI arbiter / mux
    // ------------------------------------------------------------------
    localparam [1:0] ARB_IDLE = 2'd0,
                     ARB_RD   = 2'd1,
                     ARB_WR   = 2'd2;

    reg [1:0] arb_state;
    reg       arb_rd_ar_done;
    reg       arb_wr_aw_done;
    reg       arb_wr_w_done;
    reg       pref_wr;

    wire rd_want = rd_arvalid;
    wire wr_want = wr_awvalid;

    always @(posedge dhi_clk or negedge rst_dhi_n) begin
        if (!rst_dhi_n) begin
            arb_state      <= ARB_IDLE;
            arb_rd_ar_done <= 1'b0;
            arb_wr_aw_done <= 1'b0;
            arb_wr_w_done  <= 1'b0;
            pref_wr        <= 1'b0;
        end else if (phase != PH_RUN) begin
            arb_state      <= ARB_IDLE;
            arb_rd_ar_done <= 1'b0;
            arb_wr_aw_done <= 1'b0;
            arb_wr_w_done  <= 1'b0;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    if (rd_want && wr_want) begin
                        if (pref_wr) begin
                            arb_state      <= ARB_WR;
                            arb_wr_aw_done <= 1'b0;
                            arb_wr_w_done  <= 1'b0;
                        end else begin
                            arb_state      <= ARB_RD;
                            arb_rd_ar_done <= 1'b0;
                        end
                    end else if (rd_want) begin
                        arb_state      <= ARB_RD;
                        arb_rd_ar_done <= 1'b0;
                    end else if (wr_want) begin
                        arb_state      <= ARB_WR;
                        arb_wr_aw_done <= 1'b0;
                        arb_wr_w_done  <= 1'b0;
                    end
                end

                ARB_RD: begin
                    // Own the bus until AR is accepted AND the R beat is
                    // taken. Never release on a stale R.
                    if (rd_arvalid && paxi_arready)
                        arb_rd_ar_done <= 1'b1;
                    if (arb_rd_ar_done && paxi_rvalid && rd_rready) begin
                        arb_state <= ARB_IDLE;
                        pref_wr   <= 1'b1;   // give the writer a slot next
                    end
                end

                ARB_WR: begin
                    if (wr_awvalid && paxi_awready)
                        arb_wr_aw_done <= 1'b1;
                    if (wr_wvalid && paxi_wready)
                        arb_wr_w_done <= 1'b1;
                    if ((arb_wr_aw_done || (wr_awvalid && paxi_awready)) &&
                        (arb_wr_w_done  || (wr_wvalid  && paxi_wready))) begin
                        arb_state <= ARB_IDLE;
                        pref_wr   <= 1'b0;   // give the reader a slot next
                    end
                end

                default: arb_state <= ARB_IDLE;
            endcase
        end
    end

    // Master-side ready routing
    assign self_awready = (phase == PH_SELF) ? paxi_awready : 1'b0;
    assign self_wready  = (phase == PH_SELF) ? paxi_wready  : 1'b0;
    assign self_arready = (phase == PH_SELF) ? paxi_arready : 1'b0;
    wire [127:0] self_rdata_r = paxi_rdata;
    wire        self_rlast_r  = paxi_rlast;
    wire        self_rvalid_r = (phase == PH_SELF) ? paxi_rvalid : 1'b0;

    assign wr_awready = (phase == PH_RUN && arb_state == ARB_WR) ? paxi_awready : 1'b0;
    assign wr_wready  = (phase == PH_RUN && arb_state == ARB_WR) ? paxi_wready  : 1'b0;

    assign rd_arready = (phase == PH_RUN && arb_state == ARB_RD) ? paxi_arready : 1'b0;
    wire [127:0] rd_rdata_r = paxi_rdata;
    wire        rd_rlast_r  = paxi_rlast;
    wire        rd_rvalid_r = (phase == PH_RUN && arb_state == ARB_RD) ? paxi_rvalid : 1'b0;

    assign self_rdata = self_rdata_r;
    assign self_rlast = self_rlast_r;
    assign self_rvalid= self_rvalid_r;
    assign rd_rdata   = rd_rdata_r;
    assign rd_rlast   = rd_rlast_r;
    assign rd_rvalid  = rd_rvalid_r;

    // PAXI master mux
    reg [24:0]  m_awaddr;
    reg         m_awvalid;
    reg [127:0] m_wdata;
    reg [15:0]  m_wstrb;
    reg         m_wvalid, m_wlast;
    reg [24:0]  m_araddr;
    reg         m_arvalid;
    reg         m_rready;

    always @* begin
        m_awaddr  = 25'd0;
        m_awvalid = 1'b0;
        m_wdata   = 128'd0;
        m_wstrb   = 16'd0;
        m_wvalid  = 1'b0;
        m_wlast   = 1'b0;
        m_araddr  = 25'd0;
        m_arvalid = 1'b0;
        m_rready  = 1'b0;

        if (phase == PH_SELF) begin
            m_awaddr  = self_awaddr;
            m_awvalid = self_awvalid;
            m_wdata   = self_wdata;
            m_wstrb   = self_wstrb;
            m_wvalid  = self_wvalid;
            m_wlast   = self_wlast;
            m_araddr  = self_araddr;
            m_arvalid = self_arvalid;
            m_rready  = self_rready;
        end else if (phase == PH_RUN) begin
            case (arb_state)
                ARB_RD: begin
                    m_araddr  = rd_araddr;
                    m_arvalid = rd_arvalid;
                    m_rready  = rd_rready;
                end
                ARB_WR: begin
                    m_awaddr  = wr_awaddr;
                    m_awvalid = wr_awvalid;
                    m_wdata   = wr_wdata;
                    m_wstrb   = wr_wstrb;
                    m_wvalid  = wr_wvalid;
                    m_wlast   = wr_wlast;
                end
                default: begin
                    // Idle: no transaction.
                end
            endcase
        end
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

    // ------------------------------------------------------------------
    // Display FIFO + pixel gearbox
    // ------------------------------------------------------------------
    wire        fifo_rd_en;
    wire [127:0] fifo_rd_data;
    wire        fifo_rd_empty;
    wire [15:0] img565;
    wire        underflow;

    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;
    wire rst_pixel_n = rst_n && pll_lock;

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

    async_fifo_gray #(
        .DATA_WIDTH (128),
        .ADDR_WIDTH (8)
    ) u_fifo (
        .wr_clk      (dhi_clk),
        .wr_rst_n    (rst_dhi_n),
        .wr_en       (reader_fifo_wr_en),
        .wr_data     (reader_fifo_wr_data),
        .wr_full     (fifo_wr_full),
        .wr_empty    (fifo_wr_empty),
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

    video_timing #(
        .H_ACTIVE (PIXELS),
        .V_ACTIVE (V_ACTIVE)
    ) u_timing (
        .pixel_clk (pixel_clk),
        .rst       (hdmi_rst),
        .hcount    (hcount),
        .vcount    (vcount),
        .de        (de),
        .hs        (hs),
        .vs        (vs)
    );

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

    // ------------------------------------------------------------------
    // Error CDC to the pixel domain
    // ------------------------------------------------------------------
    reg self_err_p1, self_err_p2;
    reg wr_err_p1, wr_err_p2;
    reg rd_err_p1, rd_err_p2;
    reg cap_err_p1, cap_err_p2;
    reg ovf_p1, ovf_p2;

    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            self_err_p1 <= 1'b0; self_err_p2 <= 1'b0;
            wr_err_p1   <= 1'b0; wr_err_p2   <= 1'b0;
            rd_err_p1   <= 1'b0; rd_err_p2   <= 1'b0;
            cap_err_p1  <= 1'b0; cap_err_p2  <= 1'b0;
            ovf_p1      <= 1'b0; ovf_p2      <= 1'b0;
        end else begin
            self_err_p1 <= (phase == PH_ERROR);
            self_err_p2 <= self_err_p1;
            wr_err_p1   <= writer_error;
            wr_err_p2   <= wr_err_p1;
            rd_err_p1   <= reader_error;
            rd_err_p2   <= rd_err_p1;
            cap_err_p1  <= cam_capture_error;
            cap_err_p2  <= cap_err_p1;
            ovf_p1      <= reader_fifo_wr_overflow;
            ovf_p2      <= ovf_p1;
        end
    end

    // Yellow = display FIFO/stream, red = DDR self-check, magenta = DDR
    // writer/reader, orange = camera capture timeout, dark blue = waiting.
    wire [23:0] rgb = (underflow || ovf_p2) ? 24'hFFFF00 :
                      self_err_p2 ? 24'hFF0000 :
                      (wr_err_p2 || rd_err_p2) ? 24'hFF00FF :
                      cap_err_p2 ? 24'hFF8000 :
                      (!video_valid ? 24'h000040 : img888);

    // ------------------------------------------------------------------
    // TMDS chain (unchanged, board-proven)
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
    // Status
    // ------------------------------------------------------------------
    assign ddr_ready_o     = ddr_ready;
    assign self_pass_o     = (phase == PH_RUN);
    assign frame_valid_o   = complete_valid;
    assign capture_error_o = cam_capture_error;
    assign error_o         = (phase == PH_ERROR) || writer_error || reader_error ||
                             reader_fifo_wr_overflow || underflow ||
                             cam_capture_error || cam_fifo_wr_overflow;
    assign hdmi_lock_o     = pll_lock;

    // Debug visibility for ChipWatcher / simulation
    (* keep *) wire [15:0] dbg_cam_lines     = cam_lines;
    (* keep *) wire [15:0] dbg_cam_frames    = cam_frames;
    (* keep *) wire        dbg_cam_active    = cam_frame_active;
    (* keep *) wire [7:0]  dbg_cam_state     = cam_dbg_state;
    (* keep *) wire [0:0]  dbg_wr_idx        = wr_idx;
    (* keep *) wire [0:0]  dbg_disp_idx      = disp_idx;
    (* keep *) wire [0:0]  dbg_complete_idx  = complete_idx;
    (* keep *) wire        dbg_disp_valid    = disp_valid;
    (* keep *) wire        dbg_buf_free      = buf_free;
    (* keep *) wire [1:0]  dbg_arb_state     = arb_state;
    (* keep *) wire [1:0]  dbg_phase         = phase;
    (* keep *) wire        dbg_self_pass     = self_pass;

endmodule
