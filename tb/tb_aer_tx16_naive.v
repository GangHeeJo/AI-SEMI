// aer_tx16_naive 정확성 검증: 단일/동시다중/무작위 스트레스. phantom(요청 안 한 소스가 승인됨) 0건 확인.
`timescale 1ns/1ps
module tb_aer_tx16_naive;
  reg clk, rst;
  reg [15:0] req;
  wire valid;
  wire [3:0] addr;

  aer_tx16_naive dut(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));

  always #5 clk = ~clk;

  reg [15:0] req_prev;
  integer phantom_errors;
  integer i, cyc;
  integer rng_seed;

  always @(posedge clk) req_prev <= req;

  task check_no_phantom;
    begin
      if (valid && !req_prev[addr]) begin
        phantom_errors = phantom_errors + 1;
        $display("PHANTOM: cyc addr=%0d not requested (req_prev=%h)", addr, req_prev);
      end
    end
  endtask

  initial begin
    clk = 0; rst = 1; req = 16'd0; req_prev = 16'd0; phantom_errors = 0; rng_seed = 1;
    @(posedge clk); #1;
    rst = 0;

    // 1) 단일 소스
    req = 16'h0001;
    repeat (3) begin @(posedge clk); #1; check_no_phantom; end
    if (!(valid && addr == 4'd0))
      $display("FAIL(single): expected valid+addr=0, got valid=%b addr=%0d", valid, addr);
    req = 16'd0;
    repeat (2) begin @(posedge clk); #1; check_no_phantom; end

    // 2) 동시 16개 전체 요청 — 라운드로빈으로 전부 한 번씩 승인되는지
    req = 16'hFFFF;
    begin : rr_check
      reg [15:0] seen;
      seen = 16'd0;
      for (i = 0; i < 40; i = i + 1) begin
        @(posedge clk); #1; check_no_phantom;
        if (valid) seen[addr] = 1'b1;
      end
      if (seen != 16'hFFFF)
        $display("FAIL(round-robin): not all 16 sources granted in 40 cycles, seen=%h", seen);
    end
    req = 16'd0;
    repeat (2) begin @(posedge clk); #1; check_no_phantom; end

    // 3) 무작위 스트레스 3000cycle
    for (cyc = 0; cyc < 3000; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1)
        req[i] = (($random(rng_seed) % 100 + 100) % 100) < 20;
      @(posedge clk); #1; check_no_phantom;
    end

    if (phantom_errors == 0)
      $display("PASS: aer_tx16_naive correctness (phantom_errors=0)");
    else
      $display("FAIL: aer_tx16_naive phantom_errors=%0d", phantom_errors);

    $finish;
  end
endmodule
