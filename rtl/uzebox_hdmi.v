// ============================================================================
//  uzebox_hdmi.v - HDMI output for UzeTang (720x480p 59.94 Hz, 48 kHz audio)
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Reads the captured Uzebox lines from the line buffer (pixel clock domain,
//  27 MHz) and sends them through the hdl-util HDMI encoder (MIT/Apache-2.0).
//   - Horizontal: 720 pixels = 1440 Uzebox cycles (2 cycles per pixel),
//     so 6-cycle Uzebox pixels are exactly 3 HDMI pixels wide.
//   - Vertical: 480 lines = 240 Uzebox rows, each shown twice.
//   - Once per frame, at line SYNC_LINE, 'frame_tog' toggles. The AVR, which
//     runs slightly faster than real time, waits for it at the start of its
//     own frame, which keeps both sides locked with a few lines of latency.
// ============================================================================

`default_nettype none

module uzebox_hdmi #(
    parameter VOFF      = 13,       // first Uzebox row shown
    parameter SYNC_LINE = 490       // HDMI line where the AVR is released
)(
    input  wire        clk_pixel,
    input  wire        clk_pixel_x5,
    input  wire        rst,

    // line buffer read port (synchronous, 1 cycle latency)
    output reg  [13:0] lb_addr,
    input  wire [7:0]  lb_data,

    // audio sample from the AVR domain (8 bit unsigned, OCR2A)
    input  wire [7:0]  snd_val,     // stable while snd_tog does not change
    input  wire        snd_tog,     // toggles when a new sample is written

    output reg         frame_tog,

    output wire [2:0]  tmds,
    output wire        tmds_clock,

    // 1-bit sigma-delta DAC of the same sample, for analog audio out
    // (UzeTang Board: 1k + 10n low pass and a DC-blocking cap per RCA jack)
    output wire        audio_dac
);
    wire [9:0] cx;
    wire [9:0] cy;

    // ---------------- video ----------------
    // Pipeline (the encoder expects rgb of pixel cx-1):
    //   t: address of pixel cx+2 registered, t+1: RAM read, t+2: data
    //   registered, t+3: rgb (comb) for pixel cx(t)+2 = cx(t+3)-1.
    wire       wrap = (cx >= 10'd856);
    wire [9:0] nx = wrap ? cx - 10'd856 : cx + 10'd2;
    wire [9:0] ny = wrap ? ((cy == 10'd524) ? 10'd0 : cy + 10'd1) : cy;
    wire [8:0] row = VOFF[8:0] + {1'b0, ny[9:1]};
    reg        act_q1, act_q2, act_q3;
    reg [7:0]  pix_q;
    always @(posedge clk_pixel) begin
        lb_addr <= {row[2:0], (nx < 10'd720) ? {nx, 1'b0} : 11'd0};
        act_q1  <= (nx < 10'd720) && (ny < 10'd480);
        act_q2  <= act_q1;
        act_q3  <= act_q2;
        pix_q   <= lb_data;
    end
    wire [2:0] pr = pix_q[2:0];
    wire [2:0] pg = pix_q[5:3];
    wire [1:0] pb = pix_q[7:6];
    wire [23:0] rgb = act_q3 ? {pr, pr, pr[2:1], pg, pg, pg[2:1], pb, pb, pb, pb} : 24'd0;

    // frame marker for the AVR pause logic
    always @(posedge clk_pixel) begin
        if (rst) frame_tog <= 1'b0;
        else if (cx == 10'd0 && cy == SYNC_LINE[9:0]) frame_tog <= ~frame_tog;
    end

    // ---------------- audio ----------------
    // 48 kHz audio clock from 27 MHz: toggle every 281.25 cycles
    reg [10:0] aud_acc;
    reg        clk_audio;
    always @(posedge clk_pixel) begin
        if (aud_acc >= 11'd1125 - 11'd4) begin
            aud_acc   <= aud_acc + 11'd4 - 11'd1125;
            clk_audio <= ~clk_audio;
        end else
            aud_acc <= aud_acc + 11'd4;
    end
    // bring the sample over from the AVR domain
    reg [2:0]  tog_s;
    reg [7:0]  smp;
    always @(posedge clk_pixel) begin
        tog_s <= {tog_s[1:0], snd_tog};
        if (tog_s[2] != tog_s[1]) smp <= snd_val;
    end
    // First-order sigma-delta at the 27 MHz pixel clock: the density of
    // ones follows the 8-bit sample, like the Uzebox's PWM audio pin.
    reg [8:0] dac_acc;
    always @(posedge clk_pixel) begin
        if (rst) dac_acc <= 9'd0;
        else     dac_acc <= {1'b0, dac_acc[7:0]} + {1'b0, smp};
    end
    assign audio_dac = dac_acc[8];

    // one-pole low pass (~5 kHz) at 48 kHz, 16 bit signed output
    reg  signed [15:0] filt;
    wire signed [15:0] x16 = {smp ^ 8'h80, 8'h00};
    reg  [15:0] audio_word [1:0];
    always @(posedge clk_audio) begin
        filt <= filt + ((x16 - filt) >>> 1);
        audio_word[0] <= filt;
        audio_word[1] <= filt;
    end

`ifdef UZETANG_HDMI_LITE
    // open-source flow: plain Verilog HDMI encoder with audio
    // (rtl/hdmi/hdmi_lite.v), as yosys cannot read hdl-util's SystemVerilog
    hdmi hdmi_i (
        .clk_pixel_x5(clk_pixel_x5), .clk_pixel(clk_pixel), .clk_audio(clk_audio),
        .reset(rst), .rgb(rgb),
        .audio_sample_word0(audio_word[0]), .audio_sample_word1(audio_word[1]),
        .tmds(tmds), .tmds_clock(tmds_clock), .cx(cx), .cy(cy),
        .frame_width(), .frame_height(), .screen_width(), .screen_height()
    );
`else
    hdmi #(
        .VIDEO_ID_CODE(2),
        .DVI_OUTPUT(1'b0),
        .VIDEO_REFRESH_RATE(59.94),
        .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME({"UzeTang", 8'd0}),
        .PRODUCT_DESCRIPTION({"Uzebox", 80'd0}),
        .SOURCE_DEVICE_INFORMATION(8'h08)      // game
    ) hdmi_i (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .reset(rst),
        .rgb(rgb),
        .audio_sample_word(audio_word),
        .tmds(tmds),
        .tmds_clock(tmds_clock),
        .cx(cx),
        .cy(cy),
        .frame_width(),
        .frame_height(),
        .screen_width(),
        .screen_height()
    );
`endif

endmodule

`default_nettype wire
