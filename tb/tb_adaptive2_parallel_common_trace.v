// aer_tx16_adaptive2_parallel(단일사이클, 직렬화 없음)을 공식 50-workload로 검증.
// pending 클리어 순서는 §82에서 잡은 버그와 동일한 원칙(클리어를 새 도착 처리보다
// 먼저) 적용.
`timescale 1ns/1ps
module tb_adaptive2_parallel_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire [1:0] mode_w;
  wire [15:0] payload_w;
  wire valid_w;
  wire [15:0] ack_mask_w;

  aer_tx16_adaptive2_parallel dut(
    .clk(clk), .rst(rst), .req(req),
    .mode(mode_w), .payload(payload_w), .valid(valid_w), .ack_mask(ack_mask_w));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i;
  reg [15:0] pending;
  integer generated, overrun, acked;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  initial begin
    generated = 0; overrun = 0; acked = 0;
    pending = 16'd0;
    rst = 1; req = 16'd0;
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin $display("CANNOT_OPEN_TRACE %0s", trace_file_r); $finish; end
    scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
    have_next = (scan_ret == 2);

    @(posedge clk); #1;
    rst = 0;

    cyc = 0;
    while (have_next) begin
      pending = pending & ~ack_mask_w;

      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) begin
          if (next_mask[i]) begin
            generated = generated + 1;
            if (pending[i]) overrun = overrun + 1; else pending[i] = 1'b1;
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end

      req = pending;
      acked = acked + popcount16(ack_mask_w);

      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~ack_mask_w;
      req = pending;
      acked = acked + popcount16(ack_mask_w);
      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d acked=%0d",
      trace_file_r, generated, overrun, acked);
    if (acked == generated - overrun)
      $display("ADAPTIVE2_PARALLEL_TRACE_PASS %0s", trace_file_r);
    else
      $display("ADAPTIVE2_PARALLEL_TRACE_FAIL %0s acked=%0d expected=%0d", trace_file_r, acked, generated-overrun);
    $fclose(fd);
    $finish;
  end
endmodule
