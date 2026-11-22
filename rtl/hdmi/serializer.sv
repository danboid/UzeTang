// TMDS serializer for Gowin GW2A/GW2AR (OSER10), replacing the multi-vendor
// serializer of hdl-util/hdmi (MIT OR Apache-2.0) for UzeTang.
// Interface is identical to the upstream module. Under Verilator it is a
// no-op (the test bench taps the encoder's RGB input instead).

module serializer
#(
    parameter int NUM_CHANNELS = 3,
    parameter real VIDEO_RATE
)
(
    input logic clk_pixel,
    input logic clk_pixel_x5,
    input logic reset,
    input logic [9:0] tmds_internal [NUM_CHANNELS-1:0],
    output logic [2:0] tmds,
    output logic tmds_clock
);
`ifdef VERILATOR
    assign tmds = 3'b000;
    assign tmds_clock = clk_pixel;
`else
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i++)
        begin: gw_ser
            OSER10 ser (
                .Q(tmds[i]),
                .D0(tmds_internal[i][0]), .D1(tmds_internal[i][1]),
                .D2(tmds_internal[i][2]), .D3(tmds_internal[i][3]),
                .D4(tmds_internal[i][4]), .D5(tmds_internal[i][5]),
                .D6(tmds_internal[i][6]), .D7(tmds_internal[i][7]),
                .D8(tmds_internal[i][8]), .D9(tmds_internal[i][9]),
                .PCLK(clk_pixel),
                .FCLK(clk_pixel_x5),
                .RESET(reset)
            );
        end
    endgenerate
    assign tmds_clock = clk_pixel;
`endif
endmodule
