// ============================================================================
//  hdmi_lite.v - 720x480p (CEA VIC 2) HDMI encoder in plain Verilog-2005,
//  for the open-source flow (yosys cannot read hdl-util's SystemVerilog).
//  Same port list as hdl-util's 'hdmi' module (the subset UzeTang uses).
//
//  Sends true HDMI, not DVI:
//   - data islands on every line (2 packets), with preamble, guard bands,
//     TERC4 coding and BCH ECC (HDMI 1.4 section 5.2.3)
//   - AVI InfoFrame (RGB, 4:3, full range, IT content / graphics)
//   - Audio InfoFrame (2 channel PCM, refer to stream header)
//   - Audio Clock Regeneration (N = 6144, CTS = 27000: the 48 kHz audio
//     clock is derived exactly from the 27 MHz pixel clock)
//   - Audio Sample packets (L-PCM 16 bit, 48 kHz, up to 2 samples/packet)
//   - vsync edges aligned with the hsync leading edge (CEA-861)
//
//  Line layout (pixel clocks, 858 per line):
//     0..719  video (active lines)       720..735  control (16)
//   736..743  data island preamble       744..745  leading guard band
//   746..809  2 packets                  810..811  trailing guard band
//   812..847  control (36)               848..855  video preamble
//   856..857  video guard band (before active lines only)
//
//  Copyright (C) 2026 UzeTang contributors - GPL v3 or later.
//  Packet formats follow the HDMI 1.4 / CEA-861 specifications; the
//  structure of hdl-util/hdmi (MIT / Apache 2.0) was used as a reference.
// ============================================================================
`default_nettype none

module hdmi #(
    parameter VIDEO_ID_CODE = 2,
    parameter DVI_OUTPUT = 0,
    parameter VIDEO_REFRESH_RATE = 59.94,
    parameter AUDIO_RATE = 48000,
    parameter AUDIO_BIT_WIDTH = 16,
    parameter [63:0] VENDOR_NAME = 0,
    parameter [127:0] PRODUCT_DESCRIPTION = 0,
    parameter [7:0] SOURCE_DEVICE_INFORMATION = 0
)(
    input  wire        clk_pixel_x5,
    input  wire        clk_pixel,
    input  wire        clk_audio,
    input  wire        reset,
    input  wire [23:0] rgb,
    input  wire [15:0] audio_sample_word0,
    input  wire [15:0] audio_sample_word1,
    output wire [2:0]  tmds,
    output wire        tmds_clock,
    output reg  [9:0]  cx,
    output reg  [9:0]  cy,
    output wire [9:0]  frame_width,
    output wire [9:0]  frame_height,
    output wire [9:0]  screen_width,
    output wire [9:0]  screen_height
);
    assign frame_width = 10'd858;  assign frame_height = 10'd525;
    assign screen_width = 10'd720; assign screen_height = 10'd480;

    localparam [9:0] HS_START = 10'd736, HS_END = 10'd798;   // 62 clocks
    localparam [9:0] DI_PRE = 10'd736, DI_LG = 10'd744, DI_PK = 10'd746;
    localparam [9:0] DI_TG = 10'd810, DI_END = 10'd812;
    localparam [9:0] VP_START = 10'd848, VG_START = 10'd856;

    // ------------------------------------------------------------------
    // pixel counters
    // ------------------------------------------------------------------
    always @(posedge clk_pixel) begin
        if (reset) begin cx <= 10'd0; cy <= 10'd0; end
        else begin
            cx <= (cx == 10'd857) ? 10'd0 : cx + 10'd1;
            if (cx == 10'd857) cy <= (cy == 10'd524) ? 10'd0 : cy + 10'd1;
        end
    end

    // sync (negative polarity); vsync starts and ends at the hsync edge
    wire hs_act = (cx >= HS_START) && (cx < HS_END);
    wire vs_act = (cy == 10'd488 && cx >= HS_START) ||
                  (cy >= 10'd489 && cy <= 10'd493) ||
                  (cy == 10'd494 && cx <  HS_START);
    wire hs = ~hs_act;
    wire vs = ~vs_act;

    // video preamble / guard only before lines that carry video
    wire next_video = (cy == 10'd524) || (cy < 10'd479);
    wire p_video  = (cx < 10'd720) && (cy < 10'd480);
    wire p_vpre   = next_video && (cx >= VP_START) && (cx < VG_START);
    wire p_vguard = next_video && (cx >= VG_START);
    wire p_dpre   = (cx >= DI_PRE) && (cx < DI_LG);
    wire p_dguard = ((cx >= DI_LG) && (cx < DI_PK)) || ((cx >= DI_TG) && (cx < DI_END));
    wire p_disl   = (cx >= DI_PK) && (cx < DI_TG);

    // ------------------------------------------------------------------
    // audio input: 48 kHz strobe from clk_audio (made from clk_pixel)
    // ------------------------------------------------------------------
    reg aud_q;
    always @(posedge clk_pixel) aud_q <= clk_audio;
    wire aud_push = clk_audio && !aud_q;

    reg [31:0] fifo0, fifo1, fifo2, fifo3;   // {right, left}
    reg [1:0]  f_wr, f_rd;
    reg [2:0]  f_cnt;
    reg [5:0]  acr_div;                      // 48 samples = 1 ms
    reg        acr_pend;

    // ------------------------------------------------------------------
    // packet picker: latch the next packet one clock before it starts
    // ------------------------------------------------------------------
    wire pkt_load = (cx == DI_PK - 10'd1) || (cx == DI_PK + 10'd31);
    reg  [23:0] hdr;
    reg  [55:0] sb0, sb1, sb2, sb3;
    reg         avi_sent, aif_sent;
    reg  [7:0]  fc;                          // IEC 60958 frame (0..191)

    function [31:0] fifo_at;
        input [1:0] i;
        input [31:0] a, b, c, d;
        begin
            case (i)
            2'd0: fifo_at = a; 2'd1: fifo_at = b; 2'd2: fifo_at = c; default: fifo_at = d;
            endcase
        end
    endfunction
    wire [31:0] smp0 = fifo_at(f_rd,        fifo0, fifo1, fifo2, fifo3);
    wire [31:0] smp1 = fifo_at(f_rd + 2'd1, fifo0, fifo1, fifo2, fifo3);
    wire [7:0]  fc1  = (fc == 8'd191) ? 8'd0 : fc + 8'd1;

    // channel status (IEC 60958-3, consumer): copyright not asserted (2),
    // channel number (20 = left, 21 = right), 48 kHz (25), 16 bit (33)
    function cs_bit;
        input [7:0] f;
        input       right;
        begin
            cs_bit = (f == 8'd2) || (f == 8'd25) || (f == 8'd33) ||
                     (f == (right ? 8'd21 : 8'd20));
        end
    endfunction
    function [55:0] sample_sub;
        input [31:0] s;      // {right, left}
        input [7:0]  f;
        reg [23:0] l, r;
        reg cl, cr;
        begin
            l = {s[15:0], 8'd0};
            r = {s[31:16], 8'd0};
            cl = cs_bit(f, 1'b0);
            cr = cs_bit(f, 1'b1);
            // {P, C, U, V} per channel; V = 0 (valid), U = 0
            sample_sub = {^{r, cr}, cr, 1'b0, 1'b0, ^{l, cl}, cl, 1'b0, 1'b0, r, l};
        end
    endfunction

    // the number of samples the current packet takes (0, 1 or 2)
    wire [1:0] take_n = (f_cnt >= 3'd2) ? 2'd2 : f_cnt[1:0];
    reg        take;      // packet_load chose an audio sample packet

    always @(posedge clk_pixel) begin
        if (reset) begin
            f_wr <= 2'd0; f_rd <= 2'd0; f_cnt <= 3'd0;
            acr_div <= 6'd0; acr_pend <= 1'b1;
            avi_sent <= 1'b0; aif_sent <= 1'b0; fc <= 8'd0;
            hdr <= 24'd0; sb0 <= 56'd0; sb1 <= 56'd0; sb2 <= 56'd0; sb3 <= 56'd0;
        end else begin
            // ---- choose and latch a packet ----
            take = 1'b0;
            if (pkt_load) begin
                sb0 <= 56'd0; sb1 <= 56'd0; sb2 <= 56'd0; sb3 <= 56'd0;
                if (acr_pend) begin
                    // Audio Clock Regeneration: N = 6144, CTS = 27000
                    hdr <= 24'h000001;
                    sb0 <= {8'h00, 8'h18, 8'h00, 8'h78, 8'h69, 8'h00, 8'h00};
                    sb1 <= {8'h00, 8'h18, 8'h00, 8'h78, 8'h69, 8'h00, 8'h00};
                    sb2 <= {8'h00, 8'h18, 8'h00, 8'h78, 8'h69, 8'h00, 8'h00};
                    sb3 <= {8'h00, 8'h18, 8'h00, 8'h78, 8'h69, 8'h00, 8'h00};
                end else if (f_cnt != 3'd0) begin
                    // Audio Sample packet, layout 0, 1 or 2 samples
                    take = 1'b1;
                    hdr[7:0]   <= 8'h02;
                    hdr[15:8]  <= (take_n == 2'd2) ? 8'h03 : 8'h01;   // sample_present
                    hdr[23:16] <= {2'b00, (take_n == 2'd2) && (fc1 == 8'd0), (fc == 8'd0), 4'b0000};
                    sb0 <= sample_sub(smp0, fc);
                    if (take_n == 2'd2) sb1 <= sample_sub(smp1, fc1);
                    if (take_n == 2'd2) fc <= (fc1 == 8'd191) ? 8'd0 : fc1 + 8'd1;
                    else                fc <= fc1;
                end else if (!avi_sent) begin
                    // AVI InfoFrame v2: RGB, 4:3, same-as-picture AFD,
                    // IT content, full-range RGB, VIC 2
                    avi_sent <= 1'b1;
                    hdr <= {8'h0D, 8'h02, 8'h82};
                    sb0 <= {8'h00, 8'h00, 8'h02, 8'h88, 8'h18, 8'h00, 8'hCD};
                end else if (!aif_sent) begin
                    // Audio InfoFrame v1: 2 channels, rest from stream
                    aif_sent <= 1'b1;
                    hdr <= {8'h0A, 8'h01, 8'h84};
                    sb0 <= {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01, 8'h70};
                end else begin
                    hdr <= 24'h000000;          // null packet
                end
            end
            if (pkt_load && acr_pend) acr_pend <= 1'b0;
            // InfoFrames once per field
            if (cx == 10'd0 && cy == 10'd480) begin
                avi_sent <= 1'b0; aif_sent <= 1'b0;
            end

            // ---- sample FIFO (a full FIFO drops the new sample) ----
            if (aud_push && f_cnt != 3'd4) begin
                case (f_wr)
                2'd0: fifo0 <= {audio_sample_word1, audio_sample_word0};
                2'd1: fifo1 <= {audio_sample_word1, audio_sample_word0};
                2'd2: fifo2 <= {audio_sample_word1, audio_sample_word0};
                default: fifo3 <= {audio_sample_word1, audio_sample_word0};
                endcase
            end
            if (aud_push) begin
                if (acr_div == 6'd47) begin acr_div <= 6'd0; acr_pend <= 1'b1; end
                else acr_div <= acr_div + 6'd1;
            end
            // pointer and count bookkeeping
            if (aud_push && f_cnt != 3'd4) f_wr <= f_wr + 2'd1;
            if (take) f_rd <= f_rd + take_n;
            f_cnt <= f_cnt + {2'b00, aud_push && f_cnt != 3'd4} - (take ? {1'b0, take_n} : 3'd0);
        end
    end

    // ------------------------------------------------------------------
    // packet serialiser with BCH ECC (HDMI 1.4 figure 5-5)
    // ------------------------------------------------------------------
    wire [5:0] k   = cx - DI_PK;          // 0..63 inside the island
    wire [4:0] b   = k[4:0];              // bit slot within the packet
    reg  [7:0] par0, par1, par2, par3, par4;

    function [7:0] ecc1;
        input [7:0] e;
        input       d;
        begin
            ecc1 = (e >> 1) ^ ((e[0] ^ d) ? 8'b10000011 : 8'd0);
        end
    endfunction
    function [7:0] ecc2;
        input [7:0] e;
        input       d0, d1;
        begin
            ecc2 = ecc1(ecc1(e, d0), d1);
        end
    endfunction

    wire [5:0] b2  = {b, 1'b0};
    wire [5:0] b2p = {b, 1'b1};
    wire        hb  = (b < 5'd24) ? hdr[b] : par4[b - 5'd24];
    wire [3:0]  ev, od;
    assign ev[0] = (b < 5'd28) ? sb0[b2] : par0[{b[1:0], 1'b0}];
    assign ev[1] = (b < 5'd28) ? sb1[b2] : par1[{b[1:0], 1'b0}];
    assign ev[2] = (b < 5'd28) ? sb2[b2] : par2[{b[1:0], 1'b0}];
    assign ev[3] = (b < 5'd28) ? sb3[b2] : par3[{b[1:0], 1'b0}];
    assign od[0] = (b < 5'd28) ? sb0[b2p] : par0[{b[1:0], 1'b1}];
    assign od[1] = (b < 5'd28) ? sb1[b2p] : par1[{b[1:0], 1'b1}];
    assign od[2] = (b < 5'd28) ? sb2[b2p] : par2[{b[1:0], 1'b1}];
    assign od[3] = (b < 5'd28) ? sb3[b2p] : par3[{b[1:0], 1'b1}];

    always @(posedge clk_pixel) begin
        if (!p_disl || b == 5'd31) begin
            par0 <= 8'd0; par1 <= 8'd0; par2 <= 8'd0; par3 <= 8'd0; par4 <= 8'd0;
        end else begin
            if (b < 5'd28) begin
                par0 <= ecc2(par0, sb0[b2], sb0[b2p]);
                par1 <= ecc2(par1, sb1[b2], sb1[b2p]);
                par2 <= ecc2(par2, sb2[b2], sb2[b2p]);
                par3 <= ecc2(par3, sb3[b2], sb3[b2p]);
            end
            if (b < 5'd24) par4 <= ecc1(par4, hdr[b]);
        end
    end

    // ------------------------------------------------------------------
    // stage 1: period / control / island data for this pixel slot
    // ------------------------------------------------------------------
    localparam [2:0] M_CTL = 3'd0, M_VID = 3'd1, M_VGB = 3'd2, M_DI = 3'd3, M_DGB = 3'd4;
    reg [2:0]  mode;
    reg [5:0]  ctl;        // {CTL3, CTL2, CTL1, CTL0, vsync, hsync}
    reg [11:0] did;        // TERC4 nibbles ch2, ch1, ch0
    always @(posedge clk_pixel) begin
        if (reset) begin
            mode <= M_CTL; ctl <= 6'd0; did <= 12'd0;
        end else begin
            mode <= p_video ? M_VID : p_vguard ? M_VGB : p_disl ? M_DI : p_dguard ? M_DGB : M_CTL;
            ctl  <= {1'b0, p_dpre, 1'b0, p_vpre | p_dpre, vs, hs};
            did  <= {od, ev, (cx != DI_PK), hb, vs, hs};
        end
    end

    // ------------------------------------------------------------------
    // stage 2: TMDS / TERC4 / guard band coding (rgb belongs to stage 1)
    // ------------------------------------------------------------------
    wire [9:0] q0, q1, q2;
    hdmi_chan #(.CN(0)) c0 (.clk(clk_pixel), .mode(mode), .d(rgb[7:0]),   .c(ctl[1:0]), .t(did[3:0]),  .q(q0));
    hdmi_chan #(.CN(1)) c1 (.clk(clk_pixel), .mode(mode), .d(rgb[15:8]),  .c(ctl[3:2]), .t(did[7:4]),  .q(q1));
    hdmi_chan #(.CN(2)) c2 (.clk(clk_pixel), .mode(mode), .d(rgb[23:16]), .c(ctl[5:4]), .t(did[11:8]), .q(q2));

`ifndef HDMI_NO_SERIALIZER
    OSER10 s0 (.Q(tmds[0]), .D0(q0[0]), .D1(q0[1]), .D2(q0[2]), .D3(q0[3]), .D4(q0[4]),
               .D5(q0[5]), .D6(q0[6]), .D7(q0[7]), .D8(q0[8]), .D9(q0[9]),
               .PCLK(clk_pixel), .FCLK(clk_pixel_x5), .RESET(reset));
    OSER10 s1 (.Q(tmds[1]), .D0(q1[0]), .D1(q1[1]), .D2(q1[2]), .D3(q1[3]), .D4(q1[4]),
               .D5(q1[5]), .D6(q1[6]), .D7(q1[7]), .D8(q1[8]), .D9(q1[9]),
               .PCLK(clk_pixel), .FCLK(clk_pixel_x5), .RESET(reset));
    OSER10 s2 (.Q(tmds[2]), .D0(q2[0]), .D1(q2[1]), .D2(q2[2]), .D3(q2[3]), .D4(q2[4]),
               .D5(q2[5]), .D6(q2[6]), .D7(q2[7]), .D8(q2[8]), .D9(q2[9]),
               .PCLK(clk_pixel), .FCLK(clk_pixel_x5), .RESET(reset));
`else
    assign tmds = 3'b000;
`endif
    assign tmds_clock = clk_pixel;
endmodule

// one TMDS channel: video (8b/10b with DC balance), control, TERC4, guards
module hdmi_chan #(parameter CN = 0) (
    input  wire       clk,
    input  wire [2:0] mode,
    input  wire [7:0] d,
    input  wire [1:0] c,
    input  wire [3:0] t,
    output reg  [9:0] q
);
    function [3:0] ones; input [7:0] x; integer i;
        begin ones = 0; for (i = 0; i < 8; i = i + 1) ones = ones + x[i]; end
    endfunction
    function [9:0] terc4; input [3:0] x;
        begin
            case (x)
            4'h0: terc4 = 10'b1010011100; 4'h1: terc4 = 10'b1001100011;
            4'h2: terc4 = 10'b1011100100; 4'h3: terc4 = 10'b1011100010;
            4'h4: terc4 = 10'b0101110001; 4'h5: terc4 = 10'b0100011110;
            4'h6: terc4 = 10'b0110001110; 4'h7: terc4 = 10'b0100111100;
            4'h8: terc4 = 10'b1011001100; 4'h9: terc4 = 10'b0100111001;
            4'hA: terc4 = 10'b0110011100; 4'hB: terc4 = 10'b1011000110;
            4'hC: terc4 = 10'b1010001110; 4'hD: terc4 = 10'b1001110001;
            4'hE: terc4 = 10'b0101100011; default: terc4 = 10'b1011000011;
            endcase
        end
    endfunction

    // number of ones in a nibble, as a table (keeps yosys from sharing the
    // adder with n1 below, which created a false combinational loop)
    function [2:0] ones4; input [3:0] x;
        begin
            case (x)
            4'h0: ones4 = 3'd0; 4'h1, 4'h2, 4'h4, 4'h8: ones4 = 3'd1;
            4'h7, 4'hB, 4'hD, 4'hE: ones4 = 3'd3; 4'hF: ones4 = 3'd4;
            default: ones4 = 3'd2;
            endcase
        end
    endfunction
    (* keep *) wire [3:0] n1d = {1'b0, ones4(d[3:0])} + {1'b0, ones4(d[7:4])};
    wire use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && d[0] == 1'b0);
    wire [8:0] qm;
    assign qm[0] = d[0];
    genvar k;
    generate for (k = 1; k < 8; k = k + 1) begin : g
        assign qm[k] = use_xnor ? ~(qm[k-1] ^ d[k]) : (qm[k-1] ^ d[k]);
    end endgenerate
    assign qm[8] = ~use_xnor;
    (* keep *) wire [3:0] n1 = ones(qm[7:0]);
    wire [3:0] n0 = 4'd8 - n1;
    reg signed [4:0] cnt;

    always @(posedge clk) begin
        if (mode != 3'd1) cnt <= 5'sd0;
        case (mode)
        3'd1: begin
            if (cnt == 0 || n1 == n0) begin
                q   <= {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
                cnt <= qm[8] ? cnt + $signed({1'b0, n1}) - $signed({1'b0, n0})
                             : cnt + $signed({1'b0, n0}) - $signed({1'b0, n1});
            end else if ((cnt > 0 && n1 > n0) || (cnt < 0 && n0 > n1)) begin
                q   <= {1'b1, qm[8], ~qm[7:0]};
                cnt <= cnt + $signed({3'b0, qm[8], 1'b0}) + $signed({1'b0, n0}) - $signed({1'b0, n1});
            end else begin
                q   <= {1'b0, qm[8], qm[7:0]};
                cnt <= cnt - $signed({3'b0, ~qm[8], 1'b0}) + $signed({1'b0, n1}) - $signed({1'b0, n0});
            end
        end
        3'd2: q <= (CN == 1) ? 10'b0100110011 : 10'b1011001100;     // video guard
        3'd3: q <= terc4(t);                                          // data island
        3'd4: q <= (CN == 0) ? terc4({2'b11, c}) : 10'b0100110011;    // island guard
        default: case (c)                                             // control
            2'b00: q <= 10'b1101010100;
            2'b01: q <= 10'b0010101011;
            2'b10: q <= 10'b0101010100;
            default: q <= 10'b1010101011;
        endcase
        endcase
    end
endmodule

`default_nettype wire
