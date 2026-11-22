// ============================================================================
//  video_capture.v - capture the Uzebox video signal into a line buffer
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  The Uzebox draws video by writing PORTC once per pixel and generates
//  composite sync on PORTB.0. This module runs in the AVR clock domain (with
//  the AVR's clock enable) and:
//   - detects scanline starts (falling sync edges >= 1500 cycles apart),
//   - detects the vertical sync (long sync pulses) and numbers the rows of
//     each frame from 0 (first full line after vertical sync),
//   - writes cycles [HSTART, HSTART+2047] of each row to slot (row mod 8)
//     of an 8 x 2048 byte line buffer.
// ============================================================================

`default_nettype none

module video_capture #(
    parameter HSTART = 256          // first captured cycle after sync fall
)(
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,
    input  wire        sync,        // PORTB.0 (composite sync, active low)
    input  wire [7:0]  pix,         // PORTC

    // line buffer write port
    output reg         lb_we,
    output reg  [13:0] lb_addr,     // {slot[2:0], x[10:0]}
    output reg  [7:0]  lb_data,

    output reg  [8:0]  row,         // current row in frame
    output reg         frame_start, // pulse: row 0 has just started
    output reg         locked       // sync seen recently
);
    reg        sync_q;
    reg [11:0] since_fall;          // cycles since last falling edge
    reg [11:0] col;                 // cycles since last line start
    reg        vs_seen;             // long pulse seen, waiting for frame start
    reg        pending;             // next line start is row 0
    reg [20:0] lock_tmr;

    wire fall = sync_q & ~sync;
    wire rise = ~sync_q & sync;

    always @(posedge clk) begin
        if (rst) begin
            sync_q <= 1'b1; since_fall <= 12'd0; col <= 12'd0;
            vs_seen <= 1'b0; pending <= 1'b0; row <= 9'd0;
            frame_start <= 1'b0; lb_we <= 1'b0; locked <= 1'b0;
            lock_tmr <= 21'd0;
        end else if (ce) begin
            sync_q      <= sync;
            frame_start <= 1'b0;
            if (since_fall != 12'hFFF) since_fall <= since_fall + 12'd1;
            if (col != 12'hFFF)        col <= col + 12'd1;
            if (lock_tmr != 21'h1FFFFF) lock_tmr <= lock_tmr + 21'd1;
            else                        locked <= 1'b0;

            if (fall) begin
                since_fall <= 12'd0;
                if (since_fall >= 12'd1500) begin       // a normal line starts
                    col <= 12'd0;
                    if (pending) begin
                        row <= 9'd0;
                        pending <= 1'b0;
                        frame_start <= 1'b1;
                        locked <= 1'b1;
                        lock_tmr <= 21'd0;
                    end else if (row != 9'h1FF)
                        row <= row + 9'd1;
                end
            end
            if (rise) begin
                if (since_fall > 12'd500)       vs_seen <= 1'b1;   // vsync pulse
                else if (vs_seen && since_fall < 12'd200) begin    // first short pulse after
                    vs_seen <= 1'b0;
                    pending <= 1'b1;
                end
            end

            // line buffer write
            lb_we   <= (col >= HSTART) && (col < HSTART + 2048);
            lb_addr <= {row[2:0], col[10:0] - HSTART[10:0]};
            lb_data <= pix;
        end else begin
            lb_we <= 1'b0;
        end
    end
endmodule

`default_nettype wire
