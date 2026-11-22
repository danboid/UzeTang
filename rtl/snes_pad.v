// ============================================================================
//  snes_pad.v - SNES controller support for UzeTang
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  snes_pad_scan : reads a physical SNES pad (latch / clock / data pins, as
//                  wired for SNESTang on the Tang Nano 20K) every 4 ms with
//                  slow timing (60 us settling per bit) and reports buttons
//                  plus whether a pad is connected. A new button state is
//                  only accepted once two consecutive scans agree.
//  snes_pad_emu  : emulates the pad's 4021 shift register towards the AVR,
//                  driven by the Uzebox kernel's latch (PA2) and clock (PA3).
//                  This decouples the kernel's very fast (~400 ns) clocking
//                  from the real pad and adapter.
// ============================================================================

`default_nettype none

// Button vector order (bit = 1: pressed), same as the SNES serial order:
//  0 B, 1 Y, 2 SELECT, 3 START, 4 UP, 5 DOWN, 6 LEFT, 7 RIGHT,
//  8 A, 9 X, 10 L, 11 R, 12..15 extra bits (0 on a standard pad)

module snes_pad_scan #(
    parameter FREQ = 28_636_360
)(
    input  wire        clk,
    input  wire        rst,
    output reg         pad_latch,
    output reg         pad_clk,
    input  wire        pad_data,       // low = pressed (pulled up)
    output reg  [15:0] buttons,        // 1 = pressed
    output reg         connected
);
    // Slow, generous timing: each bit is sampled 60 us after the clock edge
    // that put it on the line (a SNES samples after 6 us). Some pads and
    // wiring only pull the data line high weakly, and with short settling
    // times a pressed (low) bit then leaks into the next one.
    localparam integer US     = FREQ / 1_000_000;
    localparam integer T_LAT  = 24 * US;        // latch pulse
    localparam integer T_SET  = 96 * US;        // latch fall -> first sample
    localparam integer T_HIGH = 60 * US;        // clock rise -> sample
    localparam integer T_LOW  = 12 * US;        // clock low time
    localparam integer PERIOD = FREQ / 250;     // poll every 4 ms

    localparam [2:0] S_IDLE = 3'd0, S_LATCH = 3'd1, S_SET = 3'd2,
                     S_LOW = 3'd3, S_HIGH = 3'd4;
    reg [2:0]  st;
    reg [19:0] tmr;
    reg [4:0]  nbit;      // samples taken
    reg [16:0] sh;
    reg [1:0]  dsync;
    reg [16:0] prev;      // previous raw scan (glitch filter)
    reg [1:0]  ccnt;      // consecutive scans with the 17th bit low

    always @(posedge clk) dsync <= {dsync[0], pad_data};

    // 17 samples: 16 button bits, then the bit after the 16th, which a
    // genuine pad drives low (connection detect, as the Uzebox kernel does)
    wire [16:0] sh_n = {dsync[1], sh[16:1]};

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; tmr <= 20'd0; nbit <= 5'd0;
            pad_latch <= 1'b0; pad_clk <= 1'b1;
            buttons <= 16'd0; connected <= 1'b0; sh <= 17'h1FFFF;
            prev <= 17'h1FFFF; ccnt <= 2'd0;
        end else begin
            tmr <= tmr + 20'd1;
            case (st)
            S_IDLE: if (tmr >= PERIOD) begin
                tmr <= 20'd0; st <= S_LATCH; pad_latch <= 1'b1;
            end
            S_LATCH: if (tmr >= T_LAT) begin
                tmr <= 20'd0; st <= S_SET; pad_latch <= 1'b0; nbit <= 5'd0;
            end
            S_SET, S_HIGH: if (tmr >= ((st == S_SET) ? T_SET : T_HIGH)) begin
                // sample the bit on the line, then drop the clock
                sh <= sh_n;
                tmr <= 20'd0;
                nbit <= nbit + 5'd1;
                if (nbit == 5'd16) begin
                    st <= S_IDLE;
                    prev <= sh_n;
                    if (sh_n[15:0] == prev[15:0])
                        buttons <= ~sh_n[15:0] & 16'h0FFF;
                    if (sh_n[16]) begin
                        ccnt <= 2'd0; connected <= 1'b0;
                    end else if (ccnt != 2'd3)
                        ccnt <= ccnt + 2'd1;
                    else
                        connected <= 1'b1;
                end else begin
                    st <= S_LOW; pad_clk <= 1'b0;
                end
            end
            S_LOW: if (tmr >= T_LOW) begin
                // rising edge: the pad shifts the next bit out
                tmr <= 20'd0; st <= S_HIGH; pad_clk <= 1'b1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

module snes_pad_emu (
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,
    input  wire        latch_pin,     // PA2 (PORTA & DDRA)
    input  wire        clock_pin,     // PA3
    input  wire [15:0] buttons,       // 1 = pressed
    input  wire        connected,
    output wire        data           // to PINA.0 / PINA.1
);
    reg [31:0] sr;
    reg        l_q, c_q;
    always @(posedge clk) begin
        if (rst) begin
            sr <= 32'hFFFFFFFF; l_q <= 1'b0; c_q <= 1'b0;
        end else if (ce) begin
            l_q <= latch_pin;
            c_q <= clock_pin;
            if (latch_pin)
                // 4021 parallel load: 16 button bits (low = pressed), then the
                // line goes low after 16 clocks on a genuine pad (connected),
                // stays high (pull-up) without a pad.
                sr <= {connected ? 16'h0000 : 16'hFFFF, ~buttons};
            else if (clock_pin && !c_q)
                sr <= {connected ? 1'b0 : 1'b1, sr[31:1]};
        end
    end
    assign data = sr[0];
endmodule

`default_nettype wire
