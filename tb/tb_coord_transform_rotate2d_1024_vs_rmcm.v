`timescale 1ns/1ps
module tb_eq;
  reg clk = 0, rst = 1; always #5 clk = ~clk;
  reg valid = 0; reg signed [3:0] xc2, yc2; reg [9:0] th;
  wire va, vb; wire [9:0] xa, ya, xb, yb;
  coord_transform_rotate2d_1024 A (.clk(clk), .rst(rst), .valid_in(valid), .xc2_in(xc2), .yc2_in(yc2), .theta_idx(th), .valid_out(va), .x_out(xa), .y_out(ya));
  coord_transform_rmcm B (.clk(clk), .rst(rst), .valid_in(valid), .xc2_in(xc2), .yc2_in(yc2), .theta_idx(th), .valid_out(vb), .x_out(xb), .y_out(yb));
  integer r, c, t, n = 0, bad = 0;
  initial begin
    repeat (3) @(posedge clk); #1 rst = 0;
    for (r = 0; r < 4; r = r + 1) for (c = 0; c < 4; c = c + 1) for (t = 0; t < 1024; t = t + 1) begin
      xc2 = 2*c - 3; yc2 = 2*r - 3; th = t; valid = 1; @(posedge clk); #1;
      @(posedge clk); #1;
      n = n + 1; if (xa !== xb || ya !== yb) bad = bad + 1;
    end
    $display("rotate2d_1024 vs rmcm: compared=%0d mismatches=%0d", n, bad);
    $finish;
  end
endmodule
