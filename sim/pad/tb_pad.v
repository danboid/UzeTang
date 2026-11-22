`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #17.43 clk=~clk;
  wire latch, pclk; wire [15:0] btn; wire conn;
  reg [11:0] phys = 0;
  // 4021 pair model: parallel load while latch high, shift on rising clock, serial-in GND
  reg [15:0] sr4021;
  always @(posedge latch or posedge pclk)
    if (latch) sr4021 <= {4'b1111, ~phys};
    else sr4021 <= {1'b0, sr4021[15:1]};
  always @(latch) if (latch) sr4021 = {4'b1111, ~phys};
  // slow rising edge (weak pull-up): the line only reads high once the pad
  // has output 1 for RISE ns; falling edges are immediate
  parameter RISE = 0;
  realtime t1 = 0; reg o_q = 0;
  always @(sr4021[0]) begin if (sr4021[0] && !o_q) t1 = $realtime; o_q = sr4021[0]; end
  reg data = 1;
  always #50 data = sr4021[0] && ($realtime - t1 >= RISE);
  snes_pad_scan #(.FREQ(28_687_500)) s(.clk(clk),.rst(rst),.pad_latch(latch),.pad_clk(pclk),.pad_data(data),.buttons(btn),.connected(conn));
  integer i, errs=0;
  initial begin
    #1000 rst=0;
    for (i=0;i<40;i=i+1) begin
      phys = $random;
      #15000000;
      if (i > 0 && (btn[11:0] !== phys || !conn)) begin errs=errs+1; if (errs < 4) $display("MISMATCH phys %h btn %h conn %b", phys, btn, conn); end
    end
    $display("done errs=%0d", errs); $finish;
  end
endmodule
