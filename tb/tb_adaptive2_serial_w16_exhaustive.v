// aer_tx16_adaptive2_serial_w16 + aer_rx16_adaptive2_serial_w16 왕복(encode->serial link->decode)
// 정확성을 가능한 모든 req 패턴(1~65535, 16소스 전체 부분집합)으로 전수검증.
// 현수의 961개 exhaustive(§80/81 인용 검증방식) 전례보다 더 강한 65535개 전수.
`timescale 1ns/1ps
module tb_adaptive2_serial_exhaustive;
  parameter N = 16;

  reg clk = 0;
  reg rst;
  reg [N-1:0] req;
  wire link_valid;
  wire [15:0] link_data;
  wire [N-1:0] ack_mask;
  wire [N-1:0] decoded_mask;
  wire decoded_valid;

  aer_tx16_adaptive2_serial_w16 #(.NUM_SOURCES(N)) tx(
    .clk(clk), .rst(rst), .req(req),
    .link_valid(link_valid), .link_data(link_data), .ack_mask(ack_mask));

  aer_rx16_adaptive2_serial_w16 #(.NUM_SOURCES(N)) rx(
    .clk(clk), .rst(rst),
    .link_valid(link_valid), .link_data(link_data),
    .decoded_mask(decoded_mask), .decoded_valid(decoded_valid));

  always #5 clk = ~clk;

  integer pattern;
  integer wait_cyc;
  integer mismatch_count, timeout_count, pass_count;

  initial begin
    rst = 1; req = {N{1'b0}};
    @(posedge clk); #1; rst = 0;
    @(posedge clk); #1;

    mismatch_count = 0; timeout_count = 0; pass_count = 0;

    for (pattern = 1; pattern < (1 << N); pattern = pattern + 1) begin
      req = pattern[N-1:0];
      wait_cyc = 0;
      while (!decoded_valid && wait_cyc < 20) begin
        @(posedge clk); #1;
        wait_cyc = wait_cyc + 1;
      end
      if (decoded_valid) begin
        if (decoded_mask === pattern[N-1:0]) pass_count = pass_count + 1;
        else begin
          mismatch_count = mismatch_count + 1;
          if (mismatch_count <= 5)
            $display("MISMATCH pattern=%b decoded=%b", pattern[N-1:0], decoded_mask);
        end
      end else begin
        timeout_count = timeout_count + 1;
        if (timeout_count <= 5) $display("TIMEOUT pattern=%b", pattern[N-1:0]);
      end
      req = {N{1'b0}};
      @(posedge clk); #1;
      while (link_valid) begin @(posedge clk); #1; end
      @(posedge clk); #1;
      @(posedge clk); #1;
    end

    $display("EXHAUSTIVE_DONE total=%0d pass=%0d mismatch=%0d timeout=%0d",
      (1<<N)-1, pass_count, mismatch_count, timeout_count);
    if (mismatch_count == 0 && timeout_count == 0)
      $display("ADAPTIVE2_SERIAL_EXHAUSTIVE_PASS");
    else
      $display("ADAPTIVE2_SERIAL_EXHAUSTIVE_FAIL");
    $finish;
  end
endmodule
