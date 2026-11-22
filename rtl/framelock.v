// ============================================================================
//  framelock.v - keep the AVR locked to the HDMI frame rate
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  The AVR clock is chosen slightly faster than real time (28.6875 MHz vs.
//  the HDMI side's 27 MHz * 1820/858 = 28.6364 MHz equivalent). At the start
//  of every Uzebox frame the AVR is paused (ce = 0) until the HDMI output
//  reaches the release line, signalled by 'frame_tog' toggling. This keeps
//  the AVR a few rows ahead of the HDMI reader and costs ~0.4% of the time.
//  Software cannot observe the pauses (the whole chip stops).
// ============================================================================

`default_nettype none

module framelock (
    input  wire clk,            // AVR clock
    input  wire rst,
    input  wire enable,         // 0: free running (no lock)
    input  wire frame_start,    // from video_capture (valid when ce)
    input  wire frame_tog,      // from HDMI domain (asynchronous)
    output wire ce,
    output reg  waiting
);
    reg [2:0]  tog_s;
    reg        tog_seen;
    reg [20:0] tmo;
    wire       tog = tog_s[2];

    assign ce = ~waiting;

    always @(posedge clk) begin
        tog_s <= {tog_s[1:0], frame_tog};
        if (rst || !enable) begin
            waiting  <= 1'b0;
            tog_seen <= tog;
            tmo      <= 21'd0;
        end else if (waiting) begin
            tmo <= tmo + 21'd1;
            if (tog != tog_seen || tmo == 21'h1FFFFF) begin
                waiting  <= 1'b0;
                tog_seen <= tog;
            end
        end else if (frame_start) begin
            tmo <= 21'd0;
            if (tog != tog_seen)
                tog_seen <= tog;        // HDMI already passed the point: go on
            else
                waiting  <= 1'b1;
        end
    end
endmodule

// Line buffer: 8 rows x 1440 bytes packed into 11520 bytes, stored in six
// Gowin SDPB blocks (2K x 8, write port in the AVR clock domain, read port
// in the pixel clock domain). Addresses are {slot[2:0], x[10:0]}, x < 1440.
module linebuf (
    input  wire        wclk,
    input  wire        we,
    input  wire [13:0] waddr,
    input  wire [7:0]  wdata,
    input  wire        rclk,
    input  wire [13:0] raddr,
    output wire [7:0]  rdata
);
    function [13:0] pack;
        input [13:0] a;      // slot * 1440 + x = slot*1024 + slot*256 + slot*128 + slot*32 + x
        pack = {a[13:11], 10'd0} + {1'b0, a[13:11], 8'd0} + {2'b0, a[13:11], 7'd0} +
               {4'b0, a[13:11], 5'd0} + {3'b0, a[10:0]};
    endfunction
    wire [13:0] wa = pack(waddr);
    wire [13:0] ra = pack(raddr);
    wire        wv = we && (waddr[10:0] < 11'd1440);
    wire [31:0] dout [0:5];
    reg  [2:0]  rsel;
    always @(posedge rclk) rsel <= ra[13:11];
    assign rdata = dout[rsel][7:0];
    genvar i;
    generate for (i = 0; i < 6; i = i + 1) begin : blk
        SDPB #(
            .READ_MODE(1'b0), .BIT_WIDTH_0(8), .BIT_WIDTH_1(8),
            .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")
        ) ram (
            .DO(dout[i]), .DI({24'd0, wdata}),
            .ADA({wa[10:0], 3'b000}), .ADB({ra[10:0], 3'b000}),
            .CLKA(wclk), .CEA(wv && wa[13:11] == i), .CLKB(rclk), .CEB(1'b1),
            .OCE(1'b1), .RESETA(1'b0), .RESETB(1'b0),
            .BLKSELA(3'b000), .BLKSELB(3'b000)
        );
    end endgenerate
endmodule

`default_nettype wire
