// Testbench for rtl/hdmi/hdmi_lite.v: dumps the 10-bit symbols of the three
// TMDS channels for every pixel clock, for checking by check_hdmi.py.
`timescale 1ns/1ps
module tb_hdmi;
    reg clk = 0, rst = 1;
    always #18.5 clk = ~clk;
    wire [9:0] cx, cy;
    // test picture: pixel N is presented while cx = N + 1 (see uzebox_hdmi)
    reg [9:0] px, py;
    always @(posedge clk) begin px <= cx; py <= cy; end
    wire [23:0] rgb = (px < 720 && py < 480) ? {py[7:0] ^ 8'h5A, px[7:0], 4'd0, py[3:0] ^ {2'b00, px[9:8]}} : 24'd0;
    // 48 kHz audio clock exactly as uzebox_hdmi makes it
    reg [10:0] aud_acc = 0; reg clk_audio = 0;
    always @(posedge clk) begin
        if (aud_acc >= 11'd1125 - 11'd4) begin aud_acc <= aud_acc + 11'd4 - 11'd1125; clk_audio <= ~clk_audio; end
        else aud_acc <= aud_acc + 11'd4;
    end
    reg [15:0] aw0 = 16'h1234, aw1 = 16'hA5C3;
    always @(posedge clk_audio) begin aw0 <= aw0 + 16'd257; aw1 <= aw1 - 16'd31; end
    hdmi dut (.clk_pixel_x5(1'b0), .clk_pixel(clk), .clk_audio(clk_audio), .reset(rst),
              .rgb(rgb), .audio_sample_word0(aw0), .audio_sample_word1(aw1),
              .tmds(), .tmds_clock(), .cx(cx), .cy(cy),
              .frame_width(), .frame_height(), .screen_width(), .screen_height());
    integer f, n;
    initial begin
        f = $fopen("sym.txt", "w");
        $fdisplay(f, "# audio log follows symbols as A lines");
        repeat (10) @(posedge clk);
        rst = 0;
        for (n = 0; n < 858*525*3 + 2000; n = n + 1) begin
            @(posedge clk); #1;
            $fdisplay(f, "%0d %0d %0d", dut.q0, dut.q1, dut.q2);
        end
        $fclose(f);
        $finish;
    end
    integer fa;
    initial fa = $fopen("audio_in.txt", "w");
    always @(posedge clk) if (!rst && dut.aud_push) $fdisplay(fa, "%0d %0d", aw0, aw1);
endmodule
