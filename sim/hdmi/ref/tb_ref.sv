module tb_ref(input logic clk, input logic rst, output logic [9:0] q0, output logic [9:0] q1, output logic [9:0] q2,
              output logic [9:0] cx, output logic [9:0] cy, output logic push, output logic [15:0] a0, output logic [15:0] a1);
    logic [9:0] px, py;
    always_ff @(posedge clk) begin px <= cx; py <= cy; end
    wire [23:0] rgb = (px < 720 && py < 480) ? {py[7:0] ^ 8'h5A, px[7:0], 4'd0, py[3:0] ^ {2'b00, px[9:8]}} : 24'd0;
    logic [10:0] aud_acc = 0; logic clk_audio = 0, aq = 0;
    always_ff @(posedge clk) begin
        if (aud_acc >= 11'd1121) begin aud_acc <= aud_acc + 11'd4 - 11'd1125; clk_audio <= ~clk_audio; end
        else aud_acc <= aud_acc + 11'd4;
        aq <= clk_audio;
    end
    assign push = clk_audio & ~aq;
    logic [15:0] aw [1:0];
    initial begin aw[0] = 16'h1234; aw[1] = 16'hA5C3; end
    always_ff @(posedge clk_audio) begin aw[0] <= aw[0] + 16'd257; aw[1] <= aw[1] - 16'd31; end
    assign a0 = aw[0]; assign a1 = aw[1];
    logic [2:0] tmds; logic tmds_clock;
    hdmi #(.VIDEO_ID_CODE(2), .DVI_OUTPUT(0), .VIDEO_REFRESH_RATE(59.94), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16))
      h (.clk_pixel_x5(1'b0), .clk_pixel(clk), .clk_audio(clk_audio), .reset(rst), .rgb(rgb), .audio_sample_word(aw),
         .tmds(tmds), .tmds_clock(tmds_clock), .cx(cx), .cy(cy), .frame_width(), .frame_height(), .screen_width(), .screen_height());
    assign q0 = h.tmds_internal[0]; assign q1 = h.tmds_internal[1]; assign q2 = h.tmds_internal[2];
endmodule
