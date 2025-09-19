// Implementation of HDMI serializer for various FPGA types.
// By Sameer Puri https://github.com/sameer

module serializer(
    input logic clk_pixel,
    input logic clk_pixel_x5,
    input logic reset,
    input logic [9:0] tmds_internal [0:2],
    output logic [2:0] tmds_p,
    output logic [2:0] tmds_n,
    output logic tmds_clock_p,
    output logic tmds_clock_n
);

`ifdef GW_IDE
    // Gowin OSER10 implementation for Tang Nano series
    OSER10 gwSer0(
        .Q(tmds_p[0]),
        .D0(tmds_internal[0][0]),
        .D1(tmds_internal[0][1]),
        .D2(tmds_internal[0][2]),
        .D3(tmds_internal[0][3]),
        .D4(tmds_internal[0][4]),
        .D5(tmds_internal[0][5]),
        .D6(tmds_internal[0][6]),
        .D7(tmds_internal[0][7]),
        .D8(tmds_internal[0][8]),
        .D9(tmds_internal[0][9]),
        .PCLK(clk_pixel),
        .FCLK(clk_pixel_x5),
        .RESET(reset)
    );

    OSER10 gwSer1(
        .Q(tmds_p[1]),
        .D0(tmds_internal[1][0]),
        .D1(tmds_internal[1][1]),
        .D2(tmds_internal[1][2]),
        .D3(tmds_internal[1][3]),
        .D4(tmds_internal[1][4]),
        .D5(tmds_internal[1][5]),
        .D6(tmds_internal[1][6]),
        .D7(tmds_internal[1][7]),
        .D8(tmds_internal[1][8]),
        .D9(tmds_internal[1][9]),
        .PCLK(clk_pixel),
        .FCLK(clk_pixel_x5),
        .RESET(reset)
    );

    OSER10 gwSer2(
        .Q(tmds_p[2]),
        .D0(tmds_internal[2][0]),
        .D1(tmds_internal[2][1]),
        .D2(tmds_internal[2][2]),
        .D3(tmds_internal[2][3]),
        .D4(tmds_internal[2][4]),
        .D5(tmds_internal[2][5]),
        .D6(tmds_internal[2][6]),
        .D7(tmds_internal[2][7]),
        .D8(tmds_internal[2][8]),
        .D9(tmds_internal[2][9]),
        .PCLK(clk_pixel),
        .FCLK(clk_pixel_x5),
        .RESET(reset)
    );

    // Clock output (Gowin specific)
    assign tmds_clock_p = clk_pixel;
    assign tmds_clock_n = ~clk_pixel;

    // Differential output assignment (inverted for Gowin)
    assign tmds_n = ~tmds_p;

`else
    // Generic DDR implementation for other FPGAs
    logic [2:0] tmds_d0, tmds_d1;
    logic tmds_clock_d0, tmds_clock_d1;

    // DDR registers for data
    always_ff @(posedge clk_pixel_x5) begin
        tmds_d0 <= {tmds_internal[2][0], tmds_internal[1][0], tmds_internal[0][0]};
        tmds_d1 <= {tmds_internal[2][1], tmds_internal[1][1], tmds_internal[0][1]};
        tmds_clock_d0 <= 1'b1;
        tmds_clock_d1 <= 1'b0;
    end

    // Output assignment
    assign tmds_p = tmds_d0;
    assign tmds_n = tmds_d1;
    assign tmds_clock_p = tmds_clock_d0;
    assign tmds_clock_n = tmds_clock_d1;
`endif

endmodule