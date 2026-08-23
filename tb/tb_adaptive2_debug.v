`timescale 1ns/1ps
module tb_adaptive2_debug;
  parameter N = 16;
  reg clk = 0;
  reg rst;
  reg [N-1:0] req;
  wire link_valid;
  wire [3:0] link_data;
  wire [N-1:0] ack_mask;
  wire [N-1:0] decoded_mask;
  wire decoded_valid;

  aer_tx16_adaptive2_serial #(.NUM_SOURCES(N)) tx(
    .clk(clk), .rst(rst), .req(req),
    .link_valid(link_valid), .link_data(link_data), .ack_mask(ack_mask));
  aer_rx16_adaptive2_serial #(.NUM_SOURCES(N)) rx(
    .clk(clk), .rst(rst),
    .link_valid(link_valid), .link_data(link_data),
    .decoded_mask(decoded_mask), .decoded_valid(decoded_valid));

  always #5 clk = ~clk;

  integer c, wait_cyc;
  initial begin
    rst = 1; req = {N{1'b0}};
    @(posedge clk); #1; rst = 0;
    @(posedge clk); #1;

    // pattern=1
    req = 16'd1;
    wait_cyc = 0;
    while (!decoded_valid && wait_cyc < 20) begin @(posedge clk); #1; wait_cyc=wait_cyc+1; end
    $display("PATTERN1_RESULT decoded_valid=%b decoded_mask=%b", decoded_valid, decoded_mask);
    req = {N{1'b0}};
    @(posedge clk); #1;
    while (link_valid) begin @(posedge clk); #1; end

    $display("--- now pattern=2 ---");
    req = 16'd2;
    for (c = 0; c < 8; c = c + 1) begin
      @(posedge clk); #1;
      $display("t=%0d req=%b tx.state=%0d tx.link_valid=%b link_data=%b rx.state=%0d decoded_valid=%b decoded_mask=%b",
        c, req, tx.state, link_valid, link_data, rx.state, decoded_valid, decoded_mask);
    end
    $finish;
  end
endmodule
