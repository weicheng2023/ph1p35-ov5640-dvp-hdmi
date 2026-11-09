// ============================================================================
// tmds_serializer.v
// 10:1 TMDS serializer: 10-bit character -> DDR output at 5x pixel clock.
//
//   din[0]  : first bit transmitted (DVI convention: LSB first)
//   din[9]  : last bit transmitted
//   serial_clk : 5 x pixel clock (125 MHz for 640x480@59.981 Hz at 25.0 MHz)
//
// The shift register runs at serial_clk and shifts two bits per cycle.
// The final 2:1 mux is the PH1P_LOGIC_ODDR primitive:
//   d0 is sampled on the POSEDGE (first bit of the pair)
//   d1 is sampled on the NEGEDGE (second bit of the pair)
//
// Bit reversal: word[9] = din[0], so the shift register's MSB pair is the
// first pair transmitted. The ODDR receives d0=word[9], d1=word[8].
//
// Simulation uses a behavioural PH1P_LOGIC_ODDR model from
// fpga/sim/models/ instead of the encrypted vendor model.
// ============================================================================
`timescale 1ns / 1ps

module tmds_serializer (
    input  wire       serial_clk,
    input  wire       rst,       // active high
    input  wire       load,      // one serial_clk pulse per pixel
    input  wire [9:0] din,       // din[0] transmitted first
    output wire       serial_out
);

    // First transmitted bit at bit 9 of the shift register.
    wire [9:0] word;
    assign word = {din[0], din[1], din[2], din[3], din[4],
                   din[5], din[6], din[7], din[8], din[9]};

    reg [9:0] shift;
    reg [1:0] oddr_data;

    always @(posedge serial_clk or posedge rst) begin
        if (rst)
            shift <= 10'd0;
        else if (load)
            shift <= word;
        else
            shift <= {shift[7:0], 2'b00};
    end

    always @(posedge serial_clk or posedge rst) begin
        if (rst)
            oddr_data <= 2'd0;
        else
            oddr_data <= shift[9:8];
    end

    PH1P_LOGIC_ODDR u_oddr (
        .q   (serial_out    ),
        .clk (serial_clk    ),
        .d1  (oddr_data[0]  ),   // negedge: second bit
        .d0  (oddr_data[1]  ),   // posedge: first bit
        .rst (rst           )
    );

endmodule
