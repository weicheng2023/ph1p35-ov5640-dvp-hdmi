// ============================================================================
// tb_top_cam_id.v
// 行为级 testbench：模拟一个 OV5640 SCCB 从机，返回 Chip ID 0x5640。
//
// 验证目标：
//   - 上电后 PWDN=0、RESET 先低后高
//   - SCCB 读 0x300A/0x300B
//   - LED3 在有限时间内点亮（ID 匹配）
//
// 运行（ModelSim）：
//   vlib work
//   vlog ../../rtl/camera/sccb_master.v ../../rtl/camera/ov5640_id_reader.v \
//        ../../rtl/top/top_cam_id.v tb_top_cam_id.v
//   vsim -c -do "run -all; quit" work.tb_top_cam_id
// ============================================================================
`timescale 1ns / 1ps

module tb_top_cam_id;

    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    wire [3:0] led;
    wire       cam_scl;
    tri1       cam_sda;      // 总线上拉
    wire       cam_reset_n;
    wire       cam_pwdn;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    top_cam_id #(
        .POR_CYCLES        (10),
        .HB_CYCLES         (50),
        .PWRUP_CYCLES      (20),
        .RESET_WAIT_CYCLES (20),
        .RETRY_CYCLES      (200),
        .SCCB_DIV          (250),
        .SCCB_TIMEOUT      (200_000)
    ) dut (
        .clk_50m     (clk),
        .led         (led),
        .cam_scl     (cam_scl),
        .cam_sda     (cam_sda),
        .cam_reset_n (cam_reset_n),
        .cam_pwdn    (cam_pwdn)
    );

    // ------------------------------------------------------------------
    // 极简 SCCB 从机模型
    // ------------------------------------------------------------------
    reg        sda_drive = 1'b0;
    reg        sda_o     = 1'b1;
    assign cam_sda = sda_drive ? sda_o : 1'bz;

    reg [1:0]  mode;       // 0=idle, 1=write, 2=read
    reg [2:0]  byte_idx;   // write: 0 addr, 1 reg_hi, 2 reg_lo, 3 data
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
    end

    always @(posedge clk) begin
        scl_d <= cam_scl;
        sda_d <= cam_sda;

        // START / STOP 检测（SCL 高时 SDA 跳变）
        if (cam_scl && scl_d) begin
            if (sda_d && !cam_sda) begin
                mode     <= 2'd1;
                byte_idx <= 3'd0;
                bitcnt   <= 4'd0;
                rx       <= 8'd0;
                sda_drive <= 1'b0;
            end
            if (!sda_d && cam_sda) begin
                mode      <= 2'd0;
                bitcnt    <= 4'd0;
                sda_drive <= 1'b0;
            end
        end

        // SCL 上升沿：采样 / 处理字节
        if (cam_scl && !scl_d) begin
            if (mode == 2'd1) begin
                if (bitcnt < 4'd8) begin
                    rx     <= {rx[6:0], cam_sda};
                    bitcnt <= bitcnt + 4'd1;
                end else begin
                    // 第 9 个时钟：一个字节结束
                    bitcnt <= 4'd0;
                    if (byte_idx == 3'd0) begin
                        // 设备地址
                        if (rx[7:1] == 7'h3C) begin
                            if (rx[0] == 1'b0) begin
                                mode     <= 2'd1;
                                byte_idx <= 3'd1;
                            end else begin
                                mode <= 2'd2;
                                if (reg_addr == 16'h300A)      tx <= 8'h56;
                                else if (reg_addr == 16'h300B) tx <= 8'h40;
                                else                            tx <= 8'h00;
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
                        // 写数据字节，保持 write 模式
                        byte_idx <= 3'd3;
                    end
                end
            end else if (mode == 2'd2) begin
                // 读数据：前 8 位由主机采样，第 9 位是 NA
                if (bitcnt < 4'd8) begin
                    bitcnt <= bitcnt + 4'd1;
                end else begin
                    bitcnt <= 4'd0;
                    mode   <= 2'd0;
                end
            end
        end

        // SCL 下降沿：驱动 ACK 或读数据
        if (!cam_scl && scl_d) begin
            if (mode == 2'd1 && bitcnt == 4'd8) begin
                // 写字节 ACK
                sda_drive <= 1'b1;
                sda_o     <= 1'b0;
            end else if (mode == 2'd2 && bitcnt < 4'd8) begin
                // 读数据，MSB first
                sda_drive <= 1'b1;
                sda_o     <= tx[7];
                tx        <= {tx[6:0], 1'b0};
            end else begin
                sda_drive <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // 检查
    // ------------------------------------------------------------------
    initial begin
        $display("TB: start");
        wait (led[3] === 1'b1);
        $display("TB: PASS - Chip ID matched (led=%b, id_hi=%02h, id_lo=%02h)",
                 led, dut.id_hi, dut.id_lo);
        $finish;
    end

    initial begin
        #5000000; // 5 ms, enough for 50kHz SCCB transactions
        $display("TB: FAIL - timeout (led=%b, id_hi=%02h, id_lo=%02h, link=%b, err=%b)",
                 led, dut.id_hi, dut.id_lo, dut.link_ok, dut.id_error);
        $finish;
    end

    // 可选波形
    initial begin
        $dumpfile("tb_top_cam_id.vcd");
        $dumpvars(0, tb_top_cam_id);
    end

endmodule
